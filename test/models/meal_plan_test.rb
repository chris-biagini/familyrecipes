# frozen_string_literal: true

require 'test_helper'

class MealPlanTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    MealPlan.where(kitchen: @kitchen).delete_all
  end

  test 'belongs to kitchen' do
    plan = MealPlan.create!(kitchen: @kitchen)

    assert_equal @kitchen, plan.kitchen
  end

  test 'enforces one plan per kitchen' do
    MealPlan.create!(kitchen: @kitchen)
    duplicate = MealPlan.new(kitchen: @kitchen)

    assert_not_predicate duplicate, :valid?
  end

  test 'for_kitchen creates when none exists' do
    plan = MealPlan.for_kitchen(@kitchen)

    assert_predicate plan, :persisted?
    assert_equal @kitchen, plan.kitchen
  end

  test 'for_kitchen returns existing plan' do
    existing = MealPlan.create!(kitchen: @kitchen)

    assert_equal existing, MealPlan.for_kitchen(@kitchen)
  end

  test 'for_kitchen handles race condition on duplicate insert' do
    MealPlan.create!(kitchen: @kitchen)

    plan = MealPlan.for_kitchen(@kitchen)

    assert_predicate plan, :persisted?
    assert_equal @kitchen, plan.kitchen
  end

  test 'selected_recipes returns slugs from MealPlanSelection' do
    plan = MealPlan.for_kitchen(@kitchen)
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'Recipe', selectable_id: 'pizza-dough')
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'Recipe', selectable_id: 'bagels')

    assert_equal %w[pizza-dough bagels].sort, plan.selected_recipes.sort
  end

  test 'selected_quick_bites returns IDs from MealPlanSelection' do
    plan = MealPlan.for_kitchen(@kitchen)
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'QuickBite', selectable_id: 'nachos')

    assert_equal %w[nachos], plan.selected_quick_bites
  end

  test 'selected_recipes excludes quick bite selections' do
    plan = MealPlan.for_kitchen(@kitchen)
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'Recipe', selectable_id: 'pizza-dough')
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'QuickBite', selectable_id: 'nachos')

    assert_equal %w[pizza-dough], plan.selected_recipes
  end

  test 'selected_quick_bites excludes recipe selections' do
    plan = MealPlan.for_kitchen(@kitchen)
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'Recipe', selectable_id: 'pizza-dough')
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'QuickBite', selectable_id: 'nachos')

    assert_equal %w[nachos], plan.selected_quick_bites
  end
end
