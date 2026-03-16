# frozen_string_literal: true

# Second stage of the parser pipeline. Consumes LineTokens from LineClassifier
# and assembles them into a structured hash (title, description, front_matter,
# steps, footer) that FamilyRecipes::Recipe uses to populate itself. Works as
# a single-pass cursor over the token array — peek/advance/skip_blanks. Handles
# both explicit steps (## headers) and implicit steps (ingredients without headers).
#
# Collaborators:
# - LineClassifier: produces the LineToken stream this class consumes
# - IngredientParser: parses individual :ingredient tokens into structured hashes
# - CrossReferenceParser: parses :cross_reference_block tokens
# - FamilyRecipes::Recipe: receives the assembled hash via .from_parsed
# - MarkdownImporter: the entry point that wires LineClassifier → RecipeBuilder
class RecipeBuilder # rubocop:disable Metrics/ClassLength
  def initialize(tokens)
    @tokens = tokens
    @position = 0
    @description = nil
  end

  def build
    title = parse_title
    parse_description
    front_matter = parse_front_matter
    steps = parse_steps
    footer = parse_footer

    { title:, description: @description, front_matter:, steps:, footer: }
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
      raise FamilyRecipes::ParseError,
            "Invalid recipe format at line #{line_num}: " \
            'The first line must be a level-one header (# Toasted Bread).'
    end

    token.content[0]
  end

  def parse_description
    skip_blanks
    return if at_end? || peek.type == :step_header || peek.type == :front_matter

    @description = advance.content if peek.type == :prose
  end

  def parse_front_matter
    fields = {}
    skip_blanks

    while !at_end? && peek.type == :front_matter
      token = advance
      key = token.content[0].downcase.to_sym
      fields[key] = token.content[1]
    end

    fields[:tags] = normalize_tags(fields[:tags]) if fields[:tags]
    fields
  end

  def normalize_tags(raw)
    raw.split(',').map { |t| t.strip.downcase.gsub(/\s+/, '-') }.reject(&:empty?)
  end

  def parse_steps
    skip_blanks

    if step_headers_ahead?
      absorb_stray_into_description
      return parse_explicit_steps
    end

    if !at_end? && peek.type != :step_header && peek.type != :divider
      reject_implicit_cross_reference(peek) if peek.type == :cross_reference_block
      step = parse_implicit_step
      return step[:ingredients].any? ? [step] : []
    end

    parse_explicit_steps
  end

  def step_headers_ahead?
    @tokens[@position..].any? { |t| t.type == :step_header }
  end

  def absorb_stray_into_description
    until at_end? || peek.type == :step_header || peek.type == :divider
      append_to_description(advance)
      skip_blanks
    end
  end

  def parse_explicit_steps
    steps = []

    until at_end? || peek.type == :divider
      if peek.type == :step_header
        steps << parse_step
      else
        append_to_description(advance)
      end
      skip_blanks
    end

    steps
  end

  def collect_step_body(stop_at: %i[divider], implicit: false)
    ingredients = []
    instruction_lines = []
    cross_reference = nil

    until at_end? || stop_at.include?(peek.type)
      token = advance
      cross_reference = process_step_token(token, ingredients, instruction_lines, cross_reference,
                                           implicit:)
    end

    { tldr: nil, ingredients:, instructions: instruction_lines.join("\n\n"), cross_reference: }
  end

  def process_step_token(token, ingredients, instruction_lines, cross_reference, implicit:) # rubocop:disable Metrics/MethodLength
    case token.type
    when :cross_reference_block
      reject_implicit_cross_reference(token) if implicit
      validate_cross_reference_placement(token, ingredients, instruction_lines, cross_reference)
      CrossReferenceParser.parse(token.content[0])
    when :ingredient
      raise_mixed_content_error(token, 'ingredients') if cross_reference
      ingredients << IngredientParser.parse(token.content[0])
      cross_reference
    when :prose
      raise_mixed_content_error(token, 'instructions') if cross_reference
      instruction_lines << token.content
      cross_reference
    when :blank then cross_reference
    else
      raise_mixed_content_error(token, 'instructions') if cross_reference
      instruction_lines << token_as_text(token)
      cross_reference
    end
  end # rubocop:enable Metrics/MethodLength

  def parse_implicit_step = collect_step_body(implicit: true)

  def parse_step
    tldr = advance.content[0]
    skip_blanks
    collect_step_body(stop_at: %i[step_header divider]).merge(tldr: tldr)
  end

  def token_as_text(token)
    case token.type
    when :prose then token.content
    when :ingredient then "- #{token.content[0]}"
    when :front_matter then "#{token.content[0]}: #{token.content[1]}"
    when :title then "# #{token.content[0]}"
    when :step_header then "## #{token.content[0]}"
    else Array(token.content).join(' ')
    end
  end

  def append_to_description(token)
    return if token.type == :blank

    text = token_as_text(token)
    @description = @description ? "#{@description}\n\n#{text}" : text
  end

  def reject_implicit_cross_reference(token)
    raise FamilyRecipes::ParseError,
          "Cross-reference (>) at line #{token.line_number} must appear inside " \
          'an explicit step (## Step Name)'
  end

  def validate_cross_reference_placement(token, ingredients, instruction_lines, existing_xref)
    raise_duplicate_cross_reference(token) if existing_xref
    raise_mixed_content_error(token, 'ingredients') if ingredients.any?
    raise_mixed_content_error(token, 'instructions') if instruction_lines.any?
  end

  def raise_duplicate_cross_reference(token)
    raise FamilyRecipes::ParseError,
          'Only one cross-reference (>) is allowed per step ' \
          "(line #{token.line_number})"
  end

  def raise_mixed_content_error(token, content_type)
    raise FamilyRecipes::ParseError,
          "Cross-reference (>) at line #{token.line_number} " \
          "cannot be mixed with #{content_type} in the same step"
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
