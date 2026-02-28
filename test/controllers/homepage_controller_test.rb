# frozen_string_literal: true

require 'test_helper'

class HomepageControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'renders the homepage with categories and recipes' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      A simple flatbread.

      Category: Bread

      ## Make the dough (mix ingredients)

      - Flour, 3 cups

      Mix well.
    MD

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'h1', 'Our Recipes'
    assert_select 'a[href=?]', recipe_path('focaccia', kitchen_slug: kitchen_slug), text: 'Focaccia'
  end

  test 'groups recipes by category with table of contents' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    Category.create!(name: 'Pasta', slug: 'pasta', position: 1, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      A simple flatbread.

      Category: Bread

      ## Make the dough (mix ingredients)

      - Flour, 3 cups

      Mix well.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Cacio e Pepe

      Roman pasta classic.

      Category: Pasta

      ## Cook the pasta (boil it)

      - Spaghetti, 1 lb

      Cook until al dente.
    MD

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.toc_nav a', count: 2
    assert_select 'section#bread h2', 'Bread'
    assert_select 'section#pasta h2', 'Pasta'
  end

  test 'skips empty categories' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    Category.create!(name: 'Empty', slug: 'empty', position: 1, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      A simple flatbread.

      Category: Bread

      ## Make the dough (mix ingredients)

      - Flour, 3 cups

      Mix well.
    MD

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'section#bread', count: 1
    assert_select 'section#empty', count: 0
  end

  test 'homepage includes turbo stream subscription for members' do
    log_in
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'turbo-cable-stream-source'
  end

  test 'homepage excludes turbo stream subscription for non-members' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'turbo-cable-stream-source', count: 0
  end

  test 'recipe links include description as title attribute' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      A simple flatbread.

      Category: Bread

      ## Make the dough (mix ingredients)

      - Flour, 3 cups

      Mix well.
    MD

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'a[title="A simple flatbread."]', text: 'Focaccia'
  end
end
