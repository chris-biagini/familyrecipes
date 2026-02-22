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

  test 'update returns updated_references when title changes and cross-references exist' do
    MarkdownImporter.import(<<~MD)
      # Panzanella

      Category: Bread

      ## Assemble (put it together)

      - @[Focaccia], 1
      - Tomatoes, 3

      Tear bread and toss with tomatoes.
    MD

    updated_markdown = <<~MD
      # Rosemary Focaccia

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

    assert_includes body['updated_references'], 'Panzanella'

    panzanella = Recipe.find_by!(slug: 'panzanella')

    assert_includes panzanella.markdown_source, '@[Rosemary Focaccia]'
    assert_not_includes panzanella.markdown_source, '@[Focaccia]'
  end

  test 'create saves valid markdown and returns redirect URL' do
    markdown = <<~MD
      # Ciabatta

      A rustic bread.

      Category: Bread

      ## Mix (combine ingredients)

      - Flour, 4 cups
      - Water, 2 cups

      Mix and rest overnight.
    MD

    post recipes_path,
         params: { markdown_source: markdown },
         as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal recipe_path('ciabatta'), body['redirect_url']
    assert Recipe.find_by(slug: 'ciabatta')
  end

  test 'create rejects invalid markdown' do
    post recipes_path,
         params: { markdown_source: 'not valid' },
         as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)

    assert_predicate body['errors'], :any?
  end

  test 'create sets edited_at timestamp' do
    markdown = <<~MD
      # Ciabatta

      Category: Bread

      ## Mix (combine ingredients)

      - Flour, 4 cups

      Mix it.
    MD

    post recipes_path,
         params: { markdown_source: markdown },
         as: :json

    assert_response :success
    assert_not_nil Recipe.find_by!(slug: 'ciabatta').edited_at
  end

  test 'full edit round-trip: edit, save, re-render' do
    updated_markdown = <<~MD
      # Focaccia

      An updated description.

      Category: Bread
      Serves: 12

      ## Make the dough (combine ingredients)

      - Flour, 4 cups
      - Water, 1.5 cups: Warm.
      - Salt, 2 tsp
      - Olive oil, 3 tbsp

      Mix everything together and let rest for 2 hours.

      ## Bake (put it in the oven)

      Bake at 450 degrees for 25 minutes.

      ---

      Updated notes.
    MD

    # Save the edit
    patch recipe_path('focaccia'),
          params: { markdown_source: updated_markdown },
          as: :json

    assert_response :success

    # Re-render the page
    get recipe_path('focaccia')

    assert_response :success
    assert_select 'h1', 'Focaccia'
    assert_select '.recipe-meta', /Serves 12/
    assert_select '.ingredients li', 4
    assert_select 'b', 'Olive oil'
  end
end
