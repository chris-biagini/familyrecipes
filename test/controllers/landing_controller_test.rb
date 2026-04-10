# frozen_string_literal: true

require 'test_helper'

class LandingControllerTest < ActionDispatch::IntegrationTest
  setup do
    ActsAsTenant.without_tenant { Kitchen.destroy_all }
  end

  test 'redirects to /new when no kitchens exist' do
    get root_path

    assert_redirected_to new_kitchen_path
  end

  test 'renders sole kitchen homepage when one kitchen exists' do
    Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')

    get root_path

    assert_response :success
    assert_select 'h1', 'Our Recipes'
  end

  test 'renders kitchen list with create/join links when multiple kitchens exist' do
    Kitchen.create!(name: 'Kitchen A', slug: 'kitchen-a')
    Kitchen.create!(name: 'Kitchen B', slug: 'kitchen-b')

    get root_path

    assert_response :success
    assert_select 'a', 'Kitchen A'
    assert_select 'a', 'Kitchen B'
    assert_select "a[href='#{new_kitchen_path(intentional: true)}']"
    assert_select "a[href='#{join_kitchen_path}']"
  end
end
