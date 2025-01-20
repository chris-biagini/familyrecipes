#!/usr/bin/env ruby

require 'fileutils'
require 'erb'
require 'redcarpet'

# Utility classes

class Ingredient
	attr_accessor :name, :quantity, :prep_note

	# name is required, quantity and prep_note are optional
	def initialize(name:, quantity: nil, prep_note: nil)
		@name = name
		@quantity = quantity
		@prep_note = prep_note
	end
end

class Step
	attr_accessor :tldr, :ingredients, :instructions

	def initialize(tldr:, ingredients: [], instructions:)
		if tldr.nil? || tldr.strip.empty?
			raise ArgumentError, "Step must have a tldr."
		end
		
		if ingredients.empty? && (instructions.nil? || instructions.strip.empty?)
			raise ArgumentError, "Step must have either ingredients or instructions."
		end

		@tldr = tldr
		@ingredients = ingredients
		@instructions = instructions
	end
end

class Recipe
	attr_reader :title, :description, :steps, :footer, :source, :id
	
	def initialize(markdown_file)
		@source = File.read(markdown_file)
		@id = parse_filename(markdown_file)
		
		@title = nil
		@description = nil
		@steps = []
		@footer = nil
		
		parse_recipe
	end
	
	def to_html
		# Create markdown renderer
		markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML, 
			autolink: true, 
			tables: true)
		
		# Load and compile template
		template = File.read('templates/web/recipe-template.html.erb')
		erb = ERB.new(template)
		
		# Create binding with necessary variables
		erb_binding = binding
		
		# Render the template
		erb.result(erb_binding)
	end
	
	private
	
	def parse_filename(markdown_file)
		name = File.basename(markdown_file, ".*")
		
		name.unicode_normalize(:nfkd)	# Normalize Unicode characters
			.downcase					# Convert to lowercase
			.gsub(/\s+/, '-')			# Replace spaces with hyphens
			.gsub(/[^a-z0-9\-]/, '')	# Remove non-alphanumeric characters except hyphens
	end
		
	def parse_recipe
		# just worry about non-blank lines for now
		lines = @source.split("\n").reject { |line| line.strip.empty? }
		
		# look for title, which must be an ATX-style H1 at the beginning of the file.
		current_line = lines.shift.strip
		if current_line =~ /^# (.+)$/
			@title = $1 # Capture the title text
		else
			raise StandardError, "Invalid recipe format: The first line must be a level-one header (# Toasted Bread)."
		end

		# look for description, which is just the first line after the title
		@description = lines.shift&.strip
	
		# start loop to parse steps; stop parsing steps when we hit EOF or a delimiter ("---")
		while lines.any?
			# if we're about to hit an HR, we're done looping
			break if lines.first.strip == "---" 
			current_line = lines.shift.strip
			
			# if we hit an H2, start building a new Step
			if current_line =~ /^## (.+)$/
				tldr = $1 # Capture  H2 text, which is a short blurb describing the step
				ingredients = []
				instructions = ""
				
				## start loop to parse *inside* step, accumulating ingredients or instructions
				## break loop (and go to outer loop) if we are about to hit H2 or delimiter
				while lines.any?
					break if lines.first.strip == "---" # about to hit delimiter, done parsing step
					break if lines.first.strip =~ /^## / # about to hit H2, done parsing step
					current_line = lines.shift.strip
					
					# if we find an ingredient, accumulate it as one; otherwise, accumulate it as an instruction line
					if current_line =~ /^- ([^,]+)(?:, ([^:]+))?(?:: (.+))?$/
						name = $1
						quantity = $2
						prep_note = $3
						ingredients << Ingredient.new(name: name, quantity: quantity, prep_note: prep_note)
					else
						instructions += current_line + "\n"
					end
				end #done parsing individual step
				
				# build step and throw it on the pile
				@steps << Step.new(
					tldr: tldr,
					ingredients: ingredients,
					instructions: instructions.strip
				)
			end 
		end	# done parsing all steps
		
		if @steps.empty?
			raise StandardError, "Invalid recipe format: Must have at least one step."
		  end
		
		# if we get to this point, we should have either hit a delimiter or EOF above
		if lines.any? && lines.first.strip == "---"
			lines.shift # Discard the delimiter
			@footer = lines.join("\n").strip # Accumulate the rest as the footer
		end
	end
end

# Generation logic

resources_dir = "resources/web"
output_dir = "output/web"

begin
	print "Parsing recipes..."
	
	recipe_files = Dir.glob("recipes/*")
	
	if recipe_files.empty?
		raise StandardError, "No files in `recipe` directory."
	end
		
	recipes = recipe_files.map do |file|
		Recipe.new(file)
	end
	
	print "done! (Parsed #{recipes.size} recipes.)\n"	
rescue StandardError => error
	puts "Error: #{error.message}"
	exit(1)
end

begin
	FileUtils.mkdir_p(output_dir)
rescue StandardError => e
	puts "Error creating output directory: #{e.message}"
	exit(1)
end

begin
	print "Generating output files in #{output_dir}..."
	
	recipes.each do |recipe|
		# Write text version
		text_path = File.join(output_dir, "#{recipe.id}.txt")
		File.write(text_path, recipe.source)
		
		# Write HTML version
		html_path = File.join(output_dir, "#{recipe.id}.html")
		File.write(html_path, recipe.to_html)
	end
	
	print "done!\n"
rescue StandardError => e
	puts "Error writing recipe files: #{e.message}"
	exit(1)
end

begin
	print "Generating index page..."
	
	# Load and compile template
	template = File.read('templates/web/index-template.html.erb')
	erb = ERB.new(template)
	
	# Generate the HTML using the current binding (which has access to the recipes array)
	html = erb.result(binding)
	
	# Write the file
	index_path = File.join(output_dir, "index.html")
	File.write(index_path, html)
	
	print "done!\n"
rescue StandardError => e
	puts "Error generating index page: #{e.message}"
	exit(1)
end

begin
	print "Copying web resources..."
	
	if Dir.exist?(resources_dir)
		FileUtils.cp_r("#{resources_dir}/.", output_dir) # Copy everything, including subdirectories
	else
		puts "Warning: Source directory #{resources_dir} does not exist, skipping copy."
	end
	
	print "done!\n"	
rescue StandardError => e
	puts "Error copying files: #{e.message}"
	exit(1)
end
