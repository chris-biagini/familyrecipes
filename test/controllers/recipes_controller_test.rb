# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class RecipesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    create_kitchen_and_user
    @bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # Focaccia

      A simple flatbread.

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
          params: { markdown_source: updated_markdown, category: 'Bread' },
          as: :json

    assert_response :success
    body = response.parsed_body

    assert_equal 'focaccia', body['slug']

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

      Serves: 8

      ## Make the dough (combine ingredients)

      - Flour, 4 cups

      Mix everything together.
    MD

    log_in
    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: updated_markdown, category: 'Bread' },
          as: :json

    assert_response :success
    body = response.parsed_body

    assert_equal 'rosemary-focaccia', body['slug']
    assert_nil Recipe.find_by(slug: 'focaccia')
    assert Recipe.find_by(slug: 'rosemary-focaccia')
  end

  test 'update cleans up empty categories' do
    updated_markdown = <<~MD
      # Focaccia

      ## Make it (do the thing)

      - Flour, 3 cups

      Mix everything.
    MD

    log_in
    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: updated_markdown, category: 'Pastry' },
          as: :json

    assert_response :success
    assert_nil Category.find_by(slug: 'bread')
    assert Category.find_by(slug: 'pastry')
  end

  test 'update returns updated_references when title changes and cross-references exist' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # Panzanella

      ## Make bread.
      >>> @[Focaccia], 1

      ## Assemble (put it together)

      - Tomatoes, 3

      Tear bread and toss with tomatoes.
    MD

    updated_markdown = <<~MD
      # Rosemary Focaccia

      Serves: 8

      ## Make the dough (combine ingredients)

      - Flour, 4 cups

      Mix everything together.
    MD

    log_in
    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: updated_markdown, category: 'Bread' },
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

      ## Mix (combine ingredients)

      - Flour, 4 cups
      - Water, 2 cups

      Mix and rest overnight.
    MD

    log_in
    post recipes_path(kitchen_slug: kitchen_slug),
         params: { markdown_source: markdown, category: 'Bread' },
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

      ## Mix (combine ingredients)

      - Flour, 4 cups

      Mix it.
    MD

    log_in
    post recipes_path(kitchen_slug: kitchen_slug),
         params: { markdown_source: markdown, category: 'Bread' },
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

  test 'destroy nullifies inbound cross-references' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # Panzanella

      ## Make bread.
      >>> @[Focaccia], 1

      ## Assemble (put it together)

      - Tomatoes, 3

      Tear bread and toss.
    MD

    panzanella = Recipe.find_by!(slug: 'panzanella')
    original_source = panzanella.markdown_source
    xref_step = panzanella.steps.find_by!(title: 'Make bread.')
    xref = xref_step.cross_references.find_by!(target_title: 'Focaccia')

    log_in
    delete recipe_path('focaccia', kitchen_slug: kitchen_slug), as: :json

    assert_response :success

    xref.reload

    assert_nil xref.target_recipe_id
    assert_equal original_source, panzanella.reload.markdown_source
  end

  test 'show renders resolved cross-reference as embedded recipe card' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # Pizza Dough

      ## Mix.
      - Flour, 500 g
      - Water, 300 ml

      Combine ingredients.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # White Pizza

      ## Make dough.
      >>> @[Pizza Dough]

      ## Top.
      - Mozzarella, 200 g
    MD

    get recipe_path('white-pizza')

    assert_response :success

    assert_select 'article.embedded-recipe' do
      assert_select 'h3', text: 'Pizza Dough'
      assert_select 'a.embedded-recipe-link[href=?]', recipe_path('pizza-dough')
      assert_select '.ingredients li', count: 2
    end
  end

  test 'show renders pending cross-reference as broken reference card' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # White Pizza

      ## Make dough.
      >>> @[Nonexistent Recipe]
    MD

    get recipe_path('white-pizza')

    assert_response :success

    assert_select '.broken-reference', text: /Nonexistent Recipe/
    assert_select '.broken-reference', text: /no recipe with that name exists/
  end

  test 'show renders nested cross-reference as link when embedded' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # Starter

      ## Feed.
      - Flour, 100 g
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # Pizza Dough

      ## Make starter.
      >>> @[Starter]

      ## Mix.
      - Flour, 400 g
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # White Pizza

      ## Make dough.
      >>> @[Pizza Dough]
    MD

    get recipe_path('white-pizza')

    assert_response :success

    # Only one embedded card (Pizza Dough) — Starter is a link, not a nested card
    assert_select 'article.embedded-recipe', count: 1
    assert_select 'article.embedded-recipe h3', text: 'Pizza Dough'
    assert_select 'article.embedded-recipe a', text: 'Starter'
  end

  test 'destroy broadcasts to kitchen updates stream' do
    log_in

    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      delete recipe_path('focaccia')
    end
  end

  test 'destroy returns 404 for unknown recipe' do
    log_in
    delete recipe_path('nonexistent', kitchen_slug: kitchen_slug), as: :json

    assert_response :not_found
  end

  test 'create broadcasts to kitchen updates stream' do
    log_in

    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      post recipes_path(kitchen_slug: kitchen_slug),
           params: { markdown_source: "# New Bread\n\n## Mix (do it)\n\n- Flour, 1 cup\n\nMix.", category: 'Bread' },
           as: :json
    end
  end

  test 'update broadcasts to kitchen updates stream' do
    log_in

    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
            params: { markdown_source: @kitchen.recipes.find_by!(slug: 'focaccia').markdown_source },
            as: :json
    end
  end

  test 'embedded recipe with multiplier shows scaled quantities' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # Pizza Dough

      ## Mix.
      - Flour, 500 g
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # Double Pizza

      ## Make dough.
      >>> @[Pizza Dough], 2
    MD

    get recipe_path('double-pizza')

    assert_response :success

    assert_select 'article.embedded-recipe' do
      assert_select '.quantity', text: /1000/
    end
  end

  test 'recipe editor includes category dropdown' do
    log_in
    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_select '#recipe-editor select.category-select'
  end

  test 'create returns 422 when slug collides with different title' do
    colliding = <<~MD
      # Focaccia!

      ## Mix (do it)

      - Flour, 1 cup

      Mix.
    MD

    log_in
    post recipes_path(kitchen_slug: kitchen_slug),
         params: { markdown_source: colliding, category: 'Bread' },
         as: :json

    assert_response :unprocessable_entity
    body = response.parsed_body

    assert(body['errors'].any? { |e| e.include?('Focaccia') })
  end

  test 'update returns 422 when renamed title collides with another recipe' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # Ciabatta

      ## Mix (combine)

      - Flour, 4 cups

      Mix.
    MD

    colliding = <<~MD
      # Focaccia!

      ## Mix (do it)

      - Flour, 1 cup

      Mix.
    MD

    log_in
    patch recipe_path('ciabatta', kitchen_slug: kitchen_slug),
          params: { markdown_source: colliding, category: 'Bread' },
          as: :json

    assert_response :unprocessable_entity
    body = response.parsed_body

    assert(body['errors'].any? { |e| e.include?('Focaccia') })
  end

  test 'show_html serves rendered markdown as minimal HTML document' do
    get recipe_html_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_equal 'text/html; charset=utf-8', response.content_type
    assert_includes response.body, '<!DOCTYPE html>'
    assert_includes response.body, '<meta charset="utf-8">'
    assert_includes response.body, '<title>Focaccia</title>'
    assert_includes response.body, '<h2>'
    assert_not_includes response.body, '<script'
    assert_not_includes response.body, '<link'
  end

  test 'show_html returns 404 for unknown recipe' do
    get recipe_html_path('nonexistent', kitchen_slug: kitchen_slug)

    assert_response :not_found
  end

  test 'show_markdown serves raw markdown as text/plain UTF-8' do
    get recipe_markdown_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_equal 'text/plain; charset=utf-8', response.content_type
    assert_equal @kitchen.recipes.find_by!(slug: 'focaccia').markdown_source, response.body
  end

  test 'show_markdown returns 404 for unknown recipe' do
    get recipe_markdown_path('nonexistent', kitchen_slug: kitchen_slug)

    assert_response :not_found
  end

  test 'full edit round-trip: edit, save, re-render' do
    updated_markdown = <<~MD
      # Focaccia

      An updated description.

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
          params: { markdown_source: updated_markdown, category: 'Bread' },
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

  test 'content returns markdown source as JSON for members' do
    log_in
    get recipe_content_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    body = response.parsed_body

    assert_equal @kitchen.recipes.find_by!(slug: 'focaccia').markdown_source, body['markdown_source']
  end

  test 'content returns 403 for non-members' do
    get recipe_content_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'content returns 404 for unknown recipe' do
    log_in
    get recipe_content_path('nonexistent', kitchen_slug: kitchen_slug)

    assert_response :not_found
  end
end
