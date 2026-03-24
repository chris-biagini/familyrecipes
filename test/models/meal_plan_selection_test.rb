# frozen_string_literal: true

require 'test_helper'

class MealPlanSelectionTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
  end

  # --- acts_as_tenant scoping ---

  test 'scoped to kitchen via acts_as_tenant' do
    MealPlanSelection.create!(selectable_type: 'Recipe', selectable_id: 'bagels')

    other_kitchen = nil
    with_multi_kitchen do
      other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    end
    ActsAsTenant.current_tenant = other_kitchen

    assert_empty MealPlanSelection.all
  end

  # --- validations ---

  test 'requires selectable_type to be Recipe or QuickBite' do
    selection = MealPlanSelection.new(selectable_type: 'Invalid', selectable_id: 'x')

    assert_not selection.valid?
    assert_includes selection.errors[:selectable_type], 'is not included in the list'
  end

  test 'accepts Recipe as selectable_type' do
    selection = MealPlanSelection.new(selectable_type: 'Recipe', selectable_id: 'bagels')

    assert_predicate selection, :valid?
  end

  test 'accepts QuickBite as selectable_type' do
    selection = MealPlanSelection.new(selectable_type: 'QuickBite', selectable_id: 'tacos')

    assert_predicate selection, :valid?
  end

  test 'enforces uniqueness on kitchen + type + id' do
    MealPlanSelection.create!(selectable_type: 'Recipe', selectable_id: 'bagels')
    dup = MealPlanSelection.new(selectable_type: 'Recipe', selectable_id: 'bagels')

    assert_not dup.valid?
    assert_includes dup.errors[:selectable_id], 'has already been taken'
  end

  test 'allows same selectable_id with different types' do
    MealPlanSelection.create!(selectable_type: 'Recipe', selectable_id: 'tacos')
    other = MealPlanSelection.new(selectable_type: 'QuickBite', selectable_id: 'tacos')

    assert_predicate other, :valid?
  end

  # --- scopes ---

  test 'recipes scope filters by selectable_type Recipe' do
    recipe_sel = MealPlanSelection.create!(selectable_type: 'Recipe', selectable_id: 'bagels')
    MealPlanSelection.create!(selectable_type: 'QuickBite', selectable_id: 'tacos')

    assert_equal [recipe_sel], MealPlanSelection.recipes.to_a
  end

  test 'quick_bites scope filters by selectable_type QuickBite' do
    MealPlanSelection.create!(selectable_type: 'Recipe', selectable_id: 'bagels')
    qb_sel = MealPlanSelection.create!(selectable_type: 'QuickBite', selectable_id: 'tacos')

    assert_equal [qb_sel], MealPlanSelection.quick_bites.to_a
  end

  # --- toggle ---

  test 'toggle creates selection when selected is true' do
    MealPlanSelection.toggle(kitchen: @kitchen, type: 'Recipe', id: 'bagels', selected: true)

    assert_equal 1, MealPlanSelection.recipes.size
    assert_equal 'bagels', MealPlanSelection.recipes.first.selectable_id
  end

  test 'toggle destroys selection when selected is false' do
    MealPlanSelection.create!(selectable_type: 'Recipe', selectable_id: 'bagels')

    MealPlanSelection.toggle(kitchen: @kitchen, type: 'Recipe', id: 'bagels', selected: false)

    assert_empty MealPlanSelection.recipes
  end

  test 'toggle is idempotent when creating an existing selection' do
    MealPlanSelection.create!(selectable_type: 'Recipe', selectable_id: 'bagels')

    MealPlanSelection.toggle(kitchen: @kitchen, type: 'Recipe', id: 'bagels', selected: true)

    assert_equal 1, MealPlanSelection.recipes.size
  end

  test 'toggle is idempotent when destroying a nonexistent selection' do
    MealPlanSelection.toggle(kitchen: @kitchen, type: 'Recipe', id: 'bagels', selected: false)

    assert_empty MealPlanSelection.recipes
  end

  test 'toggle works for QuickBite type' do
    MealPlanSelection.toggle(kitchen: @kitchen, type: 'QuickBite', id: 'tacos', selected: true)

    assert_equal 1, MealPlanSelection.quick_bites.size
    assert_equal 'tacos', MealPlanSelection.quick_bites.first.selectable_id
  end

  # --- prune_stale! ---

  test 'prune_stale removes recipes not in valid slugs' do
    MealPlanSelection.create!(selectable_type: 'Recipe', selectable_id: 'bagels')
    MealPlanSelection.create!(selectable_type: 'Recipe', selectable_id: 'deleted-recipe')

    MealPlanSelection.prune_stale!(kitchen: @kitchen, valid_recipe_slugs: %w[bagels], valid_qb_ids: [])

    assert_equal %w[bagels], MealPlanSelection.recipes.pluck(:selectable_id)
  end

  test 'prune_stale removes quick bites not in valid ids' do
    MealPlanSelection.create!(selectable_type: 'QuickBite', selectable_id: 'tacos')
    MealPlanSelection.create!(selectable_type: 'QuickBite', selectable_id: 'gone')

    MealPlanSelection.prune_stale!(kitchen: @kitchen, valid_recipe_slugs: [], valid_qb_ids: %w[tacos])

    assert_equal %w[tacos], MealPlanSelection.quick_bites.pluck(:selectable_id)
  end

  test 'prune_stale keeps all valid selections' do
    MealPlanSelection.create!(selectable_type: 'Recipe', selectable_id: 'bagels')
    MealPlanSelection.create!(selectable_type: 'QuickBite', selectable_id: 'tacos')

    MealPlanSelection.prune_stale!(kitchen: @kitchen, valid_recipe_slugs: %w[bagels], valid_qb_ids: %w[tacos])

    assert_equal 2, MealPlanSelection.count
  end

  test 'prune_stale is safe with empty selections' do
    MealPlanSelection.prune_stale!(kitchen: @kitchen, valid_recipe_slugs: %w[bagels], valid_qb_ids: %w[tacos])

    assert_equal 0, MealPlanSelection.count
  end
end
