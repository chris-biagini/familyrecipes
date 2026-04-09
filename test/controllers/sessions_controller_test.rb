# frozen_string_literal: true

require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'logout clears session and redirects to root' do
    log_in

    assert_predicate cookies[:session_id], :present?

    delete logout_path

    assert_redirected_to root_path
  end

  test 'logout when not logged in redirects to root' do
    delete logout_path

    assert_redirected_to root_path
  end
end
