# frozen_string_literal: true

require 'test_helper'

class GroceriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  # --- Access control ---

  test 'show requires membership' do
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'state requires membership' do
    get groceries_state_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end

  test 'aisle_order_content requires membership' do
    get groceries_aisle_order_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end

  test 'select requires membership' do
    patch groceries_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :json

    assert_response :forbidden
  end

  test 'check requires membership' do
    patch groceries_check_path(kitchen_slug: kitchen_slug),
          params: { item: 'flour', checked: true },
          as: :json

    assert_response :forbidden
  end

  test 'custom_items requires membership' do
    patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
          params: { item: 'birthday candles', action_type: 'add' },
          as: :json

    assert_response :forbidden
  end

  test 'clear requires membership' do
    delete groceries_clear_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end

  test 'update_quick_bites requires membership' do
    patch groceries_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n  - Goldfish" },
          as: :json

    assert_response :forbidden
  end

  # --- Show page ---

  test 'renders the groceries page with recipe checkboxes' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'h1', 'Groceries'
    assert_select 'input[type=checkbox][data-slug="focaccia"][data-title="Focaccia"]'
  end

  test 'includes groceries CSS and JS' do
    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select 'link[href*="groceries"]'
    assert_select 'script[src*="groceries"]'
  end

  test 'renders custom items section' do
    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#custom-items-section'
    assert_select '#custom-input'
  end

  test 'renders shopping list container with data attributes' do
    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#shopping-list'
    assert_select '#groceries-app[data-kitchen-slug]'
    assert_select '#groceries-app[data-state-url]'
    assert_select '#groceries-app[data-select-url]'
    assert_select '#groceries-app[data-check-url]'
    assert_select '#groceries-app[data-custom-items-url]'
    assert_select '#groceries-app[data-clear-url]'
  end

  test 'recipe selector has data-type attribute' do
    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#recipe-selector[data-type="recipe"]'
  end

  test 'renders noscript fallback' do
    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select 'noscript', /JavaScript/
  end

  test 'renders aisle order editor dialog for members' do
    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#edit-aisle-order-button', 'Edit Aisle Order'
    assert_select 'dialog[data-editor-open="#edit-aisle-order-button"]'
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

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#recipe-selector .category h2', 'Bread'
    assert_select '#recipe-selector .category h2', 'Pasta'
  end

  test 'renders Quick Bites section when content exists' do
    @kitchen.update!(quick_bites_content: <<~MD)
      ## Snacks
        - Goldfish
        - Hummus with Pretzels: Hummus, Pretzels
    MD

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.quick-bites h2', 'Quick Bites'
    assert_select '.quick-bites .subsection h3', 'Snacks'
    assert_select '.quick-bites[data-type="quick_bite"]'
    assert_select '.quick-bites input[type=checkbox][data-slug="goldfish"][data-title="Goldfish"]'
    assert_select '.quick-bites input[data-slug="hummus-with-pretzels"]'
  end

  test 'renders gracefully without quick bites content' do
    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
  end

  # --- Quick Bites editing ---

  test 'update_quick_bites saves valid content' do
    @kitchen.update!(quick_bites_content: 'old content')

    log_in
    patch groceries_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n  - Goldfish" },
          as: :json

    assert_response :success

    assert_equal "## Snacks\n  - Goldfish", @kitchen.reload.quick_bites_content
  end

  test 'update_quick_bites saves content when none existed' do
    log_in
    patch groceries_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n  - Goldfish" },
          as: :json

    assert_response :success
    assert_equal "## Snacks\n  - Goldfish", @kitchen.reload.quick_bites_content
  end

  test 'update_quick_bites rejects blank content' do
    @kitchen.update!(quick_bites_content: 'old content')

    log_in
    patch groceries_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: '' },
          as: :json

    assert_response :unprocessable_entity
  end

  # --- API endpoint tests ---

  test 'state returns version and empty state for new list' do
    log_in
    get groceries_state_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    json = response.parsed_body

    assert_equal 0, json['version']
    assert_empty(json['shopping_list'])
  end

  test 'select adds recipe and returns version' do
    log_in
    patch groceries_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :json

    assert_response :success
    json = response.parsed_body

    assert_operator json['version'], :>, 0
  end

  test 'check marks item as checked' do
    log_in
    patch groceries_check_path(kitchen_slug: kitchen_slug),
          params: { item: 'flour', checked: true },
          as: :json

    assert_response :success
  end

  test 'custom_items adds item' do
    log_in
    patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
          params: { item: 'birthday candles', action_type: 'add' },
          as: :json

    assert_response :success
  end

  test 'clear resets the list' do
    log_in
    delete groceries_clear_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    json = response.parsed_body

    assert json.key?('version')
  end

  test 'state includes shopping_list when recipes selected' do
    Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end

    log_in
    patch groceries_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :json

    get groceries_state_path(kitchen_slug: kitchen_slug), as: :json
    json = response.parsed_body

    assert json['shopping_list'].key?('Baking')
  end

  test 'state includes selected_recipes in response' do
    log_in
    patch groceries_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :json

    get groceries_state_path(kitchen_slug: kitchen_slug), as: :json
    json = response.parsed_body

    assert_includes json['selected_recipes'], 'focaccia'
  end

  test 'state includes all state keys' do
    log_in
    patch groceries_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :json

    get groceries_state_path(kitchen_slug: kitchen_slug), as: :json
    json = response.parsed_body

    assert json.key?('version')
    assert json.key?('selected_recipes')
    assert json.key?('selected_quick_bites')
    assert json.key?('checked_off')
    assert json.key?('custom_items')
    assert json.key?('shopping_list')
  end

  test 'select deselects recipe when selected is false' do
    log_in
    patch groceries_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :json

    patch groceries_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: false },
          as: :json

    get groceries_state_path(kitchen_slug: kitchen_slug), as: :json
    json = response.parsed_body

    assert_not_includes json['selected_recipes'], 'focaccia'
  end

  test 'custom_items removes item' do
    log_in
    patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
          params: { item: 'birthday candles', action_type: 'add' },
          as: :json

    patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
          params: { item: 'birthday candles', action_type: 'remove' },
          as: :json

    get groceries_state_path(kitchen_slug: kitchen_slug), as: :json
    json = response.parsed_body

    assert_not_includes json.fetch('custom_items', []), 'birthday candles'
  end

  # --- Aisle order ---

  test 'update_aisle_order requires membership' do
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: "Produce\nBaking" },
          as: :json

    assert_response :forbidden
  end

  test 'update_aisle_order saves valid order' do
    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: "Produce\n  Baking\nProduce\n\nFrozen" },
          as: :json

    assert_response :success
    assert_equal "Produce\nBaking\nFrozen", @kitchen.reload.aisle_order
  end

  test 'update_aisle_order clears order when empty' do
    @kitchen.update!(aisle_order: "Produce\nBaking")

    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: '' },
          as: :json

    assert_response :success
    assert_nil @kitchen.reload.aisle_order
  end

  test 'aisle_order_content returns current aisles for editor' do
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Salt') do |p|
      p.basis_grams = 6
      p.aisle = 'Spices'
    end

    log_in
    get groceries_aisle_order_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    json = response.parsed_body

    assert_includes json['aisle_order'], 'Baking'
    assert_includes json['aisle_order'], 'Spices'
  end

  test 'aisle_order_content merges saved order with catalog aisles' do
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Salt') do |p|
      p.basis_grams = 6
      p.aisle = 'Spices'
    end

    @kitchen.update!(aisle_order: "Spices\nProduce")

    log_in
    get groceries_aisle_order_content_path(kitchen_slug: kitchen_slug), as: :json

    json = response.parsed_body
    lines = json['aisle_order'].lines.map(&:strip)

    # Saved order preserved, new aisle appended
    assert_equal 'Spices', lines[0]
    assert_equal 'Produce', lines[1]
    assert_includes lines, 'Baking'
  end

  # --- Length limits ---

  test 'custom_items rejects item over 100 characters' do
    log_in
    patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
          params: { item: 'a' * 101, action_type: 'add' },
          as: :json

    assert_response :unprocessable_entity
    assert_includes response.parsed_body['errors'].first, 'too long'
  end

  test 'custom_items accepts item at exactly 100 characters' do
    log_in
    patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
          params: { item: 'a' * 100, action_type: 'add' },
          as: :json

    assert_response :success
  end

  test 'update_aisle_order rejects aisle name over 50 characters' do
    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: 'a' * 51 },
          as: :json

    assert_response :unprocessable_entity
    assert_includes response.parsed_body['errors'].first, 'too long'
  end

  test 'update_aisle_order accepts aisle name at exactly 50 characters' do
    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: 'a' * 50 },
          as: :json

    assert_response :success
  end

  test 'update_aisle_order rejects more than 50 aisles' do
    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: (1..51).map { |i| "Aisle #{i}" }.join("\n") },
          as: :json

    assert_response :unprocessable_entity
    assert_includes response.parsed_body['errors'].first, 'Too many aisles'
  end

  test 'update_aisle_order accepts exactly 50 aisles' do
    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: (1..50).map { |i| "Aisle #{i}" }.join("\n") },
          as: :json

    assert_response :success
  end

  # --- Optimistic locking / 409 Conflict ---

  test 'select returns 409 when retry exhausted' do
    log_in
    stale_list = build_stale_list(:apply_action)

    GroceryList.stub(:for_kitchen, stale_list) do
      patch groceries_select_path(kitchen_slug: kitchen_slug),
            params: { type: 'recipe', slug: 'focaccia', selected: true },
            as: :json
    end

    assert_response :conflict
    json = response.parsed_body

    assert_equal 'Grocery list was modified by another request. Please refresh.', json['error']
  end

  test 'check returns 409 when retry exhausted' do
    log_in
    stale_list = build_stale_list(:apply_action)

    GroceryList.stub(:for_kitchen, stale_list) do
      patch groceries_check_path(kitchen_slug: kitchen_slug),
            params: { item: 'flour', checked: true },
            as: :json
    end

    assert_response :conflict
  end

  test 'clear returns 409 when retry exhausted' do
    log_in
    stale_list = build_stale_list(:clear!)

    GroceryList.stub(:for_kitchen, stale_list) do
      delete groceries_clear_path(kitchen_slug: kitchen_slug), as: :json
    end

    assert_response :conflict
  end

  private

  def build_stale_list(method_to_stub)
    list = GroceryList.for_kitchen(@kitchen)
    list.define_singleton_method(method_to_stub) do |*|
      raise ActiveRecord::StaleObjectError, self
    end
    list.define_singleton_method(:reload) { self }
    list
  end
end
