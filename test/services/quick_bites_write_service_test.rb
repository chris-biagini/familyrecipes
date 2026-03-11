# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class QuickBitesWriteServiceTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    setup_test_kitchen
  end

  test 'update persists content to kitchen' do
    QuickBitesWriteService.update(kitchen: @kitchen, content: "Snacks:\n- Goldfish")

    assert_equal "Snacks:\n- Goldfish", @kitchen.reload.quick_bites_content
  end

  test 'update clears content when blank' do
    @kitchen.update!(quick_bites_content: 'old')

    QuickBitesWriteService.update(kitchen: @kitchen, content: '')

    assert_nil @kitchen.reload.quick_bites_content
  end

  test 'update returns warnings from parser' do
    result = QuickBitesWriteService.update(
      kitchen: @kitchen, content: "Snacks:\n- Goldfish\ngarbage"
    )

    assert_equal 1, result.warnings.size
    assert_match(/line 3/i, result.warnings.first)
  end

  test 'update returns empty warnings for valid content' do
    result = QuickBitesWriteService.update(
      kitchen: @kitchen, content: "Snacks:\n- Goldfish"
    )

    assert_empty result.warnings
  end

  test 'update reconciles meal plan' do
    @kitchen.update!(quick_bites_content: "Snacks:\n- Nachos: Chips\n- Pretzels: Pretzels")
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)
    plan.apply_action('select', type: 'quick_bite', slug: 'pretzels', selected: true)

    QuickBitesWriteService.update(kitchen: @kitchen, content: "Snacks:\n- Nachos: Chips")

    plan.reload

    assert_includes plan.state['selected_quick_bites'], 'nachos'
    assert_not_includes plan.state['selected_quick_bites'], 'pretzels'
  end

  test 'update broadcasts to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      QuickBitesWriteService.update(kitchen: @kitchen, content: "Snacks:\n- Goldfish")
    end
  end

  test 'update skips broadcast when batching' do
    broadcast_count = 0
    @kitchen.define_singleton_method(:broadcast_update) { broadcast_count += 1 }
    Kitchen.stub(:batching?, true) do
      QuickBitesWriteService.update(kitchen: @kitchen, content: "Snacks:\n- Goldfish")
    end

    assert_equal 0, broadcast_count
  end
end
