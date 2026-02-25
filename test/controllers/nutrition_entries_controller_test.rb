# frozen_string_literal: true

require 'test_helper'

class NutritionEntriesControllerTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  VALID_LABEL = <<~LABEL
    Serving size: 1/4 cup (30g)

    Calories          110
    Total Fat         0.5g
      Saturated Fat   0g
      Trans Fat       0g
    Cholesterol       0mg
    Sodium            5mg
    Total Carbs       23g
      Dietary Fiber   1g
      Total Sugars    0g
        Added Sugars  0g
    Protein           3g
  LABEL

  setup do
    create_kitchen_and_user
    log_in
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    IngredientCatalog.where(kitchen_id: [@kitchen.id, nil]).delete_all
  end

  # --- upsert ---

  test 'upsert creates kitchen-scoped entry from label text' do
    post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
         params: { label_text: VALID_LABEL },
         as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal 'ok', body['status']

    entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')

    assert_predicate entry, :present?
    assert_predicate entry, :custom?
    assert_in_delta 30.0, entry.basis_grams
    assert_in_delta 110.0, entry.calories
    assert_in_delta 0.5, entry.fat
    assert_in_delta 23.0, entry.carbs
    assert_in_delta 3.0, entry.protein
    assert_equal 'cup', entry.density_unit
  end

  test 'upsert updates existing kitchen entry' do
    IngredientCatalog.create!(
      kitchen: @kitchen, ingredient_name: 'flour',
      basis_grams: 100, calories: 364
    )

    post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
         params: { label_text: VALID_LABEL },
         as: :json

    assert_response :success

    entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')

    assert_in_delta 30.0, entry.basis_grams
    assert_in_delta 110.0, entry.calories
  end

  test 'upsert sets web source provenance' do
    post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
         params: { label_text: VALID_LABEL },
         as: :json

    assert_response :success

    entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')

    assert_equal [{ 'type' => 'web', 'note' => 'Entered via ingredients page' }], entry.sources
  end

  test 'upsert returns errors for invalid label' do
    post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
         params: { label_text: "Calories 100\nTotal Fat 5g" },
         as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)

    assert_predicate body['errors'], :any?
    assert(body['errors'].any? { |e| e.include?('Serving size') })
  end

  test 'upsert decodes hyphenated ingredient names' do
    post nutrition_entry_upsert_path('olive-oil', kitchen_slug: kitchen_slug),
         params: { label_text: VALID_LABEL },
         as: :json

    assert_response :success

    entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'olive oil')

    assert_predicate entry, :present?
  end

  test 'upsert recalculates affected recipes' do
    recipe = import_recipe_with_flour

    assert_nil recipe.reload.nutrition_data

    # Upsert creates a kitchen entry with density, enabling volume resolution
    post nutrition_entry_upsert_path('Flour', kitchen_slug: kitchen_slug),
         params: { label_text: VALID_LABEL },
         as: :json

    assert_response :success

    nutrition = recipe.reload.nutrition_data

    assert_not_nil nutrition
    assert_predicate nutrition.dig('per_serving', 'calories'), :positive?
  end

  test 'upsert requires membership' do
    get dev_logout_path

    post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
         params: { label_text: VALID_LABEL },
         as: :json

    assert_response :unauthorized
  end

  # --- upsert with aisle ---

  test 'upsert saves aisle alongside nutrition data' do
    post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
         params: { label_text: VALID_LABEL, aisle: 'Baking' },
         as: :json

    assert_response :success
    entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')

    assert_equal 'Baking', entry.aisle
    assert_in_delta 110.0, entry.calories
  end

  test 'upsert saves aisle-only when label is blank skeleton' do
    post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
         params: { label_text: NutritionLabelParser.blank_skeleton, aisle: 'Baking' },
         as: :json

    assert_response :success
    entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')

    assert_equal 'Baking', entry.aisle
    assert_nil entry.basis_grams
  end

  test 'upsert saves aisle-only when label is empty' do
    post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
         params: { label_text: '', aisle: 'Produce' },
         as: :json

    assert_response :success
    entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')

    assert_equal 'Produce', entry.aisle
  end

  test 'upsert appends new aisle to kitchen aisle_order' do
    post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
         params: { label_text: '', aisle: 'Deli' },
         as: :json

    assert_response :success
    assert_includes @kitchen.reload.parsed_aisle_order, 'Deli'
  end

  test 'upsert does not duplicate existing aisle in aisle_order' do
    @kitchen.update!(aisle_order: "Produce\nBaking")

    post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
         params: { label_text: '', aisle: 'Baking' },
         as: :json

    assert_response :success
    assert_equal "Produce\nBaking", @kitchen.reload.aisle_order
  end

  test 'upsert returns error when both label invalid and no aisle' do
    post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
         params: { label_text: 'garbage', aisle: '' },
         as: :json

    assert_response :unprocessable_entity
  end

  test 'upsert broadcasts content changed when aisle is saved' do
    assert_broadcast_on(GroceryListChannel.broadcasting_for(@kitchen), type: 'content_changed') do
      post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
           params: { label_text: '', aisle: 'Deli' },
           as: :json
    end
  end

  # --- destroy ---

  test 'destroy deletes kitchen override' do
    IngredientCatalog.create!(
      kitchen: @kitchen, ingredient_name: 'flour',
      basis_grams: 30, calories: 110
    )

    delete nutrition_entry_destroy_path('flour', kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')
  end

  test 'destroy does not delete global entries' do
    IngredientCatalog.create!(
      kitchen: nil, ingredient_name: 'flour',
      basis_grams: 100, calories: 364
    )

    delete nutrition_entry_destroy_path('flour', kitchen_slug: kitchen_slug), as: :json

    assert_response :not_found
    assert IngredientCatalog.exists?(kitchen_id: nil, ingredient_name: 'flour')
  end

  test 'destroy returns 404 for nonexistent entry' do
    delete nutrition_entry_destroy_path('nonexistent', kitchen_slug: kitchen_slug), as: :json

    assert_response :not_found
  end

  test 'destroy requires membership' do
    get dev_logout_path

    delete nutrition_entry_destroy_path('flour', kitchen_slug: kitchen_slug), as: :json

    assert_response :unauthorized
  end

  test 'destroy recalculates affected recipes with global fallback' do
    # Global entry has no density — cannot resolve volume units
    IngredientCatalog.create!(
      kitchen: nil, ingredient_name: 'Flour',
      basis_grams: 100, calories: 364, fat: 1.0, saturated_fat: 0,
      trans_fat: 0, cholesterol: 0, sodium: 2, carbs: 76, fiber: 2.7,
      total_sugars: 0.3, added_sugars: 0, protein: 10
    )
    # Kitchen override with density — resolves "3 cups" via volume
    IngredientCatalog.create!(
      kitchen: @kitchen, ingredient_name: 'Flour',
      basis_grams: 30, calories: 110, fat: 0.5, saturated_fat: 0,
      trans_fat: 0, cholesterol: 0, sodium: 5, carbs: 23, fiber: 1,
      total_sugars: 0, added_sugars: 0, protein: 3,
      density_grams: 30.0, density_volume: 0.25, density_unit: 'cup'
    )

    recipe = import_recipe_with_flour
    RecipeNutritionJob.perform_now(recipe.reload)
    override_calories = recipe.reload.nutrition_data.dig('per_serving', 'calories')

    assert_predicate override_calories, :positive?, 'Expected positive calories with density-enabled override'

    delete nutrition_entry_destroy_path('Flour', kitchen_slug: kitchen_slug), as: :json

    assert_response :success

    # After delete, global entry (no density) is used — volume can't resolve,
    # so Flour becomes a partial ingredient with zero calorie contribution
    nutrition = recipe.reload.nutrition_data

    assert_not_nil nutrition
    assert_includes nutrition['partial_ingredients'], 'Flour'
  end

  private

  def import_recipe_with_flour
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Test Bread

      Category: Bread
      Serves: 4

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    Recipe.find_by!(slug: 'test-bread')
  end
end
