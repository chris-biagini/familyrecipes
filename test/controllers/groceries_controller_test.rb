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
    get groceries_aisle_order_content_path(kitchen_slug: kitchen_slug), as: :json

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

  test 'show renders aisle sections when recipes selected' do
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

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select 'details.aisle[data-aisle="Baking"]'
    assert_select 'li[data-item="Flour"]'
    assert_select 'input[type="checkbox"][data-item="Flour"]'
  end

  test 'show pre-checks checked-off items' do
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

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('check', item: 'Flour', checked: true)

    log_in
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_select 'input[type="checkbox"][data-item="Flour"][checked]'
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
    assert_select '#edit-aisle-order-button', 'Edit Aisle Order'
    assert_select 'dialog[data-editor-open-selector-value="#edit-aisle-order-button"]'
  end

  # --- Mutation tests ---

  test 'check marks item as checked' do
    log_in
    patch groceries_check_path(kitchen_slug: kitchen_slug),
          params: { item: 'flour', checked: true },
          as: :turbo_stream

    assert_response :no_content
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

    assert_not_includes plan.custom_items_list, 'birthday candles'
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

  test 'check broadcasts to groceries stream' do
    log_in
    assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
      patch groceries_check_path(kitchen_slug: kitchen_slug),
            params: { item: 'flour', checked: true },
            as: :turbo_stream
    end
  end

  test 'update_custom_items broadcasts to groceries stream' do
    log_in
    assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
      patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
            params: { item: 'birthday candles', action_type: 'add' },
            as: :turbo_stream
    end
  end

  test 'update_aisle_order broadcasts to groceries stream' do
    log_in
    assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
      patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
            params: { aisle_order: "Produce\nBaking" },
            as: :json
    end
  end

  private

  def build_stale_list(method_to_stub)
    list = MealPlan.for_kitchen(@kitchen)
    list.define_singleton_method(method_to_stub) do |*, **|
      raise ActiveRecord::StaleObjectError, self
    end
    list.define_singleton_method(:reload) { self }
    list
  end
end
