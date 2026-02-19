# RecipeBuilder class
#
# Consumes LineTokens from LineClassifier and produces a structured
# document hash, which can then be converted to domain objects.

class RecipeBuilder
  attr_reader :errors

  def initialize(tokens)
    @tokens = tokens
    @position = 0
    @errors = []
  end

  # Build a document hash from the tokens
  # Returns: { title:, description:, yield_line:, steps:, footer: }
  def build
    {
      title: parse_title,
      description: parse_description,
      yield_line: parse_yield_line,
      steps: parse_steps,
      footer: parse_footer
    }
  end

  private

  # Get current token without advancing
  def peek
    @tokens[@position]
  end

  # Get current token and advance position
  def advance
    token = @tokens[@position]
    @position += 1
    token
  end

  # Check if we've reached the end
  def at_end?
    @position >= @tokens.length
  end

  # Skip blank lines
  def skip_blanks
    advance while !at_end? && peek.type == :blank
  end

  # Parse the title (first non-blank line must be a title)
  def parse_title
    skip_blanks

    token = advance
    if token.nil? || token.type != :title
      line_num = token&.line_number || 1
      raise StandardError, "Invalid recipe format at line #{line_num}: The first line must be a level-one header (# Toasted Bread)."
    end

    # Title content is an array: [captured_text]
    token.content[0]
  end

  # Parse optional description (prose between title and first step)
  def parse_description
    skip_blanks

    return nil if at_end?
    return nil if peek.type == :step_header

    if peek.type == :prose && !peek.content.match?(/\A(Makes|Serves)\b/i)
      advance.content
    else
      nil
    end
  end

  # Parse optional yield line ("Makes 30 gougères." / "Serves 4.")
  def parse_yield_line
    skip_blanks
    return nil if at_end?
    return nil if peek.type != :prose
    if peek.content.match?(/\A(Makes|Serves)\b/i)
      advance.content
    end
  end

  # Parse all steps until divider or end
  def parse_steps
    steps = []

    skip_blanks

    while !at_end? && peek.type != :divider
      if peek.type == :step_header
        steps << parse_step
      else
        # Skip unexpected tokens (shouldn't happen with well-formed input)
        advance
      end
      skip_blanks
    end

    steps
  end

  # Parse a single step (header, ingredients, instructions)
  def parse_step
    header_token = advance
    tldr = header_token.content[0] # Step header content is [captured_text]

    ingredients = []
    instruction_lines = []

    skip_blanks

    while !at_end? && peek.type != :step_header && peek.type != :divider
      token = advance

      case token.type
      when :ingredient
        # Ingredient content is [captured_text] (the part after "- ")
        ingredient_data = IngredientParser.parse(token.content[0])
        ingredients << ingredient_data
      when :prose
        instruction_lines << token.content
      when :blank
        # Blanks between instruction paragraphs
        next
      end
    end

    {
      tldr: tldr,
      ingredients: ingredients,
      instructions: instruction_lines.join("\n\n")
    }
  end

  # Parse optional footer (everything after ---)
  def parse_footer
    skip_blanks

    return nil if at_end?
    return nil unless peek.type == :divider

    advance # consume the divider

    footer_lines = []

    until at_end?
      token = advance
      next if token.type == :blank && footer_lines.empty? # skip leading blanks

      if token.type == :blank
        # Keep blank lines as paragraph separators
        footer_lines << ""
      else
        footer_lines << token.content
      end
    end

    # Remove trailing blank lines
    footer_lines.pop while footer_lines.last == ""

    return nil if footer_lines.empty?

    footer_lines.join("\n\n").gsub(/\n\n+/, "\n\n")
  end
end
