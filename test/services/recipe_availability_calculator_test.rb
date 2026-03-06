# frozen_string_literal: true

require 'test_helper'

class RecipeAvailabilityCalculatorTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category(name: 'Bread')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp
      - Water, 1 cup

      Mix well.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Bagels


      ## Mix (combine)

      - Flour, 4 cups
      - Salt, 1 tsp
      - Yeast, 1 tsp

      Mix well.
    MD

    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
    create_catalog_entry('Salt', basis_grams: 6, aisle: 'Spices')
    create_catalog_entry('Water', basis_grams: 240, aisle: 'omit')
    create_catalog_entry('Yeast', basis_grams: 3, aisle: 'Baking')
  end

  test 'returns availability for all recipes' do
    result = RecipeAvailabilityCalculator.new(kitchen: @kitchen, checked_off: []).call

    assert result.key?('focaccia')
    assert result.key?('bagels')
  end

  test 'all missing when nothing checked off' do
    result = RecipeAvailabilityCalculator.new(kitchen: @kitchen, checked_off: []).call

    assert_equal 2, result['focaccia'][:missing]
    assert_equal %w[Flour Salt], result['focaccia'][:missing_names].sort
    assert_not_includes result['focaccia'][:missing_names], 'Water'
  end

  test 'excludes omitted ingredients from count' do
    result = RecipeAvailabilityCalculator.new(kitchen: @kitchen, checked_off: []).call

    assert_not_includes result['focaccia'][:ingredients], 'Water'
  end

  test 'zero missing when all non-omit ingredients checked off' do
    result = RecipeAvailabilityCalculator.new(
      kitchen: @kitchen,
      checked_off: %w[Flour Salt]
    ).call

    assert_equal 0, result['focaccia'][:missing]
    assert_empty result['focaccia'][:missing_names]
  end

  test 'partial check-off shows correct missing count' do
    result = RecipeAvailabilityCalculator.new(
      kitchen: @kitchen,
      checked_off: %w[Flour]
    ).call

    assert_equal 1, result['focaccia'][:missing]
    assert_equal ['Salt'], result['focaccia'][:missing_names]

    assert_equal 2, result['bagels'][:missing]
    assert_equal %w[Salt Yeast], result['bagels'][:missing_names].sort
  end

  test 'includes ingredient names list per recipe' do
    result = RecipeAvailabilityCalculator.new(kitchen: @kitchen, checked_off: []).call

    assert_includes result['focaccia'][:ingredients], 'Flour'
    assert_includes result['focaccia'][:ingredients], 'Salt'
  end

  test 'treats singular and plural ingredient names as equivalent' do
    create_catalog_entry('Eggs', basis_grams: 50, aisle: 'Refrigerated')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Custard


      ## Mix (combine)

      - Egg, 1

      Mix.
    MD

    result = RecipeAvailabilityCalculator.new(
      kitchen: @kitchen,
      checked_off: %w[Eggs]
    ).call

    assert_equal 0, result['custard'][:missing],
                 'Checking off "Eggs" should satisfy a recipe that uses "Egg"'
    assert_includes result['custard'][:ingredients], 'Eggs',
                    'Ingredient should be reported under canonical name'
    assert_not_includes result['custard'][:ingredients], 'Egg',
                        'Non-canonical name should not appear'
  end

  test 'includes quick bites when present' do
    @kitchen.update!(quick_bites_content: <<~MD)
      Snacks:
      - Nachos: Tortilla chips, Cheese
    MD

    result = RecipeAvailabilityCalculator.new(kitchen: @kitchen, checked_off: ['Cheese']).call

    assert result.key?('nachos')
    assert_equal 1, result['nachos'][:missing]
    assert_equal ['Tortilla chips'], result['nachos'][:missing_names]
  end

  test 'resolves checked-off names case-insensitively' do
    result = RecipeAvailabilityCalculator.new(
      kitchen: @kitchen,
      checked_off: %w[flour salt]
    ).call

    assert_equal 0, result['focaccia'][:missing],
                 'Checking off "flour" (lowercase) should satisfy "Flour" (capitalized)'
  end

  test 'handles cross-referenced recipe ingredients' do
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
      >>> @[Poolish]

      ## Dough (assemble)

      - Salt, 1 tsp

      Make dough.
    MD

    result = RecipeAvailabilityCalculator.new(
      kitchen: @kitchen,
      checked_off: %w[Salt]
    ).call

    assert_equal 1, result['pizza'][:missing]
    assert_equal ['Flour'], result['pizza'][:missing_names]
    assert_not_includes result['pizza'][:missing_names], 'Water'
  end
end
