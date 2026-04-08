# frozen_string_literal: true

# Shared utilities for the seed catalog pipeline scripts.
# Standalone — no Rails dependency. Uses lib/familyrecipes/ modules
# for USDA portion classification only.

require 'json'
require 'fileutils'

# Load FamilyRecipes domain modules for portion classification.
# These are standalone (no Rails required). The modules assume
# FamilyRecipes is already defined and that Inflector/UnitResolver
# are loaded before UsdaPortionClassifier.
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
module FamilyRecipes; end

# Inflector uses blank? (ActiveSupport) — polyfill for standalone use
unless String.method_defined?(:blank?)
  class String
    def blank?
      strip.empty?
    end
  end
end

require 'familyrecipes/inflector'
require 'familyrecipes/unit_resolver'
require 'familyrecipes/usda_client'
require 'familyrecipes/usda_portion_classifier'

module SeedCatalog
  DATA_DIR = File.expand_path('../../data/seed_catalog', __dir__)

  # --- File I/O ---

  def self.parse_ingredient_list(path)
    category = nil

    File.readlines(path, chomp: true).each_with_object([]) do |line, list|
      if line.start_with?('## ')
        category = line.delete_prefix('## ').strip
      elsif line.start_with?('- ')
        name = line.delete_prefix('- ').strip
        list << { name: name, category: category } unless name.empty?
      end
    end
  end

  def self.read_json(path)
    return [] unless File.exist?(path)

    JSON.parse(File.read(path))
  end

  def self.write_json(path, data)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(data))
  end

  # --- Catalog Entry Builder ---

  # Transforms a UsdaClient#fetch detail hash into a hash matching
  # the ingredient-catalog.yaml schema. Uses UsdaPortionClassifier
  # for density and portion extraction.
  def self.build_catalog_entry(detail, aisle:, aliases: [])
    entry = {}
    entry['nutrients'] = build_nutrients(detail[:nutrients])
    entry['sources'] = [build_source(detail)]
    add_density_and_portions(entry, detail[:portions])
    entry['aisle'] = aisle
    entry['aliases'] = aliases unless aliases.empty?
    entry
  end

  def self.build_nutrients(raw)
    raw.transform_keys(&:to_s).slice(
      'basis_grams', 'calories', 'fat', 'saturated_fat', 'trans_fat',
      'cholesterol', 'sodium', 'carbs', 'fiber', 'total_sugars',
      'protein', 'added_sugars'
    )
  end
  private_class_method :build_nutrients

  def self.build_source(detail)
    {
      'type' => 'usda',
      'dataset' => detail[:data_type],
      'fdc_id' => detail[:fdc_id].to_s.to_i,
      'description' => detail[:description]
    }
  end
  private_class_method :build_source

  def self.add_density_and_portions(entry, raw_portions)
    return if raw_portions.nil? || raw_portions.empty?

    classified = FamilyRecipes::UsdaPortionClassifier.classify(raw_portions)
    add_density(entry, classified.density_candidates)
    add_portions(entry, classified.portion_candidates)
  end
  private_class_method :add_density_and_portions

  def self.add_density(entry, candidates)
    best = FamilyRecipes::UsdaPortionClassifier.pick_best_density(candidates)
    return unless best

    unit = FamilyRecipes::UsdaPortionClassifier.normalize_volume_unit(best[:modifier])
    entry['density'] = { 'grams' => best[:each].round(2), 'volume' => 1.0, 'unit' => unit }
  end
  private_class_method :add_density

  def self.add_portions(entry, candidates)
    return if candidates.empty?

    entry['portions'] = candidates.each_with_object({}) do |p, h|
      name = FamilyRecipes::UsdaPortionClassifier.strip_parenthetical(p[:modifier]).strip
      h[name] = p[:each].round(2)
    end
  end
  private_class_method :add_portions
end
