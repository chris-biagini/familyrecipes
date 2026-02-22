# frozen_string_literal: true

require 'test_helper'

class RecipeDependencyTest < ActiveSupport::TestCase
  DOUGH_MD = "# Pizza Dough\n\nCategory: Bread\n\n## Mix\n\n- Flour, 2 cups\n\nMix it."
  PIZZA_MD = "# Pizza\n\nCategory: Main\n\n## Assemble\n\n- Cheese, 8 oz\n\nBuild it."

  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen

    @bread_cat = Category.find_or_create_by!(name: 'Bread', slug: 'bread')
    @main_cat = Category.find_or_create_by!(name: 'Main', slug: 'main')
    @dough = Recipe.find_or_create_by!(
      title: 'Pizza Dough', slug: 'pizza-dough',
      category: @bread_cat, markdown_source: DOUGH_MD
    )
    @pizza = Recipe.find_or_create_by!(
      title: 'Pizza', slug: 'pizza',
      category: @main_cat, markdown_source: PIZZA_MD
    )
  end

  test 'auto-assigns kitchen_id via acts_as_tenant' do
    dep = RecipeDependency.create!(source_recipe: @pizza, target_recipe: @dough)

    assert_equal @kitchen.id, dep.kitchen_id
  end

  test 'enforces uniqueness scoped to kitchen and source_recipe' do
    RecipeDependency.create!(source_recipe: @pizza, target_recipe: @dough)
    dup = RecipeDependency.new(source_recipe: @pizza, target_recipe: @dough)

    assert_not dup.valid?
    assert_includes dup.errors[:target_recipe_id], 'has already been taken'
  end

  test 'kitchen has_many recipe_dependencies' do
    RecipeDependency.create!(source_recipe: @pizza, target_recipe: @dough)

    assert_equal 1, @kitchen.recipe_dependencies.count
  end
end

class RecipeNutritionDataTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread')
  end

  test 'stores and retrieves nutrition_data as JSON' do
    nutrition = { 'calories' => 250, 'fat' => 10.5, 'protein' => 8 }
    recipe = Recipe.create!(
      title: 'Test Bread', slug: 'test-bread',
      category: @category, markdown_source: "# Test Bread\n\nCategory: Bread\n\n## Mix\n\n- Flour\n\nMix.",
      nutrition_data: nutrition
    )

    recipe.reload

    assert_equal 250, recipe.nutrition_data['calories']
    assert_in_delta 10.5, recipe.nutrition_data['fat']
    assert_equal 8, recipe.nutrition_data['protein']
  end

  test 'nutrition_data defaults to nil' do
    recipe = Recipe.create!(
      title: 'Plain Bread', slug: 'plain-bread',
      category: @category, markdown_source: "# Plain Bread\n\nCategory: Bread\n\n## Mix\n\n- Flour\n\nMix."
    )

    assert_nil recipe.nutrition_data
  end
end

class StepProcessedInstructionsTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread')
    @recipe = Recipe.find_or_create_by!(
      title: 'Focaccia', slug: 'focaccia',
      category: @category, markdown_source: "# Focaccia\n\nCategory: Bread\n\n## Mix\n\n- Flour\n\nMix."
    )
  end

  test 'stores and retrieves processed_instructions' do
    step = @recipe.steps.create!(
      title: 'Mix', position: 0,
      instructions: 'Add 2 cups of flour.',
      processed_instructions: 'Add <span class="scalable">2</span> cups of flour.'
    )

    step.reload

    assert_equal 'Add <span class="scalable">2</span> cups of flour.', step.processed_instructions
  end

  test 'processed_instructions defaults to nil' do
    step = @recipe.steps.create!(title: 'Mix', position: 0, instructions: 'Mix it.')

    assert_nil step.processed_instructions
  end
end
