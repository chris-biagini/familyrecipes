# frozen_string_literal: true

require 'erb'
require 'redcarpet'
require 'digest'
require 'json'
require 'yaml'

# Root module for the recipe parser pipeline — a pure-Ruby domain layer that
# knows nothing about Rails. Parses Markdown recipe files into structured value
# objects (Recipe, Step, Ingredient, CrossReference, QuickBite) and computes
# nutrition data. Loaded once at boot via config/initializers/familyrecipes.rb,
# not through Zeitwerk. The Rails app module is Familyrecipes (lowercase r);
# this module is FamilyRecipes (uppercase R) — different constants, no collision.
module FamilyRecipes
  CONFIG = {
    quick_bites_filename: 'Quick Bites.md',
    quick_bites_category: 'Quick Bites'
  }.freeze

  def self.slugify(title)
    title
      .unicode_normalize(:nfkd)
      .downcase
      .gsub(/\s+/, '-')
      .gsub(/[^a-z0-9-]/, '')
  end

  def self.parse_recipes(recipes_dir)
    quick_bites_filename = CONFIG[:quick_bites_filename]

    recipe_files = Dir.glob(File.join(recipes_dir, '**', '*')).select do |file|
      File.file?(file) && File.basename(file) != quick_bites_filename
    end

    recipe_files.map do |file|
      source = File.read(file)
      id = slugify(File.basename(file, '.*'))
      category = File.basename(File.dirname(file)).sub(/^./, &:upcase)
      Recipe.new(markdown_source: source, id: id, category: category)
    end
  end

  def self.parse_quick_bites_content(content)
    current_subcat = nil

    content.each_line.with_object([]) do |line, quick_bites|
      case line
      when /^##\s+(.*)/
        current_subcat = ::Regexp.last_match(1).strip
      when /^\s*-\s+(.*)/
        category = [CONFIG[:quick_bites_category], current_subcat].compact.join(': ')
        quick_bites << QuickBite.new(text_source: ::Regexp.last_match(1).strip, category: category)
      end
    end
  end

  def self.parse_quick_bites(recipes_dir)
    file_path = File.join(recipes_dir, CONFIG[:quick_bites_filename])
    parse_quick_bites_content(File.read(file_path))
  end
end

require_relative 'familyrecipes/numeric_parsing'
require_relative 'familyrecipes/quantity'
require_relative 'familyrecipes/scalable_number_preprocessor'
require_relative 'familyrecipes/inflector'
require_relative 'familyrecipes/ingredient'
require_relative 'familyrecipes/ingredient_aggregator'
require_relative 'familyrecipes/ingredient_parser'
require_relative 'familyrecipes/cross_reference'
require_relative 'familyrecipes/line_classifier'
require_relative 'familyrecipes/recipe_builder'
require_relative 'familyrecipes/step'
require_relative 'familyrecipes/recipe'
require_relative 'familyrecipes/quick_bite'
require_relative 'familyrecipes/nutrition_entry_helpers'
require_relative 'familyrecipes/nutrition_calculator'
require_relative 'familyrecipes/vulgar_fractions'
require_relative 'familyrecipes/build_validator'
