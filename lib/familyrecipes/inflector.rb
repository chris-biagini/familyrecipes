# frozen_string_literal: true

module FamilyRecipes
  # Minimal inflection engine for ingredient names and measurement units. Handles
  # singular/plural forms via a curated lookup table (KNOWN_PLURALS) with rule-based
  # fallback, unit normalization (abbreviations, aliases), and ingredient variant
  # generation for fuzzy catalog matching. Avoids ActiveSupport::Inflector because
  # recipe-domain words ("gougères", "pizzelle") need explicit control.
  module Inflector # rubocop:disable Metrics/ModuleLength
    KNOWN_PLURALS = {
      # Units
      'cup' => 'cups', 'clove' => 'cloves', 'slice' => 'slices',
      'can' => 'cans', 'bunch' => 'bunches', 'spoonful' => 'spoonfuls',
      'head' => 'heads', 'stalk' => 'stalks', 'sprig' => 'sprigs',
      'piece' => 'pieces', 'stick' => 'sticks', 'item' => 'items',
      # Yield nouns
      'cookie' => 'cookies', 'loaf' => 'loaves', 'roll' => 'rolls',
      'pizza' => 'pizzas', 'taco' => 'tacos', 'pancake' => 'pancakes',
      'bagel' => 'bagels', 'biscuit' => 'biscuits', 'gougère' => 'gougères',
      'quesadilla' => 'quesadillas', 'pizzelle' => 'pizzelle',
      'bar' => 'bars', 'sandwich' => 'sandwiches', 'sheet' => 'sheets',
      # Ingredient names
      'egg' => 'eggs', 'onion' => 'onions', 'lime' => 'limes',
      'pepper' => 'peppers', 'tomato' => 'tomatoes', 'carrot' => 'carrots',
      'walnut' => 'walnuts', 'olive' => 'olives', 'lentil' => 'lentils',
      'tortilla' => 'tortillas', 'bean' => 'beans', 'leaf' => 'leaves',
      'yolk' => 'yolks', 'berry' => 'berries', 'apple' => 'apples',
      'potato' => 'potatoes', 'lemon' => 'lemons'
    }.freeze

    KNOWN_SINGULARS = KNOWN_PLURALS.invert.freeze

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

    def self.safe_plural(word)
      return word if word.blank?
      return word if ABBREVIATED_FORMS.include?(word.downcase)

      known = KNOWN_PLURALS[word.downcase]
      return apply_case(word, known) if known

      word
    end

    def self.safe_singular(word)
      return word if word.blank?

      known = KNOWN_SINGULARS[word.downcase]
      return apply_case(word, known) if known

      word
    end

    def self.unit_display(unit, count)
      return unit if ABBREVIATED_FORMS.include?(unit)

      count == 1 ? unit : safe_plural(unit)
    end

    def self.display_name(name, count)
      return name if name.blank?

      inflect_last_word(name) { |w| count == 1 ? safe_singular(w) : safe_plural(w) } || name
    end

    def self.ingredient_variants(name)
      return [] if name.blank?

      result = inflect_last_word(name) { |w| alternate_form(w) }
      result ? [result] : []
    end

    def self.normalize_unit(raw_unit)
      cleaned = raw_unit.strip.downcase.chomp('.')
      UNIT_ALIASES[cleaned] || ABBREVIATIONS[cleaned] || singular(cleaned)
    end

    def self.apply_case(original, replacement)
      original[0] == original[0].upcase ? replacement.capitalize : replacement
    end
    private_class_method :apply_case

    def self.singular(word)
      return word if word.blank?

      singularize_by_rules(word)
    end
    private_class_method :singular

    def self.plural(word)
      return word if word.blank?
      return word if ABBREVIATED_FORMS.include?(word.downcase)

      pluralize_by_rules(word)
    end
    private_class_method :plural

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

    def self.inflect_last_word(name)
      base, qualifier = split_ingredient_name(name)
      words = base.split
      adjusted = yield(words.last)
      return nil if adjusted.nil? || adjusted == words.last

      rejoin_ingredient(words[0..-2].join(' '), adjusted, qualifier)
    end
    private_class_method :inflect_last_word

    def self.rejoin_ingredient(prefix, word, qualifier)
      parts = [prefix.presence, word].compact.join(' ')
      qualifier ? "#{parts} #{qualifier}" : parts
    end
    private_class_method :rejoin_ingredient
  end
end
