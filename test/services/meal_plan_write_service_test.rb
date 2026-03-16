# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class MealPlanWriteServiceTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    setup_test_kitchen
    setup_test_category
    @plan = MealPlan.for_kitchen(@kitchen)
  end

  # --- apply_action ---

  test 'apply_action persists the mutation and returns success' do
    create_focaccia_recipe

    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: 'focaccia', selected: true
    )

    @plan.reload

    assert_includes @plan.state['selected_recipes'], 'focaccia'
    assert_predicate result, :success
    assert_empty result.errors
  end

  test 'apply_action reconciles stale selections' do
    @plan.apply_action('select', type: 'recipe', slug: 'ghost', selected: true)

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: 'ghost', selected: false
    )

    @plan.reload

    assert_not_includes @plan.state['selected_recipes'], 'ghost'
  end

  test 'apply_action broadcasts to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      MealPlanWriteService.apply_action(
        kitchen: @kitchen, action_type: 'check',
        item: 'flour', checked: true
      )
    end
  end

  test 'apply_action retries on StaleObjectError' do
    create_focaccia_recipe
    attempts = 0
    original_apply = @plan.method(:apply_action)

    @plan.define_singleton_method(:apply_action) do |*args, **kwargs|
      attempts += 1
      raise ActiveRecord::StaleObjectError, self if attempts == 1

      original_apply.call(*args, **kwargs)
    end

    MealPlan.stub(:for_kitchen, @plan) do
      MealPlanWriteService.apply_action(
        kitchen: @kitchen, action_type: 'select',
        type: 'recipe', slug: 'focaccia', selected: true
      )
    end

    assert_equal 2, attempts
  end

  test 'apply_action skips broadcast when batching' do
    broadcast_count = 0
    @kitchen.define_singleton_method(:broadcast_update) { broadcast_count += 1 }
    Kitchen.stub(:batching?, true) do
      MealPlanWriteService.apply_action(
        kitchen: @kitchen, action_type: 'check',
        item: 'flour', checked: true
      )
    end

    assert_equal 0, broadcast_count
  end

  test 'apply_action validates custom item length' do
    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'custom_items',
      item: 'a' * 101, action: 'add'
    )

    assert_not_predicate result, :success
    assert_includes result.errors.first, 'too long'
    assert_empty MealPlan.for_kitchen(@kitchen).custom_items_list
  end

  test 'apply_action accepts custom item at max length' do
    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'custom_items',
      item: 'a' * 100, action: 'add'
    )

    assert_predicate result, :success
    assert_includes MealPlan.for_kitchen(@kitchen).custom_items_list, 'a' * 100
  end

  # --- select_all ---

  test 'select_all selects all provided slugs' do
    create_focaccia_recipe

    result = MealPlanWriteService.select_all(
      kitchen: @kitchen, recipe_slugs: %w[focaccia], quick_bite_slugs: []
    )

    @plan.reload

    assert_equal %w[focaccia], @plan.state['selected_recipes']
    assert_predicate result, :success
  end

  test 'select_all reconciles stale checked-off items' do
    create_focaccia_recipe
    @plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    @plan.apply_action('check', item: 'Stale Item', checked: true)

    MealPlanWriteService.select_all(
      kitchen: @kitchen, recipe_slugs: %w[focaccia], quick_bite_slugs: []
    )

    @plan.reload

    assert_not_includes @plan.state['checked_off'], 'Stale Item'
  end

  test 'select_all broadcasts to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      MealPlanWriteService.select_all(
        kitchen: @kitchen, recipe_slugs: [], quick_bite_slugs: []
      )
    end
  end

  # --- clear ---

  test 'clear empties selections and checked_off' do
    @plan.apply_action('select', type: 'recipe', slug: 'x', selected: true)
    @plan.apply_action('check', item: 'flour', checked: true)

    result = MealPlanWriteService.clear(kitchen: @kitchen)

    @plan.reload

    assert_empty @plan.state['selected_recipes']
    assert_empty @plan.state['checked_off']
    assert_predicate result, :success
  end

  test 'clear reconciles stale checked-off items' do
    create_focaccia_recipe
    @plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    @plan.apply_action('check', item: 'Stale Item', checked: true)

    MealPlanWriteService.clear(kitchen: @kitchen)

    @plan.reload

    assert_not_includes @plan.state['checked_off'], 'Stale Item'
  end

  test 'clear broadcasts to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      MealPlanWriteService.clear(kitchen: @kitchen)
    end
  end

  private

  def create_focaccia_recipe
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix

      - Flour, 3 cups

      Mix well.
    MD
  end
end
