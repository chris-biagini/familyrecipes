# frozen_string_literal: true

require 'test_helper'

class ShoppingListBuilderTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category(name: 'Bread')
    IngredientCatalog.where(kitchen_id: nil).delete_all
    CustomGroceryItem.delete_all
    MealPlanSelection.delete_all

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
    create_catalog_entry('Salt', basis_grams: 6, aisle: 'Spices')
  end

  test 'builds shopping list organized by aisle' do
    select_recipe('focaccia')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build

    assert result.key?('Baking'), "Expected 'Baking' aisle"
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    assert flour, 'Expected Flour in Baking aisle'
  end

  test 'puts unmapped ingredients in Miscellaneous' do
    select_recipe('focaccia')
    IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: nil)

    result = ShoppingListBuilder.new(kitchen: @kitchen).build

    assert result.key?('Miscellaneous')
    salt = result['Miscellaneous'].find { |i| i[:name] == 'Salt' }

    assert salt, 'Expected Salt in Miscellaneous'
  end

  test 'omits ingredients marked omit_from_shopping' do
    IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(omit_from_shopping: true)
    select_recipe('focaccia')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    all_names = result.values.flatten.pluck(:name)

    assert_not_includes all_names, 'Salt'
  end

  test 'includes custom items in Miscellaneous' do
    add_custom_item('birthday candles')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    custom = result['Miscellaneous'].find { |i| i[:name] == 'birthday candles' }

    assert custom
    assert_empty custom[:amounts]
  end

  test 'empty list returns empty hash' do
    result = ShoppingListBuilder.new(kitchen: @kitchen).build

    assert_empty result
  end

  test 'aggregates quantities from multiple recipes' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Sourdough


      ## Mix (combine)

      - Flour, 2 cups
      - Salt, 0.5 tsp

      Mix well.
    MD

    select_recipe('focaccia')
    select_recipe('sourdough')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build

    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    assert flour, 'Expected Flour in Baking aisle'
    flour_cup = flour[:amounts].find { |_v, u| u == 'cups' }

    assert_in_delta 5.0, flour_cup[0], 0.01
  end

  test 'respects kitchen aisle_order for sorting' do
    @kitchen.update!(aisle_order: "Spices\nBaking")
    select_recipe('focaccia')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    aisle_names = result.keys

    assert_equal 'Spices', aisle_names[0]
    assert_equal 'Baking', aisle_names[1]
  end

  test 'unordered aisles appear after ordered aisles alphabetically' do
    create_catalog_entry('Eggs', basis_grams: 50, aisle: 'Refrigerated')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Scramble


      ## Cook (scramble)

      - Eggs, 3
      - Flour, 1 cup
      - Salt, 1 tsp

      Cook.
    MD

    @kitchen.update!(aisle_order: "Spices\nBaking")
    select_recipe('scramble')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    aisle_names = result.keys

    assert_equal %w[Spices Baking Refrigerated], aisle_names
  end

  test 'Miscellaneous sorts last even with aisle_order' do
    IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: nil)
    @kitchen.update!(aisle_order: 'Baking')

    select_recipe('focaccia')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build

    assert_equal 'Miscellaneous', result.keys.last
  end

  test 'Miscellaneous respects explicit position in aisle_order' do
    IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: nil)
    @kitchen.update!(aisle_order: "Miscellaneous\nBaking")

    select_recipe('focaccia')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build

    assert_equal %w[Miscellaneous Baking], result.keys
  end

  test 'falls back to alphabetical when aisle_order is nil' do
    @kitchen.update!(aisle_order: nil)
    select_recipe('focaccia')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    aisle_names = result.keys

    assert_equal %w[Baking Spices], aisle_names
  end

  test 'includes quick bite ingredients when selected' do
    @kitchen.update!(quick_bites_content: <<~MD)
      ## Snacks
      - Hummus with Pretzels: Hummus, Pretzels
    MD

    select_quick_bite('hummus-with-pretzels')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build

    all_names = result.values.flatten.pluck(:name)

    assert_includes all_names, 'Hummus'
    assert_includes all_names, 'Pretzels'
  end

  test 'includes cross-referenced recipe ingredients in shopping list' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Poolish


      ## Mix (combine)

      - Flour, 1 cup
      - Water, 1 cup

      Mix.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Pizza


      ## Make poolish.
      > @[Poolish]

      ## Dough (assemble)

      - Salt, 1 tsp

      Make dough.
    MD

    create_catalog_entry('Water', basis_grams: 240, aisle: 'Miscellaneous')

    select_recipe('pizza')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    all_names = result.values.flatten.pluck(:name)

    assert_includes all_names, 'Salt'
    assert_includes all_names, 'Flour'
    assert_includes all_names, 'Water'
  end

  test 'items include sources listing recipe titles' do
    select_recipe('focaccia')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    assert_includes flour[:sources], 'Focaccia'
  end

  test 'shared ingredients list all contributing recipe titles' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Sourdough


      ## Mix (combine)

      - Flour, 2 cups
      - Salt, 0.5 tsp

      Mix well.
    MD

    select_recipe('focaccia')
    select_recipe('sourdough')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    assert_includes flour[:sources], 'Focaccia'
    assert_includes flour[:sources], 'Sourdough'
  end

  test 'quick bite ingredients include quick bite title as source' do
    @kitchen.update!(quick_bites_content: <<~MD)
      ## Snacks
      - Hummus with Pretzels: Hummus, Pretzels
    MD

    select_quick_bite('hummus-with-pretzels')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    hummus = result.values.flatten.find { |i| i[:name] == 'Hummus' }

    assert_includes hummus[:sources], 'Hummus with Pretzels'
  end

  test 'consolidates singular and plural ingredient names into canonical form' do
    create_catalog_entry('Eggs', basis_grams: 50, aisle: 'Refrigerated')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Omelet


      ## Cook (fry)

      - Eggs, 3

      Cook.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Custard


      ## Mix (combine)

      - Egg, 1

      Mix.
    MD

    select_recipe('omelet')
    select_recipe('custard')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build

    all_names = result.values.flatten.pluck(:name)

    assert_includes all_names, 'Eggs'
    assert_not_includes all_names, 'Egg'

    eggs = result['Refrigerated'].find { |i| i[:name] == 'Eggs' }

    assert eggs
    assert_equal [[4.0, nil]], eggs[:amounts]
    assert_includes eggs[:sources], 'Omelet'
    assert_includes eggs[:sources], 'Custard'
  end

  test 'merges ingredients case-insensitively when catalog entry exists' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Soda Bread


      ## Mix (combine)

      - flour, 2 cups

      Mix.
    MD

    select_recipe('focaccia')
    select_recipe('soda-bread')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    all_names = result.values.flatten.pluck(:name)

    assert_equal 1, all_names.count { |n| n.casecmp('flour').zero? },
                 'Expected one Flour entry, not separate entries for different cases'
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    assert flour, 'Expected canonical catalog name "Flour", not lowercase "flour"'
    flour_cups = flour[:amounts].find { |_v, u| u == 'cups' }

    assert_in_delta 5.0, flour_cups[0], 0.01
  end

  test 'merges uncataloged ingredients case-insensitively' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Fizzy Water


      ## Pour (serve)

      - Seltzer, 2 cups

      Pour.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Sparkling Lemonade


      ## Mix (combine)

      - seltzer, 1 cup

      Mix.
    MD

    select_recipe('fizzy-water')
    select_recipe('sparkling-lemonade')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    all_names = result.values.flatten.pluck(:name)

    assert_equal 1, all_names.count { |n| n.casecmp('seltzer').zero? },
                 'Expected one Seltzer entry, not separate entries for different cases'

    seltzer = result.values.flatten.find { |i| i[:name].casecmp('seltzer').zero? }

    assert seltzer
    seltzer_cups = seltzer[:amounts].find { |_v, u| u == 'cups' }

    assert_in_delta 3.0, seltzer_cups[0], 0.01
    assert_includes seltzer[:sources], 'Fizzy Water'
    assert_includes seltzer[:sources], 'Sparkling Lemonade'
  end

  test 'custom item that duplicates a recipe ingredient is merged not doubled' do
    create_catalog_entry('Triscuits', basis_grams: 30, aisle: 'Snacks')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Cheese Plate


      ## Assemble (plate)

      - Triscuits, 1 box

      Arrange.
    MD

    select_recipe('cheese-plate')
    add_custom_item('triscuits')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    all_names = result.values.flatten.pluck(:name)

    assert_equal 1, all_names.count { |n| n.casecmp('triscuits').zero? },
                 'Expected one Triscuits entry, not separate recipe + custom entries'
  end

  test 'custom item that duplicates an uncataloged recipe ingredient is merged' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Snack Mix


      ## Assemble (mix)

      - Goldfish crackers, 2 cups

      Mix.
    MD

    select_recipe('snack-mix')
    add_custom_item('goldfish crackers')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    all_names = result.values.flatten.pluck(:name)

    assert_equal 1, all_names.count { |n| n.casecmp('goldfish crackers').zero? },
                 'Expected one entry, not separate recipe + custom entries'
  end

  test 'custom item with no recipe match still appears' do
    add_custom_item('paper towels')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    all_names = result.values.flatten.pluck(:name)

    assert_includes all_names, 'paper towels'
  end

  test 'custom item with explicit aisle routes to that aisle' do
    create_catalog_entry('Butter', basis_grams: 14, aisle: 'Dairy')

    add_custom_item('butter', aisle: 'Dairy')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build

    assert result.key?('Dairy'), "Expected 'Dairy' aisle for custom item with Dairy aisle"
    butter = result['Dairy'].find { |i| i[:name] == 'Butter' }

    assert butter, 'Expected custom item canonicalized to "Butter" in Dairy aisle'
    assert_empty butter[:amounts]
  end

  test 'custom item name is canonicalized to catalog name' do
    create_catalog_entry('Olive Oil', basis_grams: 14, aisle: 'Oils')

    add_custom_item('olive oil')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    all_names = result.values.flatten.pluck(:name)

    assert_includes all_names, 'Olive Oil'
    assert_not_includes all_names, 'olive oil'
  end

  test 'custom items have empty sources' do
    add_custom_item('birthday candles')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    custom = result['Miscellaneous'].find { |i| i[:name] == 'birthday candles' }

    assert_empty custom[:sources]
  end

  test 'serializes plural units for quantity greater than one' do
    select_recipe('focaccia')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    flour_amount = flour[:amounts].find { |_v, u| u == 'cups' }

    assert flour_amount, 'Expected plural unit "cups" for quantity 3.0'
    assert_in_delta 3.0, flour_amount[0], 0.01
  end

  test 'serializes singular unit for quantity of one' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Toast


      ## Make (toast)

      - Flour, 1 cup

      Toast.
    MD

    select_recipe('toast')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    flour_amount = flour[:amounts].find { |_v, u| u == 'cup' }

    assert flour_amount, 'Expected singular unit "cup" for quantity 1.0'
  end

  test 'abbreviated units stay singular regardless of quantity' do
    select_recipe('focaccia')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    salt = result['Spices'].find { |i| i[:name] == 'Salt' }

    salt_amount = salt[:amounts].find { |_v, u| u == 'tsp' }

    assert salt_amount, 'Abbreviated units should not pluralize'
  end

  test 'visible_names returns set of all ingredient names in shopping list' do
    select_recipe('focaccia')

    names = ShoppingListBuilder.new(kitchen: @kitchen).visible_names

    assert_instance_of Set, names
    assert_includes names, 'Flour'
    assert_includes names, 'Salt'
  end

  test 'visible_names includes custom items' do
    add_custom_item('birthday candles')

    names = ShoppingListBuilder.new(kitchen: @kitchen).visible_names

    assert_includes names, 'birthday candles'
  end

  test 'visible_names excludes omitted ingredients' do
    IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(omit_from_shopping: true)
    select_recipe('focaccia')

    names = ShoppingListBuilder.new(kitchen: @kitchen).visible_names

    assert_not_includes names, 'Salt'
    assert_includes names, 'Flour'
  end

  test 'visible_names returns empty set when nothing selected' do
    names = ShoppingListBuilder.new(kitchen: @kitchen).visible_names

    assert_empty names
  end

  test 'custom item with aisle hint routes to hinted aisle' do
    add_custom_item('Shaving cream', aisle: 'Personal')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build

    assert result.key?('Personal'), "Expected 'Personal' aisle"
    item = result['Personal'].find { |i| i[:name] == 'Shaving cream' }

    assert item, 'Expected "Shaving cream" in Personal aisle'
    assert_empty item[:amounts]
  end

  test 'custom item with no aisle hint falls back to catalog lookup' do
    create_catalog_entry('Butter', basis_grams: 14, aisle: 'Dairy')
    add_custom_item('Butter')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build

    assert result.key?('Miscellaneous'), 'Miscellaneous aisle stored on custom item'
    butter = result['Miscellaneous'].find { |i| i[:name] == 'Butter' }

    assert butter
  end

  test 'aisle hint matches existing aisle case-insensitively' do
    @kitchen.update!(aisle_order: "Spices\nBaking")
    select_recipe('focaccia')
    add_custom_item('cinnamon sticks', aisle: 'spices')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build

    assert result.key?('Spices'), 'Expected canonical "Spices" aisle, not lowercase'
    item = result['Spices'].find { |i| i[:name] == 'cinnamon sticks' }

    assert item, 'Expected item in existing Spices aisle via case-insensitive match'
  end

  test 'aisle hint overrides catalog aisle for known ingredient' do
    create_catalog_entry('Butter', basis_grams: 14, aisle: 'Dairy')
    add_custom_item('Butter', aisle: 'Baking')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build

    assert result.key?('Baking'), 'Hint should override catalog aisle'
    butter = result['Baking'].find { |i| i[:name] == 'Butter' }

    assert butter
  end

  test 'hinted custom item deduped against recipe ingredient by parsed name' do
    select_recipe('focaccia')
    add_custom_item('Flour', aisle: 'Pantry')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    all_names = result.values.flatten.pluck(:name)

    assert_equal 1, all_names.count { |n| n.casecmp('flour').zero? },
                 'Hinted custom item should dedup against recipe Flour'
  end

  test 'visible_names includes custom item names' do
    add_custom_item('Shaving cream', aisle: 'Personal')

    names = ShoppingListBuilder.new(kitchen: @kitchen).visible_names

    assert_includes names, 'Shaving cream'
  end

  test 'tracks uncounted when recipe ingredient has no quantity' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Salad

      ## Toss (combine)

      - Olive oil
      - Salt, 1 tsp

      Toss.
    MD

    create_catalog_entry('Olive oil', basis_grams: 14, aisle: 'Oils')

    select_recipe('salad')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    oil = result['Oils'].find { |i| i[:name] == 'Olive oil' }

    assert_equal 1, oil[:uncounted]
    assert_empty oil[:amounts]
  end

  test 'mixed counted and uncounted from two recipes' do
    create_catalog_entry('Red bell pepper', basis_grams: 150, aisle: 'Produce')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Stuffed Peppers

      ## Prep (slice)

      - Red bell pepper, 1

      Prep.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Stir Fry

      ## Cook (stir-fry)

      - Red bell pepper

      Cook.
    MD

    select_recipe('stuffed-peppers')
    select_recipe('stir-fry')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    pepper = result['Produce'].find { |i| i[:name] == 'Red bell pepper' }

    assert_equal [[1.0, nil]], pepper[:amounts]
    assert_equal 1, pepper[:uncounted]
  end

  test 'multiple uncounted sources tracked separately' do
    create_catalog_entry('Garlic', basis_grams: 5, aisle: 'Produce')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Pasta

      ## Cook (boil)

      - Garlic

      Cook.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Stir Fry

      ## Cook (stir-fry)

      - Garlic

      Cook.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Soup

      ## Cook (simmer)

      - Garlic

      Cook.
    MD

    select_recipe('pasta')
    select_recipe('stir-fry')
    select_recipe('soup')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    garlic = result['Produce'].find { |i| i[:name] == 'Garlic' }

    assert_equal 3, garlic[:uncounted]
    assert_empty garlic[:amounts]
  end

  test 'fully counted ingredients have zero uncounted' do
    select_recipe('focaccia')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    assert_equal 0, flour[:uncounted]
  end

  test 'quick bite merged with counted recipe ingredient increments uncounted' do
    create_catalog_entry('Hummus', basis_grams: 30, aisle: 'Deli')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Veggie Plate

      ## Assemble (plate)

      - Hummus, 1 cup

      Arrange.
    MD

    @kitchen.update!(quick_bites_content: <<~MD)
      ## Snacks
      - Hummus with Pretzels: Hummus, Pretzels
    MD

    select_recipe('veggie-plate')
    select_quick_bite('hummus-with-pretzels')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    hummus = result['Deli'].find { |i| i[:name] == 'Hummus' }

    assert_equal [[1.0, 'cup']], hummus[:amounts]
    assert_equal 1, hummus[:uncounted]
  end

  test 'custom items have zero uncounted' do
    add_custom_item('birthday candles')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    custom = result['Miscellaneous'].find { |i| i[:name] == 'birthday candles' }

    assert_equal 0, custom[:uncounted]
  end

  test 'cross-reference uncounted ingredient tracked in parent recipe' do
    create_catalog_entry('Garlic', basis_grams: 5, aisle: 'Produce')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Garlic Butter

      ## Melt (combine)

      - Garlic

      Melt.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Garlic Bread

      ## Prep.
      > @[Garlic Butter]

      ## Toast (bake)

      - Garlic, 2 cloves

      Toast.
    MD

    select_recipe('garlic-bread')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    garlic = result['Produce'].find { |i| i[:name] == 'Garlic' }

    assert_equal [[2.0, 'cloves']], garlic[:amounts]
    assert_equal 1, garlic[:uncounted]
  end

  test 'hinted custom item aisle respects kitchen sort order' do
    @kitchen.update!(aisle_order: "Personal\nBaking")
    select_recipe('focaccia')
    add_custom_item('Shaving cream', aisle: 'Personal')

    result = ShoppingListBuilder.new(kitchen: @kitchen).build
    aisle_names = result.keys

    assert_operator aisle_names.index('Personal'), :<, aisle_names.index('Baking'),
                    'Personal should sort before Baking per aisle_order'
  end

  private

  def select_recipe(slug)
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'Recipe', selectable_id: slug)
  end

  def select_quick_bite(id)
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'QuickBite', selectable_id: id)
  end

  def add_custom_item(name, aisle: 'Miscellaneous')
    CustomGroceryItem.create!(kitchen: @kitchen, name: name, aisle: aisle, last_used_at: Date.current)
  end
end
