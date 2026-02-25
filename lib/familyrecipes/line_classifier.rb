# frozen_string_literal: true

module LineClassifier
  LineToken = Data.define(:type, :content, :line_number)

  # Order matters — more specific patterns must come before :prose fallthrough
  LINE_PATTERNS = {
    title: /^# (.+)$/,
    step_header: /^## (.+)$/,
    ingredient: /^- (.+)$/,
    divider: /^---\s*$/,
    front_matter: /^(Category|Makes|Serves):\s+(.+)$/,
    blank: /^\s*$/
  }.freeze

  def self.classify_line(line)
    LINE_PATTERNS.each do |type, pattern|
      next unless (match = line.match(pattern))

      content = match.captures.empty? ? line : match.captures
      return [type, content]
    end

    [:prose, line]
  end

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
