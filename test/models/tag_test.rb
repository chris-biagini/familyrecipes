# frozen_string_literal: true

require 'test_helper'

class TagTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
  end

  # --- validations ---

  test 'valid with letters-only name' do
    tag = Tag.new(name: 'dinner')

    assert_predicate tag, :valid?
  end

  test 'valid with hyphenated name' do
    tag = Tag.new(name: 'kid-friendly')

    assert_predicate tag, :valid?
  end

  test 'downcases name on save' do
    tag = Tag.create!(name: 'Weeknight')

    assert_equal 'weeknight', tag.name
  end

  test 'rejects names with spaces' do
    tag = Tag.new(name: 'week night')

    assert_not tag.valid?
    assert_includes tag.errors[:name], 'only allows letters and hyphens'
  end

  test 'rejects names with numbers' do
    tag = Tag.new(name: 'dinner2')

    assert_not tag.valid?
    assert_includes tag.errors[:name], 'only allows letters and hyphens'
  end

  test 'rejects names with underscores' do
    tag = Tag.new(name: 'kid_friendly')

    assert_not tag.valid?
    assert_includes tag.errors[:name], 'only allows letters and hyphens'
  end

  test 'rejects blank name' do
    tag = Tag.new(name: '')

    assert_not tag.valid?
    assert_includes tag.errors[:name], "can't be blank"
  end

  test 'enforces kitchen-scoped uniqueness' do
    Tag.create!(name: 'dinner')
    dup = Tag.new(name: 'dinner')

    assert_not dup.valid?
    assert_includes dup.errors[:name], 'has already been taken'
  end

  test 'enforces case-insensitive uniqueness' do
    Tag.create!(name: 'dinner')
    dup = Tag.new(name: 'Dinner')

    assert_not dup.valid?
    assert_includes dup.errors[:name], 'has already been taken'
  end

  test 'allows same name in different kitchens' do
    Tag.create!(name: 'dinner')

    other_kitchen = nil
    with_multi_kitchen do
      other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    end
    ActsAsTenant.current_tenant = other_kitchen
    other_tag = Tag.new(name: 'dinner')

    assert_predicate other_tag, :valid?
  end

  # --- cleanup_orphans ---

  test 'cleanup_orphans removes tags with no recipes' do
    setup_test_category
    orphan = Tag.create!(name: 'unused')
    kept = Tag.create!(name: 'used')
    recipe = Recipe.create!(title: 'Test', slug: 'test', category: @category)
    RecipeTag.create!(recipe: recipe, tag: kept)

    Tag.cleanup_orphans(@kitchen)

    assert_not Tag.exists?(orphan.id)
    assert Tag.exists?(kept.id)
  end

  # --- dependent destroy ---

  test 'destroying tag cascades to recipe_tags' do
    setup_test_category
    tag = Tag.create!(name: 'dinner')
    recipe = Recipe.create!(title: 'Test', slug: 'test', category: @category)
    RecipeTag.create!(recipe: recipe, tag: tag)

    assert_difference 'RecipeTag.count', -1 do
      tag.destroy!
    end
  end
end
