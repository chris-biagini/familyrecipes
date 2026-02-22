# frozen_string_literal: true

require 'test_helper'

class IngredientsControllerTest < ActionDispatch::IntegrationTest
  test 'renders ingredient index grouped by ingredient name' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)
    MarkdownImporter.import(<<~MD)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    get ingredients_path

    assert_response :success
    assert_select 'h1', 'Ingredient Index'
    assert_select 'h2', 'Flour'
    assert_select 'a[href=?]', recipe_path('focaccia'), text: 'Focaccia'
  end

  test 'groups multiple recipes under the same ingredient' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)

    MarkdownImporter.import(<<~MD)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    MarkdownImporter.import(<<~MD)
      # Pizza Dough

      Category: Bread

      ## Mix (combine)

      - Flour, 4 cups

      Knead well.
    MD

    get ingredients_path

    assert_response :success
    assert_select 'article.index section' do |sections|
      flour_section = sections.detect { |s| s.at('h2').text == 'Flour' }

      assert flour_section, 'Expected a section for Flour'
      assert_select flour_section, 'li', count: 2
    end
  end

  test 'sorts ingredients alphabetically' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)
    MarkdownImporter.import(<<~MD)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Yeast, 1 tsp
      - Flour, 3 cups

      Mix well.
    MD

    get ingredients_path

    assert_response :success
    headings = css_select('article.index h2').map(&:text)

    assert_equal headings, headings.sort_by(&:downcase)
  end

  test 'does not duplicate a recipe under the same ingredient' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)
    MarkdownImporter.import(<<~MD)
      # Focaccia

      Category: Bread

      ## Step One (mix)

      - Flour, 2 cups

      Mix.

      ## Step Two (more flour)

      - Flour, 1 cup

      Add more flour.
    MD

    get ingredients_path

    assert_response :success
    assert_select 'article.index section' do |sections|
      flour_section = sections.detect { |s| s.at('h2').text == 'Flour' }

      assert flour_section, 'Expected a section for Flour'
      assert_select flour_section, 'li', count: 1
    end
  end

  test 'recipe links include description as title attribute' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)
    MarkdownImporter.import(<<~MD)
      # Focaccia

      A simple flatbread.

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    get ingredients_path

    assert_response :success
    assert_select 'a[title="A simple flatbread."]', text: 'Focaccia'
  end
end
