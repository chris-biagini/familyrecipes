# frozen_string_literal: true

require 'test_helper'

class OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user

    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: 'developer',
      uid: 'test-uid-123',
      info: { name: 'Test User', email: 'test@example.com' }
    )
  end

  teardown do
    OmniAuth.config.mock_auth[:developer] = nil
  end

  # --- #create ---

  test 'login with existing connected service signs in and redirects' do
    @user.connected_services.create!(provider: 'developer', uid: 'test-uid-123')

    assert_no_difference 'User.count' do
      assert_no_difference 'ConnectedService.count' do
        post omniauth_callback_path(provider: 'developer')
      end
    end

    assert_redirected_to root_url
    assert_predicate cookies[:session_id], :present?
  end

  test 'login creates new user when no matching service or email exists' do
    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: 'developer',
      uid: 'brand-new-uid',
      info: { name: 'New Person', email: 'new@example.com' }
    )

    assert_difference 'User.count', 1 do
      assert_difference 'ConnectedService.count', 1 do
        post omniauth_callback_path(provider: 'developer')
      end
    end

    new_user = User.find_by(email: 'new@example.com')

    assert_equal 'New Person', new_user.name
    assert new_user.connected_services.exists?(provider: 'developer', uid: 'brand-new-uid')
    assert_redirected_to root_url
  end

  test 'login links new connected service to existing user found by email' do
    assert_no_difference 'User.count' do
      assert_difference 'ConnectedService.count', 1 do
        post omniauth_callback_path(provider: 'developer')
      end
    end

    assert @user.connected_services.exists?(provider: 'developer', uid: 'test-uid-123')
    assert_redirected_to root_url
  end

  test 'login creates a database session' do
    assert_difference 'Session.count', 1 do
      post omniauth_callback_path(provider: 'developer')
    end

    assert Session.exists?(user: @user)
  end

  test 'login redirects to stored return URL when present' do
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_redirected_to '/login'

    post omniauth_callback_path(provider: 'developer')

    assert_redirected_to groceries_url(kitchen_slug: kitchen_slug)
  end

  # --- #destroy ---

  test 'logout terminates session and redirects to root' do
    post omniauth_callback_path(provider: 'developer')
    session_record = Session.last

    delete logout_path

    assert_redirected_to root_path
    assert_not Session.exists?(session_record.id)
  end

  # --- #failure ---

  test 'failure redirects to root' do
    get '/auth/failure'

    assert_redirected_to root_path
  end
end
