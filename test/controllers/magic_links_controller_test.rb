# frozen_string_literal: true

require 'test_helper'

class MagicLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    ActionMailer::Base.deliveries.clear
  end

  test 'GET /sessions/magic_link without pending_auth cookie redirects to new_session_path' do
    get sessions_magic_link_path

    assert_redirected_to new_session_path
  end

  test 'GET /sessions/magic_link with pending_auth cookie renders the code form' do
    post sessions_path, params: { email: @user.email }
    get sessions_magic_link_path

    assert_response :success
    assert_select 'form[action=?]', sessions_magic_link_path
    assert_select 'input[name=code]'
  end

  test 'GET /sessions/magic_link masks the pending email' do
    post sessions_path, params: { email: @user.email }
    get sessions_magic_link_path

    body_text = response.body

    assert_match(/example\.com/, body_text)
    assert_no_match(/test@/, body_text)
  end
end
