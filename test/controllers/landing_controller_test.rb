# frozen_string_literal: true

require 'test_helper'

class LandingControllerTest < ActionDispatch::IntegrationTest
  test 'renders landing page' do
    get root_path

    assert_response :success
    assert_select 'h1', 'Family Recipes'
  end

  test 'lists kitchens' do
    Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')

    get root_path

    assert_response :success
    assert_select 'a', 'Test Kitchen'
  end
end
