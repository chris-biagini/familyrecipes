# frozen_string_literal: true

require 'test_helper'

class SearchDataHelperTest < ActionView::TestCase
  setup do
    setup_test_kitchen
    setup_test_category(name: 'Baking')
  end

  test 'search data recipes key is an array' do
    data = JSON.parse(search_data_json)

    assert_kind_of Array, data['recipes']
  end

  test 'search_data_json returns recipe objects under recipes key' do
    markdown = "# Pancakes\n\nFluffy buttermilk pancakes.\n\n## Step 1\n\n- flour, 2 cups:\n- buttermilk, 1 cup:\n"
    MarkdownImporter.import(markdown, kitchen: @kitchen, category: @category)

    data = JSON.parse(search_data_json)
    recipes = data['recipes']

    assert_equal 1, recipes.size
    entry = recipes.first

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

    assert_equal ['eggs'], data['recipes'].first['ingredients']
  end

  test 'search_data_json returns empty recipes array when no recipes' do
    data = JSON.parse(search_data_json)

    assert_empty data['recipes']
  end

  test 'search_data_json escapes HTML in titles' do
    markdown = "# Eggs & Toast\n\nSimple.\n\n## Step 1\n\n- eggs, 2:\n"
    MarkdownImporter.import(markdown, kitchen: @kitchen, category: @category)

    json = search_data_json

    assert_not_includes json, '<'
    data = JSON.parse(json)

    assert_equal 'Eggs & Toast', data['recipes'].first['title']
  end

  test 'search data includes all_tags with all kitchen tags' do
    setup_tagged_recipe

    data = JSON.parse(search_data_json)

    assert_equal %w[quick unused vegan], data['all_tags'].sort
  end

  test 'search data includes all_categories' do
    data = JSON.parse(search_data_json)

    assert_includes data['all_categories'], @category.name
  end

  test 'search data includes tags per recipe' do
    setup_tagged_recipe

    data = JSON.parse(search_data_json)
    recipe_data = data['recipes'].find { |r| r['slug'] == 'miso-soup' }

    assert_equal %w[quick vegan], recipe_data['tags'].sort
  end

  private

  def current_kitchen = @kitchen

  def setup_tagged_recipe
    @recipe = Recipe.create!(title: 'Miso Soup', slug: 'miso-soup',
                             markdown_source: "# Miso Soup\n\n## Step\n\n- Dashi, 4 cups\n\nHeat.",
                             category: @category)
    Tag.create!(name: 'vegan').tap { |t| RecipeTag.create!(recipe: @recipe, tag: t) }
    Tag.create!(name: 'quick').tap { |t| RecipeTag.create!(recipe: @recipe, tag: t) }
    Tag.create!(name: 'unused')
  end
end
