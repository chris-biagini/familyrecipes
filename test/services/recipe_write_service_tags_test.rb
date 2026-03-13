# frozen_string_literal: true

require 'test_helper'

class RecipeWriteServiceTagsTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    Recipe.destroy_all
    Category.destroy_all
    Tag.destroy_all
  end

  MARKDOWN = <<~MD
    # Focaccia

    A simple flatbread.

    Serves: 8

    ## Make the dough (combine ingredients)

    - Flour, 3 cups
    - Salt, 1 tsp

    Mix everything together.
  MD

  test 'create with tags creates tag records and associations' do
    result = RecipeWriteService.create(
      markdown: MARKDOWN, kitchen: @kitchen, category_name: 'Bread',
      tags: %w[italian bread]
    )

    assert_equal %w[bread italian], result.recipe.tags.map(&:name).sort
    assert_equal 2, Tag.count
  end

  test 'create without tags works as before' do
    result = RecipeWriteService.create(
      markdown: MARKDOWN, kitchen: @kitchen, category_name: 'Bread'
    )

    assert_empty result.recipe.tags
  end

  test 'create finds existing tags instead of duplicating' do
    @kitchen.tags.create!(name: 'italian')

    result = RecipeWriteService.create(
      markdown: MARKDOWN, kitchen: @kitchen, category_name: 'Bread',
      tags: %w[italian bread]
    )

    assert_equal 2, Tag.count
    assert_equal %w[bread italian], result.recipe.tags.map(&:name).sort
  end

  test 'update syncs tags — adds new, removes absent' do
    RecipeWriteService.create(
      markdown: MARKDOWN, kitchen: @kitchen, category_name: 'Bread',
      tags: %w[italian bread]
    )

    result = RecipeWriteService.update(
      slug: 'focaccia', markdown: MARKDOWN, kitchen: @kitchen,
      category_name: 'Bread', tags: %w[italian quick]
    )

    assert_equal %w[italian quick], result.recipe.tags.map(&:name).sort
  end

  test 'update with empty tags removes all tags' do
    RecipeWriteService.create(
      markdown: MARKDOWN, kitchen: @kitchen, category_name: 'Bread',
      tags: %w[italian bread]
    )

    result = RecipeWriteService.update(
      slug: 'focaccia', markdown: MARKDOWN, kitchen: @kitchen,
      category_name: 'Bread', tags: []
    )

    assert_empty result.recipe.tags
  end

  test 'update without tags param leaves tags unchanged' do
    RecipeWriteService.create(
      markdown: MARKDOWN, kitchen: @kitchen, category_name: 'Bread',
      tags: %w[italian bread]
    )

    result = RecipeWriteService.update(
      slug: 'focaccia', markdown: MARKDOWN, kitchen: @kitchen,
      category_name: 'Bread'
    )

    assert_equal %w[bread italian], result.recipe.tags.map(&:name).sort
  end

  test 'removing tags cleans up orphaned tag records' do
    RecipeWriteService.create(
      markdown: MARKDOWN, kitchen: @kitchen, category_name: 'Bread',
      tags: %w[italian bread]
    )

    assert_equal 2, Tag.count

    RecipeWriteService.update(
      slug: 'focaccia', markdown: MARKDOWN, kitchen: @kitchen,
      category_name: 'Bread', tags: %w[italian]
    )

    assert_equal 1, Tag.count
    assert_equal 'italian', Tag.first.name
  end

  test 'tags are downcased on save' do
    result = RecipeWriteService.create(
      markdown: MARKDOWN, kitchen: @kitchen, category_name: 'Bread',
      tags: %w[Italian BREAD]
    )

    assert_equal %w[bread italian], result.recipe.tags.map(&:name).sort
  end

  test 'destroy removes recipe_tags and orphan cleanup handles tag records' do
    RecipeWriteService.create(
      markdown: MARKDOWN, kitchen: @kitchen, category_name: 'Bread',
      tags: %w[italian bread]
    )

    assert_equal 2, Tag.count
    assert_equal 2, RecipeTag.count

    RecipeWriteService.destroy(slug: 'focaccia', kitchen: @kitchen)

    assert_equal 0, RecipeTag.count
    assert_equal 0, Tag.count
  end
end
