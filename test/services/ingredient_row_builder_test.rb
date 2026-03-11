# frozen_string_literal: true

require 'test_helper'

class IngredientRowBuilderTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category(name: 'Bread')
    IngredientCatalog.where(kitchen_id: nil).delete_all

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Sourdough


      ## Mix (combine)

      - Flour, 2 cups
      - Yeast, 1 packet

      Mix well.
    MD
  end

  # --- rows ---

  test 'rows returns sorted ingredient rows from recipes' do
    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    rows = builder.rows

    names = rows.pluck(:name)

    assert_equal names, names.sort_by(&:downcase)
    assert_includes names, 'Flour'
    assert_includes names, 'Salt'
    assert_includes names, 'Yeast'
  end

  test 'rows includes recipe_count and recipe list' do
    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    rows = builder.rows

    flour = rows.find { |r| r[:name] == 'Flour' }
    salt = rows.find { |r| r[:name] == 'Salt' }

    assert_equal 2, flour[:recipe_count]
    assert_equal 1, salt[:recipe_count]
    assert_equal 2, flour[:recipes].size
  end

  test 'rows reflects missing catalog entry' do
    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    rows = builder.rows

    flour = rows.find { |r| r[:name] == 'Flour' }

    assert_equal 'missing', flour[:status]
    assert_equal 'missing', flour[:source]
    assert_nil flour[:entry]
    assert_not flour[:has_nutrition]
  end

  test 'rows reflects incomplete catalog entry (nutrition but no density)' do
    create_catalog_entry('Flour', basis_grams: 30)

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    rows = builder.rows

    flour = rows.find { |r| r[:name] == 'Flour' }

    assert_equal 'incomplete', flour[:status]
    assert_equal 'global', flour[:source]
    assert flour[:has_nutrition]
    assert_not flour[:has_density]
  end

  test 'rows reflects complete catalog entry' do
    create_catalog_entry('Flour', basis_grams: 30)
    entry = IngredientCatalog.find_by(ingredient_name: 'Flour', kitchen_id: nil)
    entry.update!(density_grams: 125, density_volume: 1, density_unit: 'cup')

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    rows = builder.rows

    flour = rows.find { |r| r[:name] == 'Flour' }

    assert_equal 'complete', flour[:status]
    assert flour[:has_nutrition]
    assert flour[:has_density]
  end

  test 'rows shows custom source for kitchen-scoped entry' do
    IngredientCatalog.create!(
      kitchen: @kitchen, ingredient_name: 'Flour',
      basis_grams: 30, density_grams: 125, density_volume: 1, density_unit: 'cup'
    )

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    rows = builder.rows

    flour = rows.find { |r| r[:name] == 'Flour' }

    assert_equal 'custom', flour[:source]
  end

  test 'rows includes aisle from catalog entry' do
    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    rows = builder.rows

    flour = rows.find { |r| r[:name] == 'Flour' }

    assert_equal 'Baking', flour[:aisle]
  end

  test 'rows canonicalizes ingredient names through inflector variants' do
    create_catalog_entry('Eggs', basis_grams: 50)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Omelet


      ## Cook (fry)

      - Egg, 2

      Cook.
    MD

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    rows = builder.rows

    names = rows.pluck(:name)

    assert_includes names, 'Eggs'
    assert_not_includes names, 'Egg'
  end

  # --- summary ---

  test 'summary counts statuses correctly' do
    create_catalog_entry('Flour', basis_grams: 30)
    entry = IngredientCatalog.find_by(ingredient_name: 'Flour', kitchen_id: nil)
    entry.update!(density_grams: 125, density_volume: 1, density_unit: 'cup')

    create_catalog_entry('Salt', basis_grams: 6)

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    summary = builder.summary

    assert_equal 3, summary[:total]
    assert_equal 1, summary[:complete]
    assert_equal 1, summary[:missing_nutrition]
    assert_equal 2, summary[:missing_density]
  end

  # --- next_needing_attention ---

  test 'next_needing_attention finds next incomplete ingredient after given name' do
    create_catalog_entry('Flour', basis_grams: 30)
    entry = IngredientCatalog.find_by(ingredient_name: 'Flour', kitchen_id: nil)
    entry.update!(density_grams: 125, density_volume: 1, density_unit: 'cup')

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    next_name = builder.next_needing_attention(after: 'Flour')

    assert_equal 'Salt', next_name
  end

  test 'next_needing_attention returns nil when no more incomplete ingredients' do
    create_catalog_entry('Flour', basis_grams: 30)
    entry_f = IngredientCatalog.find_by(ingredient_name: 'Flour', kitchen_id: nil)
    entry_f.update!(density_grams: 125, density_volume: 1, density_unit: 'cup')

    create_catalog_entry('Salt', basis_grams: 6)
    entry_s = IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)
    entry_s.update!(density_grams: 6, density_volume: 1, density_unit: 'tsp')

    create_catalog_entry('Yeast', basis_grams: 3)
    entry_y = IngredientCatalog.find_by(ingredient_name: 'Yeast', kitchen_id: nil)
    entry_y.update!(density_grams: 4, density_volume: 1, density_unit: 'packet')

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    next_name = builder.next_needing_attention(after: 'Yeast')

    assert_nil next_name
  end

  test 'next_needing_attention returns nil for unknown ingredient' do
    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    next_name = builder.next_needing_attention(after: 'Nonexistent')

    assert_nil next_name
  end

  # --- precomputed resolver ---

  test 'accepts precomputed resolver to avoid redundant query' do
    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
    resolver = IngredientCatalog.resolver_for(@kitchen)

    builder = IngredientRowBuilder.new(kitchen: @kitchen, resolver:)
    rows = builder.rows

    flour = rows.find { |r| r[:name] == 'Flour' }

    assert_equal 'Baking', flour[:aisle]
    assert_equal 'global', flour[:source]
  end

  # --- explicit recipes scope ---

  test 'accepts explicit recipes scope' do
    focaccia = @kitchen.recipes.find_by!(slug: 'focaccia')
    builder = IngredientRowBuilder.new(kitchen: @kitchen, recipes: [focaccia])
    rows = builder.rows

    names = rows.pluck(:name)

    assert_includes names, 'Flour'
    assert_includes names, 'Salt'
    assert_not_includes names, 'Yeast'
  end

  # --- quick bites ---

  test 'includes quick bite ingredients in rows' do
    @kitchen.update!(quick_bites_content: <<~MD)
      Snacks:
      - Hummus with Pretzels: Hummus, Pretzels
    MD

    rows = IngredientRowBuilder.new(kitchen: @kitchen).rows
    names = rows.pluck(:name)

    assert_includes names, 'Hummus'
    assert_includes names, 'Pretzels'
  end

  test 'quick bite sources count toward recipe_count' do
    @kitchen.update!(quick_bites_content: <<~MD)
      Snacks:
      - Toast: Flour, Butter
    MD

    rows = IngredientRowBuilder.new(kitchen: @kitchen).rows
    flour = rows.find { |r| r[:name] == 'Flour' }

    assert_equal 3, flour[:recipe_count]
  end

  test 'quick bite sources appear as QuickBiteSource in recipes list' do
    @kitchen.update!(quick_bites_content: <<~MD)
      Snacks:
      - Hummus with Pretzels: Hummus, Pretzels
    MD

    rows = IngredientRowBuilder.new(kitchen: @kitchen).rows
    hummus = rows.find { |r| r[:name] == 'Hummus' }

    assert_equal 1, hummus[:recipe_count]
    assert_instance_of IngredientRowBuilder::QuickBiteSource, hummus[:recipes].first
    assert_equal 'Hummus with Pretzels', hummus[:recipes].first.title
  end

  test 'quick bite ingredients are canonicalized through resolver' do
    create_catalog_entry('Eggs', basis_grams: 50)
    @kitchen.update!(quick_bites_content: <<~MD)
      Breakfast:
      - Quick Eggs: Egg, Toast
    MD

    rows = IngredientRowBuilder.new(kitchen: @kitchen).rows
    names = rows.pluck(:name)

    assert_includes names, 'Eggs'
    assert_not_includes names, 'Egg'
  end

  # --- needed_units ---

  test 'needed_units returns units used across recipes' do
    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    units = builder.needed_units('Flour')

    assert_includes units.pluck(:unit), 'cup'
  end

  test 'needed_units marks weight units as resolvable without catalog entry' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Bread by Weight

      ## Mix (combine)

      - Flour, 500 g

      Mix.
    MD

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    units = builder.needed_units('Flour')

    gram_entry = units.find { |u| u[:unit] == 'g' }

    assert gram_entry, 'expected a g unit entry'
    assert gram_entry[:resolvable]
    assert_equal 'weight', gram_entry[:method]
  end

  test 'needed_units marks volume units as unresolvable without density' do
    create_catalog_entry('Flour', basis_grams: 30)

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    units = builder.needed_units('Flour')

    cup_entry = units.find { |u| u[:unit] == 'cup' }

    assert cup_entry, 'expected a cup unit entry'
    assert_not cup_entry[:resolvable]
    assert_equal 'no density', cup_entry[:method]
  end

  test 'needed_units marks volume units as resolvable with density' do
    create_catalog_entry('Flour', basis_grams: 30)
    entry = IngredientCatalog.find_by(ingredient_name: 'Flour', kitchen_id: nil)
    entry.update!(density_grams: 125, density_volume: 1, density_unit: 'cup')

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    units = builder.needed_units('Flour')

    cup_entry = units.find { |u| u[:unit] == 'cup' }

    assert cup_entry, 'expected a cup unit entry'
    assert cup_entry[:resolvable]
    assert_equal 'via density', cup_entry[:method]
  end

  test 'needed_units returns empty array for unknown ingredient' do
    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    units = builder.needed_units('Nonexistent')

    assert_empty units
  end

  # --- coverage ---

  test 'coverage includes summary stats plus resolution data' do
    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    cov = builder.coverage

    assert_equal 3, cov[:total]
    assert cov.key?(:fully_resolvable)
    assert cov.key?(:unresolvable)
  end

  test 'coverage counts fully resolvable ingredients' do
    create_catalog_entry('Flour', basis_grams: 30)
    entry = IngredientCatalog.find_by(ingredient_name: 'Flour', kitchen_id: nil)
    entry.update!(density_grams: 125, density_volume: 1, density_unit: 'cup')

    create_catalog_entry('Salt', basis_grams: 6)
    salt = IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)
    salt.update!(density_grams: 6, density_volume: 1, density_unit: 'tsp')

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    cov = builder.coverage

    assert_equal 2, cov[:fully_resolvable]
  end

  test 'coverage lists unresolvable ingredients with bad units and recipes' do
    create_catalog_entry('Flour', basis_grams: 30)

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    cov = builder.coverage

    flour_entry = cov[:unresolvable].find { |u| u[:name] == 'Flour' }

    assert flour_entry, 'expected Flour in unresolvable list'
    assert(flour_entry[:units].any? { |u| u[:unit] == 'cup' && u[:method] == 'no density' })
    assert_equal 2, flour_entry[:recipes].size
  end

  test 'coverage reports no nutrition data for uncataloged ingredients' do
    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    cov = builder.coverage

    yeast_entry = cov[:unresolvable].find { |u| u[:name] == 'Yeast' }

    assert yeast_entry, 'expected Yeast in unresolvable list'
    assert(yeast_entry[:units].any? { |u| u[:method] == 'no nutrition data' })
  end

  test 'coverage omits fully resolvable ingredients from unresolvable list' do
    create_catalog_entry('Flour', basis_grams: 30)
    entry = IngredientCatalog.find_by(ingredient_name: 'Flour', kitchen_id: nil)
    entry.update!(density_grams: 125, density_volume: 1, density_unit: 'cup')

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    cov = builder.coverage

    assert_nil(cov[:unresolvable].find { |u| u[:name] == 'Flour' })
  end

  # --- needed_units ---

  test 'needed_units marks named portion as resolvable' do
    create_catalog_entry('Yeast', basis_grams: 3)
    entry = IngredientCatalog.find_by(ingredient_name: 'Yeast', kitchen_id: nil)
    entry.update!(portions: { 'packet' => 7.0 })

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    units = builder.needed_units('Yeast')

    packet_entry = units.find { |u| u[:unit] == 'packet' }

    assert packet_entry, 'expected a packet unit entry'
    assert packet_entry[:resolvable]
  end

  test 'needed_units handles bare counts' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Scrambled Eggs

      ## Cook (fry)

      - Eggs, 3

      Cook.
    MD

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    units = builder.needed_units('Eggs')

    bare_entry = units.find { |u| u[:unit].nil? }

    assert bare_entry, 'expected a nil unit entry for bare count'
    assert_not bare_entry[:resolvable]
    assert_equal 'no nutrition data', bare_entry[:method]
  end
end
