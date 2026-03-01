# frozen_string_literal: true

require 'test_helper'

class StepModelTest < ActiveSupport::TestCase
  BASIC_MD = "# Test\n\nCategory: Test\n\n## Step\n\n- Flour\n\nMix."

  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    @category = Category.find_or_create_by!(name: 'Test', slug: 'test')
    @recipe = Recipe.find_or_create_by!(
      title: 'Test Recipe', slug: 'step-test-recipe',
      category: @category, markdown_source: BASIC_MD
    )
  end

  # --- validations ---

  test 'allows nil title for implicit steps' do
    step = Step.new(recipe: @recipe, title: nil, position: 1)

    assert_predicate step, :valid?
  end

  test 'rejects blank title' do
    step = Step.new(recipe: @recipe, title: '', position: 1)

    assert_not step.valid?
  end

  test 'requires position' do
    step = Step.new(recipe: @recipe, title: 'Mix')

    assert_not step.valid?
    assert_includes step.errors[:position], "can't be blank"
  end

  test 'valid with title and position' do
    step = Step.new(recipe: @recipe, title: 'Mix', position: 1)

    assert_predicate step, :valid?
  end

  # --- associations ---

  test 'ingredients are ordered by position' do
    step = Step.create!(recipe: @recipe, title: 'Mix', position: 1)
    step.ingredients.create!(name: 'Salt', position: 2)
    step.ingredients.create!(name: 'Flour', position: 1)

    assert_equal %w[Flour Salt], step.ingredients.pluck(:name)
  end

  test 'cross_references are ordered by position' do
    step = Step.create!(recipe: @recipe, title: 'Mix', position: 1)
    target_a = Recipe.create!(title: 'Alpha', category: @category, markdown_source: BASIC_MD)
    target_b = Recipe.create!(title: 'Beta', category: @category, markdown_source: BASIC_MD)
    step.cross_references.create!(target_recipe: target_b, target_slug: 'beta', target_title: 'Beta', position: 2)
    step.cross_references.create!(target_recipe: target_a, target_slug: 'alpha', target_title: 'Alpha', position: 1)

    assert_equal [target_a.id, target_b.id], step.cross_references.pluck(:target_recipe_id)
  end

  test 'destroying step destroys associated ingredients' do
    step = Step.create!(recipe: @recipe, title: 'Mix', position: 1)
    step.ingredients.create!(name: 'Flour', position: 1)

    assert_difference 'Ingredient.count', -1 do
      step.destroy
    end
  end

  test 'destroying step destroys associated cross_references' do
    step = Step.create!(recipe: @recipe, title: 'Mix', position: 1)
    target = Recipe.create!(title: 'Poolish', category: @category, markdown_source: BASIC_MD)
    step.cross_references.create!(target_recipe: target, target_slug: 'poolish', target_title: 'Poolish', position: 1)

    assert_difference 'CrossReference.count', -1 do
      step.destroy
    end
  end

  # --- processed_instructions ---

  test 'stores processed_instructions' do
    step = Step.create!(
      recipe: @recipe, title: 'Mix', position: 1,
      instructions: 'Combine everything.',
      processed_instructions: 'Combine <span class="scalable">everything</span>.'
    )

    assert_equal 'Combine <span class="scalable">everything</span>.', step.reload.processed_instructions
  end
end
