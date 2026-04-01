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
    assert_select '.index-nav-link a', count: 2
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

  test 'new recipe editor includes CodeMirror mount without side panel' do
    log_in
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '#recipe-editor .cm-mount'
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

  test 'recipe cards show description as visible text' do
    bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: bread)
      # Focaccia

      A simple flatbread.


      ## Make the dough (mix ingredients)

      - Flour, 3 cups

      Mix well.
    MD

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.recipe-card .recipe-card-title', text: 'Focaccia'
    assert_select '.recipe-card .recipe-description', text: 'A simple flatbread.'
  end

  test 'recipe cards display tag pills' do
    @kitchen.update!(decorate_tags: false)
    Category.create!(name: 'Weeknight', slug: 'weeknight', position: 0, kitchen: @kitchen)
    create_recipe("# Tagged Recipe\n\nCategory: Weeknight\nTags: weeknight, italian\n\n## Cook it\n\nDo the thing.",
                  category_name: 'Weeknight', kitchen: @kitchen)

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.recipe-card .recipe-tag', count: 2
    assert_select '.recipe-card .recipe-tag', text: 'weeknight'
    assert_select '.recipe-card .recipe-tag', text: 'italian'
  end

  test 'recipe listings render as cards with descriptions' do
    bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    create_recipe("# Tasty Pasta\n\nA simple weeknight meal.\n\nCategory: #{bread.name}\n\n- Pasta, 400 g",
                  category_name: bread.name, kitchen: @kitchen)

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.recipe-card' do |cards|
      assert_operator cards.size, :>=, 1
    end
    assert_select '.recipe-card .recipe-description', text: /simple weeknight/
  end

  test 'recipe cards omit description when blank' do
    bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    create_recipe("# No Desc Recipe\n\nCategory: #{bread.name}\n\n- Flour, 1 cup", category_name: bread.name,
                                                                                   kitchen: @kitchen)

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.recipe-card .recipe-description', count: 0
  end

  test 'recipe cards carry data-tags attribute' do
    bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    create_recipe("# Tagged\n\nCategory: #{bread.name}\nTags: weeknight, comfort-food\n\n- Flour, 1 cup",
                  category_name: bread.name, kitchen: @kitchen)

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.recipe-card[data-recipe-filter-target="card"][data-tags="comfort-food,weeknight"]'
  end

  test 'category sections have back-to-top link' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    create_recipe("# Something\n\nCategory: Bread\n\n- Flour, 1 cup", category_name: 'Bread', kitchen: @kitchen)

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'section .category-top-link'
  end

  test 'tag filter bar renders when recipes have tags' do
    bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    create_recipe(
      "# Tagged\n\nCategory: #{bread.name}\nTags: weeknight\n\n- Flour, 1 cup",
      category_name: bread.name, kitchen: @kitchen
    )

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.index-nav .tag-filter-pill', count: 1
    assert_select '.tag-filter-pill', text: /weeknight/
  end

  test 'tag filter bar absent when no tags exist' do
    bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    create_recipe(
      "# Plain\n\nCategory: #{bread.name}\n\n- Flour, 1 cup",
      category_name: bread.name, kitchen: @kitchen
    )

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.tag-filter-pill', count: 0
  end

  test 'tag filter pills show smart decoration when decorate_tags enabled' do
    @kitchen.update!(decorate_tags: true)
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    create_recipe(
      "# Tagged\n\nCategory: Bread\nTags: vegetarian\n\n- Flour, 1 cup",
      category_name: 'Bread', kitchen: @kitchen
    )

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.tag-filter-pill.tag-pill--green'
    assert_select '.tag-filter-pill .smart-icon', text: /🥕/
  end

  test 'tag filter pills are plain when decorate_tags disabled' do
    @kitchen.update!(decorate_tags: false)
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    create_recipe(
      "# Tagged\n\nCategory: Bread\nTags: vegetarian\n\n- Flour, 1 cup",
      category_name: 'Bread', kitchen: @kitchen
    )

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.tag-filter-pill.tag-pill--green', count: 0
    assert_select '.tag-filter-pill .smart-icon', count: 0
  end

  test 'recipe card tags show smart decoration when decorate_tags enabled' do
    @kitchen.update!(decorate_tags: true)
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    create_recipe(
      "# Tagged\n\nCategory: Bread\nTags: vegetarian\n\n- Flour, 1 cup",
      category_name: 'Bread', kitchen: @kitchen
    )

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.recipe-card .tag-pill.tag-pill--green'
    assert_select '.recipe-card .smart-icon', text: /🥕/
  end

  test 'recipe card tags are plain when decorate_tags disabled' do
    @kitchen.update!(decorate_tags: false)
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    create_recipe(
      "# Tagged\n\nCategory: Bread\nTags: vegetarian\n\n- Flour, 1 cup",
      category_name: 'Bread', kitchen: @kitchen
    )

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.recipe-card .tag-pill.tag-pill--green', count: 0
    assert_select '.recipe-card .recipe-tag', text: 'vegetarian'
  end
end
