# frozen_string_literal: true

# This file handles loading all required libraries and classes

# libraries

require 'erb'
require 'redcarpet'
require 'digest'
require 'json'
require 'yaml'

# Shared utilities
module FamilyRecipes
  CONFIG = {
    quick_bites_filename: 'Quick Bites.md',
    quick_bites_category: 'Quick Bites'
  }.freeze

  # Generate a URL-safe slug from a title string
  def self.slugify(title)
    title
      .unicode_normalize(:nfkd)
      .downcase
      .gsub(/\s+/, '-')
      .gsub(/[^a-z0-9-]/, '')
  end

  # Parse grocery-info.yaml into structured data
  # Items can be simple strings or hashes with 'name' and 'aliases' keys
  def self.parse_grocery_info(yaml_path)
    raw = YAML.safe_load_file(yaml_path, permitted_classes: [], permitted_symbols: [], aliases: false)

    raw.transform_values do |items|
      items.map do |item|
        if item.is_a?(Hash)
          { name: item['name'], aliases: item['aliases'] || [] }
        else
          { name: item, aliases: [] }
        end
      end
    end
  end

  # Parse grocery aisles from markdown into structured data
  # Uses ## headings as aisle names and - items as ingredients
  def self.parse_grocery_aisles_markdown(content)
    current_aisle = nil

    content.each_line.with_object({}) do |line, aisles|
      case line
      when /^##\s+(.*)/
        current_aisle = ::Regexp.last_match(1).strip
        aisles[current_aisle] = []
      when /^\s*-\s+(.*)/
        next unless current_aisle

        aisles[current_aisle] << { name: ::Regexp.last_match(1).strip }
      end
    end
  end

  # Build a reverse lookup map: alias -> canonical name (all keys downcased)
  def self.build_alias_map(grocery_aisles)
    grocery_aisles.each_value.with_object({}) do |items, alias_map|
      items.each do |item|
        canonical = item[:name]

        alias_map[canonical.downcase] = canonical

        (item[:aliases] || []).each { |al| alias_map[al.downcase] = canonical }

        singular = Inflector.singular(canonical)
        alias_map[singular.downcase] = canonical unless singular.downcase == canonical.downcase

        (item[:aliases] || []).each do |al|
          singular = Inflector.singular(al)
          alias_map[singular.downcase] = canonical unless singular.downcase == al.downcase
        end
      end
    end
  end

  # Build set of all known ingredient names (all entries downcased)
  def self.build_known_ingredients(grocery_aisles, alias_map)
    grocery_aisles.each_value.with_object(Set.new) do |items, known|
      items.each do |item|
        known << item[:name].downcase
        (item[:aliases] || []).each { |al| known << al.downcase }
      end
    end.merge(alias_map.keys)
  end

  # Parse all recipe files from the given directory into Recipe objects
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

  # Parse Quick Bites file into QuickBite objects
  def self.parse_quick_bites(recipes_dir)
    quick_bites_filename = CONFIG[:quick_bites_filename]
    quick_bites_category = CONFIG[:quick_bites_category]
    file_path = File.join(recipes_dir, quick_bites_filename)

    quick_bites = []
    current_subcat = nil

    File.foreach(file_path) do |line|
      case line
      when /^##\s+(.*)/
        current_subcat = ::Regexp.last_match(1).strip
      when /^\s*-\s+(.*)/
        category = [quick_bites_category, current_subcat].compact.join(': ')
        quick_bites << QuickBite.new(text_source: ::Regexp.last_match(1).strip, category: category)
      end
    end

    quick_bites
  end
end

# my classes

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
