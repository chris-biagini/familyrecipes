# frozen_string_literal: true

require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'GET /sessions/new renders the email form' do
    get new_session_path

    assert_response :success
    assert_select 'form[action=?]', sessions_path
    assert_select 'input[type=email][name=email]'
  end

  test 'GET /sessions/new redirects to root when already signed in' do
    log_in

    get new_session_path

    assert_redirected_to root_path
  end
end
