# frozen_string_literal: true

require 'test_helper'

class RecipesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)
    MarkdownImporter.import(<<~MD)
      # Focaccia

      A simple flatbread.

      Category: Bread
      Serves: 8

      ## Make the dough (combine ingredients)

      - Flour, 3 cups
      - Water, 1 cup: Warm.
      - Salt, 1 tsp

      Mix everything together and let rest for 1* hour.

      ## Bake (put it in the oven)

      Bake at 425* degrees for 20* minutes.

      ---

      A classic Italian bread.
    MD
  end

  test 'renders a recipe page' do
    get recipe_path('focaccia')

    assert_response :success
    assert_select 'h1', 'Focaccia'
    assert_select '.recipe-meta', /Bread/
    assert_select '.recipe-meta', /Serves 8/
    assert_select 'h2', 'Make the dough (combine ingredients)'
    assert_select '.ingredients li', 3
    assert_select 'b', 'Flour'
  end

  test 'returns 404 for unknown recipe' do
    get recipe_path('nonexistent')

    assert_response :not_found
  end

  test 'includes recipe JavaScript' do
    get recipe_path('focaccia')

    assert_select 'script[src*="recipe-state-manager"]'
  end

  test 'renders scale button' do
    get recipe_path('focaccia')

    assert_select '#scale-button'
  end

  test 'renders ingredient data attributes for scaling' do
    get recipe_path('focaccia')

    assert_match(/data-quantity-value=/, response.body)
  end
end
