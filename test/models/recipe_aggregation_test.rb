# frozen_string_literal: true

require 'test_helper'

class RecipeAggregationTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category(name: 'Bread')
  end

  test 'own_ingredients_aggregated groups by name and sums quantities' do
    recipe = Recipe.find_or_create_by!(
      title: 'Focaccia', slug: 'focaccia',
      category: @category
    )
    step1 = recipe.steps.find_or_create_by!(title: 'Mix', position: 1)
    step1.ingredients.find_or_create_by!(name: 'Flour', quantity: '2', unit: 'cups', position: 1)
    step2 = recipe.steps.find_or_create_by!(title: 'Knead', position: 2)
    step2.ingredients.find_or_create_by!(name: 'Flour', quantity: '1', unit: 'cup', position: 1)
    step2.ingredients.find_or_create_by!(name: 'Salt', quantity: '1', unit: 'tsp', position: 2)

    result = recipe.own_ingredients_aggregated

    assert result.key?('Flour')
    flour_cup = result['Flour'].find { |q| q&.unit == 'cup' }

    assert_in_delta 3.0, flour_cup.value, 0.01
    assert result.key?('Salt')
  end

  test 'own_ingredients_aggregated handles unquantified ingredients' do
    recipe = Recipe.find_or_create_by!(
      title: 'Simple', slug: 'simple',
      category: @category
    )
    step = recipe.steps.find_or_create_by!(title: 'Mix', position: 1)
    step.ingredients.find_or_create_by!(name: 'Salt', position: 1)

    result = recipe.own_ingredients_aggregated

    assert result.key?('Salt')
    assert_includes result['Salt'], nil
  end

  test 'all_ingredients_with_quantities includes cross-reference ingredients' do
    target = Recipe.find_or_create_by!(
      title: 'Poolish', slug: 'poolish',
      category: @category
    )
    target_step = target.steps.find_or_create_by!(title: 'Mix', position: 1)
    target_step.ingredients.find_or_create_by!(name: 'Flour', quantity: '1', unit: 'cup', position: 1)

    recipe = Recipe.find_or_create_by!(
      title: 'Focaccia', slug: 'focaccia',
      category: @category
    )
    step = recipe.steps.find_or_create_by!(title: 'Dough', position: 1)
    step.ingredients.find_or_create_by!(name: 'Salt', quantity: '1', unit: 'tsp', position: 1)
    step.cross_references.find_or_create_by!(
      target_recipe: target, target_slug: 'poolish', target_title: 'Poolish',
      position: 2
    )

    loaded = Recipe.includes(steps: [:ingredients, { cross_references: { target_recipe: { steps: :ingredients } } }])
                   .find(recipe.id)
    result = loaded.all_ingredients_with_quantities

    names = result.map(&:first)

    assert_includes names, 'Salt'
    assert_includes names, 'Flour'
  end

  test 'all_ingredients_with_quantities merges duplicate names from own and xref' do
    target = Recipe.find_or_create_by!(
      title: 'Poolish', slug: 'poolish',
      category: @category
    )
    target_step = target.steps.find_or_create_by!(title: 'Mix', position: 1)
    target_step.ingredients.find_or_create_by!(name: 'Flour', quantity: '2', unit: 'cups', position: 1)

    recipe = Recipe.find_or_create_by!(
      title: 'Focaccia', slug: 'focaccia',
      category: @category
    )
    step = recipe.steps.find_or_create_by!(title: 'Dough', position: 1)
    step.ingredients.find_or_create_by!(name: 'Flour', quantity: '3', unit: 'cups', position: 1)
    step.cross_references.find_or_create_by!(
      target_recipe: target, target_slug: 'poolish', target_title: 'Poolish',
      position: 2
    )

    loaded = Recipe.includes(steps: [:ingredients, { cross_references: { target_recipe: { steps: :ingredients } } }])
                   .find(recipe.id)
    result = loaded.all_ingredients_with_quantities
    flour = result.find { |name, _| name == 'Flour' }
    flour_cup = flour[1].find { |q| q&.unit == 'cup' }

    assert_in_delta 5.0, flour_cup.value, 0.01
  end

  test 'all_ingredients_with_quantities skips unresolved cross-references' do
    recipe = Recipe.find_or_create_by!(
      title: 'Bread', slug: 'bread',
      category: @category
    )
    step = recipe.steps.find_or_create_by!(title: 'Mix', position: 1)
    step.ingredients.find_or_create_by!(name: 'Flour', quantity: '1', unit: 'cup', position: 1)
    step.cross_references.find_or_create_by!(
      target_slug: 'nonexistent', target_title: 'Nonexistent',
      position: 2
    )

    loaded = Recipe.includes(steps: [:ingredients, { cross_references: { target_recipe: { steps: :ingredients } } }])
                   .find(recipe.id)
    result = loaded.all_ingredients_with_quantities

    names = result.map(&:first)

    assert_equal ['Flour'], names
  end
end
