# frozen_string_literal: true

module FamilyRecipes
  module Inflector # rubocop:disable Metrics/ModuleLength
    IRREGULAR_SINGULAR_TO_PLURAL = {
      'cookie' => 'cookies',
      'leaf' => 'leaves',
      'loaf' => 'loaves',
      'taco' => 'tacos'
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
      'gō' => 'gō',
      'tbsp' => 'tbsp', 'tablespoon' => 'tbsp', 'tablespoons' => 'tbsp',
      'tsp' => 'tsp', 'teaspoon' => 'tsp', 'teaspoons' => 'tsp',
      'oz' => 'oz', 'ounce' => 'oz', 'ounces' => 'oz',
      'lb' => 'lb', 'lbs' => 'lb', 'pound' => 'lb', 'pounds' => 'lb',
      'l' => 'l', 'liter' => 'l', 'liters' => 'l',
      'ml' => 'ml'
    }.freeze

    UNIT_ALIASES = {
      'small slices' => 'slice'
    }.freeze

    ABBREVIATED_FORMS = ABBREVIATIONS.values.to_set.freeze

    # --- Public API ---

    def self.singular(word)
      return word if word.blank?
      return word if uncountable?(word)

      irregular = IRREGULAR_PLURAL_TO_SINGULAR[word.downcase]
      return apply_case(word, irregular) if irregular

      singularize_by_rules(word)
    end

    def self.plural(word)
      return word if word.blank?
      return word if uncountable?(word)
      return word if ABBREVIATED_FORMS.include?(word.downcase)

      irregular = IRREGULAR_SINGULAR_TO_PLURAL[word.downcase]
      return apply_case(word, irregular) if irregular

      pluralize_by_rules(word)
    end

    def self.uncountable?(word)
      UNCOUNTABLE.include?(word.downcase)
    end

    def self.ingredient_variants(name)
      return [] if name.blank?

      base, qualifier = split_ingredient_name(name)
      words = base.split
      last_word = words.last
      prefix = words[0..-2].join(' ')

      alternate = alternate_form(last_word)
      return [] unless alternate

      [rejoin_ingredient(prefix, alternate, qualifier)]
    end

    def self.normalize_unit(raw_unit)
      cleaned = raw_unit.strip.downcase.chomp('.')
      UNIT_ALIASES[cleaned] || ABBREVIATIONS[cleaned] || singular(cleaned)
    end

    def self.unit_display(unit, count)
      return unit if ABBREVIATED_FORMS.include?(unit)

      count == 1 ? unit : plural(unit)
    end

    # --- Private helpers ---

    def self.apply_case(original, replacement)
      original[0] == original[0].upcase ? replacement.capitalize : replacement
    end
    private_class_method :apply_case

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

    # Words ending in 's' are ambiguous — could already be plural
    def self.alternate_form(word)
      singular_form = singular(word)
      return singular_form if singular_form != word

      plural_form = plural(word)
      return plural_form if plural_form != word && !word.end_with?('s')

      nil
    end
    private_class_method :alternate_form

    def self.split_ingredient_name(name)
      match = name.match(/\A(.+?)\s*(\([^)]+\))\z/)
      match ? [match[1].strip, match[2]] : [name, nil]
    end
    private_class_method :split_ingredient_name

    def self.rejoin_ingredient(prefix, word, qualifier)
      parts = [prefix.presence, word].compact.join(' ')
      qualifier ? "#{parts} #{qualifier}" : parts
    end
    private_class_method :rejoin_ingredient
  end
end
