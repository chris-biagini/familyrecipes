# frozen_string_literal: true

require 'test_helper'

class RecipeModelTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category
  end

  # --- validations ---

  test 'requires title' do
    recipe = Recipe.new(category: @category, slug: 'test')

    assert_not recipe.valid?
    assert_includes recipe.errors[:title], "can't be blank"
  end

  test 'requires slug' do
    recipe = Recipe.new(title: 'Test', category: @category)
    recipe.define_singleton_method(:generate_slug) { nil }
    recipe.valid?

    assert_includes recipe.errors[:slug], "can't be blank"
  end

  test 'enforces unique slug within kitchen' do
    Recipe.create!(title: 'First', slug: 'test-recipe', category: @category)
    dup = Recipe.new(title: 'Second', slug: 'test-recipe', category: @category)

    assert_not dup.valid?
    assert_includes dup.errors[:slug], 'has already been taken'
  end

  test 'allows same slug in different kitchens' do
    Recipe.create!(title: 'First', slug: 'pizza', category: @category)

    other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    ActsAsTenant.current_tenant = other_kitchen
    other_category = Category.create!(name: 'Test', slug: 'test')
    other_recipe = Recipe.new(title: 'First', slug: 'pizza', category: other_category)

    assert_predicate other_recipe, :valid?
  end

  # --- slug generation ---

  test 'generates slug from title when slug is blank' do
    recipe = Recipe.create!(title: 'Pizza Dough', category: @category)

    assert_equal 'pizza-dough', recipe.slug
  end

  test 'does not overwrite existing slug' do
    recipe = Recipe.create!(title: 'Pizza Dough', slug: 'custom-slug', category: @category)

    assert_equal 'custom-slug', recipe.slug
  end

  test 'slug strips non-alphanumeric characters' do
    recipe = Recipe.create!(title: "Grandma's Best Recipe!", category: @category)

    assert_equal 'grandmas-best-recipe', recipe.slug
  end

  # --- makes ---

  test 'stores makes_quantity and makes_unit_noun' do
    recipe = Recipe.create!(
      title: 'Cookies', category: @category,
      makes_quantity: 30, makes_unit_noun: 'cookies'
    )

    assert_equal 30, recipe.makes_quantity
    assert_equal 'cookies', recipe.makes_unit_noun
  end

  # --- referencing_recipes ---

  test 'referencing_recipes returns recipes that cross-reference this one' do
    target = Recipe.create!(title: 'Poolish', category: @category)
    referrer = Recipe.create!(title: 'Focaccia', slug: 'focaccia', category: @category)
    step = referrer.steps.create!(title: 'Mix', position: 1)
    CrossReference.create!(step: step, target_recipe: target, target_slug: 'poolish', target_title: 'Poolish',
                           position: 1)

    assert_includes target.referencing_recipes, referrer
  end

  test 'referencing_recipes returns empty when no references exist' do
    recipe = Recipe.create!(title: 'Solo Recipe', category: @category)

    assert_empty recipe.referencing_recipes
  end

  test 'referencing_recipes deduplicates when multiple steps reference same recipe' do
    target = Recipe.create!(title: 'Poolish', category: @category)
    referrer = Recipe.create!(title: 'Focaccia', slug: 'focaccia', category: @category)
    step1 = referrer.steps.create!(title: 'Mix', position: 1)
    step2 = referrer.steps.create!(title: 'Shape', position: 2)
    CrossReference.create!(step: step1, target_recipe: target, target_slug: 'poolish', target_title: 'Poolish',
                           position: 1)
    CrossReference.create!(step: step2, target_recipe: target, target_slug: 'poolish', target_title: 'Poolish',
                           position: 1)

    assert_equal 1, target.referencing_recipes.size
    assert_includes target.referencing_recipes, referrer
  end

  # --- alphabetical scope ---

  test 'alphabetical scope orders by title' do
    Recipe.create!(title: 'Zucchini Bread', category: @category)
    Recipe.create!(title: 'Apple Pie', category: @category)
    Recipe.create!(title: 'Muffins', category: @category)

    titles = Recipe.alphabetical.pluck(:title)

    assert_equal ['Apple Pie', 'Muffins', 'Zucchini Bread'], titles
  end

  # --- associations ---

  test 'steps are ordered by position' do
    recipe = Recipe.create!(title: 'Test', category: @category)
    recipe.steps.create!(title: 'Second', position: 2)
    recipe.steps.create!(title: 'First', position: 1)

    assert_equal %w[First Second], recipe.steps.pluck(:title)
  end

  test 'destroying recipe destroys associated steps' do
    recipe = Recipe.create!(title: 'Test', category: @category)
    recipe.steps.create!(title: 'Step One', position: 1)

    assert_difference 'Step.count', -1 do
      recipe.destroy
    end
  end

  # --- with_full_tree scope ---

  test 'with_full_tree eager loads steps, ingredients, and cross references' do
    recipe = MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category).recipe
      # Poolish

      ## Mix (combine)

      - Flour, 1 cup

      Mix.
    MD

    loaded = Recipe.with_full_tree.find(recipe.id)

    assert_predicate loaded.association(:steps), :loaded?
    assert_predicate loaded.steps.first.association(:ingredients), :loaded?
    assert_predicate loaded.steps.first.association(:cross_references), :loaded?
  end
end
