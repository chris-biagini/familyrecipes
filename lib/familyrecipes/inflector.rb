# frozen_string_literal: true

module FamilyRecipes
  module Inflector
    IRREGULAR_SINGULAR_TO_PLURAL = {
      'leaf' => 'leaves',
      'loaf' => 'loaves'
    }.freeze

    IRREGULAR_PLURAL_TO_SINGULAR = IRREGULAR_SINGULAR_TO_PLURAL.invert.freeze

    UNCOUNTABLE = Set.new(
      [
        'asparagus', 'baby spinach', 'basil', 'bread', 'broccoli', 'butter', 'buttermilk',
        'celery', 'cheddar', 'chocolate', 'cornmeal', 'cornstarch', 'cream cheese',
        'flour', 'garlic', 'gouda', 'gruyère', 'heavy cream', 'honey', 'hummus',
        'milk', 'mozzarella', 'muesli', 'muenster', 'oil', 'oregano', 'parmesan', 'parsley',
        'pecorino', 'rice', 'ricotta', 'salt', 'sour cream', 'sugar', 'thyme',
        'watermelon', 'whipped cream', 'water', 'yeast', 'yogurt'
      ]
    ).freeze

    ABBREVIATIONS = {
      'g' => 'g', 'gram' => 'g', 'grams' => 'g',
      'tbsp' => 'tbsp', 'tablespoon' => 'tbsp', 'tablespoons' => 'tbsp',
      'tsp' => 'tsp', 'teaspoon' => 'tsp', 'teaspoons' => 'tsp',
      'oz' => 'oz', 'ounce' => 'oz', 'ounces' => 'oz',
      'lb' => 'lb', 'lbs' => 'lb', 'pound' => 'lb', 'pounds' => 'lb',
      'l' => 'l', 'liter' => 'l', 'liters' => 'l',
      'ml' => 'ml'
    }.freeze

    UNIT_ALIASES = {
      'small slices' => 'slice',
      'gō' => 'go'
    }.freeze

    ABBREVIATED_FORMS = ABBREVIATIONS.values.to_set.freeze

    # --- Public API ---

    def self.singular(word)
      return word if word.nil? || word.empty?
      return word if uncountable?(word)

      irregular = IRREGULAR_PLURAL_TO_SINGULAR[word.downcase]
      return apply_case(word, irregular) if irregular

      singularize_by_rules(word)
    end

    def self.plural(word)
      return word if word.nil? || word.empty?
      return word if uncountable?(word)

      irregular = IRREGULAR_SINGULAR_TO_PLURAL[word.downcase]
      return apply_case(word, irregular) if irregular

      pluralize_by_rules(word)
    end

    def self.uncountable?(word)
      UNCOUNTABLE.include?(word.downcase)
    end

    def self.normalize_unit(raw_unit)
      cleaned = raw_unit.strip.downcase.chomp('.')
      UNIT_ALIASES[cleaned] || ABBREVIATIONS[cleaned] || singular(cleaned)
    end

    def self.unit_display(unit, count)
      return unit if ABBREVIATED_FORMS.include?(unit)

      count == 1 ? unit : plural(unit)
    end

    def self.name_for_grocery(name)
      return name if uncountable_name?(name)

      base, qualifier = split_qualified(name)
      pluralized = plural(base)
      qualifier ? "#{pluralized} (#{qualifier})" : pluralized
    end

    def self.name_for_count(name, count)
      return name if uncountable_name?(name)
      return name if count == 1

      base, qualifier = split_qualified(name)
      pluralized = plural(base)
      qualifier ? "#{pluralized} (#{qualifier})" : pluralized
    end

    # --- Private helpers ---

    def self.apply_case(original, replacement)
      original[0] == original[0].upcase ? replacement.capitalize : replacement
    end
    private_class_method :apply_case

    def self.uncountable_name?(name)
      base, = split_qualified(name)
      uncountable?(base)
    end
    private_class_method :uncountable_name?

    def self.split_qualified(name)
      match = name.match(/\A(.+?)\s*\((.+)\)\z/)
      match ? [match[1].strip, match[2]] : [name, nil]
    end
    private_class_method :split_qualified

    def self.singularize_by_rules(word)
      case word.downcase
      when /ies$/ then "#{word[0..-4]}y"
      when /(s|x|z|ch|sh)es$/, /oes$/ then word[0..-3]
      when /(?<!s)s$/ then word[0..-2]
      else word
      end
    end
    private_class_method :singularize_by_rules

    def self.pluralize_by_rules(word)
      case word.downcase
      when /[^aeiou]y$/ then "#{word[0..-2]}ies"
      when /(s|x|z|ch|sh)$/, /[bcdfghjklmnpqrstvwxyz]o$/i then "#{word}es"
      else "#{word}s"
      end
    end
    private_class_method :pluralize_by_rules
  end
end
