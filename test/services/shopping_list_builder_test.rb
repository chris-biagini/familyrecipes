# frozen_string_literal: true

require 'test_helper'

class ShoppingListBuilderTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Salt') do |p|
      p.basis_grams = 6
      p.aisle = 'Spices'
    end
  end

  test 'builds shopping list organized by aisle' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

    assert result.key?('Baking'), "Expected 'Baking' aisle"
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    assert flour, 'Expected Flour in Baking aisle'
  end

  test 'puts unmapped ingredients in Miscellaneous' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: nil)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

    assert result.key?('Miscellaneous')
    salt = result['Miscellaneous'].find { |i| i[:name] == 'Salt' }

    assert salt, 'Expected Salt in Miscellaneous'
  end

  test 'omits ingredients with aisle omit' do
    IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: 'omit')
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
    all_names = result.values.flatten.pluck(:name)

    assert_not_includes all_names, 'Salt'
  end

  test 'includes custom items in Miscellaneous' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
    custom = result['Miscellaneous'].find { |i| i[:name] == 'birthday candles' }

    assert custom
    assert_empty custom[:amounts]
  end

  test 'empty list returns empty hash' do
    list = MealPlan.for_kitchen(@kitchen)
    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

    assert_empty result
  end

  test 'aggregates quantities from multiple recipes' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Sourdough

      Category: Bread

      ## Mix (combine)

      - Flour, 2 cups
      - Salt, 0.5 tsp

      Mix well.
    MD

    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    list.apply_action('select', type: 'recipe', slug: 'sourdough', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    assert flour, 'Expected Flour in Baking aisle'
    flour_cup = flour[:amounts].find { |_v, u| u == 'cup' }

    assert_in_delta 5.0, flour_cup[0], 0.01
  end

  test 'respects kitchen aisle_order for sorting' do
    @kitchen.update!(aisle_order: "Spices\nBaking")
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
    aisle_names = result.keys

    assert_equal 'Spices', aisle_names[0]
    assert_equal 'Baking', aisle_names[1]
  end

  test 'unordered aisles appear after ordered aisles alphabetically' do
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Eggs') do |p|
      p.basis_grams = 50
      p.aisle = 'Refrigerated'
    end

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Scramble

      Category: Bread

      ## Cook (scramble)

      - Eggs, 3
      - Flour, 1 cup
      - Salt, 1 tsp

      Cook.
    MD

    @kitchen.update!(aisle_order: "Spices\nBaking")
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'scramble', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
    aisle_names = result.keys

    assert_equal %w[Spices Baking Refrigerated], aisle_names
  end

  test 'Miscellaneous sorts last even with aisle_order' do
    IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: nil)
    @kitchen.update!(aisle_order: 'Baking')

    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

    assert_equal 'Miscellaneous', result.keys.last
  end

  test 'Miscellaneous respects explicit position in aisle_order' do
    IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: nil)
    @kitchen.update!(aisle_order: "Miscellaneous\nBaking")

    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

    assert_equal %w[Miscellaneous Baking], result.keys
  end

  test 'falls back to alphabetical when aisle_order is nil' do
    @kitchen.update!(aisle_order: nil)
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
    aisle_names = result.keys

    assert_equal %w[Baking Spices], aisle_names
  end

  test 'includes quick bite ingredients when selected' do
    @kitchen.update!(quick_bites_content: <<~MD)
      ## Snacks
        - Hummus with Pretzels: Hummus, Pretzels
    MD

    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'quick_bite', slug: 'hummus-with-pretzels', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

    all_names = result.values.flatten.pluck(:name)

    assert_includes all_names, 'Hummus'
    assert_includes all_names, 'Pretzels'
  end

  test 'includes cross-referenced recipe ingredients in shopping list' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Poolish

      Category: Bread

      ## Mix (combine)

      - Flour, 1 cup
      - Water, 1 cup

      Mix.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Pizza

      Category: Bread

      ## Dough (assemble)

      - Salt, 1 tsp
      - @[Poolish]

      Make dough.
    MD

    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Water') do |p|
      p.basis_grams = 240
      p.aisle = 'Miscellaneous'
    end

    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
    all_names = result.values.flatten.pluck(:name)

    assert_includes all_names, 'Salt'
    assert_includes all_names, 'Flour'
    assert_includes all_names, 'Water'
  end

  test 'items include sources listing recipe titles' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    assert_includes flour[:sources], 'Focaccia'
  end

  test 'shared ingredients list all contributing recipe titles' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Sourdough

      Category: Bread

      ## Mix (combine)

      - Flour, 2 cups
      - Salt, 0.5 tsp

      Mix well.
    MD

    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    list.apply_action('select', type: 'recipe', slug: 'sourdough', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    assert_includes flour[:sources], 'Focaccia'
    assert_includes flour[:sources], 'Sourdough'
  end

  test 'quick bite ingredients include quick bite title as source' do
    @kitchen.update!(quick_bites_content: <<~MD)
      ## Snacks
        - Hummus with Pretzels: Hummus, Pretzels
    MD

    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'quick_bite', slug: 'hummus-with-pretzels', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
    hummus = result.values.flatten.find { |i| i[:name] == 'Hummus' }

    assert_includes hummus[:sources], 'Hummus with Pretzels'
  end

  test 'consolidates singular and plural ingredient names into canonical form' do
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Eggs') do |p|
      p.basis_grams = 50
      p.aisle = 'Refrigerated'
    end

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Omelet

      Category: Bread

      ## Cook (fry)

      - Eggs, 3

      Cook.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Custard

      Category: Bread

      ## Mix (combine)

      - Egg, 1

      Mix.
    MD

    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'omelet', selected: true)
    list.apply_action('select', type: 'recipe', slug: 'custard', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

    all_names = result.values.flatten.pluck(:name)

    assert_includes all_names, 'Eggs'
    assert_not_includes all_names, 'Egg'

    eggs = result['Refrigerated'].find { |i| i[:name] == 'Eggs' }

    assert eggs
    assert_equal [[4.0, nil]], eggs[:amounts]
    assert_includes eggs[:sources], 'Omelet'
    assert_includes eggs[:sources], 'Custard'
  end

  test 'custom items have empty sources' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
    custom = result['Miscellaneous'].find { |i| i[:name] == 'birthday candles' }

    assert_empty custom[:sources]
  end
end
