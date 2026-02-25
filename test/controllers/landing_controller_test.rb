# frozen_string_literal: true

require 'test_helper'

class LandingControllerTest < ActionDispatch::IntegrationTest
  setup do
    add_placeholder_auth_routes
  end

  teardown do
    reload_original_routes
  end

  test 'redirects to sole kitchen when exactly one exists' do
    kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')

    get root_path

    assert_redirected_to kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  test 'renders landing page when no kitchens exist' do
    get root_path

    assert_response :success
    assert_select 'h1', 'Family Recipes'
  end

  test 'renders landing page with kitchen list when multiple exist' do
    Kitchen.create!(name: 'Kitchen A', slug: 'kitchen-a')
    Kitchen.create!(name: 'Kitchen B', slug: 'kitchen-b')

    get root_path

    assert_response :success
    assert_select 'a', 'Kitchen A'
    assert_select 'a', 'Kitchen B'
  end

  private

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
