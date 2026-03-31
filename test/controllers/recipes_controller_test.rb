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
    assert_select '.recipe-yield', /Serves 8/
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

  test 'renders editor dialog with Turbo Frame' do
    log_in

    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_select '#recipe-editor turbo-frame#recipe-editor-content[src]'
    assert_select '#recipe-editor turbo-frame[data-editor-target="frame"]'
  end

  test 'renders scale bar with toggle and presets' do
    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_select '.scale-bar .scale-toggle'
    assert_select '.scale-preset', count: 4
    assert_select '.scale-input'
  end

  test 'renders ingredient data attributes for scaling' do
    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_match(/data-quantity-low=/, response.body)
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
      > @[Focaccia], 1

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
    xref = panzanella.cross_references.find_by(target_title: 'Rosemary Focaccia')

    assert xref, 'cross-reference to Rosemary Focaccia should exist'
    assert_nil panzanella.cross_references.find_by(target_title: 'Focaccia')
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
      > @[Focaccia], 1

      ## Assemble (put it together)

      - Tomatoes, 3

      Tear bread and toss.
    MD

    panzanella = Recipe.find_by!(slug: 'panzanella')
    xref_step = panzanella.steps.find_by!(title: 'Make bread.')
    xref = xref_step.cross_references.find_by!(target_title: 'Focaccia')

    log_in
    delete recipe_path('focaccia', kitchen_slug: kitchen_slug), as: :json

    assert_response :success

    xref.reload

    assert_nil xref.target_recipe_id
    assert_predicate xref, :persisted?
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
      > @[Pizza Dough]

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
      > @[Nonexistent Recipe]
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
      > @[Starter]

      ## Mix.
      - Flour, 400 g
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # White Pizza

      ## Make dough.
      > @[Pizza Dough]
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
    focaccia = @kitchen.recipes.find_by!(slug: 'focaccia')
    ir = FamilyRecipes::RecipeSerializer.from_record(focaccia)
    focaccia_markdown = FamilyRecipes::RecipeSerializer.serialize(ir)

    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
            params: { markdown_source: focaccia_markdown },
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
      > @[Pizza Dough], 2
    MD

    get recipe_path('double-pizza')

    assert_response :success

    assert_select 'article.embedded-recipe' do
      assert_select '.quantity', text: /1000/
    end
  end

  test 'embedded recipe article includes data-base-multiplier' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # Pizza Dough

      ## Mix.
      - Flour, 500 g
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # Double Pizza

      ## Make dough.
      > @[Pizza Dough], 2
    MD

    get recipe_path('double-pizza')

    assert_select 'article.embedded-recipe[data-base-multiplier="2.0"]'
  end

  test 'recipe editor uses Turbo Frame instead of inline content' do
    log_in
    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_select '#recipe-editor turbo-frame#recipe-editor-content'
    assert_select '#recipe-editor select.category-select', count: 0
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

    focaccia = @kitchen.recipes.find_by!(slug: 'focaccia')
    ir = FamilyRecipes::RecipeSerializer.from_record(focaccia)
    expected = FamilyRecipes::RecipeSerializer.serialize(ir)

    assert_equal expected, response.body
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
    assert_select '.recipe-yield', /Serves 12/
    assert_select '.ingredients li', 4
    assert_select 'b', 'Olive oil'
  end

  test 'content returns markdown source as JSON for members' do
    log_in
    get recipe_content_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    body = response.parsed_body

    assert_includes body['markdown_source'], '# Focaccia'
    assert_includes body['markdown_source'], 'Serves: 8'
  end

  test 'content returns structure alongside markdown' do
    log_in
    get recipe_content_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :ok
    body = response.parsed_body

    assert_includes body['markdown_source'], '# Focaccia'
    assert_equal 'Focaccia', body['structure']['title']
    assert_equal 2, body['structure']['steps'].size
    assert_equal 'Make the dough (combine ingredients)', body['structure']['steps'][0]['tldr']
  end

  test 'content regenerates markdown_source with front matter' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')
    recipe.tags.create!(name: 'italian', kitchen: @kitchen)

    log_in
    get recipe_content_path('focaccia', kitchen_slug: kitchen_slug)

    body = response.parsed_body

    assert_includes body['markdown_source'], 'Category: Bread'
    assert_includes body['markdown_source'], 'Tags: italian'
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

  test 'create with tags assigns tags to the recipe' do
    markdown = "# Tag Test\n\n## Step (do it)\n\n- Flour, 1 cup\n\nMix."
    log_in
    post recipes_path(kitchen_slug: kitchen_slug),
         params: { markdown_source: markdown, category: @bread.name,
                   tags: %w[vegan quick] },
         as: :json

    assert_response :success
    recipe = Recipe.find_by!(slug: 'tag-test')

    assert_equal %w[quick vegan], recipe.tags.map(&:name).sort
  end

  test 'update with tags syncs tags' do
    focaccia = @kitchen.recipes.find_by!(slug: 'focaccia')
    ir = FamilyRecipes::RecipeSerializer.from_record(focaccia)
    focaccia_markdown = FamilyRecipes::RecipeSerializer.serialize(ir)

    log_in
    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: focaccia_markdown, category: @bread.name,
                    tags: %w[vegan] },
          as: :json

    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: focaccia_markdown, category: @bread.name,
                    tags: %w[quick weeknight] },
          as: :json

    assert_response :success
    recipe = Recipe.find_by!(slug: 'focaccia')

    assert_equal %w[quick weeknight], recipe.tags.map(&:name).sort
  end

  test 'show page displays tags as pills' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')
    tag = Tag.create!(name: 'vegan', kitchen: @kitchen)
    RecipeTag.create!(recipe: recipe, tag: tag)

    get recipe_path(recipe.slug, kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.recipe-tag-pill', /vegan/
  end

  test 'full tag lifecycle: create, update, display, remove' do
    markdown = "# Tag Lifecycle\n\n## Step (do it)\n\n- Flour, 1 cup\n\nMix."

    log_in
    post recipes_path(kitchen_slug: kitchen_slug),
         params: { markdown_source: markdown, category: @bread.name,
                   tags: %w[vegan quick] },
         as: :json

    assert_response :success

    get recipe_path('tag-lifecycle', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.recipe-tag-pill', count: 2

    patch recipe_path('tag-lifecycle', kitchen_slug: kitchen_slug),
          params: { markdown_source: markdown, category: @bread.name,
                    tags: %w[vegan weeknight] },
          as: :json

    assert_response :success

    recipe = Recipe.find_by!(slug: 'tag-lifecycle')

    assert_equal %w[vegan weeknight], recipe.tags.map(&:name).sort
    assert_not Tag.exists?(name: 'quick')
  end

  test 'parse returns IR from markdown' do
    log_in
    post recipe_parse_path,
         params: { markdown_source: "# Test\n\nServes: 2\n\n## Mix.\n\n- Flour\n\nMix." },
         as: :json

    assert_response :ok
    body = response.parsed_body

    assert_equal 'Test', body['title']
    assert_equal 'Mix.', body['steps'][0]['tldr']
    assert_equal 'Flour', body['steps'][0]['ingredients'][0]['name']
  end

  test 'parse returns errors for invalid markdown' do
    log_in
    post recipe_parse_path, params: { markdown_source: '' }, as: :json

    assert_response :unprocessable_content
    assert_predicate response.parsed_body['errors'], :any?
  end

  test 'serialize returns markdown from IR' do
    log_in
    ir = {
      title: 'Test',
      description: nil,
      front_matter: { serves: '2' },
      steps: [{
        tldr: 'Mix.',
        ingredients: [{ name: 'Flour', quantity: nil, prep_note: nil }],
        instructions: 'Mix.', cross_reference: nil
      }],
      footer: nil
    }

    post recipe_serialize_path, params: { structure: ir }, as: :json

    assert_response :ok
    body = response.parsed_body

    assert_includes body['markdown_source'], '# Test'
    assert_includes body['markdown_source'], '## Mix.'
    assert_includes body['markdown_source'], '- Flour'
  end

  test 'create with structure param uses structured path' do
    log_in
    ir = {
      title: 'GUI Recipe',
      description: nil,
      front_matter: { category: 'Basics', tags: %w[test] },
      steps: [{
        tldr: 'Mix.',
        ingredients: [{ name: 'Flour', quantity: nil, prep_note: nil }],
        instructions: 'Mix.', cross_reference: nil
      }],
      footer: nil
    }

    assert_difference 'Recipe.count', 1 do
      post recipes_path, params: { structure: ir }, as: :json
    end

    assert_response :ok
    recipe = Recipe.last

    assert_equal 'GUI Recipe', recipe.title
    assert_equal 'Basics', recipe.category.name
  end

  test 'update with structure param uses structured path' do
    log_in
    recipe = create_recipe("# Existing\n\n## Step\n\n- Flour\n\nMix.")

    ir = {
      title: 'Existing',
      description: 'Now with a description.',
      front_matter: {},
      steps: [{
        tldr: 'Step.',
        ingredients: [{ name: 'Flour', quantity: nil, prep_note: nil }],
        instructions: 'Mix.', cross_reference: nil
      }],
      footer: nil
    }

    patch recipe_path(recipe.slug), params: { structure: ir }, as: :json

    assert_response :ok
    recipe.reload

    assert_equal 'Now with a description.', recipe.description
  end

  test 'create with structure rejects unexpected top-level keys' do
    log_in
    ir = {
      title: 'Bad Recipe', evil: 'payload',
      steps: [{ tldr: 'Mix.', ingredients: [], instructions: 'Mix.', cross_reference: nil }],
      description: nil, front_matter: {}, footer: nil
    }

    post recipes_path, params: { structure: ir }, as: :json

    assert_response :bad_request
  end

  test 'update with structure rejects unexpected top-level keys' do
    log_in
    ir = {
      title: 'Focaccia', injected: true,
      steps: [{ tldr: 'Mix.', ingredients: [], instructions: 'Mix.', cross_reference: nil }],
      description: nil, front_matter: {}, footer: nil
    }

    patch recipe_path('focaccia'), params: { structure: ir }, as: :json

    assert_response :bad_request
  end

  test 'show renders recipe with freeform quantity ingredient' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # Salad

      ## Toss (combine ingredients)

      - Basil, a few leaves
      - Lettuce, 1 head

      Toss everything together.
    MD

    get recipe_path('salad', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'b.ingredient-name', text: 'Basil'
    assert_select 'li', text: /a few leaves/
  end

  test 'hides nutrition table when show_nutrition is false' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')
    recipe.update_column(:nutrition_data, { # rubocop:disable Rails/SkipsModelValidations
                           'totals' => { 'calories' => 200 },
                           'per_serving' => { 'calories' => 25 }
                         })

    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.nutrition-label', count: 0
  end

  test 'show renders ingredient tooltip title when nutrition data present' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')
    first = recipe.steps.first.ingredients.first
    unit_key = FamilyRecipes::Inflector.normalize_unit(first.unit) || '~unitless'
    recipe.update_column(:nutrition_data, { # rubocop:disable Rails/SkipsModelValidations
                           'ingredient_details' => {
                             first.name.downcase => {
                               'nutrients_per_gram' => {
                                 'calories' => 3.0, 'protein' => 0.1, 'fat' => 0.01,
                                 'carbs' => 0.8, 'sodium' => 0.02, 'fiber' => 0.03
                               },
                               'grams_per_unit' => { unit_key => 1.0 }
                             }
                           },
                           'missing_ingredients' => [],
                           'partial_ingredients' => [],
                           'skipped_ingredients' => [],
                           'totals' => { 'calories' => 820.0 }
                         })

    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.ingredients li[title]'
  end

  test 'shows nutrition table when show_nutrition is true' do
    @kitchen.update!(show_nutrition: true)
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')
    recipe.update_column(:nutrition_data, { # rubocop:disable Rails/SkipsModelValidations
                           'totals' => { 'calories' => 200 },
                           'per_serving' => { 'calories' => 25 }
                         })

    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.nutrition-label'
  end

  # --- editor_frame ---

  test 'editor_frame returns turbo frame with correct ID' do
    log_in
    get recipe_editor_frame_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'turbo-frame#recipe-editor-content'
  end

  test 'editor_frame contains embedded markdown JSON' do
    log_in
    get recipe_editor_frame_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'script[type="application/json"][data-editor-markdown]' do |scripts|
      json = JSON.parse(scripts.first.text)

      assert_includes json['plaintext'], '# Focaccia'
      assert_includes json['plaintext'], 'Serves: 8'
    end
  end

  test 'editor_frame contains server-rendered graphical form with step cards' do
    log_in
    get recipe_editor_frame_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.graphical-step-card', count: 2
    assert_select '.graphical-step-title', text: 'Make the dough (combine ingredients)'
    assert_select '.graphical-step-title', text: 'Bake (put it in the oven)'
    assert_select '.graphical-ingredient-card', count: 3
  end

  test 'editor_frame pre-populates front matter fields' do
    log_in
    get recipe_editor_frame_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select "input[data-recipe-graphical-target='title']" do |inputs|
      assert_equal 'Focaccia', inputs.first['value']
    end
    assert_select "textarea[data-recipe-graphical-target='description']", text: 'A simple flatbread.'
    assert_select "input[data-recipe-graphical-target='serves']" do |inputs|
      assert_equal '8', inputs.first['value']
    end
  end

  test 'editor_frame includes plaintext container with CodeMirror mount' do
    log_in
    get recipe_editor_frame_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.cm-mount'
  end

  test 'editor_frame requires membership' do
    get recipe_editor_frame_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'editor_frame returns 404 for unknown recipe' do
    log_in
    get recipe_editor_frame_path('nonexistent', kitchen_slug: kitchen_slug)

    assert_response :not_found
  end

  test 'editor_frame renders cross-reference steps' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # Pizza Dough

      ## Mix.
      - Flour, 500 g

      Combine ingredients.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
      # White Pizza

      ## Make dough.
      > @[Pizza Dough], 2

      ## Top (add toppings)
      - Mozzarella, 200 g

      Spread cheese.
    MD

    log_in
    get recipe_editor_frame_path('white-pizza', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.graphical-step-card--crossref .graphical-crossref-label', text: /Imports from Pizza Dough/
    assert_select '.graphical-crossref-hint', text: 'edit in </> mode'
  end

  test 'editor_frame pre-populates footer' do
    log_in
    get recipe_editor_frame_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select "textarea[data-recipe-graphical-target='footer']", text: 'A classic Italian bread.'
  end
end
