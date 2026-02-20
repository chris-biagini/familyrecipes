# frozen_string_literal: true

# LineClassifier module
#
# Converts raw recipe text into an array of typed line tokens.
# Each line is classified independently using regex patterns.

module LineClassifier
  # A single classified line with its type, content, and line number
  LineToken = Data.define(:type, :content, :line_number)

  # Pattern map for line classification (order matters for some edge cases)
  LINE_PATTERNS = {
    title: /^# (.+)$/,
    step_header: /^## (.+)$/,
    ingredient: /^- (.+)$/,
    divider: /^---\s*$/,
    front_matter: /^(Category|Makes|Serves):\s+(.+)$/,
    blank: /^\s*$/
  }.freeze

  # Classify a single line and return its type and captured content
  def self.classify_line(line)
    LINE_PATTERNS.each do |type, pattern|
      next unless (match = line.match(pattern))

      # For patterns with captures, return the captured content
      # For blank/divider, return the original line
      content = match.captures.empty? ? line : match.captures
      return [type, content]
    end

    # Default: prose (any line that doesn't match other patterns)
    [:prose, line]
  end

  # Convert raw text into an array of LineTokens
  def self.classify(text)
    lines = text.split("\n")

    lines.map.with_index(1) do |line, line_number|
      type, content = classify_line(line)

      LineToken.new(
        type: type,
        content: content,
        line_number: line_number
      )
    end
  end
end
