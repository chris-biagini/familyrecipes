# Recipe class
#
# Parses and encapsulates an entire recipe

class Recipe
  attr_reader :title, :description, :steps, :footer, :source, :id, :version_hash, :category

  # Shared markdown renderer with SmartyPants for typographic quotes/dashes
  MARKDOWN = Redcarpet::Markdown.new(
    Redcarpet::Render::SmartyHTML.new,
    tables: true,
    fenced_code_blocks: true,
    autolink: true,
    no_intra_emphasis: true
  )

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
    markdown = MARKDOWN
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
    lines = @source.split("\n").reject { |line| line.strip.empty? }

    @title = parse_title(lines)
    @description = parse_description(lines)
    @steps = parse_steps(lines)
    @footer = parse_footer(lines)

    if @steps.empty?
      raise StandardError, "Invalid recipe format: Must have at least one step."
    end
  end

  def parse_title(lines)
    first_line = lines.shift&.strip
    if first_line&.match(/^# (.+)$/)
      $1
    else
      raise StandardError, "Invalid recipe format: The first line must be a level-one header (# Toasted Bread)."
    end
  end

  def parse_description(lines)
    return nil if lines.empty?
    return nil if lines.first.strip.match(/^## /)

    lines.shift.strip
  end

  def parse_steps(lines)
    steps = []

    while lines.any?
      break if lines.first.strip == "---"

      current_line = lines.shift.strip
      if current_line.match(/^## (.+)$/)
        steps << parse_step($1, lines)
      end
    end

    steps
  end

  def parse_step(tldr, lines)
    ingredients = []
    instruction_lines = []

    while lines.any?
      break if lines.first.strip == "---"
      break if lines.first.strip.match(/^## /)

      current_line = lines.shift.strip

      if current_line.match(/^- (.+)$/)
        ingredients << parse_ingredient($1)
      else
        instruction_lines << current_line
      end
    end

    Step.new(
      tldr: tldr,
      ingredients: ingredients,
      instructions: instruction_lines.join("\n\n")
    )
  end

  def parse_ingredient(text)
    parts = text.split(':', 2)
    left_side = parts[0]
    prep_note = parts[1]&.strip

    left_parts = left_side.split(',', 2)
    name = left_parts[0].strip
    quantity = left_parts[1]&.strip

    Ingredient.new(name: name, quantity: quantity, prep_note: prep_note)
  end

  def parse_footer(lines)
    return nil if lines.empty?
    return nil unless lines.first.strip == "---"

    lines.shift # Discard the delimiter
    lines.join("\n\n").strip
  end
end
