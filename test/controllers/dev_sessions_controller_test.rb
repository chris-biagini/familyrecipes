# frozen_string_literal: true

require 'test_helper'

class DevSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'login sets session and redirects to kitchen' do
    get dev_login_path(id: @user.id)

    assert_redirected_to kitchen_root_path(kitchen_slug: @kitchen.slug)
  end

  test 'logout clears session and redirects to landing' do
    log_in

    get dev_logout_path

    assert_redirected_to root_path
  end
end
