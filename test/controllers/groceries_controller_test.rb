# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class GroceriesControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    create_kitchen_and_user
  end

  # --- Access control ---

  test 'show requires membership' do
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'aisle_order_content requires membership' do
    get groceries_aisle_order_content_path(kitchen_slug: kitchen_slug)

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

  test 'have_it requires membership' do
    patch groceries_have_it_path(kitchen_slug: kitchen_slug),
          params: { item: 'flour' },
          as: :json

    assert_response :forbidden
  end

  test 'need_it requires membership' do
    patch groceries_need_it_path(kitchen_slug: kitchen_slug),
          params: { item: 'flour' },
          as: :json

    assert_response :forbidden
  end

  test 'confirm_all requires membership' do
    patch groceries_confirm_all_path(kitchen_slug: kitchen_slug),
          params: { items: ['flour'] },
          as: :json

    assert_response :forbidden
  end

  # --- Show page ---

  test 'includes groceries CSS and Stimulus controllers' do
    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select 'link[href*="groceries"]'
    assert_select '[data-controller~="grocery-ui"]'
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
    assert_select '#groceries-app[data-check-url]'
    assert_select '#groceries-app[data-have-it-url]'
    assert_select '#groceries-app[data-need-it-url]'
    assert_select '#groceries-app[data-confirm-all-url]'
    assert_select '#groceries-app[data-custom-items-url]'
  end

  test 'does not render noscript fallback' do
    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select 'noscript', count: 0
  end

  test 'show renders shopping list header' do
    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '.shopping-list-header h2', 'Shopping List'
  end

  test 'show renders empty message when no recipes selected' do
    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '#grocery-preview-empty', 'No items yet.'
  end

  test 'show renders aisle sections for to-buy items' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('need_it', item: 'Flour')

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select 'section.aisle-group[data-aisle="Baking"]'
    assert_select 'li[data-item="Flour"]'
    assert_select 'input[type="checkbox"][data-item="Flour"]'
  end

  test 'show renders All Stocked button when 5+ IC items' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups
      - Yeast, 1 tsp
      - Olive oil, 2 tbsp
      - Salt, 1 tsp
      - Sugar, 1 tsp

      Mix well.
    MD

    %w[Flour Yeast Salt Sugar].each { |name| create_catalog_entry(name, basis_grams: 10, aisle: 'Baking') }
    create_catalog_entry('Olive oil', basis_grams: 14, aisle: 'Oils')

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '[data-grocery-action="confirm-all"]', 'Have All'
    assert_select '[data-grocery-action="deplete-all"]', 'Need All'
  end

  test 'show omits bulk IC buttons when fewer than 5 IC items' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '[data-grocery-action="confirm-all"]', count: 0
  end

  test 'show renders inventory check for new items' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '.inventory-check-section'
    assert_select '.inventory-check-items li[data-item="Flour"]'
    assert_select '[data-grocery-action="need-it"][data-item="Flour"]'
    assert_select '[data-grocery-action="have-it"][data-item="Flour"]'
  end

  test 'show pre-checks checked-off items' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('check', item: 'Flour', checked: true)

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select 'input[type="checkbox"][data-item="Flour"][checked]'
  end

  test 'show renders all-checked aisle as collapsed summary' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('check', item: 'Flour', checked: true)

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select 'section.aisle-group[data-aisle="Baking"]' do
      assert_select '.aisle-check'
      assert_select 'details.on-hand-section'
      assert_select '.on-hand-items'
    end
  end

  test 'show renders on-hand divider in mixed aisle' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups
      - Yeast, 1 tsp

      Mix well.
    MD

    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Yeast') do |p|
      p.basis_grams = 4
      p.aisle = 'Baking'
    end

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('need_it', item: 'Yeast')
    plan.apply_action('check', item: 'Flour', checked: true)

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select 'section.aisle-group[data-aisle="Baking"]' do
      assert_select '.to-buy-items li[data-item="Yeast"]'
      assert_select 'details.on-hand-section'
      assert_select '.on-hand-items li[data-item="Flour"]'
    end
  end

  test 'show renders confirmed-today class on items confirmed today' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('check', item: 'Flour', checked: true)

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '.on-hand-items li.confirmed-today[data-item="Flour"]'
  end

  test 'show omits confirmed-today class on items confirmed yesterday' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('check', item: 'Flour', checked: true)
    plan.on_hand['Flour']['confirmed_at'] = (Date.current - 1).iso8601
    plan.save!

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '.on-hand-items li[data-item="Flour"]'
    assert_select '.on-hand-items li.confirmed-today[data-item="Flour"]', count: 0
  end

  test 'show renders custom items' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('custom_items', item: 'Birthday candles', action: 'add')

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '#custom-items-list li span', 'Birthday candles'
    assert_select '#custom-items-list button.custom-item-remove[data-item="Birthday candles"]'
  end

  test 'renders aisle order editor dialog for members' do
    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#edit-aisle-order-button', 'Edit Aisles'
    assert_select 'dialog[data-controller="editor ordered-list-editor"]'
  end

  # --- Uncounted indicators ---

  test 'shopping list shows uncounted indicator for mixed quantities' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    create_catalog_entry('Red bell pepper', basis_grams: 150, aisle: 'Produce')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Stuffed Peppers

      ## Prep (slice)

      - Red bell pepper, 1

      Prep.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Stir Fry

      ## Cook (stir-fry)

      - Red bell pepper

      Cook.
    MD

    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'stuffed-peppers', selected: true)
    list.apply_action('select', type: 'recipe', slug: 'stir-fry', selected: true)
    list.apply_action('need_it', item: 'Red bell pepper')

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.item-amount', text: /\+ 1.more/
  end

  test 'shopping list shows uses indicator for all-uncounted multi-source' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    create_catalog_entry('Garlic', basis_grams: 5, aisle: 'Produce')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Pasta

      ## Cook (boil)

      - Garlic

      Cook.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Stir Fry

      ## Cook (stir-fry)

      - Garlic

      Cook.
    MD

    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pasta', selected: true)
    list.apply_action('select', type: 'recipe', slug: 'stir-fry', selected: true)
    list.apply_action('need_it', item: 'Garlic')

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.item-amount', text: /2.uses/
  end

  # --- Mutation tests ---

  test 'check marks item as checked' do
    log_in
    patch groceries_check_path(kitchen_slug: kitchen_slug),
          params: { item: 'flour', checked: true },
          as: :turbo_stream

    assert_response :no_content
  end

  test 'have_it returns no_content' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Flour', checked: true)

    log_in
    patch groceries_have_it_path(kitchen_slug: kitchen_slug),
          params: { item: 'Flour' },
          as: :turbo_stream

    assert_response :no_content
  end

  test 'need_it returns no_content' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Flour', checked: true)

    log_in
    patch groceries_need_it_path(kitchen_slug: kitchen_slug),
          params: { item: 'Flour' },
          as: :turbo_stream

    assert_response :no_content
  end

  test 'confirm_all moves multiple IC items to on-hand' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups
      - Yeast, 1 tsp
      - Olive oil, 2 tbsp
      - Salt, 1 tsp
      - Sugar, 1 tsp

      Mix well.
    MD

    %w[Flour Yeast Salt Sugar].each { |name| create_catalog_entry(name, basis_grams: 10, aisle: 'Baking') }
    create_catalog_entry('Olive oil', basis_grams: 14, aisle: 'Oils')

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    log_in
    patch groceries_confirm_all_path(kitchen_slug: kitchen_slug),
          params: { items: ['Flour', 'Yeast', 'Salt', 'Sugar', 'Olive oil'] },
          as: :turbo_stream

    assert_response :no_content

    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '.inventory-check-items li', count: 0
    %w[Flour Yeast Salt Sugar].each do |name|
      assert_select '.on-hand-items li[data-item=?]', name
    end
    assert_select '.on-hand-items li[data-item="Olive oil"]'
  end

  test 'custom_items adds item' do
    log_in
    patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
          params: { item: 'birthday candles', action_type: 'add' },
          as: :turbo_stream

    assert_response :no_content
  end

  test 'custom_items removes item' do
    log_in
    patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
          params: { item: 'birthday candles', action_type: 'add' },
          as: :turbo_stream

    patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
          params: { item: 'birthday candles', action_type: 'remove' },
          as: :turbo_stream

    plan = MealPlan.for_kitchen(@kitchen)

    assert_not plan.custom_items.key?('birthday candles')
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

  test 'aisle_order_content returns turbo frame with rows' do
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Salt') do |p|
      p.basis_grams = 6
      p.aisle = 'Spices'
    end

    log_in
    get groceries_aisle_order_content_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'turbo-frame#aisle-order-frame'
    assert_select "[data-ordered-list-editor-target='list']"
    assert_select '.aisle-row[data-name="Baking"]'
    assert_select '.aisle-row[data-name="Spices"]'
  end

  test 'aisle_order_content frame respects saved order' do
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
    get groceries_aisle_order_content_path(kitchen_slug: kitchen_slug)

    assert_response :success
    names = css_select('.aisle-row').pluck('data-name')

    assert_equal 'Spices', names[0]
    assert_equal 'Produce', names[1]
    assert_includes names, 'Baking'
    remaining = names[2..]

    assert_equal remaining.sort, remaining
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
          as: :turbo_stream

    assert_response :no_content
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
    assert_includes response.parsed_body['errors'].first, 'Too many items'
  end

  test 'update_aisle_order accepts exactly 50 aisles' do
    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: (1..50).map { |i| "Aisle #{i}" }.join("\n") },
          as: :json

    assert_response :success
  end

  # --- Optimistic locking / 409 Conflict ---

  test 'check returns 409 when retry exhausted' do
    log_in
    stale_list = build_stale_list(:apply_action)

    MealPlan.stub(:for_kitchen, stale_list) do
      patch groceries_check_path(kitchen_slug: kitchen_slug),
            params: { item: 'flour', checked: true },
            as: :turbo_stream
    end

    assert_response :conflict
  end

  # --- Broadcast assertions ---

  test 'check broadcasts meal plan refresh' do
    log_in
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      patch groceries_check_path(kitchen_slug: kitchen_slug),
            params: { item: 'flour', checked: true },
            as: :turbo_stream
    end
  end

  test 'update_custom_items broadcasts meal plan refresh' do
    log_in
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
            params: { item: 'birthday candles', action_type: 'add' },
            as: :turbo_stream
    end
  end

  test 'update_aisle_order broadcasts meal plan refresh' do
    log_in
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
            params: { aisle_order: "Produce\nBaking" },
            as: :json
    end
  end

  # --- Aisle rename/delete cascading ---

  test 'update_aisle_order cascades renames to catalog entries' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Bananas', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Milk', aisle: 'Dairy')

    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: "Fruits & Vegetables\nDairy",
                    renames: { 'Produce' => 'Fruits & Vegetables' } },
          as: :json

    assert_response :success
    assert_equal 'Fruits & Vegetables', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_equal 'Fruits & Vegetables', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Bananas').aisle
    assert_equal 'Dairy', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Milk').aisle
  end

  test 'update_aisle_order clears aisle from catalog entries on delete' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Milk', aisle: 'Dairy')

    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: 'Dairy',
                    deletes: ['Produce'] },
          as: :json

    assert_response :success
    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_equal 'Dairy', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Milk').aisle
  end

  test 'update_aisle_order handles renames and deletes together' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Bread', aisle: 'Bakery')

    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: 'Fruits & Vegetables',
                    renames: { 'Produce' => 'Fruits & Vegetables' },
                    deletes: ['Bakery'] },
          as: :json

    assert_response :success
    assert_equal 'Fruits & Vegetables', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Bread').aisle
  end

  test 'update_aisle_order cascades renames case-insensitively' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Bananas', aisle: 'Produce')

    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: 'Fruits & Vegetables',
                    renames: { 'Produce' => 'Fruits & Vegetables' } },
          as: :json

    assert_response :success
    assert_equal 'Fruits & Vegetables', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_equal 'Fruits & Vegetables', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Bananas').aisle
  end

  test 'update_aisle_order cascades deletes case-insensitively' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Bananas', aisle: 'Produce')

    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: '',
                    deletes: ['Produce'] },
          as: :json

    assert_response :success
    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Bananas').aisle
  end

  test 'update_aisle_order rejects case-duplicate aisles' do
    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: "Produce\nproduce\nBaking" },
          as: :json

    assert_response :unprocessable_content
    assert_includes response.parsed_body['errors'].first, 'more than once'
  end

  test 'update_aisle_order rename does not affect other kitchens' do
    other_kitchen = nil
    with_multi_kitchen do
      other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    end
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: other_kitchen, ingredient_name: 'Apples', aisle: 'Produce')

    log_in
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: 'Fruits',
                    renames: { 'Produce' => 'Fruits' } },
          as: :json

    assert_response :success
    assert_equal 'Produce', IngredientCatalog.find_by(kitchen: other_kitchen, ingredient_name: 'Apples').aisle
  end

  # --- Full lifecycle integration ---

  test 'inventory check full cycle: new → have it → expired → need it → buy → on hand' do # rubocop:disable Minitest/MultipleAssertions
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    log_in

    # 1) New item appears in Inventory Check
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '.inventory-check-section'
    assert_select '.inventory-check-items li[data-item="Flour"]'

    # 2) "Have It" moves it to On Hand
    patch groceries_have_it_path(kitchen_slug: kitchen_slug),
          params: { item: 'Flour' },
          as: :turbo_stream

    assert_response :no_content

    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '.on-hand-items li[data-item="Flour"]'
    assert_select '.inventory-check-items li[data-item="Flour"]', count: 0

    # 3) Simulate timer expiring: set confirmed_at far enough in the past
    plan.reload
    entry = plan.on_hand['Flour']
    expired_date = (Date.current - entry['interval'].to_i - 1).iso8601
    entry['confirmed_at'] = expired_date
    plan.save!

    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '.inventory-check-items li[data-item="Flour"]'
    assert_select '.on-hand-items li[data-item="Flour"]', count: 0

    # 4) "Need It" depletes the item — moves to To Buy
    patch groceries_need_it_path(kitchen_slug: kitchen_slug),
          params: { item: 'Flour' },
          as: :turbo_stream

    assert_response :no_content

    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '.to-buy-items li[data-item="Flour"]'
    assert_select '.inventory-check-items li[data-item="Flour"]', count: 0
    assert_select '.on-hand-items li[data-item="Flour"]', count: 0

    # 5) Purchase (check off) moves to On Hand
    patch groceries_check_path(kitchen_slug: kitchen_slug),
          params: { item: 'Flour', checked: true },
          as: :turbo_stream

    assert_response :no_content

    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select '.on-hand-items li[data-item="Flour"]'
    assert_select '.to-buy-items li[data-item="Flour"]', count: 0
    assert_select '.inventory-check-items li[data-item="Flour"]', count: 0
  end

  # --- Quick-add (POST /groceries/need) ---

  test 'need adds unknown item as custom → status added' do
    log_in
    post groceries_need_path(kitchen_slug: kitchen_slug),
         params: { item: 'Birthday Candles', aisle: 'Miscellaneous' },
         as: :json

    assert_response :success
    body = response.parsed_body

    assert_equal 'added', body['status']
  end

  test 'need returns already_needed when item is in To Buy' do
    log_in
    setup_test_category(name: 'Bread', slug: 'bread')
    create_recipe_with_ingredient('Flour')
    select_recipe('focaccia')
    mark_need_it('Flour')

    post groceries_need_path(kitchen_slug: kitchen_slug),
         params: { item: 'Flour' },
         as: :json

    assert_response :success
    assert_equal 'already_needed', response.parsed_body['status']
  end

  test 'need depletes on-hand item → status moved_to_buy' do
    log_in
    setup_test_category(name: 'Bread', slug: 'bread')
    create_recipe_with_ingredient('Flour')
    select_recipe('focaccia')
    check_have_it('Flour')

    post groceries_need_path(kitchen_slug: kitchen_slug),
         params: { item: 'Flour' },
         as: :json

    assert_response :success
    assert_equal 'moved_to_buy', response.parsed_body['status']
  end

  test 'need depletes inventory-check item → status moved_to_buy' do
    log_in
    setup_test_category(name: 'Bread', slug: 'bread')
    create_recipe_with_ingredient('Flour')
    select_recipe('focaccia')

    # Item is in inventory check (visible, no on_hand entry yet → expired-like)
    # First have_it then travel forward so it expires into IC
    check_have_it('Flour')
    travel 365.days do
      post groceries_need_path(kitchen_slug: kitchen_slug),
           params: { item: 'Flour' },
           as: :json

      assert_response :success
      assert_equal 'moved_to_buy', response.parsed_body['status']
    end
  end

  test 'need rejects item that is too long' do
    log_in
    post groceries_need_path(kitchen_slug: kitchen_slug),
         params: { item: 'x' * (MealPlan::MAX_CUSTOM_ITEM_LENGTH + 1) },
         as: :json

    assert_response :unprocessable_content
  end

  test 'need rejects blank item' do
    log_in
    post groceries_need_path(kitchen_slug: kitchen_slug),
         params: { item: '' },
         as: :json

    assert_response :unprocessable_content
  end

  test 'need requires membership' do
    post groceries_need_path(kitchen_slug: kitchen_slug),
         params: { item: 'Flour' },
         as: :json

    assert_response :forbidden
  end

  private

  def create_recipe_with_ingredient(ingredient_name)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia
      ## Mix
      - #{ingredient_name}, 3 cups
      Mix well.
    MD
  end

  def select_recipe(slug)
    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: slug, selected: true
    )
  end

  def mark_need_it(item)
    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'need_it', item: item
    )
  end

  def check_have_it(item)
    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'have_it', item: item
    )
  end

  def build_stale_list(method_to_stub)
    list = MealPlan.for_kitchen(@kitchen)
    list.define_singleton_method(method_to_stub) do |*, **|
      raise ActiveRecord::StaleObjectError, self
    end
    list.define_singleton_method(:reload) { self }
    list
  end
end
