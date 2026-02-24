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
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build

    assert result.key?('Baking'), "Expected 'Baking' aisle"
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    assert flour, 'Expected Flour in Baking aisle'
  end

  test 'puts unmapped ingredients in Miscellaneous' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: nil)

    result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build

    assert result.key?('Miscellaneous')
    salt = result['Miscellaneous'].find { |i| i[:name] == 'Salt' }

    assert salt, 'Expected Salt in Miscellaneous'
  end

  test 'omits ingredients with aisle omit' do
    IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: 'omit')
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build
    all_names = result.values.flatten.map { |i| i[:name] }

    refute_includes all_names, 'Salt'
  end

  test 'includes custom items in Miscellaneous' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')

    result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build
    custom = result['Miscellaneous'].find { |i| i[:name] == 'birthday candles' }

    assert custom
    assert_empty custom[:amounts]
  end

  test 'empty list returns empty hash' do
    list = GroceryList.for_kitchen(@kitchen)
    result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build

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

    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    list.apply_action('select', type: 'recipe', slug: 'sourdough', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build

    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    assert flour, 'Expected Flour in Baking aisle'
    flour_cup = flour[:amounts].find { |_v, u| u == 'cup' }

    assert_in_delta 5.0, flour_cup[0], 0.01
  end

  test 'includes quick bite ingredients when selected' do
    @kitchen.update!(quick_bites_content: <<~MD)
      ## Snacks
        - Hummus with Pretzels: Hummus, Pretzels
    MD

    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'quick_bite', slug: 'hummus-with-pretzels', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build

    all_names = result.values.flatten.map { |i| i[:name] }

    assert_includes all_names, 'Hummus'
    assert_includes all_names, 'Pretzels'
  end
end
