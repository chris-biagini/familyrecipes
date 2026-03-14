# frozen_string_literal: true

require 'test_helper'

class HomepageControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'renders the homepage with categories and recipes' do
    bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: bread)
      # Focaccia

      A simple flatbread.


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
    bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    pasta = Category.create!(name: 'Pasta', slug: 'pasta', position: 1, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: bread)
      # Focaccia

      A simple flatbread.


      ## Make the dough (mix ingredients)

      - Flour, 3 cups

      Mix well.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: pasta)
      # Cacio e Pepe

      Roman pasta classic.


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
    bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    Category.create!(name: 'Empty', slug: 'empty', position: 1, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: bread)
      # Focaccia

      A simple flatbread.


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

  test 'new recipe editor includes textarea without side panel' do
    log_in
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '#recipe-editor textarea.editor-textarea'
    assert_select '#recipe-editor select.category-select', count: 0
  end

  test 'homepage renders Edit Categories button for members' do
    log_in
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '#edit-categories-button'
  end

  test 'homepage does not render Edit Categories for non-members' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '#edit-categories-button', count: 0
  end

  test 'homepage uses kitchen site_title in page title' do
    log_in
    @kitchen.update!(site_title: 'Our Family Kitchen')
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'title', 'Our Family Kitchen'
  end

  test 'homepage uses kitchen heading and subtitle' do
    log_in
    @kitchen.update!(homepage_heading: 'Custom Heading', homepage_subtitle: 'Custom Sub')
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'h1', 'Custom Heading'
    assert_select 'header p', 'Custom Sub'
  end

  test 'recipe links include description as title attribute' do
    bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: bread)
      # Focaccia

      A simple flatbread.


      ## Make the dough (mix ingredients)

      - Flour, 3 cups

      Mix well.
    MD

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'a[title="A simple flatbread."]', text: 'Focaccia'
  end
end
