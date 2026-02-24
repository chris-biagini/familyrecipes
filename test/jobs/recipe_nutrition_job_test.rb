# frozen_string_literal: true

require 'test_helper'

class RecipeNutritionJobTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    Recipe.destroy_all
    Category.destroy_all
    IngredientCatalog.destroy_all

    IngredientCatalog.create!(
      ingredient_name: 'Flour',
      basis_grams: 30.0,
      calories: 110.0,
      fat: 0.5,
      protein: 3.0
    )
  end

  test 'computes and stores nutrition_data on recipe' do
    markdown = "# Bread\n\nCategory: Cat\nServes: 2\n\n## Mix\n\n- Flour, 60 g\n\nMix."
    recipe = import_without_nutrition(markdown)

    RecipeNutritionJob.perform_now(recipe)
    recipe.reload

    assert_predicate recipe.nutrition_data, :present?
    assert_predicate recipe.nutrition_data['totals']['calories'], :positive?
  end

  test 'stores per_serving when recipe has serves' do
    markdown = "# Bread\n\nCategory: Cat\nServes: 2\n\n## Mix\n\n- Flour, 60 g\n\nMix."
    recipe = import_without_nutrition(markdown)

    RecipeNutritionJob.perform_now(recipe)
    recipe.reload

    assert_equal 2, recipe.nutrition_data['serving_count']
    assert_predicate recipe.nutrition_data['per_serving']['calories'], :positive?
  end

  test 'handles recipe with no nutrition entries gracefully' do
    IngredientCatalog.destroy_all

    markdown = "# Salad\n\nCategory: Cat\n\n## Toss\n\n- Lettuce, 1 head\n\nToss."
    recipe = import_without_nutrition(markdown)

    RecipeNutritionJob.perform_now(recipe)
    recipe.reload

    assert_nil recipe.nutrition_data
  end

  test 'records missing ingredients' do
    markdown = "# Salad\n\nCategory: Cat\n\n## Toss\n\n- Lettuce, 100 g\n- Flour, 30 g\n\nToss."
    recipe = import_without_nutrition(markdown)

    RecipeNutritionJob.perform_now(recipe)
    recipe.reload

    assert_includes recipe.nutrition_data['missing_ingredients'], 'Lettuce'
  end

  test 'markdown importer triggers nutrition computation' do
    markdown = "# Auto Bread\n\nCategory: Cat\nServes: 4\n\n## Mix\n\n- Flour, 120 g\n\nMix."
    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)

    assert_predicate recipe.nutrition_data, :present?
    assert_predicate recipe.nutrition_data['totals']['calories'], :positive?
  end

  test 'uses kitchen override when available' do
    # Global entry exists from setup (Flour, calories: 110)
    # Create kitchen override with different calories
    IngredientCatalog.create!(
      kitchen: @kitchen,
      ingredient_name: 'Flour',
      basis_grams: 30.0,
      calories: 200.0,
      fat: 1.0,
      protein: 5.0
    )

    markdown = "# Bread\n\nCategory: Cat\nServes: 1\n\n## Mix\n\n- Flour, 30 g\n\nMix."
    recipe = import_without_nutrition(markdown)

    RecipeNutritionJob.perform_now(recipe)
    recipe.reload

    # Should use the kitchen override (200 cal) not global (110 cal)
    assert_in_delta 200.0, recipe.nutrition_data['totals']['calories'], 0.01
  end

  test 'cascade job recomputes nutrition for referencing recipes' do
    dough = MarkdownImporter.import(
      "# Dough\n\nCategory: Cat\nServes: 2\n\n## Mix\n\n- Flour, 60 g\n\nMix.", kitchen: @kitchen
    )
    pizza = MarkdownImporter.import(
      "# Pizza\n\nCategory: Cat\nServes: 4\n\n## Build\n\n- @[Dough]\n\nBuild.", kitchen: @kitchen
    )

    CascadeNutritionJob.perform_now(dough)
    pizza.reload

    assert_predicate pizza.nutrition_data, :present?
    assert_predicate pizza.nutrition_data['totals']['calories'], :positive?
  end

  private

  def import_without_nutrition(markdown)
    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)
    recipe.update_column(:nutrition_data, nil)
    recipe
  end
end
