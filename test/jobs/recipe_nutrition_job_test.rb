# frozen_string_literal: true

require 'test_helper'

class RecipeNutritionJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    setup_test_kitchen
    Recipe.destroy_all
    Category.destroy_all
    IngredientCatalog.destroy_all
    setup_test_category

    create_catalog_entry('Flour', basis_grams: 30.0, calories: 110.0, fat: 0.5, protein: 3.0)
  end

  test 'computes and stores nutrition_data on recipe' do
    markdown = "# Bread\n\nServes: 2\n\n## Mix\n\n- Flour, 60 g\n\nMix."
    recipe = import_without_nutrition(markdown)

    RecipeNutritionJob.perform_now(recipe)
    recipe.reload

    assert_predicate recipe.nutrition_data, :present?
    assert_predicate recipe.nutrition_data['totals']['calories'], :positive?
  end

  test 'stores per_serving when recipe has serves' do
    markdown = "# Bread\n\nServes: 2\n\n## Mix\n\n- Flour, 60 g\n\nMix."
    recipe = import_without_nutrition(markdown)

    RecipeNutritionJob.perform_now(recipe)
    recipe.reload

    assert_equal 2, recipe.nutrition_data['serving_count']
    assert_predicate recipe.nutrition_data['per_serving']['calories'], :positive?
  end

  test 'handles recipe with no nutrition entries gracefully' do
    IngredientCatalog.destroy_all

    markdown = "# Salad\n\n\n## Toss\n\n- Lettuce, 1 head\n\nToss."
    recipe = import_without_nutrition(markdown)

    RecipeNutritionJob.perform_now(recipe)
    recipe.reload

    assert_nil recipe.nutrition_data
  end

  test 'records missing ingredients' do
    markdown = "# Salad\n\n\n## Toss\n\n- Lettuce, 100 g\n- Flour, 30 g\n\nToss."
    recipe = import_without_nutrition(markdown)

    RecipeNutritionJob.perform_now(recipe)
    recipe.reload

    assert_includes recipe.nutrition_data['missing_ingredients'], 'Lettuce'
  end

  test 'markdown importer triggers nutrition computation' do
    markdown = "# Auto Bread\n\nServes: 4\n\n## Mix\n\n- Flour, 120 g\n\nMix."
    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @category)

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

    markdown = "# Bread\n\nServes: 1\n\n## Mix\n\n- Flour, 30 g\n\nMix."
    recipe = import_without_nutrition(markdown)

    RecipeNutritionJob.perform_now(recipe)
    recipe.reload

    # Should use the kitchen override (200 cal) not global (110 cal)
    assert_in_delta 200.0, recipe.nutrition_data['totals']['calories'], 0.01
  end

  test 'cascade job recomputes nutrition for referencing recipes' do
    dough = MarkdownImporter.import(
      "# Dough\n\nServes: 2\n\n## Mix\n\n- Flour, 60 g\n\nMix.", kitchen: @kitchen, category: @category
    )
    pizza_md = "# Pizza\n\nServes: 4\n\n" \
               "## Make dough.\n>>> @[Dough]\n\n## Build\n\n- Cheese, 1 oz\n\nBuild."
    pizza = MarkdownImporter.import(pizza_md, kitchen: @kitchen, category: @category)

    CascadeNutritionJob.perform_now(dough)
    pizza.reload

    assert_predicate pizza.nutrition_data, :present?
    assert_predicate pizza.nutrition_data['totals']['calories'], :positive?
  end

  test 'records skipped ingredients for unquantified items' do
    markdown = "# Salad\n\n\n## Toss\n\n- Flour, 30 g\n- Pepper\n\nToss."
    recipe = import_without_nutrition(markdown)

    RecipeNutritionJob.perform_now(recipe)
    recipe.reload

    assert_includes recipe.nutrition_data['skipped_ingredients'], 'Pepper'
    assert_not_includes recipe.nutrition_data['missing_ingredients'], 'Pepper'
  end

  test 'MarkdownImporter enqueues CascadeNutritionJob' do
    assert_enqueued_with(job: CascadeNutritionJob) do
      MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
        # Cascade Test

        ## Step (do it)

        - Flour, 1 cup

        Mix.
      MD
    end
  end

  test 'stores total_weight_grams in nutrition_data' do
    markdown = "# Bread\n\nServes: 2\n\n## Mix\n\n- Flour, 60 g\n\nMix."
    recipe = import_without_nutrition(markdown)

    RecipeNutritionJob.perform_now(recipe)
    recipe.reload

    assert_in_delta 60.0, recipe.nutrition_data['total_weight_grams'], 0.1
  end

  private

  def import_without_nutrition(markdown)
    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @category)
    recipe.update_column(:nutrition_data, nil) # rubocop:disable Rails/SkipsModelValidations
    recipe
  end
end
