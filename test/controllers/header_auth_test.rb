# frozen_string_literal: true

require 'test_helper'

class HeaderAuthTest < ActionDispatch::IntegrationTest
  setup do
    setup_test_kitchen
  end

  test 'creates user and session from trusted headers' do
    assert_difference 'User.count', 1 do
      assert_difference 'Session.count', 1 do
        get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
          'HTTP_REMOTE_USER' => 'alice',
          'HTTP_REMOTE_NAME' => 'Alice Smith',
          'HTTP_REMOTE_EMAIL' => 'alice@example.com'
        }
      end
    end

    assert_response :success
    user = User.find_by(email: 'alice@example.com')

    assert_equal 'Alice Smith', user.name
    assert_predicate cookies[:session_id], :present?
  end

  test 'reuses existing user matched by email' do
    User.create!(name: 'Alice', email: 'alice@example.com')

    assert_no_difference 'User.count' do
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
        'HTTP_REMOTE_USER' => 'alice',
        'HTTP_REMOTE_NAME' => 'Alice Updated',
        'HTTP_REMOTE_EMAIL' => 'alice@example.com'
      }
    end

    assert_response :success
  end

  test 'does nothing without Remote-User header' do
    assert_no_difference 'User.count' do
      assert_no_difference 'Session.count' do
        get kitchen_root_path(kitchen_slug: @kitchen.slug)
      end
    end

    assert_response :success
  end

  test 'does not create duplicate session when cookie already valid' do
    get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
      'HTTP_REMOTE_USER' => 'alice',
      'HTTP_REMOTE_NAME' => 'Alice',
      'HTTP_REMOTE_EMAIL' => 'alice@example.com'
    }

    assert_difference 'Session.count', 0 do
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
        'HTTP_REMOTE_USER' => 'alice',
        'HTTP_REMOTE_NAME' => 'Alice',
        'HTTP_REMOTE_EMAIL' => 'alice@example.com'
      }
    end
  end

  test 'uses Remote-User as name fallback when Remote-Name is absent' do
    get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
      'HTTP_REMOTE_USER' => 'bob',
      'HTTP_REMOTE_EMAIL' => 'bob@example.com'
    }

    assert_equal 'bob', User.find_by(email: 'bob@example.com').name
  end

  test 'auto-joins new trusted-header user when sole kitchen exists' do
    assert_difference 'Membership.count', 1 do
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
        'HTTP_REMOTE_USER' => 'carol',
        'HTTP_REMOTE_NAME' => 'Carol',
        'HTTP_REMOTE_EMAIL' => 'carol@example.com'
      }
    end

    assert_response :success
    user = User.find_by!(email: 'carol@example.com')
    membership = Membership.find_by!(user_id: user.id, kitchen_id: @kitchen.id)

    assert_equal 'member', membership.role
  end

  test 'does not auto-join when multiple kitchens exist' do
    ActsAsTenant.without_tenant { Kitchen.create!(name: 'Other', slug: 'other') }

    assert_no_difference 'Membership.count' do
      assert_difference 'User.count', 1 do
        assert_difference 'Session.count', 1 do
          get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
            'HTTP_REMOTE_USER' => 'dave',
            'HTTP_REMOTE_NAME' => 'Dave',
            'HTTP_REMOTE_EMAIL' => 'dave@example.com'
          }
        end
      end
    end
  end

  test 'does not auto-join when user already has a membership' do
    existing = User.create!(name: 'Erin', email: 'erin@example.com')
    Membership.create!(kitchen: @kitchen, user: existing, role: 'owner')

    assert_no_difference 'Membership.count' do
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
        'HTTP_REMOTE_USER' => 'erin',
        'HTTP_REMOTE_NAME' => 'Erin',
        'HTTP_REMOTE_EMAIL' => 'erin@example.com'
      }
    end

    assert_equal 'owner', Membership.find_by!(user_id: existing.id).role
  end

  test 'ignores headers when peer IP is outside the allowlist' do
    assert_no_difference 'User.count' do
      assert_no_difference 'Session.count' do
        get kitchen_root_path(kitchen_slug: @kitchen.slug),
            headers: {
              'REMOTE_ADDR' => '203.0.113.5',
              'HTTP_REMOTE_USER' => 'mallory',
              'HTTP_REMOTE_NAME' => 'Mallory',
              'HTTP_REMOTE_EMAIL' => 'mallory@attacker.example'
            }
      end
    end

    assert_response :success
  end

  test 'ignores headers when peer is RFC1918 but XFF claims loopback' do
    # Regression: request.remote_ip walks the XFF chain past Rails default
    # trusted proxies (all RFC1918), so an attacker on any private network
    # could set XFF=127.0.0.1 to bypass the gate. The gate must read the
    # raw TCP peer (REMOTE_ADDR), not request.remote_ip.
    assert_no_difference 'User.count' do
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
        'REMOTE_ADDR' => '10.1.2.3',
        'HTTP_X_FORWARDED_FOR' => '127.0.0.1',
        'HTTP_REMOTE_USER' => 'mallory',
        'HTTP_REMOTE_EMAIL' => 'mallory@attacker.example'
      }
    end
  end

  test 'honors headers when peer IP is inside the default loopback allowlist' do
    # ActionDispatch::IntegrationTest sets REMOTE_ADDR to 127.0.0.1 by default,
    # which is inside the loopback default. No override needed.
    assert_difference 'User.count', 1 do
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
        'HTTP_REMOTE_USER' => 'frank',
        'HTTP_REMOTE_NAME' => 'Frank',
        'HTTP_REMOTE_EMAIL' => 'frank@example.com'
      }
    end
  end

  test 'honors a custom header name when TRUSTED_HEADER_USER is configured' do
    stub_trusted_proxy_config(user_header_name: 'X-Webauth-User', email_header_name: 'X-Webauth-Email') do
      assert_difference 'User.count', 1 do
        get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
          'HTTP_X_WEBAUTH_USER' => 'grace',
          'HTTP_X_WEBAUTH_EMAIL' => 'grace@example.com'
        }
      end
    end

    assert_predicate User.find_by(email: 'grace@example.com'), :present?
  end

  test 'ignores the default Remote-User header when a custom header name is configured' do
    stub_trusted_proxy_config(user_header_name: 'X-Webauth-User') do
      assert_no_difference 'User.count' do
        get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
          'HTTP_REMOTE_USER' => 'heidi',
          'HTTP_REMOTE_EMAIL' => 'heidi@example.com'
        }
      end
    end
  end

  private

  def stub_trusted_proxy_config(**overrides)
    original = Rails.application.config.trusted_proxy_config
    env = {
      'TRUSTED_HEADER_USER' => overrides[:user_header_name] || 'Remote-User',
      'TRUSTED_HEADER_EMAIL' => overrides[:email_header_name] || 'Remote-Email',
      'TRUSTED_HEADER_NAME' => overrides[:name_header_name] || 'Remote-Name'
    }
    Rails.application.config.trusted_proxy_config = FamilyRecipes::TrustedProxyConfig.from_env(env)
    yield
  ensure
    Rails.application.config.trusted_proxy_config = original
  end
end
