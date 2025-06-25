# Recipe class
#
# Parses and encapsulates an entire recipe

class Recipe
  attr_reader :title, :description, :steps, :footer, :source, :id, :version_hash, :category
  
  def initialize(markdown_source:, id:, category:)
    @source = markdown_source
    @id = id
    @category = category
  
    @version_hash = Digest::SHA256.hexdigest(@source)
    
    @title = nil
    @description = nil
    @steps = []
    @footer = nil
  
    parse_recipe
  end
  
  def relative_url
    "/#{@id}"
  end
  
  def to_html(erb_template_path:)
    # HTML renderer that includes SmartyPants
    renderer = Redcarpet::Render::SmartyHTML.new
    
    # Turn on whatever other extensions you want (tables, fenced code, autolink, etc.)
    markdown = Redcarpet::Markdown.new(renderer,
      tables:               true,
      fenced_code_blocks:   true,
      autolink:             true,
      no_intra_emphasis:    true
    )
    
    template = File.read(erb_template_path)
    ERB.new(template, trim_mode: '-').result(binding)
  end

  def all_ingredients
    # magic ruby syntax, returns a flat array of all unique ingredients
    @steps.flat_map(&:ingredients).uniq { |ingredient| ingredient.normalized_name }
  end
  
  def all_ingredient_names
    @steps
      .flat_map(&:ingredients)
      .map(&:normalized_name)
      .uniq
  end
  
  private

  def parse_recipe
    # just worry about non-blank lines for now
    lines = @source.split("\n").reject { |line| line.strip.empty? }
    
    # look for title, which must be an ATX-style H1 at the beginning of the file.
    current_line = lines.shift.strip
    if current_line.match(/^# (.+)$/)
      @title = $1 # Capture the title text
    else
      raise StandardError, "Invalid recipe format: The first line must be a level-one header (# Toasted Bread)."
    end

    # look for optional description, which is just the first line after the title
    if lines.first.strip.match(/^## (.+)$/)
      @description = nil
    else
      @description = lines.shift.strip
    end
  
    # start loop to parse steps; stop parsing steps when we hit EOF or a delimiter ("---")
    while lines.any?
      # if we're about to hit an HR, we're done looping
      break if lines.first.strip == "---" 
      current_line = lines.shift.strip
      
      # if we hit an H2, start building a new Step
      if current_line.match(/^## (.+)$/)
        tldr = $1 # Capture  H2 text, which is a short blurb describing the step
        ingredients = []
        instructions = ""
        
        ## start loop to parse *inside* step, accumulating ingredients or instructions
        ## break loop (and go to outer loop) if we are about to hit H2 or delimiter
        while lines.any?
          break if lines.first.strip == "---" # about to hit delimiter, done parsing step
          break if lines.first.strip.match(/^## /) # about to hit H2, done parsing step
          current_line = lines.shift.strip
          
          # if we find an ingredient, accumulate it as one; otherwise, accumulate it as an instruction line
          if current_line.match(/^- (.+)$/)
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
    end  # done parsing all steps
    
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
