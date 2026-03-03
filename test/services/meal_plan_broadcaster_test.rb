# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class MealPlanBroadcasterTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    create_kitchen_and_user
  end

  test 'broadcast_grocery_morph broadcasts to groceries stream' do
    assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
      MealPlanBroadcaster.broadcast_grocery_morph(@kitchen)
    end
  end

  test 'broadcast_menu_morph broadcasts to menu stream' do
    assert_turbo_stream_broadcasts [@kitchen, 'menu'] do
      MealPlanBroadcaster.broadcast_menu_morph(@kitchen)
    end
  end

  test 'broadcast_all broadcasts to both streams' do
    assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
      assert_turbo_stream_broadcasts [@kitchen, 'menu'] do
        MealPlanBroadcaster.broadcast_all(@kitchen)
      end
    end
  end

  test 'grocery broadcast targets shopping-list and custom-items-section' do
    streams = capture_turbo_stream_broadcasts([@kitchen, 'groceries']) do
      MealPlanBroadcaster.broadcast_grocery_morph(@kitchen)
    end

    targets = streams.pluck('target')

    assert_includes targets, 'shopping-list'
    assert_includes targets, 'custom-items-section'
  end

  test 'menu broadcast targets recipe-selector' do
    streams = capture_turbo_stream_broadcasts([@kitchen, 'menu']) do
      MealPlanBroadcaster.broadcast_menu_morph(@kitchen)
    end

    targets = streams.pluck('target')

    assert_includes targets, 'recipe-selector'
  end

  test 'broadcasts succeed without tenant context' do
    ActsAsTenant.current_tenant = nil

    assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
      assert_turbo_stream_broadcasts [@kitchen, 'menu'] do
        MealPlanBroadcaster.broadcast_all(@kitchen)
      end
    end
  ensure
    ActsAsTenant.current_tenant = @kitchen
  end
end
