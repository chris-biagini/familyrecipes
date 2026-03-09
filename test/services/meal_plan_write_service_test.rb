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

  test 'apply_action persists the mutation' do
    create_focaccia_recipe

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: 'focaccia', selected: true
    )

    @plan.reload

    assert_includes @plan.state['selected_recipes'], 'focaccia'
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

  # --- select_all ---

  test 'select_all selects all provided slugs' do
    MealPlanWriteService.select_all(
      kitchen: @kitchen, recipe_slugs: %w[a b], quick_bite_slugs: %w[c]
    )

    @plan.reload

    assert_equal %w[a b], @plan.state['selected_recipes']
    assert_equal %w[c], @plan.state['selected_quick_bites']
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

    MealPlanWriteService.clear(kitchen: @kitchen)

    @plan.reload

    assert_empty @plan.state['selected_recipes']
    assert_empty @plan.state['checked_off']
  end

  test 'clear broadcasts to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      MealPlanWriteService.clear(kitchen: @kitchen)
    end
  end

  # --- reconcile ---

  test 'reconcile prunes stale selections and broadcasts' do
    @plan.apply_action('select', type: 'quick_bite', slug: 'gone', selected: true)

    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      MealPlanWriteService.reconcile(kitchen: @kitchen)
    end

    @plan.reload

    assert_not_includes @plan.state['selected_quick_bites'], 'gone'
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
