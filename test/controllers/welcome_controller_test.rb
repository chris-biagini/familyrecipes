# frozen_string_literal: true

require 'test_helper'

class WelcomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'show with valid signed kitchen ID renders join code' do
    signed_id = sign_welcome_kitchen(@kitchen.id)

    get welcome_path(k: signed_id)

    assert_response :success
    assert_match @kitchen.join_code, response.body
    assert_select 'h1', text: /welcome/i
  end

  test 'show with invalid signed ID redirects to root' do
    get welcome_path(k: 'tampered-value')

    assert_redirected_to root_path
  end

  test 'show with expired signed ID redirects to root' do
    signed_id = sign_welcome_kitchen(@kitchen.id)
    travel 20.minutes

    get welcome_path(k: signed_id)

    assert_redirected_to root_path
  end

  private

  def sign_welcome_kitchen(id)
    Rails.application.message_verifier(:welcome).generate(id, purpose: :welcome, expires_in: 15.minutes)
  end
end
