# frozen_string_literal: true

require 'test_helper'

class RecipesControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
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
    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'h1', 'Focaccia'
    assert_select '.recipe-meta', /Bread/
    assert_select '.recipe-meta', /Serves 8/
    assert_select 'h2', 'Make the dough (combine ingredients)'
    assert_select '.ingredients li', 3
    assert_select 'b', 'Flour'
  end

  test 'returns 404 for unknown recipe' do
    get recipe_path('nonexistent', kitchen_slug: kitchen_slug)

    assert_response :not_found
  end

  test 'attaches recipe-state Stimulus controller' do
    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_select 'article[data-controller*="recipe-state"]'
  end

  test 'renders edit button for members' do
    log_in

    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_select '#edit-button'
  end

  test 'renders editor dialog with markdown source' do
    log_in

    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_select '#recipe-editor'
    assert_select '.editor-textarea'
  end

  test 'renders scale button' do
    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_select '#scale-button'
  end

  test 'renders ingredient data attributes for scaling' do
    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_match(/data-quantity-value=/, response.body)
  end

  test 'recipe page includes turbo stream subscription for members' do
    log_in
    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_select 'turbo-cable-stream-source'
  end

  test 'recipe page excludes turbo stream subscription for non-members' do
    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_select 'turbo-cable-stream-source', count: 0
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

    log_in
    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: updated_markdown },
          as: :json

    assert_response :success
    body = response.parsed_body

    assert_equal recipe_path('focaccia', kitchen_slug: kitchen_slug), body['redirect_url']

    recipe = Recipe.find_by!(slug: 'focaccia')

    assert_equal 'A revised flatbread.', recipe.description
    assert_not_nil recipe.edited_at
  end

  test 'update rejects invalid markdown' do
    log_in
    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: 'not valid markdown' },
          as: :json

    assert_response :unprocessable_entity
    body = response.parsed_body

    assert_predicate body['errors'], :any?
  end

  test 'update returns 404 for unknown recipe' do
    log_in
    patch recipe_path('nonexistent', kitchen_slug: kitchen_slug),
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

    log_in
    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: updated_markdown },
          as: :json

    assert_response :success
    body = response.parsed_body

    assert_equal recipe_path('rosemary-focaccia', kitchen_slug: kitchen_slug), body['redirect_url']
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

    log_in
    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: updated_markdown },
          as: :json

    assert_response :success
    assert_nil Category.find_by(slug: 'bread')
    assert Category.find_by(slug: 'pastry')
  end

  test 'update returns updated_references when title changes and cross-references exist' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
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

    log_in
    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: updated_markdown },
          as: :json

    assert_response :success
    body = response.parsed_body

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

    log_in
    post recipes_path(kitchen_slug: kitchen_slug),
         params: { markdown_source: markdown },
         as: :json

    assert_response :success
    body = response.parsed_body

    assert_equal recipe_path('ciabatta', kitchen_slug: kitchen_slug), body['redirect_url']
    assert Recipe.find_by(slug: 'ciabatta')
  end

  test 'create rejects invalid markdown' do
    log_in
    post recipes_path(kitchen_slug: kitchen_slug),
         params: { markdown_source: 'not valid' },
         as: :json

    assert_response :unprocessable_entity
    body = response.parsed_body

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

    log_in
    post recipes_path(kitchen_slug: kitchen_slug),
         params: { markdown_source: markdown },
         as: :json

    assert_response :success
    assert_not_nil Recipe.find_by!(slug: 'ciabatta').edited_at
  end

  test 'destroy deletes recipe and returns redirect to homepage' do
    log_in
    delete recipe_path('focaccia', kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    body = response.parsed_body

    assert_equal kitchen_root_path(kitchen_slug: kitchen_slug), body['redirect_url']
    assert_nil Recipe.find_by(slug: 'focaccia')
  end

  test 'destroy cleans up empty categories' do
    log_in
    delete recipe_path('focaccia', kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    assert_nil Category.find_by(slug: 'bread')
  end

  test 'destroy strips cross-references from referencing recipes' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Panzanella

      Category: Bread

      ## Assemble (put it together)

      - @[Focaccia], 1
      - Tomatoes, 3

      Tear bread and toss.
    MD

    log_in
    delete recipe_path('focaccia', kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    body = response.parsed_body

    assert_includes body['updated_references'], 'Panzanella'

    panzanella = Recipe.find_by!(slug: 'panzanella')

    assert_includes panzanella.markdown_source, 'Focaccia'
    assert_not_includes panzanella.markdown_source, '@[Focaccia]'
  end

  test 'show renders pending cross-reference as plain text' do
    category = Category.create!(name: 'Main', slug: 'main', kitchen: @kitchen)
    recipe = Recipe.create!(
      title: 'Pasta', slug: 'pasta', category: category,
      markdown_source: "# Pasta\n\nCategory: Main\n\n## Cook\n\n- Spaghetti\n\nCook.",
      kitchen: @kitchen
    )
    step = recipe.steps.create!(title: 'Cook', position: 0)
    step.cross_references.create!(
      target_slug: 'missing-sauce', target_title: 'Missing Sauce',
      position: 0, multiplier: 1.0
    )

    get recipe_path('pasta', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'li.cross-reference b', 'Missing Sauce'
    assert_select 'li.cross-reference a', count: 0
  end

  test 'destroy returns 404 for unknown recipe' do
    log_in
    delete recipe_path('nonexistent', kitchen_slug: kitchen_slug), as: :json

    assert_response :not_found
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
    log_in
    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: updated_markdown },
          as: :json

    assert_response :success

    # Re-render the page
    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'h1', 'Focaccia'
    assert_select '.recipe-meta', /Serves 12/
    assert_select '.ingredients li', 4
    assert_select 'b', 'Olive oil'
  end
end
