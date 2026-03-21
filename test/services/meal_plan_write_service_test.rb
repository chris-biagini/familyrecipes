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

  # --- check action canonicalization ---

  test 'check action canonicalizes item name via IngredientResolver' do
    create_catalog_entry('Flour', aisle: 'Baking')
    select_recipe_with_flour

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'check',
      item: 'flour', checked: true
    )

    plan = MealPlan.for_kitchen(@kitchen)

    assert plan.on_hand.key?('Flour'), 'on_hand key should use canonical catalog name'
    assert_not plan.on_hand.key?('flour'), 'non-canonical name should not be stored'
  end

  test 'check action sets null interval for custom items' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('custom_items', item: 'Birthday candles', action: 'add')

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'check',
      item: 'Birthday candles', checked: true
    )

    plan.reload
    entry = plan.on_hand['Birthday candles']

    assert_nil entry['interval'], 'Custom items should get null interval'
  end

  test 'check action sets recipe interval for non-custom items' do
    select_recipe_with_flour

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'check',
      item: 'Flour', checked: true
    )

    plan = MealPlan.for_kitchen(@kitchen)

    assert_equal 7, plan.on_hand['Flour']['interval']
  end

  test 'check action detects custom items case-insensitively' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('custom_items', item: 'Paper Towels', action: 'add')

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'check',
      item: 'paper towels', checked: true
    )

    plan.reload
    entry = plan.on_hand.values.find { |e| e['interval'].nil? }

    assert_not_nil entry, 'Custom item should have null interval'
  end

  private

  def select_recipe_with_flour
    create_focaccia_recipe
    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: 'focaccia', selected: true
    )
  end

  def create_focaccia_recipe
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix

      - Flour, 3 cups

      Mix well.
    MD
  end
end
