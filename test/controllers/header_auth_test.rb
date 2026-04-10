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
end
