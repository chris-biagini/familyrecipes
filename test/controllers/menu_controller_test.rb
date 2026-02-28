# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class MenuControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    create_kitchen_and_user
  end

  # --- Access control ---

  test 'show requires membership' do
    get menu_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'select requires membership' do
    patch menu_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :json

    assert_response :forbidden
  end

  test 'clear requires membership' do
    delete menu_clear_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end

  test 'update_quick_bites requires membership' do
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n  - Goldfish" },
          as: :json

    assert_response :forbidden
  end

  test 'quick_bites_content requires membership' do
    get menu_quick_bites_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end

  # --- Show page ---

  test 'show renders successfully when logged in' do
    log_in
    get menu_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'h1', 'Menu'
    assert_select '[data-controller~="menu"]'
    assert_select '#recipe-selector'
  end

  # --- Select ---

  test 'select adds recipe and returns version' do
    log_in
    patch menu_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :json

    assert_response :success
    json = response.parsed_body

    assert_operator json['version'], :>, 0
  end

  test 'select broadcasts version via MealPlanChannel' do
    log_in
    stream = MealPlanChannel.broadcasting_for(@kitchen)

    assert_broadcasts(stream, 1) do
      patch menu_select_path(kitchen_slug: kitchen_slug),
            params: { type: 'recipe', slug: 'focaccia', selected: true },
            as: :json
    end
  end

  test 'select deselects recipe when selected is false' do
    log_in
    patch menu_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :json

    patch menu_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: false },
          as: :json

    plan = MealPlan.for_kitchen(@kitchen)

    assert_not_includes plan.state['selected_recipes'], 'focaccia'
  end

  test 'select returns 409 when retry exhausted' do
    log_in
    stale_plan = build_stale_plan(:apply_action)

    MealPlan.stub(:for_kitchen, stale_plan) do
      patch menu_select_path(kitchen_slug: kitchen_slug),
            params: { type: 'recipe', slug: 'focaccia', selected: true },
            as: :json
    end

    assert_response :conflict
    json = response.parsed_body

    assert_equal 'Meal plan was modified by another request. Please refresh.', json['error']
  end

  # --- Select All ---

  test 'select_all requires membership' do
    patch menu_select_all_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end

  test 'select_all selects all recipes and quick bites' do
    log_in
    @kitchen.update!(quick_bites_content: "## Snacks\n  - Goldfish: Goldfish crackers")

    patch menu_select_all_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success

    plan = MealPlan.for_kitchen(@kitchen)
    recipe_slugs = @kitchen.recipes.pluck(:slug)

    assert_equal recipe_slugs.sort, plan.state['selected_recipes'].sort
    assert_includes plan.state['selected_quick_bites'], 'goldfish'
  end

  test 'select_all preserves custom items and checked off' do
    log_in
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('custom_items', item: 'birthday candles', action: 'add')
    plan.apply_action('check', item: 'flour', checked: true)

    patch menu_select_all_path(kitchen_slug: kitchen_slug), as: :json

    plan.reload

    assert_includes plan.state['custom_items'], 'birthday candles'
    assert_includes plan.state['checked_off'], 'flour'
  end

  test 'select_all broadcasts version' do
    log_in
    stream = MealPlanChannel.broadcasting_for(@kitchen)

    assert_broadcasts(stream, 1) do
      patch menu_select_all_path(kitchen_slug: kitchen_slug), as: :json
    end
  end

  # --- Clear ---

  test 'clear resets selections and checked off' do
    log_in
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('custom_items', item: 'birthday candles', action: 'add')
    plan.apply_action('check', item: 'flour', checked: true)

    delete menu_clear_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    json = response.parsed_body

    assert json.key?('version')

    plan.reload

    assert_empty plan.state['selected_recipes']
    assert_empty plan.state['selected_quick_bites']
    assert_includes plan.state['custom_items'], 'birthday candles'
    assert_empty plan.state['checked_off']
  end

  test 'clear broadcasts version' do
    log_in
    stream = MealPlanChannel.broadcasting_for(@kitchen)

    assert_broadcasts(stream, 1) do
      delete menu_clear_path(kitchen_slug: kitchen_slug), as: :json
    end
  end

  test 'clear returns 409 when retry exhausted' do
    log_in
    stale_plan = build_stale_plan(:clear_selections!)

    MealPlan.stub(:for_kitchen, stale_plan) do
      delete menu_clear_path(kitchen_slug: kitchen_slug), as: :json
    end

    assert_response :conflict
  end

  # --- Quick Bites ---

  test 'quick_bites_content returns current content' do
    @kitchen.update!(quick_bites_content: "## Snacks\n  - Goldfish")

    log_in
    get menu_quick_bites_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    json = response.parsed_body

    assert_equal "## Snacks\n  - Goldfish", json['content']
  end

  test 'quick_bites_content returns empty string when no content' do
    log_in
    get menu_quick_bites_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    json = response.parsed_body

    assert_equal '', json['content']
  end

  test 'update_quick_bites saves content' do
    log_in
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n  - Goldfish" },
          as: :json

    assert_response :success
    assert_equal "## Snacks\n  - Goldfish", @kitchen.reload.quick_bites_content
  end

  test 'update_quick_bites rejects blank content' do
    @kitchen.update!(quick_bites_content: 'old content')

    log_in
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: '' },
          as: :json

    assert_response :unprocessable_entity
  end

  test 'update_quick_bites broadcasts Turbo Stream to menu_content' do
    log_in

    assert_turbo_stream_broadcasts [@kitchen, 'menu_content'] do
      patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
            params: { content: "## Snacks\n  - Goldfish" },
            as: :json
    end
  end

  # --- State endpoint ---

  test 'state requires membership' do
    get menu_state_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end

  test 'state returns version and selections' do
    log_in
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    get menu_state_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    json = response.parsed_body

    assert json.key?('version')
    assert_includes json['selected_recipes'], 'focaccia'
    assert json.key?('selected_quick_bites')
  end

  test 'state includes availability map' do
    log_in
    get menu_state_path(kitchen_slug: kitchen_slug), as: :json

    json = response.parsed_body

    assert json.key?('availability')
  end

  test 'state availability reflects checked_off items' do
    Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Salt') do |p|
      p.basis_grams = 6
      p.aisle = 'Spices'
    end

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Flour', checked: true)

    log_in
    get menu_state_path(kitchen_slug: kitchen_slug), as: :json

    json = response.parsed_body
    focaccia = json['availability']['focaccia']

    assert_equal 1, focaccia['missing']
    assert_includes focaccia['missing_names'], 'Salt'
    assert_includes focaccia['ingredients'], 'Flour'
    assert_includes focaccia['ingredients'], 'Salt'
  end

  private

  def build_stale_plan(method_to_stub)
    plan = MealPlan.for_kitchen(@kitchen)
    plan.define_singleton_method(method_to_stub) do |*, **|
      raise ActiveRecord::StaleObjectError, self
    end
    plan.define_singleton_method(:reload) { self }
    plan
  end
end
