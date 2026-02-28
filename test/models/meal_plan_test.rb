# frozen_string_literal: true

require 'test_helper'

class MealPlanTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    MealPlan.where(kitchen: @kitchen).delete_all
  end

  test 'belongs to kitchen' do
    list = MealPlan.create!(kitchen: @kitchen)

    assert_equal @kitchen, list.kitchen
  end

  test 'enforces one list per kitchen' do
    MealPlan.create!(kitchen: @kitchen)
    duplicate = MealPlan.new(kitchen: @kitchen)

    assert_not_predicate duplicate, :valid?
  end

  test 'defaults to version 0 and empty state' do
    list = MealPlan.create!(kitchen: @kitchen)

    assert_equal 0, list.lock_version
    assert_empty list.state
  end

  test 'for_kitchen finds or creates' do
    list = MealPlan.for_kitchen(@kitchen)

    assert_predicate list, :persisted?
    assert_equal @kitchen, list.kitchen

    assert_equal list, MealPlan.for_kitchen(@kitchen)
  end

  test 'apply_action adds recipe to selected_recipes' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)

    assert_includes list.state['selected_recipes'], 'pizza-dough'
  end

  test 'apply_action removes recipe from selected_recipes' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: false)

    assert_not_includes list.state['selected_recipes'], 'pizza-dough'
  end

  test 'apply_action adds quick bite to selected_quick_bites' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)

    assert_includes list.state['selected_quick_bites'], 'nachos'
  end

  test 'apply_action checks off item' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: true)

    assert_includes list.state['checked_off'], 'milk'
  end

  test 'apply_action unchecks item' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: true)
    list.apply_action('check', item: 'milk', checked: false)

    assert_not_includes list.state['checked_off'], 'milk'
  end

  test 'apply_action adds custom item' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')

    assert_includes list.state['custom_items'], 'birthday candles'
  end

  test 'apply_action removes custom item' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')
    list.apply_action('custom_items', item: 'birthday candles', action: 'remove')

    assert_not_includes list.state['custom_items'], 'birthday candles'
  end

  test 'apply_action handles string selected param' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: 'true')

    assert_includes list.state['selected_recipes'], 'pizza-dough'

    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: 'false')

    assert_not_includes list.state['selected_recipes'], 'pizza-dough'
  end

  test 'apply_action handles string checked param' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: 'true')

    assert_includes list.state['checked_off'], 'milk'

    list.apply_action('check', item: 'milk', checked: 'false')

    assert_not_includes list.state['checked_off'], 'milk'
  end

  test 'clear resets state and bumps version' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)
    old_version = list.lock_version

    list.clear!

    assert_empty list.state
    assert_operator list.lock_version, :>, old_version
  end

  test 'select_all sets all recipes and quick bites while preserving custom items' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')
    list.apply_action('check', item: 'milk', checked: true)

    list.select_all!(%w[focaccia bagels], %w[goldfish nachos])

    assert_equal %w[focaccia bagels], list.state['selected_recipes']
    assert_equal %w[goldfish nachos], list.state['selected_quick_bites']
    assert_includes list.state['custom_items'], 'birthday candles'
    assert_includes list.state['checked_off'], 'milk'
  end

  test 'clear_selections resets selections and checked off but preserves custom items' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)
    list.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')
    list.apply_action('check', item: 'milk', checked: true)

    list.clear_selections!

    assert_empty list.state['selected_recipes']
    assert_empty list.state['selected_quick_bites']
    assert_includes list.state['custom_items'], 'birthday candles'
    assert_empty list.state['checked_off']
  end

  test 'apply_action bumps version' do
    list = MealPlan.for_kitchen(@kitchen)
    old_version = list.lock_version

    list.apply_action('check', item: 'milk', checked: true)

    assert_operator list.lock_version, :>, old_version
  end

  test 'operations are idempotent' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: true)
    version_after_first = list.lock_version

    list.apply_action('check', item: 'milk', checked: true)

    assert_equal version_after_first, list.lock_version
  end

  test 'ignores unknown action types' do
    list = MealPlan.for_kitchen(@kitchen)
    old_version = list.lock_version

    list.apply_action('bogus', foo: 'bar')

    assert_equal old_version, list.lock_version
  end

  test 'with_optimistic_retry retries on StaleObjectError' do
    list = MealPlan.for_kitchen(@kitchen)
    attempts = 0

    list.with_optimistic_retry do
      attempts += 1
      raise ActiveRecord::StaleObjectError, list if attempts == 1
    end

    assert_equal 2, attempts
  end

  test 'with_optimistic_retry raises after max attempts' do
    list = MealPlan.for_kitchen(@kitchen)

    assert_raises(ActiveRecord::StaleObjectError) do
      list.with_optimistic_retry(max_attempts: 2) do
        raise ActiveRecord::StaleObjectError, list
      end
    end
  end

  test 'deselecting recipe prunes orphaned checked_off items' do
    setup_recipe_with_ingredients
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    list.apply_action('check', item: 'Flour', checked: true)
    list.apply_action('check', item: 'Salt', checked: true)

    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)

    assert_empty list.state['checked_off']
  end

  test 'deselecting recipe preserves checked items still on shopping list' do
    setup_two_recipes_sharing_ingredient
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    list.apply_action('select', type: 'recipe', slug: 'bagels', selected: true)
    list.apply_action('check', item: 'Flour', checked: true)
    list.apply_action('check', item: 'Salt', checked: true)

    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)

    assert_includes list.state['checked_off'], 'Flour'
    assert_not_includes list.state['checked_off'], 'Salt'
  end

  test 'deselecting quick bite prunes orphaned checked_off items' do
    @kitchen.update!(quick_bites_content: "## Snacks\n  - Nachos: Chips, Salsa")
    ensure_catalog_entries('Chips' => 'Snacks', 'Salsa' => 'Condiments')
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)
    list.apply_action('check', item: 'Chips', checked: true)

    list.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: false)

    assert_empty list.state['checked_off']
  end

  test 'selecting does not prune checked_off' do
    setup_recipe_with_ingredients
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'Milk', checked: true)

    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    assert_includes list.state['checked_off'], 'Milk'
  end

  test 'prune preserves custom items in checked_off' do
    setup_recipe_with_ingredients
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')
    list.apply_action('check', item: 'birthday candles', checked: true)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)

    assert_includes list.state['checked_off'], 'birthday candles'
  end

  private

  def setup_recipe_with_ingredients
    Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD
    ensure_catalog_entries('Flour' => 'Baking', 'Salt' => 'Spices')
  end

  def setup_two_recipes_sharing_ingredient
    Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Bagels

      Category: Bread

      ## Mix (combine)

      - Flour, 4 cups
      - Yeast, 1 tsp

      Mix well.
    MD
    ensure_catalog_entries('Flour' => 'Baking', 'Salt' => 'Spices', 'Yeast' => 'Baking')
  end

  def ensure_catalog_entries(name_aisle_pairs)
    name_aisle_pairs.each do |name, aisle|
      IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: name) do |entry|
        entry.aisle = aisle
      end
    end
  end
end
