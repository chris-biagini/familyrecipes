# frozen_string_literal: true

require 'test_helper'

class LandingControllerTest < ActionDispatch::IntegrationTest
  setup do
    ActsAsTenant.without_tenant { Kitchen.destroy_all }
  end

  test 'renders homepage for sole kitchen without redirect' do
    Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')

    get root_path

    assert_response :success
    assert_select 'h1', 'Our Recipes'
  end

  test 'renders landing page when no kitchens exist' do
    get root_path

    assert_response :success
    assert_select 'h1', 'Family Recipes'
  end

  test 'renders landing page with kitchen list when multiple exist' do
    with_multi_kitchen do
      Kitchen.create!(name: 'Kitchen A', slug: 'kitchen-a')
      Kitchen.create!(name: 'Kitchen B', slug: 'kitchen-b')
    end

    get root_path

    assert_response :success
    assert_select 'a', 'Kitchen A'
    assert_select 'a', 'Kitchen B'
  end
end
