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

  test 'renders edit button' do
    get recipe_path('focaccia')

    assert_select '#edit-button'
  end

  test 'renders editor dialog with markdown source' do
    get recipe_path('focaccia')

    assert_select '#recipe-editor'
    assert_select '#editor-textarea'
  end

  test 'renders scale button' do
    get recipe_path('focaccia')

    assert_select '#scale-button'
  end

  test 'renders ingredient data attributes for scaling' do
    get recipe_path('focaccia')

    assert_match(/data-quantity-value=/, response.body)
  end

  test 'update saves valid markdown and returns redirect URL' do
    updated_markdown = <<~MD
      # Focaccia

      A revised flatbread.

      Category: Bread
      Serves: 8

      ## Make the dough (combine ingredients)

      - Flour, 4 cups
      - Water, 1.5 cups: Warm.
      - Salt, 1 tsp

      Mix everything together and let rest for 1 hour.

      ## Bake (put it in the oven)

      Bake at 425 degrees for 20 minutes.

      ---

      A classic Italian bread.
    MD

    patch recipe_path('focaccia'),
          params: { markdown_source: updated_markdown },
          as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal recipe_path('focaccia'), body['redirect_url']

    recipe = Recipe.find_by!(slug: 'focaccia')

    assert_equal 'A revised flatbread.', recipe.description
    assert_not_nil recipe.edited_at
  end

  test 'update rejects invalid markdown' do
    patch recipe_path('focaccia'),
          params: { markdown_source: 'not valid markdown' },
          as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)

    assert_predicate body['errors'], :any?
  end

  test 'update returns 404 for unknown recipe' do
    patch recipe_path('nonexistent'),
          params: { markdown_source: '# Whatever' },
          as: :json

    assert_response :not_found
  end

  test 'update handles title change with new slug' do
    updated_markdown = <<~MD
      # Rosemary Focaccia

      A revised flatbread.

      Category: Bread
      Serves: 8

      ## Make the dough (combine ingredients)

      - Flour, 4 cups

      Mix everything together.
    MD

    patch recipe_path('focaccia'),
          params: { markdown_source: updated_markdown },
          as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal recipe_path('rosemary-focaccia'), body['redirect_url']
    assert_nil Recipe.find_by(slug: 'focaccia')
    assert Recipe.find_by(slug: 'rosemary-focaccia')
  end

  test 'update cleans up empty categories' do
    updated_markdown = <<~MD
      # Focaccia

      Category: Pastry

      ## Make it (do the thing)

      - Flour, 3 cups

      Mix everything.
    MD

    patch recipe_path('focaccia'),
          params: { markdown_source: updated_markdown },
          as: :json

    assert_response :success
    assert_nil Category.find_by(slug: 'bread')
    assert Category.find_by(slug: 'pastry')
  end
end
