# frozen_string_literal: true

require 'test_helper'

class CrossReferenceModelTest < ActiveSupport::TestCase
  DOUGH_MD = "# Pizza Dough\n\nCategory: Bread\n\n## Mix\n\n- Flour, 2 cups\n\nMix it."
  POOLISH_MD = "# Poolish\n\nCategory: Bread\n\n## Mix\n\n- Flour, 1 cup\n\nMix it."

  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen

    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread')
    @recipe = Recipe.find_or_create_by!(
      title: 'Pizza Dough', slug: 'pizza-dough',
      category: @category, markdown_source: DOUGH_MD
    )
    @target_recipe = Recipe.find_or_create_by!(
      title: 'Poolish', slug: 'poolish',
      category: @category, markdown_source: POOLISH_MD
    )
    @step = @recipe.steps.find_or_create_by!(title: 'Mix', position: 1)
  end

  test 'belongs to step' do
    cross_ref = CrossReference.new(step: @step, target_recipe: @target_recipe, position: 1)

    assert_equal @step, cross_ref.step
  end

  test 'belongs to target_recipe' do
    cross_ref = CrossReference.new(step: @step, target_recipe: @target_recipe, position: 1)

    assert_equal @target_recipe, cross_ref.target_recipe
  end

  test 'defaults multiplier to 1.0' do
    cross_ref = CrossReference.create!(step: @step, target_recipe: @target_recipe, position: 1)

    assert_equal BigDecimal('1.0'), cross_ref.multiplier
  end

  test 'requires target_recipe' do
    cross_ref = CrossReference.new(step: @step, position: 1)

    assert_not cross_ref.valid?
    assert_includes cross_ref.errors[:target_recipe], 'must exist'
  end

  test 'requires position' do
    cross_ref = CrossReference.new(step: @step, target_recipe: @target_recipe)

    assert_not cross_ref.valid?
    assert_includes cross_ref.errors[:position], "can't be blank"
  end

  test 'enforces unique position within step' do
    CrossReference.create!(step: @step, target_recipe: @target_recipe, position: 1)
    dup = CrossReference.new(step: @step, target_recipe: @target_recipe, position: 1)

    assert_not dup.valid?
    assert_includes dup.errors[:position], 'has already been taken'
  end

  test 'stores optional prep_note' do
    cross_ref = CrossReference.create!(
      step: @step, target_recipe: @target_recipe,
      position: 1, prep_note: 'room temperature'
    )

    assert_equal 'room temperature', cross_ref.reload.prep_note
  end

  test 'stores custom multiplier' do
    cross_ref = CrossReference.create!(
      step: @step, target_recipe: @target_recipe,
      position: 1, multiplier: 2.5
    )

    assert_equal BigDecimal('2.5'), cross_ref.reload.multiplier
  end

  test 'delegates target_slug to target_recipe' do
    cross_ref = CrossReference.new(step: @step, target_recipe: @target_recipe, position: 1)

    assert_equal 'poolish', cross_ref.target_slug
  end

  test 'delegates target_title to target_recipe' do
    cross_ref = CrossReference.new(step: @step, target_recipe: @target_recipe, position: 1)

    assert_equal 'Poolish', cross_ref.target_title
  end
end

class StepIngredientListItemsTest < ActiveSupport::TestCase
  FOCACCIA_MD = "# Focaccia\n\nCategory: Bread\n\n## Mix\n\n- Flour, 2 cups\n\nMix it."
  POOLISH_MD = "# Poolish\n\nCategory: Bread\n\n## Mix\n\n- Flour, 1 cup\n\nMix it."

  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen

    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread')
    @recipe = Recipe.find_or_create_by!(
      title: 'Focaccia', slug: 'focaccia',
      category: @category, markdown_source: FOCACCIA_MD
    )
    @target = Recipe.find_or_create_by!(
      title: 'Poolish', slug: 'poolish',
      category: @category, markdown_source: POOLISH_MD
    )
    @step = @recipe.steps.find_or_create_by!(title: 'Dough', position: 1)
  end

  test 'ingredient_list_items merges ingredients and cross_references by position' do
    @step.ingredients.create!(name: 'Flour', quantity: '2', unit: 'cups', position: 1)
    @step.cross_references.create!(target_recipe: @target, multiplier: 0.5, position: 2)
    @step.ingredients.create!(name: 'Salt', position: 3)

    items = @step.ingredient_list_items

    assert_equal 3, items.size
    assert_instance_of Ingredient, items[0]
    assert_instance_of CrossReference, items[1]
    assert_instance_of Ingredient, items[2]
    assert_equal [1, 2, 3], items.map(&:position)
  end

  test 'ingredient_list_items returns empty array when step has no items' do
    assert_empty @step.ingredient_list_items
  end

  test 'ingredient_list_items works with only ingredients' do
    @step.ingredients.create!(name: 'Flour', position: 1)
    @step.ingredients.create!(name: 'Water', position: 2)

    items = @step.ingredient_list_items

    assert_equal 2, items.size
    assert(items.all? { |item| item.is_a?(Ingredient) })
  end

  test 'ingredient_list_items works with only cross_references' do
    @step.cross_references.create!(target_recipe: @target, position: 1)

    items = @step.ingredient_list_items

    assert_equal 1, items.size
    assert_instance_of CrossReference, items.first
  end
end
