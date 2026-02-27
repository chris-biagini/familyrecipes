# frozen_string_literal: true

require 'test_helper'

class IngredientsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'requires membership to view ingredients' do
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'renders ingredient index grouped by ingredient name' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'h1', 'Ingredients'
    assert_select 'h2', /Flour/
    assert_select 'a[href=?]', recipe_path('focaccia', kitchen_slug: kitchen_slug), text: 'Focaccia'
  end

  test 'groups multiple recipes under the same ingredient' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Pizza Dough

      Category: Bread

      ## Mix (combine)

      - Flour, 4 cups

      Knead well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'article.index section' do |sections|
      flour_section = sections.detect { |s| s.at('h2').text.include?('Flour') }

      assert flour_section, 'Expected a section for Flour'
      assert_select flour_section, 'li', count: 2
    end
  end

  test 'sorts ingredients alphabetically' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Yeast, 1 tsp
      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    headings = css_select('article.index h2').map { |h| h.text.strip }

    assert_equal headings, headings.sort_by(&:downcase)
  end

  test 'does not duplicate a recipe under the same ingredient' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Step One (mix)

      - Flour, 2 cups

      Mix.

      ## Step Two (more flour)

      - Flour, 1 cup

      Add more flour.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'article.index section' do |sections|
      flour_section = sections.detect { |s| s.at('h2').text.include?('Flour') }

      assert flour_section, 'Expected a section for Flour'
      assert_select flour_section, 'li', count: 1
    end
  end

  test 'recipe links include description as title attribute' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      A simple flatbread.

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'a[title="A simple flatbread."]', text: 'Focaccia'
  end

  test 'shows missing nutrition badge for ingredients without data' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.nutrition-missing'
  end

  test 'shows global badge for ingredients with global nutrition data' do
    IngredientCatalog.create!(ingredient_name: 'Flour', basis_grams: 30, calories: 110)
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.nutrition-global'
  end

  test 'shows custom badge for ingredients with kitchen override' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30, calories: 110)
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.nutrition-custom'
  end

  test 'consolidates singular and plural ingredient variants into one entry' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Topping (add)

      - Onion, 1: thinly sliced

      Scatter over dough.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Pizza Dough

      Category: Bread

      ## Topping (add)

      - Onions, 2: diced

      Scatter over dough.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    sections = css_select('article.index section')
    onion_sections = sections.select { |s| s.at('h2').text.include?('Onion') }

    assert_equal 1, onion_sections.size, 'Expected singular and plural Onion to merge into one section'
    assert_select onion_sections.first, 'li', count: 2
  end

  test 'uses catalog entry name as canonical form for variants' do
    IngredientCatalog.create!(ingredient_name: 'Eggs', basis_grams: 50, calories: 70)
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Brioche

      Category: Bread

      ## Mix (combine)

      - Egg, 1

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    sections = css_select('article.index section')
    egg_section = sections.detect { |s| s.at('h2').text.include?('Egg') }

    assert egg_section, 'Expected a section for Eggs'
    assert_includes egg_section.at('h2').text, 'Eggs', 'Should use catalog name "Eggs" not recipe name "Egg"'
  end

  test 'shows missing ingredients banner when nutrition data is absent' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'details.nutrition-banner'
  end

  # --- show action (Turbo Frame detail panel) ---

  test 'show returns detail panel for ingredient with catalog entry' do
    IngredientCatalog.create!(ingredient_name: 'Flour', basis_grams: 30, calories: 110)
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredient_detail_path('Flour', kitchen_slug: kitchen_slug)

    assert_response :success
  end

  test 'show returns 404 for unknown ingredient' do
    log_in
    get ingredient_detail_path('Nonexistent', kitchen_slug: kitchen_slug)

    assert_response :not_found
  end

  test 'show requires membership' do
    get ingredient_detail_path('Flour', kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  # --- edit action (Turbo Frame editor form) ---

  test 'edit returns structured form for ingredient with data' do
    IngredientCatalog.create!(ingredient_name: 'Flour', basis_grams: 30, calories: 110,
                              fat: 0.5, saturated_fat: 0, trans_fat: 0, cholesterol: 0, sodium: 5,
                              carbs: 23, fiber: 1, total_sugars: 0, added_sugars: 0, protein: 3,
                              density_grams: 120, density_volume: 1, density_unit: 'cup')

    log_in
    get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

    assert_response :success
  end

  test 'edit returns blank form for ingredient without data' do
    log_in
    get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

    assert_response :success
  end

  test 'edit requires membership' do
    get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end
end
