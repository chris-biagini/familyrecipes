# frozen_string_literal: true

require 'erb'
require 'redcarpet'
require 'json'
require 'yaml'

# Root module for the recipe parser pipeline — a pure-Ruby domain layer that
# knows nothing about Rails. Parses Markdown recipe files into structured value
# objects (Recipe, Step, Ingredient, CrossReference, QuickBite) and computes
# nutrition data. Loaded once at boot via config/initializers/mirepoix.rb, not
# through Zeitwerk (see config/application.rb autoload_lib ignore list).
module Mirepoix
  # Raised by parser pipeline components (RecipeBuilder, IngredientParser,
  # CrossReferenceParser) for structurally invalid input. Controllers rescue
  # this specifically instead of broad RuntimeError.
  class ParseError < RuntimeError; end

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

  def self.normalize_for_comparison(str)
    return '' if str.nil?

    str.tr("\u2018\u2019\u201C\u201D", "''\"\"")
  end

  QuickBitesResult = Data.define(:quick_bites, :warnings)

  def self.parse_quick_bites_content(content) # rubocop:disable Metrics/MethodLength
    current_subcat = nil
    quick_bites = []
    warnings = []

    content.each_line.with_index(1) do |line, line_number|
      stripped = line.strip
      next if stripped.empty?

      case line
      when /^\s*-\s+(.*)/
        category = [CONFIG[:quick_bites_category], current_subcat].compact.join(': ')
        quick_bites << QuickBite.new(text_source: ::Regexp.last_match(1).strip, category: category)
      when /^##\s+(.+)$/
        current_subcat = ::Regexp.last_match(1).strip
      else
        warnings << "Line #{line_number} not recognized"
      end
    end

    QuickBitesResult.new(quick_bites:, warnings:)
  end

  def self.parse_quick_bites(recipes_dir)
    file_path = File.join(recipes_dir, CONFIG[:quick_bites_filename])
    parse_quick_bites_content(File.read(file_path, encoding: 'utf-8')).quick_bites
  end
end

require_relative 'mirepoix/numeric_parsing'
require_relative 'mirepoix/quantity'
require_relative 'mirepoix/scalable_number_preprocessor'
require_relative 'mirepoix/inflector'
require_relative 'mirepoix/ingredient'
require_relative 'mirepoix/ingredient_aggregator'
require_relative 'mirepoix/ingredient_parser'
require_relative 'mirepoix/cross_reference_parser'
require_relative 'mirepoix/cross_reference'
require_relative 'mirepoix/line_classifier'
require_relative 'mirepoix/recipe_builder'
require_relative 'mirepoix/recipe_serializer'
require_relative 'mirepoix/step'
require_relative 'mirepoix/recipe'
require_relative 'mirepoix/quick_bite'
require_relative 'mirepoix/quick_bites_serializer'
require_relative 'mirepoix/nutrition_constraints'
require_relative 'mirepoix/unit_resolver'
require_relative 'mirepoix/nutrition_calculator'
require_relative 'mirepoix/vulgar_fractions'
require_relative 'mirepoix/build_validator'
require_relative 'mirepoix/usda_client'
require_relative 'mirepoix/usda_portion_classifier'
require_relative 'mirepoix/smart_tag_registry'
require_relative 'mirepoix/logger_delivery'
