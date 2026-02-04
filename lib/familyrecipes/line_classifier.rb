# LineClassifier module
#
# Converts raw recipe text into an array of typed line tokens.
# Each line is classified independently using regex patterns.

module LineClassifier
  # A single classified line with its type, content, and line number
  LineToken = Struct.new(:type, :content, :line_number, keyword_init: true)

  # Pattern map for line classification (order matters for some edge cases)
  LINE_PATTERNS = {
    title:       /^# (.+)$/,
    step_header: /^## (.+)$/,
    ingredient:  /^- (.+)$/,
    divider:     /^---\s*$/,
    blank:       /^\s*$/
  }.freeze

  # Classify a single line and return its type and captured content
  def self.classify_line(line)
    LINE_PATTERNS.each do |type, pattern|
      if (match = line.match(pattern))
        # For patterns with captures, return the captured content
        # For blank/divider, return the original line
        content = match.captures.empty? ? line : match.captures
        return [type, content]
      end
    end

    # Default: prose (any line that doesn't match other patterns)
    [:prose, line]
  end

  # Convert raw text into an array of LineTokens
  def self.classify(text)
    lines = text.split("\n")

    lines.each_with_index.map do |line, index|
      type, content = classify_line(line)

      LineToken.new(
        type: type,
        content: content,
        line_number: index + 1
      )
    end
  end
end
