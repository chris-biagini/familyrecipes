# frozen_string_literal: true

require 'test_helper'

class XssPreventionTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    Category.create!(name: 'Test', slug: 'test', position: 0, kitchen: @kitchen)
  end

  test 'script tag in instructions is escaped' do
    import_recipe(<<~MD)
      # Safe Recipe

      Category: Test

      ## Step one (do it)

      - Flour, 2 cups

      Mix for 3* minutes. <script>alert('xss')</script>
    MD

    get recipe_path('safe-recipe', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_no_match(/<script>alert/, response.body)
    assert_includes response.body, '&lt;script&gt;'
  end

  test 'img onerror in step title is escaped' do
    import_recipe(<<~MD)
      # Safe Recipe

      Category: Test

      ## Mix <img onerror=alert(1)> (do it)

      - Flour, 2 cups

      Mix it.
    MD

    get recipe_path('safe-recipe', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_no_match(/<img[^>]*onerror/, response.body)
  end

  test 'script tag in footer is escaped' do
    import_recipe(<<~MD)
      # Safe Recipe

      Category: Test

      ## Mix (do it)

      - Flour, 2 cups

      Mix it.

      ---

      Source: <script>alert('xss')</script>
    MD

    get recipe_path('safe-recipe', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_no_match(/<script>alert/, response.body)
  end

  test 'malicious makes unit is escaped in yield display' do
    import_recipe(<<~MD)
      # Safe Recipe

      Category: Test
      Makes: 12 <b>loaves</b>

      ## Mix (do it)

      - Flour, 2 cups

      Mix it.
    MD

    get recipe_path('safe-recipe', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_no_match(%r{<b>loaves</b>}, response.body)
  end

  private

  def import_recipe(markdown)
    MarkdownImporter.import(markdown, kitchen: @kitchen)
  end
end
