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
    skip 'ingredient-catalog.yaml is empty' if catalog_data.blank?

    failures = catalog_data.filter_map do |name, entry|
      record = IngredientCatalog.new(ingredient_name: name, **IngredientCatalog.attrs_from_yaml(entry))
      "#{name}: #{record.errors.full_messages.join('; ')}" unless record.valid?
    end

    assert_empty failures,
                 "#{failures.size} catalog entries failed validation:\n  #{failures.join("\n  ")}"
  end

  test 'sync preserves aliases from YAML entries' do
    IngredientCatalog.where(kitchen_id: nil).delete_all

    yaml_content = {
      'Flour (all-purpose)' => {
        'aisle' => 'Baking',
        'aliases' => ['AP flour', 'Plain flour'],
        'nutrients' => { 'basis_grams' => 30, 'calories' => 110 }
      }
    }

    yaml_content.each do |name, entry|
      profile = IngredientCatalog.find_or_initialize_by(kitchen_id: nil, ingredient_name: name)
      profile.assign_attributes(IngredientCatalog.attrs_from_yaml(entry))
      profile.save!
    end

    record = IngredientCatalog.find_by!(kitchen_id: nil, ingredient_name: 'Flour (all-purpose)')

    assert_equal ['AP flour', 'Plain flour'], record.aliases
  end

  test 'AliasCollisionDetector reports alias-vs-alias collisions' do
    collisions = AliasCollisionDetector.detect(
      'Salt (Table)' => { 'aliases' => ['Kosher salt'], 'aisle' => 'Baking' },
      'Salt (Kosher)' => { 'aliases' => ['Kosher salt'], 'aisle' => 'Baking' }
    )

    assert_equal 1, collisions.size
    assert_match(/Kosher salt/, collisions.first)
  end

  test 'AliasCollisionDetector reports alias-vs-canonical collisions' do
    collisions = AliasCollisionDetector.detect(
      'Butter' => { 'aisle' => 'Dairy' },
      'Ghee' => { 'aliases' => ['Butter'], 'aisle' => 'Dairy' }
    )

    assert_equal 1, collisions.size
    assert_match(/canonical/, collisions.first)
  end

  test 'AliasCollisionDetector reports no collisions for clean data' do
    collisions = AliasCollisionDetector.detect(
      'Salt (Table)' => { 'aliases' => ['Table salt'], 'aisle' => 'Baking' },
      'Salt (Kosher)' => { 'aliases' => ['Kosher salt'], 'aisle' => 'Baking' }
    )

    assert_empty collisions
  end

  test 'catalog aliases do not collide with other entries' do
    catalog_data = YAML.safe_load_file(CATALOG_PATH, permitted_classes: [], permitted_symbols: [], aliases: false)
    skip 'ingredient-catalog.yaml is empty' if catalog_data.blank?

    canonical_names = catalog_data.keys.map(&:downcase).to_set
    alias_owners = {}
    collisions = []

    catalog_data.each do |name, entry|
      (entry['aliases'] || []).each do |alias_name|
        lowered = alias_name.downcase

        if canonical_names.include?(lowered)
          collisions << "#{name}: alias '#{alias_name}' matches canonical entry"
        elsif alias_owners.key?(lowered)
          collisions << "#{name}: alias '#{alias_name}' also claimed by '#{alias_owners[lowered]}'"
        else
          alias_owners[lowered] = name
        end
      end
    end

    assert_empty collisions,
                 "#{collisions.size} alias collision(s):\n  #{collisions.join("\n  ")}"
  end
end
