# frozen_string_literal: true

require 'test_helper'

class NavLoginTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'anonymous user does not see log in or log out' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav form[action*="logout"]', count: 0
  end

  test 'logged-in user sees log out button' do
    log_in

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav form[action*="logout"] button', text: 'Log out'
  end
end
