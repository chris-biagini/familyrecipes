#!/usr/bin/env ruby

require 'fileutils'
require 'erb'
require 'redcarpet'
require 'digest'

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
	attr_reader :title, :description, :steps, :footer, :source, :id, :version_hash, :category
	
	def initialize(markdown_file_path)
		@source = File.read(markdown_file_path)
		@version_hash = Digest::SHA256.hexdigest(@source)
		
		@title = nil
		@description = nil
		@steps = []
		@footer = nil
		
		parse_filename(markdown_file_path)
		parse_recipe
	end
	
	def to_html
		markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
		template = File.read('templates/web/recipe-template.html.erb')
		erb = ERB.new(template, trim_mode: '-')
		erb.result(binding)
	end
	
	private
	
	def parse_filename(markdown_file_path)
		@id = File.basename(markdown_file_path, ".*") # Get name without extension
				.unicode_normalize(:nfkd)		 # Normalize Unicode characters
				.downcase						 # Convert to lowercase
				.gsub(/\s+/, '-')				 # Replace spaces with hyphens
				.gsub(/[^a-z0-9\-]/, '')		 # Remove non-alphanumeric characters except hyphens
			
		@category = File.basename(File.dirname(markdown_file_path)).sub(/^./, &:upcase)
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
					if current_line =~ /^- (.+)$/
						ingredient_text = $1
						
						# chop up string, look for prep notes
						parts = ingredient_text.split(':', 2) 
						left_side = parts[0]
						prep_note = parts[1]&.strip # ampersand allows this to be nil
						
						# look for name and quantity
						left_parts = left_side.split(',',2)
						name = left_parts[0].strip
						quantity = left_parts[1]&.strip

						ingredients << Ingredient.new(name: name, quantity: quantity, prep_note: prep_note)
					else
						instructions += current_line + "\n\n" # hack to undo stripping whitespace, need to fix
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
			@footer = lines.join("\n\n").strip # Accumulate the rest as the footer / hack to undo stripping whitespace, need to fix
		end
	end
end

# Generation logic

recipes_dir = "recipes"
template_dir = "templates/web"
resources_dir = "resources/web"
output_dir = "output/web"

# parse recipes; actual parsing happens in Recipe constructor
print "Parsing recipes from #{recipes_dir}..."

recipe_files = Dir.glob(File.join(recipes_dir, "**", "*")).select { |file| File.file?(file) }
recipes = recipe_files.map do |file|
	Recipe.new(file)
end

print "done! (Parsed #{recipes.size} recipes.)\n"	

# make output directory
FileUtils.mkdir_p(output_dir)

# write text and HTML files to output directory
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

# build index page
print "Generating index page in #{output_dir}..."

grouped_recipes = recipes.group_by(&:category) # hash of recipes, with categories as keys

# Read and process the template
template_path = File.join(template_dir, "index-template.html.erb")
erb_template = ERB.new(File.read(template_path), trim_mode: "-")

# Generate the index file
index_path = File.join(output_dir, "index.html")
File.write(index_path, erb_template.result_with_hash(grouped_recipes: grouped_recipes))

print "done!\n"

# Copy resources (e.g., stylesheets, javascript)
print "Copying web resources from #{resources_dir} to #{output_dir}..."
FileUtils.cp_r("#{resources_dir}/.", output_dir) # Copy everything, including subdirectories
print "done!\n"	

# Generate ingredient report
ingredient_report_path = File.join("output", "ingredient-report.txt")
print "Generating ingredient report: #{ingredient_report_path}..."
ingredient_usage = Hash.new { |hash, key| hash[key] = [] }

# Define equivalent ingredient names (synonyms)
ingredient_synonyms = {
  "Egg" => "Eggs",
  "Egg yolks" => "Eggs",
  "Egg yolk" => "Eggs"
}

def normalize_ingredient(name, synonyms)
  base_name = name.downcase.strip
  synonyms[base_name] || base_name # Use mapped name if it exists; otherwise, keep original
end

recipes.each do |recipe|
  recipe.steps.each do |step|
	step.ingredients.each do |ingredient|
	  normalized_name = ingredient_synonyms[ingredient.name] || ingredient.name # Use mapped name if it exists; otherwise, keep original
	  ingredient_usage[normalized_name] << recipe.title unless ingredient_usage[normalized_name].include?(recipe.title)
	end
  end
end

sorted_ingredients = ingredient_usage.sort_by { |_, recipes| -recipes.size }

ingredient_report = "# Ingredient Report\n\n"
sorted_ingredients.each_with_index do |(ingredient, recipes), index|
  ingredient_report += "#{index + 1}. #{ingredient} (#{recipes.join(', ')})\n"
end

File.write(ingredient_report_path, ingredient_report)
print "done!\n"
