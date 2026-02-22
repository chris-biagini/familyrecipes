# frozen_string_literal: true

require 'test_helper'

class GroceriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'renders the groceries page with recipe checkboxes' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'h1', 'Groceries'
    assert_select 'input[type=checkbox][data-title="Focaccia"]'
  end

  test 'includes groceries CSS and JS' do
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select 'link[href*="groceries"]'
    assert_select 'script[src*="groceries"]'
  end

  test 'renders aisle sections from grocery data' do
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'details.aisle summary', /Produce/
    assert_select 'details.aisle summary', /Baking/
    assert_select '#misc-aisle summary', /Miscellaneous/
  end

  test 'does not render Omit_From_List aisle' do
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'details.aisle summary', { text: /Omit_From_List/, count: 0 }
  end

  test 'renders custom items section' do
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#custom-items-section'
    assert_select '#custom-input'
  end

  test 'renders share section' do
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#share-section'
    assert_select '#qr-container'
  end

  test 'renders UNIT_PLURALS script' do
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_match(/window\.UNIT_PLURALS/, response.body)
  end

  test 'groups recipes by category' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    Category.create!(name: 'Pasta', slug: 'pasta', position: 1, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Cacio e Pepe

      Category: Pasta

      ## Cook (boil it)

      - Spaghetti, 1 lb

      Cook until al dente.
    MD

    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#recipe-selector .category h2', 'Bread'
    assert_select '#recipe-selector .category h2', 'Pasta'
  end

  test 'renders Quick Bites section when document exists' do
    SiteDocument.create!(name: 'quick_bites', kitchen: @kitchen, content: <<~MD)
      ## Snacks
        - Goldfish
        - Hummus with Pretzels: Hummus, Pretzels
    MD

    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.quick-bites h2', 'Quick Bites'
    assert_select '.quick-bites .subsection h3', 'Snacks'
    assert_select '.quick-bites input[type=checkbox][data-title="Goldfish"]'
    assert_select '.quick-bites input[type=checkbox][data-title="Hummus with Pretzels"]'
  end

  test 'renders gracefully without site documents' do
    SiteDocument.where(name: %w[quick_bites grocery_aisles]).destroy_all

    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
  end

  test 'update_quick_bites saves valid content' do
    SiteDocument.create!(name: 'quick_bites', kitchen: @kitchen, content: 'old content')

    log_in
    patch groceries_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n  - Goldfish" },
          as: :json

    assert_response :success

    doc = SiteDocument.find_by(name: 'quick_bites')

    assert_equal "## Snacks\n  - Goldfish", doc.content
  end

  test 'update_quick_bites creates document if missing' do
    log_in
    patch groceries_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n  - Goldfish" },
          as: :json

    assert_response :success
    assert SiteDocument.exists?(name: 'quick_bites')
  end

  test 'update_quick_bites rejects blank content' do
    SiteDocument.create!(name: 'quick_bites', kitchen: @kitchen, content: 'old content')

    log_in
    patch groceries_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: '' },
          as: :json

    assert_response :unprocessable_entity
  end

  test 'update_grocery_aisles saves valid content' do
    SiteDocument.create!(name: 'grocery_aisles', kitchen: @kitchen, content: 'old')

    new_content = "## Produce\n- Apples\n\n## Baking\n- Flour"
    log_in
    patch groceries_grocery_aisles_path(kitchen_slug: kitchen_slug),
          params: { content: new_content },
          as: :json

    assert_response :success

    doc = SiteDocument.find_by(name: 'grocery_aisles')

    assert_equal new_content, doc.content
  end

  test 'update_grocery_aisles rejects content with no aisles' do
    SiteDocument.create!(name: 'grocery_aisles', kitchen: @kitchen, content: 'old')

    log_in
    patch groceries_grocery_aisles_path(kitchen_slug: kitchen_slug),
          params: { content: 'just some text with no headings' },
          as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)

    assert_includes json['errors'], 'Must have at least one aisle (## Aisle Name).'
  end

  test 'recipe checkboxes include ingredient data as JSON' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    checkbox = css_select('input[data-title="Focaccia"]').first
    ingredients_json = checkbox['data-ingredients']

    assert_predicate ingredients_json, :present?, 'Expected data-ingredients attribute'

    ingredients = JSON.parse(ingredients_json)
    ingredient_names = ingredients.map(&:first)

    assert_includes ingredient_names, 'Flour'
  end
end
