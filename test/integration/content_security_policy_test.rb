# frozen_string_literal: true

require 'test_helper'

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'responses include Content-Security-Policy header' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_response :success

    csp = response.headers['Content-Security-Policy']

    assert csp, 'Expected Content-Security-Policy header to be present'

    assert_match(/default-src 'self'/, csp)
    assert_match(/script-src 'self' 'nonce-/, csp)
    assert_match(/style-src 'self'/, csp)
    assert_match(/connect-src 'self' ws: wss:/, csp)
    assert_match(/object-src 'none'/, csp)
    assert_match(/frame-src 'none'/, csp)
    assert_match(/base-uri 'self'/, csp)
    assert_match(/form-action 'self'/, csp)
  end
end
