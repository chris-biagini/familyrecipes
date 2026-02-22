# frozen_string_literal: true

require 'test_helper'

class GroceriesControllerTest < ActionDispatch::IntegrationTest
  test 'renders the groceries page with recipe checkboxes' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)
    MarkdownImporter.import(<<~MD)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    get groceries_path

    assert_response :success
    assert_select 'h1', 'Groceries'
    assert_select 'input[type=checkbox][data-title="Focaccia"]'
  end

  test 'includes groceries CSS and JS' do
    get groceries_path

    assert_select 'link[href*="groceries"]'
    assert_select 'script[src*="groceries"]'
  end

  test 'renders aisle sections from grocery data' do
    get groceries_path

    assert_response :success
    assert_select 'details.aisle summary', /Produce/
    assert_select 'details.aisle summary', /Baking/
    assert_select '#misc-aisle summary', /Miscellaneous/
  end

  test 'does not render Omit_From_List aisle' do
    get groceries_path

    assert_response :success
    assert_select 'details.aisle summary', { text: /Omit_From_List/, count: 0 }
  end

  test 'renders custom items section' do
    get groceries_path

    assert_response :success
    assert_select '#custom-items-section'
    assert_select '#custom-input'
  end

  test 'renders share section' do
    get groceries_path

    assert_response :success
    assert_select '#share-section'
    assert_select '#qr-container'
  end

  test 'renders UNIT_PLURALS script' do
    get groceries_path

    assert_response :success
    assert_match(/window\.UNIT_PLURALS/, response.body)
  end

  test 'groups recipes by category' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)
    Category.create!(name: 'Pasta', slug: 'pasta', position: 1)

    MarkdownImporter.import(<<~MD)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    MarkdownImporter.import(<<~MD)
      # Cacio e Pepe

      Category: Pasta

      ## Cook (boil it)

      - Spaghetti, 1 lb

      Cook until al dente.
    MD

    get groceries_path

    assert_response :success
    assert_select '#recipe-selector .category h2', 'Bread'
    assert_select '#recipe-selector .category h2', 'Pasta'
  end

  test 'recipe checkboxes include ingredient data as JSON' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)
    MarkdownImporter.import(<<~MD)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    get groceries_path

    assert_response :success
    checkbox = css_select('input[data-title="Focaccia"]').first
    ingredients_json = checkbox['data-ingredients']

    assert_predicate ingredients_json, :present?, 'Expected data-ingredients attribute'

    ingredients = JSON.parse(ingredients_json)
    ingredient_names = ingredients.map(&:first)

    assert_includes ingredient_names, 'Flour'
  end
end
