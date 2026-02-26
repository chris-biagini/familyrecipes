# frozen_string_literal: true

class NutritionLabelParser # rubocop:disable Metrics/ClassLength
  Result = Data.define(:nutrients, :density, :portions, :errors) do
    def success? = errors.empty?
  end

  NUTRIENT_MAP = [
    [/\Acalories\z/i,                    :calories],
    [/\Atotal\s+fat\z/i,                 :fat],
    [/\Asaturated\s+fat\z/i,             :saturated_fat],
    [/\Atrans\s+fat\z/i,                 :trans_fat],
    [/\Acholesterol\z/i,                 :cholesterol],
    [/\Asodium\z/i,                      :sodium],
    [/\Atotal\s+carb(?:ohydrate)?s?\z/i, :carbs],
    [/\A(?:dietary\s+)?fiber\z/i,        :fiber],
    [/\Atotal\s+sugars?\z/i,             :total_sugars],
    [/\Aadded\s+sugars?\z/i,             :added_sugars],
    [/\Aprotein\z/i,                     :protein]
  ].freeze

  NUTRIENT_KEYS = NUTRIENT_MAP.map(&:last).freeze

  UNIT_SUFFIX = /\s*(?:g|mg|mcg)\s*\z/i

  LABEL_LINES = [
    ['Calories',        :calories,     ''],
    ['Total Fat',       :fat,          'g'],
    ['  Saturated Fat', :saturated_fat, 'g'],
    ['  Trans Fat',     :trans_fat,    'g'],
    ['Cholesterol',     :cholesterol,  'mg'],
    ['Sodium',          :sodium,       'mg'],
    ['Total Carbs',     :carbs,        'g'],
    ['  Dietary Fiber', :fiber,        'g'],
    ['  Total Sugars',  :total_sugars, 'g'],
    ['    Added Sugars', :added_sugars, 'g'],
    ['Protein', :protein, 'g']
  ].freeze

  def self.parse(text)
    new(text).parse
  end

  def self.format(entry)
    Formatter.new(entry).to_s
  end

  def self.blank_skeleton
    (['Serving size:', ''] + LABEL_LINES.map { |label, _, _| label }).join("\n")
  end

  def initialize(text)
    @text = text.to_s
  end

  def parse
    serving = parse_serving_size
    return serving if serving.is_a?(Result)

    nutrients = parse_nutrients.merge(basis_grams: serving[:grams])
    errors = validate_nutrients(nutrients)
    return Result.new(nutrients: {}, density: nil, portions: {}, errors:) if errors.any?

    density = parse_density_section || build_density(serving)
    portions = parse_portions.merge(auto_portions(serving))

    Result.new(nutrients:, density:, portions:, errors: [])
  end

  private

  def parse_serving_size
    line = lines.find { |l| l.match?(/\Aserving\s+size\s*:/i) }
    return failure('Serving size is required') unless line

    raw = line.sub(/\Aserving\s+size\s*:\s*/i, '').strip
    parsed = FamilyRecipes::NutritionEntryHelpers.parse_serving_size(raw)
    return failure('Serving size must include a gram weight (e.g., 30g)') unless parsed

    parsed
  end

  MAX_NUTRIENT_VALUE = 10_000
  private_constant :MAX_NUTRIENT_VALUE

  def validate_nutrients(nutrients)
    nutrients.each_with_object([]) do |(key, value), errors|
      next if key == :basis_grams

      label = key.to_s.tr('_', ' ').capitalize
      errors << "#{label} cannot be negative" if value.negative?
      errors << "#{label} exceeds maximum (#{MAX_NUTRIENT_VALUE})" if value > MAX_NUTRIENT_VALUE
    end
  end

  def failure(message)
    Result.new(nutrients: {}, density: nil, portions: {}, errors: [message])
  end

  def lines
    @lines ||= @text.lines.map(&:strip)
  end

  def parse_nutrients
    found = nutrient_lines.each_with_object({}) do |line, hash|
      key, value = match_nutrient(line)
      hash[key] = value if key
    end
    NUTRIENT_KEYS.index_with { |key| found.fetch(key, 0.0) }
  end

  def nutrient_lines
    lines.reject do |l|
      l.empty? || serving_size_line?(l) || portions_header?(l) || portion_line?(l) ||
        density_header?(l) || density_line?(l)
    end
  end

  def serving_size_line?(line) = line.match?(/\Aserving\s+size\s*:/i)
  def density_header?(line) = line.match?(/\Adensity\s*:/i)
  def density_line?(line) = line.match?(/\A[\d.]+\s+\S+\s*=\s*[\d.]+\s*g?\s*\z/i)
  def portions_header?(line) = line.match?(/\Aportions\s*:/i)
  def portion_line?(line) = in_portions_section? && line.match?(/\A\S+\s*:\s*\d/)

  def match_nutrient(line)
    name_part, value_part = split_nutrient_line(line)
    return nil unless name_part

    key = identify_nutrient(name_part)
    return nil unless key

    [key, extract_value(value_part)]
  end

  def split_nutrient_line(line)
    cleaned = line.strip
    return nil if cleaned.empty?

    # Split on the boundary between name and value: last word group with digits
    match = cleaned.match(/\A(.+?)\s+([\d.]+\s*(?:g|mg|mcg)?)\s*\z/i)
    return [cleaned, ''] unless match

    [match[1].strip, match[2].strip]
  end

  def identify_nutrient(name)
    NUTRIENT_MAP.find { |pattern, _| name.match?(pattern) }&.last
  end

  def extract_value(raw)
    return 0.0 if raw.nil? || raw.strip.empty?

    raw.gsub(UNIT_SUFFIX, '').strip.to_f
  end

  def build_density(serving)
    return nil unless serving[:volume_amount] && serving[:volume_unit]

    { grams: serving[:grams], volume: serving[:volume_amount], unit: serving[:volume_unit] }
  end

  def auto_portions(serving)
    return {} unless serving[:auto_portion]

    { serving[:auto_portion][:unit] => serving[:auto_portion][:grams] }
  end

  def parse_density_section
    idx = lines.index { |l| density_header?(l) }
    return nil unless idx

    # Look for "X unit = Yg" on the next non-empty line
    lines[(idx + 1)..].each do |line|
      next if line.empty?

      match = line.match(/\A([\d.]+)\s+(\S+)\s*=\s*([\d.]+)\s*g?\s*\z/i)
      return { volume: match[1].to_f, unit: match[2], grams: match[3].to_f } if match

      break
    end
    nil
  end

  def parse_portions
    return {} unless (idx = portions_section_start)

    lines[(idx + 1)..].each_with_object({}) do |line, hash|
      break hash if line.empty? && hash.any?

      match = line.match(/\A(\S+)\s*:\s*([\d.]+)\s*g?\s*\z/i)
      hash[match[1]] = match[2].to_f if match
    end
  end

  def portions_section_start
    lines.index { |l| portions_header?(l) }
  end

  def in_portions_section?
    @in_portions_section ||= lines.any? { |l| portions_header?(l) }
  end

  class Formatter
    def initialize(entry)
      @entry = entry
    end

    def to_s
      [serving_line, '', *nutrient_lines, *density_section, *portions_section].join("\n")
    end

    private

    def serving_line
      "Serving size: #{format_grams(@entry.basis_grams)}"
    end

    def nutrient_lines
      LABEL_LINES.map do |label, key, unit|
        value = @entry.public_send(key).to_f
        "#{label}#{pad(label)}#{format_number(value)}#{unit}"
      end
    end

    def pad(label)
      width = 20 - label.size
      ' ' * [width, 1].max
    end

    def density_section
      return [] unless @entry.density_grams && @entry.density_volume

      volume = "#{format_number(@entry.density_volume)} #{@entry.density_unit}"
      ['', 'Density:', "  #{volume} = #{format_grams(@entry.density_grams)}"]
    end

    def portions_section
      portions = @entry.portions
      return [] if portions.blank?

      header = ['', 'Portions:']
      entries = portions.map { |name, grams| "  #{name}: #{format_grams(grams)}" }
      header + entries
    end

    def format_grams(value)
      "#{format_number(value)}g"
    end

    def format_number(value)
      value == value.to_i ? value.to_i.to_s : value.to_s
    end
  end
end # rubocop:enable Metrics/ClassLength
