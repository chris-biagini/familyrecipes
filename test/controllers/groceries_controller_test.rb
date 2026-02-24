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
end
