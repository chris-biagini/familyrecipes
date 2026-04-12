# frozen_string_literal: true

require 'test_helper'

class AuthFlowTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    ActionMailer::Base.deliveries.clear
    @user.update!(email_verified_at: nil)
  end

  test 'full magic link sign-in flow: email -> mailer -> code -> session' do
    get new_session_path

    assert_response :success

    perform_enqueued_jobs do
      post sessions_path, params: { email: @user.email }
    end

    assert_redirected_to sessions_magic_link_path

    delivered = ActionMailer::Base.deliveries.last

    assert_equal [@user.email], delivered.to

    code = MagicLink.order(:created_at).last.code

    assert_match(/\A[A-HJ-NP-Z2-9]{6}\z/, code)

    get sessions_magic_link_path

    assert_response :success

    post sessions_magic_link_path, params: { code: }

    assert_redirected_to kitchen_root_path(kitchen_slug: @kitchen.slug)

    follow_redirect!

    assert_response :success
    assert_not_nil @user.reload.email_verified_at
  end
end
