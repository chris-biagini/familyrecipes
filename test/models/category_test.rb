# frozen_string_literal: true

require 'test_helper'

class CategoryTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
  end

  # --- validations ---

  test 'requires name' do
    category = Category.new(slug: 'test')

    assert_not category.valid?
    assert_includes category.errors[:name], "can't be blank"
  end

  test 'requires slug' do
    category = Category.new(name: 'Test')
    category.slug = nil # prevent before_validation from filling it

    # Manually skip the callback to test the validation directly
    category.define_singleton_method(:generate_slug) { nil }
    category.valid?

    assert_includes category.errors[:slug], "can't be blank"
  end

  test 'enforces unique name within kitchen' do
    Category.create!(name: 'Bread', slug: 'bread')
    dup = Category.new(name: 'Bread', slug: 'bread-2')

    assert_not dup.valid?
    assert_includes dup.errors[:name], 'has already been taken'
  end

  test 'enforces unique slug within kitchen' do
    Category.create!(name: 'Bread', slug: 'bread')
    dup = Category.new(name: 'Different', slug: 'bread')

    assert_not dup.valid?
    assert_includes dup.errors[:slug], 'has already been taken'
  end

  test 'allows same name in different kitchens' do
    Category.create!(name: 'Bread', slug: 'bread')

    other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    ActsAsTenant.current_tenant = other_kitchen
    other_category = Category.new(name: 'Bread', slug: 'bread')

    assert_predicate other_category, :valid?
  end

  # --- slug generation ---

  test 'generates slug from name when slug is blank' do
    category = Category.create!(name: 'Bread')

    assert_equal 'bread', category.slug
  end

  test 'does not overwrite existing slug' do
    category = Category.create!(name: 'Bread', slug: 'custom-slug')

    assert_equal 'custom-slug', category.slug
  end

  test 'generates slug with hyphens for spaces' do
    category = Category.create!(name: 'Main Dishes')

    assert_equal 'main-dishes', category.slug
  end

  test 'generates slug stripping accented characters' do
    category = Category.create!(name: 'Cafe Entrees')

    assert_equal 'cafe-entrees', category.slug
  end

  # --- ordered scope ---

  test 'ordered scope sorts by position then name' do
    Category.create!(name: 'Desserts', position: 2)
    Category.create!(name: 'Appetizers', position: 1)
    Category.create!(name: 'Bread', position: 1)

    names = Category.ordered.pluck(:name)

    assert_equal %w[Appetizers Bread Desserts], names
  end
end
