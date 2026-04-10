# frozen_string_literal: true

require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'logout renders interstitial with join code' do
    log_in

    delete logout_path

    assert_response :success
    assert_select 'h1', text: /signed out/i
    assert_match @kitchen.join_code, response.body
  end

  test 'logout clears session' do
    log_in

    assert_predicate cookies[:session_id], :present?

    delete logout_path

    assert_equal 0, @user.sessions.count
  end

  test 'logout when not logged in redirects to root' do
    delete logout_path

    assert_redirected_to root_path
  end
end
