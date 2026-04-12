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

  test 'POST /sessions/magic_link with valid code starts a session and sets email_verified_at' do
    post sessions_path, params: { email: @user.email }
    @user.update_column(:email_verified_at, nil) # rubocop:disable Rails/SkipsModelValidations -- intentional: reset for side-effect assertion
    link = MagicLink.order(:created_at).last

    freeze_time do
      post sessions_magic_link_path, params: { code: link.code }

      assert_redirected_to kitchen_root_path(kitchen_slug: @kitchen.slug)
      assert_equal Time.current, @user.reload.email_verified_at
    end
  end

  test 'POST /sessions/magic_link consumes the link (single-use)' do
    post sessions_path, params: { email: @user.email }
    link = MagicLink.order(:created_at).last

    post sessions_magic_link_path, params: { code: link.code }
    delete logout_path
    cookies.delete(:pending_auth)

    post sessions_path, params: { email: @user.email }
    post sessions_magic_link_path, params: { code: link.code }

    assert_response :unprocessable_content
  end

  test 'POST /sessions/magic_link fails closed on code/email mismatch' do
    other_user = ActsAsTenant.without_tenant do
      User.create!(name: 'Other', email: 'other@example.com')
    end
    ActsAsTenant.with_tenant(@kitchen) do
      Membership.create!(kitchen: @kitchen, user: other_user)
    end

    post sessions_path, params: { email: other_user.email }
    other_link = MagicLink.order(:created_at).last

    cookies.delete(:pending_auth)
    post sessions_path, params: { email: @user.email }

    post sessions_magic_link_path, params: { code: other_link.code }

    assert_response :unprocessable_content
    assert_select 'input[name=code]'
  end

  test 'POST /sessions/magic_link with code/email mismatch re-renders the form (no redirect)' do
    other_user = ActsAsTenant.without_tenant do
      User.create!(name: 'Other2', email: 'other2@example.com')
    end
    ActsAsTenant.with_tenant(@kitchen) do
      Membership.create!(kitchen: @kitchen, user: other_user)
    end

    post sessions_path, params: { email: other_user.email }
    other_link = MagicLink.order(:created_at).last

    cookies.delete(:pending_auth)
    post sessions_path, params: { email: @user.email }

    post sessions_magic_link_path, params: { code: other_link.code }

    assert_response :unprocessable_content
    assert_select 'input[name=code]'
  end

  test 'POST /sessions/magic_link preserves pending_auth cookie on failed consume' do
    post sessions_path, params: { email: @user.email }

    post sessions_magic_link_path, params: { code: 'ZZZZZZ' }

    assert_not_empty cookies[:pending_auth].to_s
  end

  test 'POST /sessions/magic_link with :join purpose creates the membership idempotently' do
    other_kitchen = ActsAsTenant.without_tenant do
      Kitchen.create!(name: 'Another', slug: 'another')
    end
    joiner = ActsAsTenant.without_tenant do
      User.create!(name: 'Joiner', email: 'joiner@example.com')
    end
    link = MagicLink.create!(
      user: joiner,
      kitchen: other_kitchen,
      purpose: :join,
      expires_at: 15.minutes.from_now
    )

    establish_pending_auth_for(joiner.email)

    assert_difference -> { Membership.unscoped.count } => 1 do
      post sessions_magic_link_path, params: { code: link.code }
    end

    assert_redirected_to kitchen_root_path(kitchen_slug: other_kitchen.slug)
  end

  test 'POST /sessions/magic_link with invalid code re-renders with error' do
    post sessions_path, params: { email: @user.email }

    post sessions_magic_link_path, params: { code: 'ZZZZZZ' }

    assert_response :unprocessable_content
  end

  test 'POST /sessions/magic_link is rate-limited' do
    post sessions_path, params: { email: @user.email }

    11.times { post sessions_magic_link_path, params: { code: 'ZZZZZZ' } }

    assert_response :too_many_requests
  end

  private

  def establish_pending_auth_for(email)
    post sessions_path, params: { email: email }
  end
end
