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

  test 'update_quick_bites requires membership' do
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n- Goldfish" },
          as: :json

    assert_response :forbidden
  end

  test 'quick_bites_content requires membership' do
    get menu_quick_bites_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end

  test 'quickbites_editor_frame requires membership' do
    get menu_quickbites_editor_frame_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  # --- Quick Bites Editor Frame ---

  test 'quickbites_editor_frame returns turbo frame with correct ID' do
    log_in
    get menu_quickbites_editor_frame_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'turbo-frame#quickbites-editor-content'
  end

  test 'quickbites_editor_frame contains embedded content JSON' do
    @kitchen.update!(quick_bites_content: "## Snacks\n- Goldfish")

    log_in
    get menu_quickbites_editor_frame_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'script[type="application/json"][data-editor-markdown]' do |scripts|
      json = JSON.parse(scripts.first.text)

      assert_equal "## Snacks\n- Goldfish", json['plaintext']
    end
  end

  test 'quickbites_editor_frame renders category cards' do
    @kitchen.update!(quick_bites_content: "## Snacks\n- Goldfish\n- Hummus with Pretzels: Hummus, Pretzels")

    log_in
    get menu_quickbites_editor_frame_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.graphical-step-card', count: 1
    assert_select '.graphical-step-title', text: 'Snacks'
    assert_select '.graphical-ingredient-summary', text: '2 items'
    assert_select '.graphical-ingredient-row', count: 2
  end

  test 'quickbites_editor_frame renders empty state when no content' do
    log_in
    get menu_quickbites_editor_frame_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.graphical-step-card', count: 0
    assert_select 'script[type="application/json"][data-editor-markdown]' do |scripts|
      json = JSON.parse(scripts.first.text)

      assert_equal '', json['plaintext']
    end
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

  test 'show pre-checks selected recipes' do
    log_in
    create_focaccia_recipe
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    get menu_path(kitchen_slug: kitchen_slug)

    assert_select '#recipe-selector input[data-slug="focaccia"][checked]'
  end

  test 'show does not check unselected recipes' do
    log_in
    create_focaccia_recipe

    get menu_path(kitchen_slug: kitchen_slug)

    assert_select '#recipe-selector input[checked]', count: 0
  end

  test 'show renders M/N badge when partially available' do
    log_in
    create_two_ingredient_recipe
    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
    create_catalog_entry('Salt', basis_grams: 5, aisle: 'Baking')
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Salt', checked: true)

    get menu_path(kitchen_slug: kitchen_slug)

    assert_select 'details.collapse-header summary', text: %r{1/2}
  end

  test 'show renders x for single-ingredient recipe when not on hand' do
    log_in
    create_focaccia_recipe
    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')

    get menu_path(kitchen_slug: kitchen_slug)

    assert_select 'span.availability-single.not-on-hand svg'
  end

  test 'show renders checkmark for single-ingredient recipe when on hand' do
    log_in
    create_focaccia_recipe
    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Flour', checked: true)

    get menu_path(kitchen_slug: kitchen_slug)

    assert_select 'span.availability-single.on-hand svg'
  end

  test 'show renders checkmark-only pill when multi-ingredient recipe all on hand' do
    log_in
    create_two_ingredient_recipe
    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
    create_catalog_entry('Salt', basis_grams: 5, aisle: 'Baking')
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Flour', checked: true)
    plan.apply_action('check', item: 'Salt', checked: true)

    get menu_path(kitchen_slug: kitchen_slug)

    assert_select 'details.collapse-header.all-on-hand summary', text: %r{2/2}
  end

  test 'show embeds cook history weights' do
    log_in
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['cook_history'] = [
      { 'slug' => 'focaccia', 'at' => 1.day.ago.iso8601 }
    ]
    plan.save!

    get menu_path(kitchen_slug:)

    assert_response :ok
    assert_select '[data-controller*="dinner-picker"]' do
      assert_select '[data-dinner-picker-weights-value]'
    end
  end

  test 'show renders have and missing ingredient lists in detail' do
    log_in
    create_two_ingredient_recipe
    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
    create_catalog_entry('Salt', basis_grams: 5, aisle: 'Baking')
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Salt', checked: true)

    get menu_path(kitchen_slug: kitchen_slug)

    assert_select '.availability-have', text: /Salt/
    assert_select '.availability-need', text: /Flour/
  end

  # --- Select ---

  test 'select adds recipe' do
    log_in
    create_focaccia_recipe
    patch menu_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :turbo_stream

    assert_response :no_content

    plan = MealPlan.for_kitchen(@kitchen)

    assert_includes plan.state['selected_recipes'], 'focaccia'
  end

  test 'select broadcasts meal plan refresh' do
    log_in
    create_focaccia_recipe
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      patch menu_select_path(kitchen_slug: kitchen_slug),
            params: { type: 'recipe', slug: 'focaccia', selected: true },
            as: :turbo_stream
    end
  end

  test 'select deselects recipe when selected is false' do
    log_in
    create_focaccia_recipe
    patch menu_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :turbo_stream

    patch menu_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: false },
          as: :turbo_stream

    plan = MealPlan.for_kitchen(@kitchen)

    assert_not_includes plan.state['selected_recipes'], 'focaccia'
  end

  test 'select returns 409 when retry exhausted' do
    log_in
    stale_plan = build_stale_plan(:apply_action)

    MealPlan.stub(:for_kitchen, stale_plan) do
      patch menu_select_path(kitchen_slug: kitchen_slug),
            params: { type: 'recipe', slug: 'focaccia', selected: true },
            as: :turbo_stream
    end

    assert_response :conflict
    json = response.parsed_body

    assert_equal 'Meal plan was modified by another request. Please refresh.', json['error']
  end

  # --- Quick Bites ---

  test 'quick_bites_content returns current content and structure' do
    @kitchen.update!(quick_bites_content: "## Snacks\n- Goldfish")

    log_in
    get menu_quick_bites_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    json = response.parsed_body

    assert_equal "## Snacks\n- Goldfish", json['content']
    assert_equal 'Snacks', json['structure']['categories'].first['name']
    assert_equal 'Goldfish', json['structure']['categories'].first['items'].first['name']
  end

  test 'quick_bites_content returns empty string and empty structure when no content' do
    log_in
    get menu_quick_bites_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    json = response.parsed_body

    assert_equal '', json['content']
    assert_empty json['structure']['categories']
  end

  test 'update_quick_bites saves content' do
    log_in
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n- Goldfish" },
          as: :json

    assert_response :success
    assert_equal "## Snacks\n- Goldfish", @kitchen.reload.quick_bites_content
  end

  test 'update_quick_bites clears content when blank' do
    @kitchen.update!(quick_bites_content: 'old content')

    log_in
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: '' },
          as: :json

    assert_response :success
    assert_nil @kitchen.reload.quick_bites_content
  end

  test 'update_quick_bites returns warnings for unrecognized lines' do
    log_in
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n- Goldfish\ngarbage line\n- Dried fruit" },
          as: :json

    assert_response :success
    json = response.parsed_body

    assert_equal 'ok', json['status']
    assert_equal 1, json['warnings'].size
    assert_match(/line 3/i, json['warnings'].first)
  end

  test 'update_quick_bites returns no warnings for clean content' do
    log_in
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n- Goldfish\n" },
          as: :json

    assert_response :success
    json = response.parsed_body

    assert_equal 'ok', json['status']
    assert_nil json['warnings']
  end

  test 'update_quick_bites prunes removed quick bite from selections' do
    both = "## Snacks\n- Nachos: Chips\n- Pretzels: Pretzels\n"
    @kitchen.update!(quick_bites_content: both)
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)
    plan.apply_action('select', type: 'quick_bite', slug: 'pretzels', selected: true)

    log_in
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n- Nachos: Chips\n" },
          as: :json

    plan.reload

    assert_includes plan.state['selected_quick_bites'], 'nachos'
    assert_not_includes plan.state['selected_quick_bites'], 'pretzels'
  end

  test 'update_quick_bites broadcasts meal plan refresh' do
    log_in
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
            params: { content: "## Snacks\n- Goldfish" },
            as: :json
    end
  end

  test 'parse_quick_bites returns IR from content' do
    log_in
    content = "## Snacks\n- Apples and Honey: Apples, Honey"

    post menu_parse_quick_bites_path(kitchen_slug: kitchen_slug),
         params: { content: }, as: :json

    assert_response :ok
    body = response.parsed_body

    assert_equal 1, body['categories'].size
    assert_equal 'Snacks', body['categories'][0]['name']
    assert_equal 'Apples and Honey', body['categories'][0]['items'][0]['name']
  end

  test 'serialize_quick_bites returns content from IR' do
    log_in
    ir = {
      categories: [
        { name: 'Snacks', items: [{ name: 'Apples', ingredients: %w[Apples] }] }
      ]
    }

    post menu_serialize_quick_bites_path(kitchen_slug: kitchen_slug),
         params: { structure: ir }, as: :json

    assert_response :ok
    assert_includes response.parsed_body['content'], '## Snacks'
    assert_includes response.parsed_body['content'], '- Apples'
  end

  test 'update_quick_bites with structure rejects unexpected keys' do
    log_in
    ir = { categories: [], evil: 'payload' }

    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { structure: ir }, as: :json

    assert_response :bad_request
  end

  test 'serialize_quick_bites rejects unexpected keys' do
    log_in
    ir = { categories: [], injected: true }

    post menu_serialize_quick_bites_path(kitchen_slug: kitchen_slug),
         params: { structure: ir }, as: :json

    assert_response :bad_request
  end

  test 'update_quick_bites with structure param uses structured path' do
    log_in
    ir = {
      categories: [
        { name: 'Snacks', items: [{ name: 'Crackers', ingredients: %w[Ritz] }] }
      ]
    }

    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { structure: ir }, as: :json

    assert_response :ok
    assert_includes @kitchen.reload.quick_bites_content, '## Snacks'
    assert_includes @kitchen.quick_bites_content, '- Crackers: Ritz'
  end

  private

  def create_two_ingredient_recipe
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD
  end

  def create_focaccia_recipe
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix

      - Flour, 3 cups

      Mix well.
    MD
  end

  def build_stale_plan(method_to_stub)
    plan = MealPlan.for_kitchen(@kitchen)
    plan.define_singleton_method(method_to_stub) do |*, **|
      raise ActiveRecord::StaleObjectError, self
    end
    plan.define_singleton_method(:reload) { self }
    plan
  end
end
