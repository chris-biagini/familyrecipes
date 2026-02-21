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

  test 'renders full recipe template with scale button' do
    get '/focaccia'

    assert_includes response.body, 'id="scale-button"'
  end

  test 'renders ingredient data attributes for scaling' do
    get '/focaccia'

    assert_match(/data-quantity-value=/, response.body)
  end

  test 'renders nutrition table when data exists' do
    get '/focaccia'

    assert_includes response.body, 'class="nutrition-facts"'
    assert_includes response.body, 'Nutrition Facts'
  end

  test 'renders recipe metadata with category link' do
    get '/focaccia'

    assert_match(%r{<a href="index\.html#[^"]+">Bread</a>}, response.body)
  end

  test 'includes recipe-state-manager script' do
    get '/focaccia'

    assert_includes response.body, 'recipe-state-manager.js'
  end
end
