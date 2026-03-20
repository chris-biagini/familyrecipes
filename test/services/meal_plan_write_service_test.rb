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

  test 'deselecting a recipe records cook history' do
    create_focaccia_recipe
    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: 'focaccia', selected: true
    )
    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: 'focaccia', selected: false
    )

    plan = MealPlan.for_kitchen(@kitchen)
    history = plan.cook_history

    assert_equal 1, history.size
    assert_equal 'focaccia', history.first['slug']
  end

  test 'apply_action validates custom item length' do
    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'custom_items',
      item: 'a' * 101, action: 'add'
    )

    assert_not_predicate result, :success
    assert_includes result.errors.first, 'too long'
    assert_empty MealPlan.for_kitchen(@kitchen).custom_items
  end

  test 'apply_action accepts custom item at max length' do
    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'custom_items',
      item: 'a' * 100, action: 'add'
    )

    assert_predicate result, :success
    assert_includes MealPlan.for_kitchen(@kitchen).custom_items, 'a' * 100
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
