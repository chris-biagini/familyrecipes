# frozen_string_literal: true

require 'test_helper'

class LandingControllerTest < ActionDispatch::IntegrationTest

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

end
