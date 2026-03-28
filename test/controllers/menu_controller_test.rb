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
    create_quick_bite('Goldfish', category_name: 'Snacks')

    log_in
    get menu_quickbites_editor_frame_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'script[type="application/json"][data-editor-markdown]' do |scripts|
      json = JSON.parse(scripts.first.text)

      assert_includes json['plaintext'], 'Goldfish'
    end
  end

  test 'quickbites_editor_frame renders category cards' do
    create_quick_bite('Goldfish', category_name: 'Snacks')
    create_quick_bite('Hummus with Pretzels', category_name: 'Snacks', ingredients: %w[Hummus Pretzels])

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
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'Recipe', selectable_id: 'focaccia')

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
    OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Salt',
                        confirmed_at: Date.current, interval: 7, ease: 1.5)

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
    OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour',
                        confirmed_at: Date.current, interval: 7, ease: 1.5)

    get menu_path(kitchen_slug: kitchen_slug)

    assert_select 'span.availability-single.on-hand svg'
  end

  test 'show renders checkmark-only pill when multi-ingredient recipe all on hand' do
    log_in
    create_two_ingredient_recipe
    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
    create_catalog_entry('Salt', basis_grams: 5, aisle: 'Baking')
    OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour',
                        confirmed_at: Date.current, interval: 7, ease: 1.5)
    OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Salt',
                        confirmed_at: Date.current, interval: 7, ease: 1.5)

    get menu_path(kitchen_slug: kitchen_slug)

    assert_select 'details.collapse-header.all-on-hand summary', text: %r{2/2}
  end

  test 'show includes dinner picker weights url' do
    log_in

    get menu_path(kitchen_slug:)

    assert_response :ok
    assert_select '[data-controller*="dinner-picker"]' do
      assert_select '[data-dinner-picker-weights-url-value]'
    end
  end

  test 'dinner_weights returns cook history weights as json' do
    log_in
    CookHistoryEntry.create!(kitchen: @kitchen, recipe_slug: 'focaccia', cooked_at: 1.day.ago)

    get menu_dinner_weights_path(kitchen_slug:)

    assert_response :ok
    assert_equal 'application/json', response.media_type
    weights = response.parsed_body

    assert weights.key?('focaccia')
  end

  test 'show renders have and missing ingredient lists in detail' do
    log_in
    create_two_ingredient_recipe
    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
    create_catalog_entry('Salt', basis_grams: 5, aisle: 'Baking')
    OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Salt',
                        confirmed_at: Date.current, interval: 7, ease: 1.5)

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

    assert MealPlanSelection.exists?(kitchen: @kitchen, selectable_type: 'Recipe', selectable_id: 'focaccia')
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

    assert_not MealPlanSelection.exists?(kitchen: @kitchen, selectable_type: 'Recipe', selectable_id: 'focaccia')
  end

  test 'select returns 409 when StaleObjectError raised' do
    log_in
    MealPlanWriteService.stub(:apply_action, ->(**) { raise ActiveRecord::StaleObjectError, nil }) do
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
    create_quick_bite('Goldfish', category_name: 'Snacks')

    log_in
    get menu_quick_bites_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    json = response.parsed_body

    assert_includes json['content'], 'Goldfish'
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
    assert_equal 1, @kitchen.quick_bites.count
    assert_equal 'Goldfish', @kitchen.quick_bites.first.title
  end

  test 'update_quick_bites clears content when blank' do
    create_quick_bite('Goldfish', category_name: 'Snacks')

    log_in
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: '' },
          as: :json

    assert_response :success
    assert_equal 0, @kitchen.quick_bites.reload.count
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
    nachos = create_quick_bite('Nachos', category_name: 'Snacks', ingredients: ['Chips'])
    pretzels = create_quick_bite('Pretzels', category_name: 'Snacks', ingredients: ['Pretzels'])
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'QuickBite', selectable_id: nachos.id.to_s)
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'QuickBite', selectable_id: pretzels.id.to_s)

    log_in
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n- Nachos: Chips\n" },
          as: :json

    # Nachos was re-created with a new ID; old selections for removed QBs are pruned
    new_nachos = @kitchen.quick_bites.find_by(title: 'Nachos')

    assert new_nachos, 'Nachos should still exist'
    pretzels_sel = { kitchen: @kitchen, selectable_type: 'QuickBite', selectable_id: pretzels.id.to_s }

    assert_not MealPlanSelection.exists?(pretzels_sel)
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

  test 'menu shows qb zone wrapper around quick bites for members' do
    create_quick_bite('Goldfish', category_name: 'Snacks')
    log_in

    get menu_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.qb-zone' do
      assert_select '.qb-zone-header'
      assert_select '.qb-zone-label', text: 'Quick Bites'
      assert_select '.qb-zone-edit'
    end
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
    qb = @kitchen.quick_bites.find_by(title: 'Crackers')

    assert qb
    assert_equal ['Ritz'], qb.quick_bite_ingredients.map(&:name)
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
end
