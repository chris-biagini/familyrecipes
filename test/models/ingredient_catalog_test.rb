# frozen_string_literal: true

require 'test_helper'

class IngredientCatalogTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    IngredientCatalog.where(kitchen_id: [@kitchen.id, nil]).delete_all
  end

  test 'global? returns true when kitchen_id is nil' do
    entry = IngredientCatalog.create!(ingredient_name: 'Butter', basis_grams: 100)

    assert_predicate entry, :global?
    assert_not_predicate entry, :custom?
  end

  test 'custom? returns true when kitchen_id is present' do
    entry = IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Butter', basis_grams: 100)

    assert_not_predicate entry, :global?
    assert_predicate entry, :custom?
  end

  test 'lookup_for returns global entries when no kitchen overrides' do
    IngredientCatalog.create!(ingredient_name: 'Butter', basis_grams: 100, calories: 717)
    result = IngredientCatalog.lookup_for(@kitchen)

    assert_equal 2, result.size
    assert_in_delta 717, result['Butter'].calories.to_f
    assert_predicate result['Butter'], :global?
  end

  test 'lookup_for returns kitchen override when it exists' do
    IngredientCatalog.create!(ingredient_name: 'Butter', basis_grams: 100, calories: 717)
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Butter', basis_grams: 100, calories: 700)

    result = IngredientCatalog.lookup_for(@kitchen)

    assert_equal 2, result.size
    assert_in_delta 700, result['Butter'].calories.to_f
    assert_predicate result['Butter'], :custom?
  end

  test 'lookup_for merges global and kitchen entries' do
    IngredientCatalog.create!(ingredient_name: 'Butter', basis_grams: 100)
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30)

    result = IngredientCatalog.lookup_for(@kitchen)

    assert_equal 4, result.size
    assert result.key?('Butter')
    assert result.key?('Flour')
  end

  test 'lookup_for does not return entries from other kitchens' do
    other = Kitchen.find_or_create_by!(name: 'Other Kitchen', slug: 'other-kitchen')
    IngredientCatalog.create!(kitchen: other, ingredient_name: 'Butter', basis_grams: 100)

    result = IngredientCatalog.lookup_for(@kitchen)

    assert_empty result
  end

  test 'stores nutrient data for an ingredient' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour (all-purpose)',
      basis_grams: 30.0,
      calories: 110.0,
      fat: 0.5,
      saturated_fat: 0.0,
      trans_fat: 0.0,
      cholesterol: 0.0,
      sodium: 0.0,
      carbs: 23.0,
      fiber: 1.0,
      total_sugars: 0.0,
      added_sugars: 0.0,
      protein: 3.0
    )

    entry.reload

    assert_equal 'Flour (all-purpose)', entry.ingredient_name
    assert_in_delta 30.0, entry.basis_grams.to_f
    assert_in_delta 110.0, entry.calories.to_f
    assert_in_delta 0.5, entry.fat.to_f
    assert_in_delta 23.0, entry.carbs.to_f
    assert_in_delta 1.0, entry.fiber.to_f
    assert_in_delta 3.0, entry.protein.to_f
  end

  test 'stores zero-value nutrients correctly' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour (all-purpose)',
      basis_grams: 30.0,
      saturated_fat: 0.0,
      trans_fat: 0.0,
      cholesterol: 0.0,
      sodium: 0.0,
      total_sugars: 0.0,
      added_sugars: 0.0
    )

    entry.reload

    assert_in_delta 0.0, entry.saturated_fat.to_f
    assert_in_delta 0.0, entry.trans_fat.to_f
    assert_in_delta 0.0, entry.cholesterol.to_f
    assert_in_delta 0.0, entry.sodium.to_f
    assert_in_delta 0.0, entry.total_sugars.to_f
    assert_in_delta 0.0, entry.added_sugars.to_f
  end

  test 'stores density data' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour (all-purpose)',
      basis_grams: 30.0,
      density_grams: 30.0,
      density_volume: 0.25,
      density_unit: 'cup'
    )

    entry.reload

    assert_in_delta 30.0, entry.density_grams.to_f
    assert_in_delta 0.25, entry.density_volume.to_f
    assert_equal 'cup', entry.density_unit
  end

  test 'stores portions as JSON' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Butter',
      basis_grams: 14.0,
      portions: { 'stick' => 113.0 }
    )

    entry.reload

    assert_equal({ 'stick' => 113.0 }, entry.portions)
  end

  test 'stores sources as JSON array' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Cream cheese',
      basis_grams: 28.0,
      sources: [{ 'type' => 'usda', 'fdc_id' => 173_530 }]
    )

    entry.reload

    assert_equal [{ 'type' => 'usda', 'fdc_id' => 173_530 }], entry.sources
  end

  test 'validates ingredient_name presence' do
    entry = IngredientCatalog.new(basis_grams: 100)

    assert_not_predicate entry, :valid?
    assert_includes entry.errors[:ingredient_name], "can't be blank"
  end

  test 'allows nil basis_grams for aisle-only rows' do
    entry = IngredientCatalog.new(ingredient_name: 'Egg yolk')

    assert_predicate entry, :valid?
  end

  test 'rejects zero basis_grams' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', basis_grams: 0)

    assert_not_predicate entry, :valid?
  end

  test 'rejects negative basis_grams' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', basis_grams: -5)

    assert_not_predicate entry, :valid?
  end

  test 'enforces uniqueness of ingredient_name within same kitchen' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Butter', basis_grams: 100)
    duplicate = IngredientCatalog.new(kitchen: @kitchen, ingredient_name: 'Butter', basis_grams: 100)

    assert_not_predicate duplicate, :valid?
  end

  test 'allows same ingredient_name in different kitchens' do
    other = Kitchen.find_or_create_by!(name: 'Other Kitchen', slug: 'other-kitchen')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Butter', basis_grams: 100)
    entry = IngredientCatalog.new(kitchen: other, ingredient_name: 'Butter', basis_grams: 100)

    assert_predicate entry, :valid?
  end

  test 'allows same ingredient_name as global and kitchen entry' do
    IngredientCatalog.create!(ingredient_name: 'Butter', basis_grams: 100)
    entry = IngredientCatalog.new(kitchen: @kitchen, ingredient_name: 'Butter', basis_grams: 100)

    assert_predicate entry, :valid?
  end

  test 'allows aisle-only rows without basis_grams' do
    entry = IngredientCatalog.new(ingredient_name: 'Egg yolk', aisle: 'Refrigerated')

    assert_predicate entry, :valid?
  end

  test 'stores aisle data' do
    entry = IngredientCatalog.create!(ingredient_name: 'Flour', basis_grams: 30, aisle: 'Baking')
    entry.reload

    assert_equal 'Baking', entry.aisle
  end

  test 'lookup_for resolves singular variant of plural catalog name' do
    IngredientCatalog.create!(ingredient_name: 'Eggs', basis_grams: 50, calories: 70)
    result = IngredientCatalog.lookup_for(@kitchen)

    assert result.key?('Eggs'), 'exact key should exist'
    assert result.key?('Egg'), 'singular variant should resolve'
    assert_equal result['Eggs'].id, result['Egg'].id
  end

  test 'lookup_for resolves plural variant of singular catalog name' do
    IngredientCatalog.create!(ingredient_name: 'Carrot', basis_grams: 50, calories: 25)
    result = IngredientCatalog.lookup_for(@kitchen)

    assert result.key?('Carrot'), 'exact key should exist'
    assert result.key?('Carrots'), 'plural variant should resolve'
    assert_equal result['Carrot'].id, result['Carrots'].id
  end

  test 'lookup_for does not overwrite explicit entry with variant' do
    eggs_entry = IngredientCatalog.create!(ingredient_name: 'Eggs', basis_grams: 50, calories: 70)
    egg_entry = IngredientCatalog.create!(ingredient_name: 'Egg', basis_grams: 50, calories: 80)
    result = IngredientCatalog.lookup_for(@kitchen)

    assert_equal eggs_entry.id, result['Eggs'].id
    assert_equal egg_entry.id, result['Egg'].id
  end

  test 'lookup_for includes variants for mass nouns' do
    IngredientCatalog.create!(ingredient_name: 'Butter', basis_grams: 14)
    result = IngredientCatalog.lookup_for(@kitchen)

    assert result.key?('Butter')
    assert result.key?('Butters')
    assert_equal 2, result.size
  end

  test 'lookup_for handles qualified names with variants' do
    IngredientCatalog.create!(ingredient_name: 'Tomatoes (canned)', basis_grams: 100)
    result = IngredientCatalog.lookup_for(@kitchen)

    assert result.key?('Tomatoes (canned)')
    assert result.key?('Tomato (canned)')
  end

  test 'lookup_for kitchen override applies to variants too' do
    IngredientCatalog.create!(ingredient_name: 'Eggs', basis_grams: 50, calories: 70)
    kitchen_entry = IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Eggs', basis_grams: 50, calories: 80)
    result = IngredientCatalog.lookup_for(@kitchen)

    assert_equal kitchen_entry.id, result['Egg'].id
  end

  # --- validation: nutrients_require_basis_grams ---

  test 'rejects nutrient values without basis_grams' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', calories: 100)

    assert_not_predicate entry, :valid?
    assert_includes entry.errors[:basis_grams].join, 'required when nutrient values are present'
  end

  test 'allows nil nutrients without basis_grams' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', aisle: 'Baking')

    assert_predicate entry, :valid?
  end

  # --- validation: nutrient_values_in_range ---

  test 'rejects negative nutrient values' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', basis_grams: 100, calories: -5)

    assert_not_predicate entry, :valid?
    assert(entry.errors[:calories].any? { |e| e.include?('between 0 and 10000') })
  end

  test 'rejects nutrient values over default cap' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', basis_grams: 100, calories: 10_001)

    assert_not_predicate entry, :valid?
    assert(entry.errors[:calories].any? { |e| e.include?('between 0 and 10000') })
  end

  test 'sodium allows higher values than default cap' do
    entry = IngredientCatalog.new(ingredient_name: 'Salt', basis_grams: 100, sodium: 38_758)

    assert_predicate entry, :valid?
  end

  test 'rejects sodium over 50000' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', basis_grams: 100, sodium: 50_001)

    assert_not_predicate entry, :valid?
    assert(entry.errors[:sodium].any? { |e| e.include?('between 0 and 50000') })
  end

  test 'allows nutrient values at boundaries' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', basis_grams: 100, calories: 0, sodium: 10_000)

    assert_predicate entry, :valid?
  end

  # --- validation: density_completeness ---

  test 'rejects partial density — missing grams' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', density_volume: 1, density_unit: 'cup')

    assert_not_predicate entry, :valid?
    assert_includes entry.errors[:density_grams].join, 'required'
  end

  test 'rejects partial density — missing unit' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', density_volume: 1, density_grams: 120)

    assert_not_predicate entry, :valid?
    assert_includes entry.errors[:density_unit].join, 'required'
  end

  test 'allows complete density' do
    entry = IngredientCatalog.new(
      ingredient_name: 'Test', density_volume: 1, density_unit: 'cup', density_grams: 120
    )

    assert_predicate entry, :valid?
  end

  test 'allows no density fields at all' do
    entry = IngredientCatalog.new(ingredient_name: 'Test')

    assert_predicate entry, :valid?
  end

  # --- validation: portion_values_positive ---

  test 'rejects zero portion value' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', portions: { 'stick' => 0 })

    assert_not_predicate entry, :valid?
    assert(entry.errors[:portions].any? { |e| e.include?('stick') })
  end

  test 'rejects negative portion value' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', portions: { 'each' => -10 })

    assert_not_predicate entry, :valid?
  end

  test 'allows positive portion values' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', portions: { 'stick' => 113 })

    assert_predicate entry, :valid?
  end

  # --- validation: aisle length ---

  test 'rejects aisle name over max length' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', aisle: 'a' * 51)

    assert_not_predicate entry, :valid?
    assert(entry.errors[:aisle].any? { |e| e.include?('too long') })
  end

  test 'allows aisle name at max length' do
    entry = IngredientCatalog.new(ingredient_name: 'Test', aisle: 'a' * 50)

    assert_predicate entry, :valid?
  end

  # --- callback: normalize_portion_keys ---

  test 'normalize_portion_keys converts each to ~unitless on save' do
    entry = IngredientCatalog.create!(
      kitchen: @kitchen, ingredient_name: 'Eggs',
      portions: { 'each' => 50, 'stick' => 113 }
    )

    assert_equal 50, entry.portions['~unitless']
    assert_equal 113, entry.portions['stick']
    assert_nil entry.portions['each']
  end

  test 'normalize_portion_keys converts Each to ~unitless on save' do
    entry = IngredientCatalog.create!(
      kitchen: @kitchen, ingredient_name: 'Rolls',
      portions: { 'Each' => 60 }
    )

    assert_equal 60, entry.portions['~unitless']
    assert_nil entry.portions['Each']
  end

  # --- assign_from_params ---

  test 'assign_from_params sets nutrients' do
    entry = IngredientCatalog.new(kitchen: @kitchen, ingredient_name: 'Flour')
    entry.assign_from_params(
      nutrients: { basis_grams: 30, calories: 110, fat: 0.5 },
      density: {}, portions: {}, aisle: nil,
      sources: [{ 'type' => 'web' }]
    )

    assert_in_delta 30.0, entry.basis_grams
    assert_in_delta 110.0, entry.calories
    assert_in_delta 0.5, entry.fat
  end

  test 'assign_from_params sets density' do
    entry = IngredientCatalog.new(kitchen: @kitchen, ingredient_name: 'Flour')
    entry.assign_from_params(
      nutrients: {}, density: { volume: 0.25, unit: 'cup', grams: 30 },
      portions: {}, aisle: nil, sources: []
    )

    assert_in_delta 0.25, entry.density_volume
    assert_equal 'cup', entry.density_unit
    assert_in_delta 30.0, entry.density_grams
  end

  test 'assign_from_params clears density when blank' do
    entry = IngredientCatalog.create!(
      kitchen: @kitchen, ingredient_name: 'Flour',
      density_volume: 0.25, density_unit: 'cup', density_grams: 30
    )
    entry.assign_from_params(
      nutrients: {}, density: {}, portions: {}, aisle: nil, sources: []
    )

    assert_nil entry.density_volume
    assert_nil entry.density_unit
    assert_nil entry.density_grams
  end

  test 'assign_from_params normalizes each in portions' do
    entry = IngredientCatalog.new(kitchen: @kitchen, ingredient_name: 'Eggs')
    entry.assign_from_params(
      nutrients: {}, density: {},
      portions: { 'each' => 50 },
      aisle: nil, sources: []
    )

    assert_equal 50, entry.portions['~unitless']
    assert_nil entry.portions['each']
  end

  test 'assign_from_params sets aisle when present' do
    entry = IngredientCatalog.new(kitchen: @kitchen, ingredient_name: 'Flour')
    entry.assign_from_params(
      nutrients: {}, density: {}, portions: {},
      aisle: 'Baking', sources: []
    )

    assert_equal 'Baking', entry.aisle
  end

  test 'assign_from_params skips aisle when nil' do
    entry = IngredientCatalog.new(kitchen: @kitchen, ingredient_name: 'Flour', aisle: 'Existing')
    entry.assign_from_params(
      nutrients: {}, density: {}, portions: {},
      aisle: nil, sources: []
    )

    assert_equal 'Existing', entry.aisle
  end

  test 'assign_from_params sets sources' do
    entry = IngredientCatalog.new(kitchen: @kitchen, ingredient_name: 'Flour')
    entry.assign_from_params(
      nutrients: {}, density: {}, portions: {},
      aisle: nil, sources: [{ 'type' => 'web', 'note' => 'test' }]
    )

    assert_equal [{ 'type' => 'web', 'note' => 'test' }], entry.sources
  end
end
