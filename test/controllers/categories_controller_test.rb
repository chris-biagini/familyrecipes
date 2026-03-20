# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    create_kitchen_and_user
    @bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    @dessert = Category.create!(name: 'Dessert', slug: 'dessert', position: 1, kitchen: @kitchen)
    @kitchen.recipes.create!(title: 'Bagels', slug: 'bagels', category: @bread)
    @kitchen.recipes.create!(title: 'Cake', slug: 'cake', category: @dessert)
  end

  test 'order_content returns turbo frame with category rows' do
    get categories_order_content_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'turbo-frame#category-order-frame'
    assert_select "[data-ordered-list-editor-target='list']"
    assert_select '.aisle-row[data-name="Bread"]'
    assert_select '.aisle-row[data-name="Dessert"]'
  end

  test 'order_content frame preserves position order' do
    get categories_order_content_path(kitchen_slug: kitchen_slug)

    rows = css_select('.aisle-row')

    assert_equal 'Bread', rows[0]['data-name']
    assert_equal 'Dessert', rows[1]['data-name']
  end

  test 'order_content returns categories as JSON' do
    log_in
    get categories_order_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    body = response.parsed_body

    assert_equal 2, body['categories'].size
    assert_equal 'Bread', body['categories'][0]['name']
  end

  test 'update_order renames a category' do
    log_in
    patch categories_order_path(kitchen_slug: kitchen_slug),
          params: {
            category_order: ['Artisan Bread', 'Dessert'],
            renames: { 'Bread' => 'Artisan Bread' }, deletes: []
          },
          as: :json

    assert_response :success
    @bread.reload

    assert_equal 'Artisan Bread', @bread.name
    assert_equal 'artisan-bread', @bread.slug
  end

  test 'update_order deletes a category and reassigns recipes to Miscellaneous' do
    MarkdownImporter.import("# Rolls\n\n## Mix (do it)\n\n- Flour, 1 cup\n\nMix.",
                            kitchen: @kitchen, category: @bread)

    log_in
    patch categories_order_path(kitchen_slug: kitchen_slug),
          params: { category_order: ['Dessert'], renames: {}, deletes: ['Bread'] },
          as: :json

    assert_response :success
    assert_nil Category.find_by(name: 'Bread')
    assert_equal 'Miscellaneous', Recipe.find_by!(slug: 'rolls').category.name
  end

  test 'update_order reorders categories' do
    log_in
    patch categories_order_path(kitchen_slug: kitchen_slug),
          params: { category_order: %w[Dessert Bread], renames: {}, deletes: [] },
          as: :json

    assert_response :success
    assert_equal 0, Category.find_by!(name: 'Dessert').position
    assert_equal 1, Category.find_by!(name: 'Bread').position
  end

  test 'update_order renames with case mismatch' do
    log_in
    patch categories_order_path(kitchen_slug: kitchen_slug),
          params: {
            category_order: ['Artisan Bread', 'Dessert'],
            renames: { 'bread' => 'Artisan Bread' }, deletes: []
          },
          as: :json

    assert_response :success
    @bread.reload

    assert_equal 'Artisan Bread', @bread.name
    assert_equal 'artisan-bread', @bread.slug
  end

  test 'update_order handles case-only rename' do
    log_in
    patch categories_order_path(kitchen_slug: kitchen_slug),
          params: {
            category_order: %w[bread Dessert],
            renames: { 'Bread' => 'bread' }, deletes: []
          },
          as: :json

    assert_response :success
    @bread.reload

    assert_equal 'bread', @bread.name
  end

  test 'update_order deletes with case mismatch' do
    log_in
    patch categories_order_path(kitchen_slug: kitchen_slug),
          params: { category_order: ['Dessert'], renames: {}, deletes: ['bread'] },
          as: :json

    assert_response :success
    assert_nil Category.find_by(slug: 'bread')
  end

  test 'update_order reorders with case mismatch' do
    log_in
    patch categories_order_path(kitchen_slug: kitchen_slug),
          params: { category_order: %w[dessert bread], renames: {}, deletes: [] },
          as: :json

    assert_response :success
    assert_equal 0, @dessert.reload.position
    assert_equal 1, @bread.reload.position
  end

  test 'update_order rejects case-insensitive duplicate names' do
    log_in
    patch categories_order_path(kitchen_slug: kitchen_slug),
          params: { category_order: %w[Bread bread Dessert], renames: {}, deletes: [] },
          as: :json

    assert_response :unprocessable_entity
    assert(response.parsed_body['errors'].any? { |e| e.include?('more than once') })
  end

  test 'update_order requires membership' do
    patch categories_order_path(kitchen_slug: kitchen_slug),
          params: { category_order: [], renames: {}, deletes: [] },
          as: :json

    assert_response :forbidden
  end

  test 'update_order broadcasts to kitchen updates stream' do
    log_in

    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      patch categories_order_path(kitchen_slug: kitchen_slug),
            params: { category_order: %w[Bread Dessert], renames: {}, deletes: [] },
            as: :json
    end
  end
end
