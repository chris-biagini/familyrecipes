# frozen_string_literal: true

class RecipeBuilder
  attr_reader :errors

  def initialize(tokens)
    @tokens = tokens
    @position = 0
    @errors = []
  end

  def build
    {
      title: parse_title,
      description: parse_description,
      front_matter: parse_front_matter,
      steps: parse_steps,
      footer: parse_footer
    }
  end

  private

  def peek
    @tokens[@position]
  end

  def advance
    token = @tokens[@position]
    @position += 1
    token
  end

  def at_end?
    @position >= @tokens.size
  end

  def skip_blanks
    advance while peek&.type == :blank
  end

  def parse_title
    skip_blanks

    token = advance
    if token.nil? || token.type != :title
      line_num = token&.line_number || 1
      raise "Invalid recipe format at line #{line_num}: The first line must be a level-one header (# Toasted Bread)."
    end

    token.content[0]
  end

  def parse_description
    skip_blanks

    return nil if at_end?
    return nil if peek.type == :step_header
    return nil if peek.type == :front_matter

    advance.content if peek.type == :prose
  end

  def parse_front_matter
    fields = {}
    skip_blanks

    while !at_end? && peek.type == :front_matter
      token = advance
      key = token.content[0].downcase.to_sym
      fields[key] = token.content[1]
    end

    fields
  end

  def parse_steps
    skip_blanks

    return [parse_implicit_step] if !at_end? && peek.type != :step_header && peek.type != :divider

    parse_explicit_steps
  end

  def parse_explicit_steps
    steps = []

    until at_end? || peek.type == :divider
      if peek.type == :step_header
        steps << parse_step
      else
        advance
      end
      skip_blanks
    end

    steps
  end

  def collect_step_body(stop_at: %i[divider])
    ingredients = []
    instruction_lines = []

    until at_end? || stop_at.include?(peek.type)
      token = advance

      case token.type
      when :ingredient
        ingredients << IngredientParser.parse(token.content[0])
      when :prose
        instruction_lines << token.content
      end
    end

    { tldr: nil, ingredients: ingredients, instructions: instruction_lines.join("\n\n") }
  end

  def parse_implicit_step = collect_step_body

  def parse_step
    tldr = advance.content[0]
    skip_blanks
    collect_step_body(stop_at: %i[step_header divider]).merge(tldr: tldr)
  end

  def parse_footer # rubocop:disable Metrics/MethodLength
    skip_blanks

    return nil if at_end?
    return nil unless peek.type == :divider

    advance # consume the divider

    footer_lines = []

    until at_end?
      token = advance
      next if token.type == :blank && footer_lines.empty? # skip leading blanks

      footer_lines << if token.type == :blank
                        ''
                      else
                        token.content
                      end
    end

    footer_lines.pop while footer_lines.last == ''

    return nil if footer_lines.empty?

    footer_lines.join("\n\n").gsub(/\n\n+/, "\n\n")
  end # rubocop:enable Metrics/MethodLength
end
