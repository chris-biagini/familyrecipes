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
    cross_ref = CrossReference.new(
      step: @step, target_recipe: @target_recipe, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    assert_equal @step, cross_ref.step
  end

  test 'belongs to target_recipe' do
    cross_ref = CrossReference.new(
      step: @step, target_recipe: @target_recipe, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    assert_equal @target_recipe, cross_ref.target_recipe
  end

  test 'defaults multiplier to 1.0' do
    cross_ref = CrossReference.create!(
      step: @step, target_recipe: @target_recipe, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    assert_equal BigDecimal('1.0'), cross_ref.multiplier
  end

  test 'allows nil target_recipe (deferred resolution)' do
    cross_ref = CrossReference.new(
      step: @step, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    assert_predicate cross_ref, :valid?
  end

  test 'requires position' do
    cross_ref = CrossReference.new(
      step: @step, target_recipe: @target_recipe,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    assert_not cross_ref.valid?
    assert_includes cross_ref.errors[:position], "can't be blank"
  end

  test 'enforces unique position within step' do
    CrossReference.create!(
      step: @step, target_recipe: @target_recipe, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )
    dup = CrossReference.new(
      step: @step, target_recipe: @target_recipe, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    assert_not dup.valid?
    assert_includes dup.errors[:position], 'has already been taken'
  end

  test 'stores optional prep_note' do
    cross_ref = CrossReference.create!(
      step: @step, target_recipe: @target_recipe,
      position: 1, prep_note: 'room temperature',
      target_slug: 'poolish', target_title: 'Poolish'
    )

    assert_equal 'room temperature', cross_ref.reload.prep_note
  end

  test 'stores custom multiplier' do
    cross_ref = CrossReference.create!(
      step: @step, target_recipe: @target_recipe,
      position: 1, multiplier: 2.5,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    assert_equal BigDecimal('2.5'), cross_ref.reload.multiplier
  end

  test 'target_slug returns stored column value' do
    cross_ref = CrossReference.new(
      step: @step, target_recipe: @target_recipe, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    assert_equal 'poolish', cross_ref.target_slug
  end

  test 'target_title returns stored column value' do
    cross_ref = CrossReference.new(
      step: @step, target_recipe: @target_recipe, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    assert_equal 'Poolish', cross_ref.target_title
  end

  test 'allows nil target_recipe when target_slug and target_title are present' do
    cross_ref = CrossReference.create!(
      step: @step, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    assert_predicate cross_ref, :persisted?
    assert_nil cross_ref.target_recipe_id
  end

  test 'requires target_slug' do
    cross_ref = CrossReference.new(step: @step, position: 1, target_title: 'Poolish')

    assert_not cross_ref.valid?
    assert_includes cross_ref.errors[:target_slug], "can't be blank"
  end

  test 'requires target_title' do
    cross_ref = CrossReference.new(step: @step, position: 1, target_slug: 'poolish')

    assert_not cross_ref.valid?
    assert_includes cross_ref.errors[:target_title], "can't be blank"
  end

  test 'resolved? returns true when target_recipe is set' do
    cross_ref = CrossReference.new(
      step: @step, target_recipe: @target_recipe, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    assert_predicate cross_ref, :resolved?
  end

  test 'pending? returns true when target_recipe is nil' do
    cross_ref = CrossReference.new(
      step: @step, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    assert_predicate cross_ref, :pending?
  end

  test 'pending scope returns only unresolved references' do
    CrossReference.create!(
      step: @step, target_recipe: @target_recipe, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )
    CrossReference.create!(
      step: @step, position: 2,
      target_slug: 'nonexistent', target_title: 'Nonexistent'
    )

    assert_equal 1, CrossReference.pending.count
    assert_equal 'nonexistent', CrossReference.pending.first.target_slug
  end

  test 'resolve_pending links pending refs to matching recipes' do
    CrossReference.create!(
      step: @step, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    CrossReference.resolve_pending(kitchen: @kitchen)

    ref = CrossReference.find_by(target_slug: 'poolish')

    assert_equal @target_recipe.id, ref.target_recipe_id
  end

  test 'resolve_pending skips refs whose target does not exist' do
    CrossReference.create!(
      step: @step, position: 1,
      target_slug: 'nonexistent', target_title: 'Nonexistent'
    )

    CrossReference.resolve_pending(kitchen: @kitchen)

    ref = CrossReference.find_by(target_slug: 'nonexistent')

    assert_nil ref.target_recipe_id
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
    @step.cross_references.create!(
      target_recipe: @target, multiplier: 0.5, position: 2,
      target_slug: 'poolish', target_title: 'Poolish'
    )
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
    assert(items.all?(Ingredient))
  end

  test 'ingredient_list_items works with only cross_references' do
    @step.cross_references.create!(
      target_recipe: @target, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    items = @step.ingredient_list_items

    assert_equal 1, items.size
    assert_instance_of CrossReference, items.first
  end
end

class CrossReferenceExpandedIngredientsTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen

    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread')

    # Target recipe: Poolish with "Flour, 2 cups" and "Water, 1 cup"
    @target = Recipe.find_or_create_by!(
      title: 'Poolish', slug: 'poolish',
      category: @category,
      markdown_source: "# Poolish\n\nCategory: Bread\n\n## Mix\n\n- Flour, 2 cups\n- Water, 1 cup\n\nMix."
    )
    target_step = @target.steps.find_or_create_by!(title: 'Mix', position: 1)
    target_step.ingredients.find_or_create_by!(name: 'Flour', quantity: '2', unit: 'cups', position: 1)
    target_step.ingredients.find_or_create_by!(name: 'Water', quantity: '1', unit: 'cup', position: 2)

    # Parent recipe with a cross-reference to Poolish
    @recipe = Recipe.find_or_create_by!(
      title: 'Focaccia', slug: 'focaccia',
      category: @category, markdown_source: "# Focaccia\n\nCategory: Bread\n\n## Mix\n\n- @[Poolish]\n\nMix."
    )
    @step = @recipe.steps.find_or_create_by!(title: 'Mix', position: 1)
  end

  test 'expanded_ingredients returns target ingredients with default multiplier' do
    xref = CrossReference.create!(
      step: @step, target_recipe: @target, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    result = xref.expanded_ingredients

    assert_equal 2, result.size
    flour = result.find { |name, _| name == 'Flour' }

    assert flour, 'Expected Flour in expanded ingredients'
    assert_in_delta 2.0, flour[1].first.value, 0.01
    assert_equal 'cup', flour[1].first.unit
  end

  test 'expanded_ingredients scales by multiplier' do
    xref = CrossReference.create!(
      step: @step, target_recipe: @target, position: 1,
      target_slug: 'poolish', target_title: 'Poolish', multiplier: 0.5
    )

    result = xref.expanded_ingredients

    flour = result.find { |name, _| name == 'Flour' }

    assert_in_delta 1.0, flour[1].first.value, 0.01
  end

  test 'expanded_ingredients returns empty array when target_recipe is nil' do
    xref = CrossReference.create!(
      step: @step, position: 1,
      target_slug: 'nonexistent', target_title: 'Nonexistent'
    )

    assert_empty xref.expanded_ingredients
  end
end
