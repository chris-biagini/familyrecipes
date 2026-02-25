# frozen_string_literal: true

require 'test_helper'

class HeaderAuthTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    add_placeholder_auth_routes
  end

  teardown do
    reload_original_routes
  end

  test 'creates user and session from trusted headers' do
    assert_difference 'User.count', 1 do
      assert_difference 'Session.count', 1 do
        get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
          'Remote-User' => 'alice',
          'Remote-Name' => 'Alice Smith',
          'Remote-Email' => 'alice@example.com'
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
        'Remote-User' => 'alice',
        'Remote-Name' => 'Alice Updated',
        'Remote-Email' => 'alice@example.com'
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
      'Remote-User' => 'alice',
      'Remote-Name' => 'Alice',
      'Remote-Email' => 'alice@example.com'
    }

    assert_difference 'Session.count', 0 do
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
        'Remote-User' => 'alice',
        'Remote-Name' => 'Alice',
        'Remote-Email' => 'alice@example.com'
      }
    end
  end

  test 'uses Remote-User as name fallback when Remote-Name is absent' do
    get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
      'Remote-User' => 'bob',
      'Remote-Email' => 'bob@example.com'
    }

    assert_equal 'bob', User.find_by(email: 'bob@example.com').name
  end

  private

  # Nav partial still references login_path/logout_path removed in Task 0.
  # Temporarily add placeholders so these tests render pages until Task 6 restores routes.
  def add_placeholder_auth_routes
    return if Rails.application.routes.named_routes.key?(:login)

    @routes_need_reload = true
    Rails.application.routes.append do
      get 'login', to: 'dev_sessions#create', as: :login
      delete 'logout', to: 'dev_sessions#destroy', as: :logout
    end
  end

  def reload_original_routes
    return unless @routes_need_reload

    Rails.application.reload_routes!
  end
end
