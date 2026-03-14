# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class CategoryWriteServiceTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    setup_test_kitchen
    Category.destroy_all
    @bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    @dessert = Category.create!(name: 'Dessert', slug: 'dessert', position: 1, kitchen: @kitchen)
  end

  # --- validation ---

  test 'update_order returns errors for too many categories' do
    names = (1..51).map { |i| "Cat #{i}" }

    result = CategoryWriteService.update_order(kitchen: @kitchen, names:, renames: {}, deletes: [])

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('Too many') })
  end

  test 'update_order returns errors for name too long' do
    result = CategoryWriteService.update_order(
      kitchen: @kitchen, names: ['a' * 51], renames: {}, deletes: []
    )

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('too long') })
  end

  test 'update_order returns errors for case-insensitive duplicates' do
    result = CategoryWriteService.update_order(
      kitchen: @kitchen, names: %w[Bread bread Dessert], renames: {}, deletes: []
    )

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('more than once') })
  end

  # --- renames ---

  test 'update_order renames a category' do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: ['Artisan Bread', 'Dessert'],
      renames: { 'Bread' => 'Artisan Bread' }, deletes: []
    )

    @bread.reload

    assert_equal 'Artisan Bread', @bread.name
    assert_equal 'artisan-bread', @bread.slug
  end

  test 'update_order renames with case mismatch' do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: ['Artisan Bread', 'Dessert'],
      renames: { 'bread' => 'Artisan Bread' }, deletes: []
    )

    assert_equal 'Artisan Bread', @bread.reload.name
  end

  test 'update_order handles case-only rename' do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: %w[bread Dessert],
      renames: { 'Bread' => 'bread' }, deletes: []
    )

    assert_equal 'bread', @bread.reload.name
  end

  # --- rename length validation ---

  test 'rename rejects name exceeding MAX_NAME_LENGTH' do
    long_name = 'a' * (CategoryWriteService::MAX_NAME_LENGTH + 1)

    result = CategoryWriteService.update_order(
      kitchen: @kitchen, names: %w[Bread Dessert],
      renames: { 'Bread' => long_name }, deletes: []
    )

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('exceeds maximum length') })
  end

  # --- deletes ---

  test 'update_order deletes category and reassigns recipes to Miscellaneous' do
    MarkdownImporter.import("# Rolls\n\n## Mix (do it)\n\n- Flour, 1 cup\n\nMix.",
                            kitchen: @kitchen, category: @bread)

    CategoryWriteService.update_order(
      kitchen: @kitchen, names: ['Dessert'],
      renames: {}, deletes: ['Bread']
    )

    assert_nil Category.find_by(name: 'Bread')
    assert_equal 'Miscellaneous', Recipe.find_by!(slug: 'rolls').category.name
  end

  test 'update_order deletes with case mismatch' do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: ['Dessert'],
      renames: {}, deletes: ['bread']
    )

    assert_nil Category.find_by(slug: 'bread')
  end

  # --- reordering ---

  test 'update_order reorders categories by position' do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: %w[Dessert Bread],
      renames: {}, deletes: []
    )

    assert_equal 0, @dessert.reload.position
    assert_equal 1, @bread.reload.position
  end

  test 'update_order reorders with case mismatch' do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: %w[dessert bread],
      renames: {}, deletes: []
    )

    assert_equal 0, @dessert.reload.position
    assert_equal 1, @bread.reload.position
  end

  # --- broadcasts ---

  test 'update_order broadcasts to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      CategoryWriteService.update_order(
        kitchen: @kitchen, names: %w[Bread Dessert], renames: {}, deletes: []
      )
    end
  end

  test 'update_order does not broadcast on validation failure' do
    assert_no_turbo_stream_broadcasts [@kitchen, :updates] do
      CategoryWriteService.update_order(
        kitchen: @kitchen, names: (1..51).map { |i| "Cat #{i}" }, renames: {}, deletes: []
      )
    end
  end

  # --- success result ---

  test 'update_order returns success on valid input' do
    result = CategoryWriteService.update_order(
      kitchen: @kitchen, names: %w[Bread Dessert],
      renames: {}, deletes: []
    )

    assert result.success
    assert_empty result.errors
  end
end
