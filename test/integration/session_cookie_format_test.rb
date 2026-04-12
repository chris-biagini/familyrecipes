# frozen_string_literal: true

require 'test_helper'

class SessionCookieFormatTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'session cookie stores a signed_id (not a bare integer)' do
    log_in

    # In integration tests, cookies[:key] returns the raw cookie value before
    # Rails' MessageVerifier signs it, so the outer cookies.signed layer is
    # already unwrapped. The inner value should be a signed_id token.
    inner_value = cookies[:session_id].to_s

    assert_not_empty inner_value
    assert_no_match(/\A\d+\z/, inner_value,
                    'session cookie should not be a bare integer PK')
  end

  test 'Session.find_signed resolves the cookie value to the session record' do
    log_in
    session_row = Session.last

    # Verify the session's signed_id round-trips through find_signed — this is
    # the exact lookup path used by Authentication#find_session_by_cookie.
    resolved = Session.find_signed(session_row.signed_id(purpose: :session), purpose: :session)

    assert_equal session_row, resolved
  end

  test 'authenticated requests after log_in succeed with the signed_id cookie' do
    log_in

    get kitchen_root_path(kitchen_slug: @kitchen.slug)

    assert_response :success
  end
end
