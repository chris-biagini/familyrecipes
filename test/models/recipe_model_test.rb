# frozen_string_literal: true

require 'test_helper'

class RecipeModelTest < ActiveSupport::TestCase
  BASIC_MD = "# Test Recipe\n\nCategory: Test\n\n## Step\n\n- Flour\n\nMix."

  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    @category = Category.find_or_create_by!(name: 'Test', slug: 'test')
  end

  # --- validations ---

  test 'requires title' do
    recipe = Recipe.new(category: @category, slug: 'test', markdown_source: BASIC_MD)

    assert_not recipe.valid?
    assert_includes recipe.errors[:title], "can't be blank"
  end

  test 'requires slug' do
    recipe = Recipe.new(title: 'Test', category: @category, markdown_source: BASIC_MD)
    recipe.define_singleton_method(:generate_slug) { nil }
    recipe.valid?

    assert_includes recipe.errors[:slug], "can't be blank"
  end

  test 'requires markdown_source' do
    recipe = Recipe.new(title: 'Test', slug: 'test', category: @category)

    assert_not recipe.valid?
    assert_includes recipe.errors[:markdown_source], "can't be blank"
  end

  test 'enforces unique slug within kitchen' do
    Recipe.create!(title: 'First', slug: 'test-recipe', category: @category, markdown_source: BASIC_MD)
    dup = Recipe.new(title: 'Second', slug: 'test-recipe', category: @category, markdown_source: BASIC_MD)

    assert_not dup.valid?
    assert_includes dup.errors[:slug], 'has already been taken'
  end

  test 'allows same slug in different kitchens' do
    Recipe.create!(title: 'First', slug: 'pizza', category: @category, markdown_source: BASIC_MD)

    other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    ActsAsTenant.current_tenant = other_kitchen
    other_category = Category.create!(name: 'Test', slug: 'test')
    other_recipe = Recipe.new(title: 'First', slug: 'pizza', category: other_category, markdown_source: BASIC_MD)

    assert_predicate other_recipe, :valid?
  end

  # --- slug generation ---

  test 'generates slug from title when slug is blank' do
    recipe = Recipe.create!(title: 'Pizza Dough', category: @category, markdown_source: BASIC_MD)

    assert_equal 'pizza-dough', recipe.slug
  end

  test 'does not overwrite existing slug' do
    recipe = Recipe.create!(title: 'Pizza Dough', slug: 'custom-slug', category: @category, markdown_source: BASIC_MD)

    assert_equal 'custom-slug', recipe.slug
  end

  test 'slug strips non-alphanumeric characters' do
    recipe = Recipe.create!(title: "Grandma's Best Recipe!", category: @category, markdown_source: BASIC_MD)

    assert_equal 'grandmas-best-recipe', recipe.slug
  end

  # --- makes ---

  test 'makes returns formatted string with integer quantity' do
    recipe = Recipe.create!(
      title: 'Cookies', category: @category, markdown_source: BASIC_MD,
      makes_quantity: 30, makes_unit_noun: 'cookies'
    )

    assert_equal '30 cookies', recipe.makes
  end

  test 'makes returns formatted string with decimal quantity' do
    recipe = Recipe.create!(
      title: 'Dough', category: @category, markdown_source: BASIC_MD,
      makes_quantity: 1.5, makes_unit_noun: 'loaves'
    )

    assert_equal '1.5 loaves', recipe.makes
  end

  test 'makes returns nil when makes_quantity is nil' do
    recipe = Recipe.create!(title: 'Stew', category: @category, markdown_source: BASIC_MD)

    assert_nil recipe.makes
  end

  test 'makes formats whole numbers without decimal point' do
    recipe = Recipe.new(makes_quantity: 12.0, makes_unit_noun: 'rolls')

    assert_equal '12 rolls', recipe.makes
  end

  # --- referencing_recipes ---

  test 'referencing_recipes returns recipes that cross-reference this one' do
    target = Recipe.create!(title: 'Poolish', category: @category, markdown_source: BASIC_MD)
    referrer = Recipe.create!(title: 'Focaccia', slug: 'focaccia', category: @category, markdown_source: BASIC_MD)
    step = referrer.steps.create!(title: 'Mix', position: 1)
    CrossReference.create!(step: step, target_recipe: target, position: 1)

    assert_includes target.referencing_recipes, referrer
  end

  test 'referencing_recipes returns empty when no references exist' do
    recipe = Recipe.create!(title: 'Solo Recipe', category: @category, markdown_source: BASIC_MD)

    assert_empty recipe.referencing_recipes
  end

  test 'referencing_recipes deduplicates when multiple steps reference same recipe' do
    target = Recipe.create!(title: 'Poolish', category: @category, markdown_source: BASIC_MD)
    referrer = Recipe.create!(title: 'Focaccia', slug: 'focaccia', category: @category, markdown_source: BASIC_MD)
    step1 = referrer.steps.create!(title: 'Mix', position: 1)
    step2 = referrer.steps.create!(title: 'Shape', position: 2)
    CrossReference.create!(step: step1, target_recipe: target, position: 1)
    CrossReference.create!(step: step2, target_recipe: target, position: 1)

    assert_equal 1, target.referencing_recipes.size
    assert_includes target.referencing_recipes, referrer
  end

  # --- alphabetical scope ---

  test 'alphabetical scope orders by title' do
    Recipe.create!(title: 'Zucchini Bread', category: @category, markdown_source: BASIC_MD)
    Recipe.create!(title: 'Apple Pie', category: @category, markdown_source: BASIC_MD)
    Recipe.create!(title: 'Muffins', category: @category, markdown_source: BASIC_MD)

    titles = Recipe.alphabetical.pluck(:title)

    assert_equal ['Apple Pie', 'Muffins', 'Zucchini Bread'], titles
  end

  # --- associations ---

  test 'steps are ordered by position' do
    recipe = Recipe.create!(title: 'Test', category: @category, markdown_source: BASIC_MD)
    recipe.steps.create!(title: 'Second', position: 2)
    recipe.steps.create!(title: 'First', position: 1)

    assert_equal %w[First Second], recipe.steps.pluck(:title)
  end

  test 'destroying recipe destroys associated steps' do
    recipe = Recipe.create!(title: 'Test', category: @category, markdown_source: BASIC_MD)
    recipe.steps.create!(title: 'Step One', position: 1)

    assert_difference 'Step.count', -1 do
      recipe.destroy
    end
  end
end
