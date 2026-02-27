# frozen_string_literal: true

require 'test_helper'

class CatalogSyncTest < ActiveSupport::TestCase
  CATALOG_PATH = Rails.root.join('db/seeds/resources/ingredient-catalog.yaml')

  test 'catalog YAML file exists' do
    assert_predicate CATALOG_PATH, :exist?, "Expected #{CATALOG_PATH} to exist"
  end

  test 'catalog entries have unique names' do
    raw_keys = CATALOG_PATH.readlines
                           .select { |line| line.match?(/\A\S/) && line.strip.end_with?(':') }
                           .map { |line| line.strip.chomp(':') }

    duplicates = raw_keys.tally.select { |_, count| count > 1 }

    assert_empty duplicates,
                 "Duplicate ingredient names in YAML: #{duplicates.keys.join(', ')}"
  end

  test 'all catalog entries pass model validations' do
    catalog_data = YAML.safe_load_file(CATALOG_PATH, permitted_classes: [], permitted_symbols: [], aliases: false)

    failures = catalog_data.filter_map do |name, entry|
      record = IngredientCatalog.new(ingredient_name: name, **build_attrs(entry))
      "#{name}: #{record.errors.full_messages.join('; ')}" unless record.valid?
    end

    assert_empty failures,
                 "#{failures.size} catalog entries failed validation:\n  #{failures.join("\n  ")}"
  end

  private

  def build_attrs(entry)
    attrs = { aisle: entry['aisle'] }

    if (nutrients = entry['nutrients'])
      attrs.merge!(
        basis_grams: nutrients['basis_grams'],
        calories: nutrients['calories'],
        fat: nutrients['fat'],
        saturated_fat: nutrients['saturated_fat'],
        trans_fat: nutrients['trans_fat'],
        cholesterol: nutrients['cholesterol'],
        sodium: nutrients['sodium'],
        carbs: nutrients['carbs'],
        fiber: nutrients['fiber'],
        total_sugars: nutrients['total_sugars'],
        added_sugars: nutrients['added_sugars'],
        protein: nutrients['protein']
      )
    end

    if (density = entry['density'])
      attrs.merge!(
        density_grams: density['grams'],
        density_volume: density['volume'],
        density_unit: density['unit']
      )
    end

    attrs[:portions] = entry['portions'] || {}
    attrs[:sources] = entry['sources'] || []

    attrs
  end
end
