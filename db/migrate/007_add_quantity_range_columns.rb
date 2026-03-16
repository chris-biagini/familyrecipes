# frozen_string_literal: true

class AddQuantityRangeColumns < ActiveRecord::Migration[8.1]
  module QuantityParser
    VULGAR_TO_ASCII = {
      '½' => '1/2', '⅓' => '1/3', '⅔' => '2/3',
      '¼' => '1/4', '¾' => '3/4',
      '⅛' => '1/8', '⅜' => '3/8', '⅝' => '5/8', '⅞' => '7/8'
    }.freeze

    VULGAR_PATTERN = /[#{VULGAR_TO_ASCII.keys.join}]/

    module_function

    def parse_value(str)
      return [nil, nil] if str.nil? || str.strip.empty?

      s = normalize(str.strip)
      parts = s.split('-', 2)

      if parts.size == 2
        low = safe_parse(parts[0].strip)
        high = safe_parse(parts[1].strip)
        return [low, high] if low && high && low < high
        return [low, nil] if low && high && (low - high).abs < 0.0001
      end

      value = safe_parse(s)
      value ? [value, nil] : [nil, nil]
    end

    def normalize(s)
      result = s.gsub(/(\d*)\s*(#{VULGAR_PATTERN})/) do
        prefix = Regexp.last_match(1)
        glyph = Regexp.last_match(2)
        ascii = VULGAR_TO_ASCII[glyph]
        prefix.empty? ? ascii : "#{prefix} #{ascii}"
      end
      result.tr("\u2013", '-')
    end

    def safe_parse(s)
      return nil if s.nil? || s.empty?

      if (match = s.match(/\A(\d+)\s+(\d+\/\d+)\z/))
        return match[1].to_f + parse_fraction(match[2])
      end

      return parse_fraction(s) if s.include?('/')

      Float(s, exception: false)
    end

    def parse_fraction(s)
      num, den = s.split('/', 2).map { |p| Float(p, exception: false) }
      return nil unless num && den && !den.zero?

      num / den
    end
  end

  def change
    add_column :ingredients, :quantity_low, :decimal
    add_column :ingredients, :quantity_high, :decimal

    reversible do |dir|
      dir.up { backfill }
    end
  end

  private

  def backfill
    rows = execute("SELECT id, quantity FROM ingredients WHERE quantity IS NOT NULL")
    rows.each do |row|
      id = row['id'] || row[0]
      qty = row['quantity'] || row[1]
      low, high = QuantityParser.parse_value(qty)
      next unless low

      if high
        execute("UPDATE ingredients SET quantity_low = #{low}, quantity_high = #{high} WHERE id = #{id}")
      else
        execute("UPDATE ingredients SET quantity_low = #{low} WHERE id = #{id}")
      end
    end
  end
end
