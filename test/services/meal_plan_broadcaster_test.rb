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
end
