# frozen_string_literal: true

require 'test_helper'

class NavLoginTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'nav does not show log out button' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav form[action*="logout"]', count: 0
  end

  test 'nav does not show log out button even when logged in' do
    log_in

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav form[action*="logout"]', count: 0
  end
end
