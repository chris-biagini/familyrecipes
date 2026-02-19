# ScalableNumberPreprocessor
#
# Wraps numbers in <span class="scalable"> tags so they can be scaled
# by the client-side recipe scaler.
#
# Two entry points:
# - process_instructions(text): replaces NUMBER* patterns (asterisk consumed)
# - process_yield_line(text): wraps the first number found (no asterisk needed)

module ScalableNumberPreprocessor
  WORD_VALUES = {
    "zero" => 0, "one" => 1, "two" => 2, "three" => 3, "four" => 4,
    "five" => 5, "six" => 6, "seven" => 7, "eight" => 8, "nine" => 9,
    "ten" => 10, "eleven" => 11, "twelve" => 12
  }.freeze

  WORD_PATTERN = WORD_VALUES.keys.join("|")

  # Match word* or numeral* (fraction or decimal or integer, followed by *)
  INSTRUCTION_PATTERN = /
    (?:
      (#{WORD_PATTERN})\*                  # word number with asterisk
    |
      (\d+(?:\.\d+)?(?:\/\d+(?:\.\d+)?)?)\* # numeral (int, decimal, or fraction) with asterisk
    )
  /ix

  # Match the first number (word or numeral) in a yield line
  YIELD_NUMBER_PATTERN = /
    (?:
      \b(#{WORD_PATTERN})\b     # word number
    |
      \b(\d+(?:\.\d+)?(?:\/\d+(?:\.\d+)?)?)\b  # numeral
    )
  /ix

  module_function

  def process_instructions(text)
    text.gsub(INSTRUCTION_PATTERN) { span_from_match($1, $2) }
  end

  def process_yield_line(text)
    text.sub(YIELD_NUMBER_PATTERN) { span_from_match($1, $2) }
  end

  def span_from_match(word_match, numeral_match)
    if word_match
      build_span(WORD_VALUES[word_match.downcase], word_match)
    else
      build_span(parse_numeral(numeral_match), numeral_match)
    end
  end

  def parse_numeral(str)
    return str.to_f unless str.include?("/")

    numerator, denominator = str.split("/")
    numerator.to_f / denominator.to_f
  end

  def build_span(value, original_text)
    %(<span class="scalable" data-base-value="#{value}" data-original-text="#{original_text}">#{original_text}</span>)
  end
end
