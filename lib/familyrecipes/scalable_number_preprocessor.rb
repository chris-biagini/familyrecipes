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
    "ten" => 10
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
    text.gsub(INSTRUCTION_PATTERN) do
      if $1
        # Word number
        word = $1
        value = WORD_VALUES[word.downcase]
        build_span(value, word)
      else
        # Numeral
        numeral = $2
        value = parse_numeral(numeral)
        build_span(value, numeral)
      end
    end
  end

  def process_yield_line(text)
    replaced = false
    text.sub(YIELD_NUMBER_PATTERN) do
      next $& if replaced
      replaced = true
      if $1
        word = $1
        value = WORD_VALUES[word.downcase]
        build_span(value, word)
      else
        numeral = $2
        value = parse_numeral(numeral)
        build_span(value, numeral)
      end
    end
  end

  def parse_numeral(str)
    if str.include?("/")
      parts = str.split("/")
      parts[0].to_f / parts[1].to_f
    else
      str.to_f
    end
  end

  def build_span(value, original_text)
    %(<span class="scalable" data-base-value="#{value}" data-original-text="#{original_text}">#{original_text}</span>)
  end
end
