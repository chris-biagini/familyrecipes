# frozen_string_literal: true

require 'test_helper'

class SearchDataHelperTest < ActionView::TestCase
  setup do
    setup_test_kitchen
    setup_test_category(name: 'Baking')
  end

  test 'search_data_json returns JSON array of recipe objects' do
    markdown = "# Pancakes\n\nFluffy buttermilk pancakes.\n\n## Step 1\n\n- flour, 2 cups:\n- buttermilk, 1 cup:\n"
    MarkdownImporter.import(markdown, kitchen: @kitchen, category: @category)

    data = JSON.parse(search_data_json)

    assert_equal 1, data.size
    entry = data.first

    assert_equal 'Pancakes', entry['title']
    assert_equal 'pancakes', entry['slug']
    assert_equal 'Fluffy buttermilk pancakes.', entry['description']
    assert_equal 'Baking', entry['category']
    assert_includes entry['ingredients'], 'flour'
    assert_includes entry['ingredients'], 'buttermilk'
  end

  test 'search_data_json deduplicates ingredients across steps' do
    markdown = "# Eggs\n\nSimple.\n\n## Step 1\n\n- eggs, 2:\n\n## Step 2\n\n- eggs, 1:\n"
    MarkdownImporter.import(markdown, kitchen: @kitchen, category: @category)

    data = JSON.parse(search_data_json)

    assert_equal ['eggs'], data.first['ingredients']
  end

  test 'search_data_json returns empty array when no recipes' do
    assert_equal '[]', search_data_json
  end

  test 'search_data_json escapes HTML in titles' do
    markdown = "# Eggs & Toast\n\nSimple.\n\n## Step 1\n\n- eggs, 2:\n"
    MarkdownImporter.import(markdown, kitchen: @kitchen, category: @category)

    json = search_data_json

    assert_not_includes json, '<'
    data = JSON.parse(json)

    assert_equal 'Eggs & Toast', data.first['title']
  end

  private

  def current_kitchen = @kitchen
end
