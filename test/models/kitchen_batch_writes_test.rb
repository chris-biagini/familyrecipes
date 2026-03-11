# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class KitchenBatchWritesTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    setup_test_kitchen
  end

  test 'batching? is false outside a batch block' do
    assert_not_predicate Kitchen, :batching?
  end

  test 'batching? is true inside a batch block' do
    Kitchen.batch_writes(@kitchen) do
      assert_predicate Kitchen, :batching?
    end
  end

  test 'batching? is false after block exits' do
    Kitchen.batch_writes(@kitchen) { :noop }

    assert_not Kitchen.batching?
  end

  test 'batching? is false after block raises' do
    assert_raises(RuntimeError) do
      Kitchen.batch_writes(@kitchen) { raise 'boom' }
    end

    assert_not Kitchen.batching?
  end

  test 'batch_writes broadcasts once on block exit' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      Kitchen.batch_writes(@kitchen) { :noop }
    end
  end

  test 'batch_writes reconciles once on block exit' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'ghost', selected: true)

    Kitchen.batch_writes(@kitchen) { :noop }

    plan.reload

    assert_not_includes plan.selected_recipes_set, 'ghost'
  end

  test 'batch_writes reconciles and broadcasts even when block raises' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'ghost', selected: true)

    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      assert_raises(RuntimeError) do
        Kitchen.batch_writes(@kitchen) { raise 'boom' }
      end
    end

    plan.reload

    assert_not_includes plan.selected_recipes_set, 'ghost'
  end
end
