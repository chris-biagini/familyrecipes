# frozen_string_literal: true

# Generates cooking-themed join codes in the format:
# "descriptor ingredient ingredient dish"
# Loaded once at boot via initializer; arrays frozen for thread safety.
# Uses SecureRandom for index selection.
#
# - Kitchen: calls generate on create, stores result in join_code column
# - config/initializers/join_code_generator.rb: triggers load! at boot
module JoinCodeGenerator
  WORDS_PATH = Rails.root.join('db/seeds/resources/join-code-words.yaml')

  class << self
    attr_reader :descriptors, :ingredients, :dishes

    def load!
      data = YAML.load_file(WORDS_PATH)
      @descriptors = data.fetch('descriptors').map(&:freeze).freeze
      @ingredients = data.fetch('ingredients').map(&:freeze).freeze
      @dishes = data.fetch('dishes').map(&:freeze).freeze
    end

    def generate
      d = descriptors[SecureRandom.random_number(descriptors.size)]
      i1 = ingredients[SecureRandom.random_number(ingredients.size)]
      i2 = pick_second_ingredient(i1)
      dish = dishes[SecureRandom.random_number(dishes.size)]
      "#{d} #{i1} #{i2} #{dish}"
    end

    private

    def pick_second_ingredient(first)
      loop do
        candidate = ingredients[SecureRandom.random_number(ingredients.size)]
        return candidate unless candidate == first
      end
    end
  end
end
