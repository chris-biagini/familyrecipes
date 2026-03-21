# frozen_string_literal: true

require 'test_helper'

class IngredientResolverRegressionTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category(name: 'Italian')

    create_catalog_entry('Parmesan', basis_grams: 10, aisle: 'Dairy')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Pasta Alfredo


      ## Cook (toss)

      - Parmesan, 1 cup

      Toss.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Caesar Salad


      ## Toss (combine)

      - parmesan, 0.5 cup

      Toss.
    MD
  end

  test 'shopping list and availability agree on canonical name for different casings' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'pasta-alfredo', selected: true)
    plan.apply_action('select', type: 'recipe', slug: 'caesar-salad', selected: true)

    resolver = IngredientCatalog.resolver_for(@kitchen)

    shopping = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan, resolver:).build
    all_names = shopping.values.flatten.pluck(:name)

    assert_equal 1, all_names.count { |n| n.casecmp('parmesan').zero? },
                 'Expected one Parmesan entry in shopping list'
    assert_includes all_names, 'Parmesan',
                    'Expected canonical catalog name, not lowercase variant'

    plan.state['on_hand'] = { 'Parmesan' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 7 } }
    plan.save!
    checked_off = plan.effective_on_hand.keys

    availability = RecipeAvailabilityCalculator.new(
      kitchen: @kitchen, checked_off:, resolver:
    ).call

    assert_equal 0, availability['pasta-alfredo'][:missing],
                 'Parmesan checked off should satisfy Pasta Alfredo'
    assert_equal 0, availability['caesar-salad'][:missing],
                 'Parmesan checked off should satisfy Caesar Salad (lowercase "parmesan" in recipe)'
  end

  test 'uncataloged ingredients collapse across services with shared resolver' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Bruschetta


      ## Top (assemble)

      - Balsamic glaze, 2 tbsp

      Top.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Caprese


      ## Drizzle (serve)

      - balsamic glaze, 1 tbsp

      Drizzle.
    MD

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'bruschetta', selected: true)
    plan.apply_action('select', type: 'recipe', slug: 'caprese', selected: true)

    resolver = IngredientCatalog.resolver_for(@kitchen)
    shopping = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan, resolver:).build
    all_names = shopping.values.flatten.pluck(:name)

    assert_equal 1, all_names.count { |n| n.casecmp('balsamic glaze').zero? },
                 'Expected one Balsamic glaze entry, not two'
  end
end
