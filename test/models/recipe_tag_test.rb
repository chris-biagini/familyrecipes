# frozen_string_literal: true

require 'test_helper'

class RecipeTagTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category
    @recipe = Recipe.create!(title: 'Test', slug: 'test', category: @category)
    @tag = Tag.create!(name: 'dinner')
  end

  test 'valid with recipe and tag' do
    recipe_tag = RecipeTag.new(recipe: @recipe, tag: @tag)

    assert_predicate recipe_tag, :valid?
  end

  test 'prevents duplicate recipe-tag pairs' do
    RecipeTag.create!(recipe: @recipe, tag: @tag)
    dup = RecipeTag.new(recipe: @recipe, tag: @tag)

    assert_not dup.valid?
    assert_includes dup.errors[:tag_id], 'has already been taken'
  end
end
