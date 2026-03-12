# frozen_string_literal: true

require 'test_helper'

class SearchOverlayTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    setup_test_category(name: 'Baking')
    markdown = "# Pancakes\n\nFluffy buttermilk pancakes.\n\n## Step 1\n\n- flour, 2 cups:\n"
    MarkdownImporter.import(markdown, kitchen: @kitchen, category: @category)
  end

  test 'homepage includes search data JSON and dialog' do
    get root_path

    assert_response :success
    assert_select 'script[type="application/json"][data-search-overlay-target="data"]'
    assert_select 'dialog.search-overlay'
  end

  test 'recipe page includes search data JSON' do
    get recipe_path('pancakes')

    assert_response :success
    assert_select 'script[type="application/json"][data-search-overlay-target="data"]'
  end

  test 'search data contains recipe with expected fields' do
    get root_path

    json_tag = css_select('script[data-search-overlay-target="data"]').first
    data = JSON.parse(json_tag.text)

    assert_equal 1, data.size
    assert_equal 'Pancakes', data.first['title']
    assert_equal 'pancakes', data.first['slug']
    assert_includes data.first['ingredients'], 'flour'
  end

  test 'nav includes search button' do
    get root_path

    assert_select 'button.nav-search-btn'
  end
end
