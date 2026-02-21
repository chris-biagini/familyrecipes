# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

require_relative '../../config/environment'
require 'rails/test_help'

class RecipesControllerTest < ActionDispatch::IntegrationTest
  test 'shows a recipe by slug' do
    get '/focaccia'

    assert_response :success
    assert_includes response.body, 'Focaccia'
  end

  test 'returns 404 for unknown recipe' do
    get '/nonexistent-recipe'

    assert_response :not_found
  end
end
