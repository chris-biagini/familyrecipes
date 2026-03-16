# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class TagWriteServiceTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    setup_test_kitchen
    setup_test_category
    Tag.destroy_all
    @vegan = Tag.create!(name: 'vegan', kitchen: @kitchen)
    @quick = Tag.create!(name: 'quick', kitchen: @kitchen)
    recipe = @kitchen.recipes.create!(title: 'Salad', slug: 'salad', category: @category)
    RecipeTag.create!(recipe:, tag: @vegan)
    RecipeTag.create!(recipe:, tag: @quick)
  end

  test 'rename updates tag name' do
    TagWriteService.update(kitchen: @kitchen, renames: { 'vegan' => 'plant-based' }, deletes: [])

    assert_equal 'plant-based', @vegan.reload.name
  end

  test 'rename rejects duplicate name' do
    result = TagWriteService.update(kitchen: @kitchen, renames: { 'vegan' => 'Quick' }, deletes: [])

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('already exists') })
  end

  test 'delete removes tag and associations' do
    TagWriteService.update(kitchen: @kitchen, renames: {}, deletes: ['vegan'])

    assert_nil Tag.find_by(name: 'vegan')
    assert_equal 0, RecipeTag.where(tag_id: @vegan.id).count
  end

  test 'rename and delete in same changeset' do
    TagWriteService.update(kitchen: @kitchen, renames: { 'vegan' => 'plant-based' }, deletes: ['quick'])

    assert_equal 'plant-based', @vegan.reload.name
    assert_nil Tag.find_by(name: 'quick')
  end

  test 'empty changeset succeeds' do
    result = TagWriteService.update(kitchen: @kitchen, renames: {}, deletes: [])

    assert result.success
    assert_empty result.errors
  end

  test 'rename downcases new name' do
    TagWriteService.update(kitchen: @kitchen, renames: { 'vegan' => 'PLANT-BASED' }, deletes: [])

    assert_equal 'plant-based', @vegan.reload.name
  end
end
