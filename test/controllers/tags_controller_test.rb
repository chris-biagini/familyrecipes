# frozen_string_literal: true

require 'test_helper'

class TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    log_in
    @vegan = Tag.create!(name: 'vegan', kitchen: @kitchen)
    @quick = Tag.create!(name: 'quick', kitchen: @kitchen)
  end

  test 'tags_content returns tag names as JSON' do
    get tags_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    body = response.parsed_body

    names = body['items'].pluck('name')

    assert_includes names, 'vegan'
    assert_includes names, 'quick'
  end

  test 'update_tags renames and deletes' do
    patch tags_update_path(kitchen_slug: kitchen_slug),
          params: { renames: { 'vegan' => 'plant-based' }, deletes: ['quick'] },
          as: :json

    assert_response :success
    assert_equal 'plant-based', @vegan.reload.name
    assert_not Tag.exists?(@quick.id)
  end

  test 'update_tags returns errors on duplicate rename' do
    patch tags_update_path(kitchen_slug: kitchen_slug),
          params: { renames: { 'vegan' => 'quick' }, deletes: [] },
          as: :json

    assert_response :unprocessable_entity
    body = response.parsed_body

    assert_predicate body['errors'], :any?
  end

  test 'update_tags rejects rename with overly long name' do
    long_name = 'a' * 51

    patch tags_update_path(kitchen_slug: kitchen_slug),
          params: { renames: { 'vegan' => long_name }, deletes: [] },
          as: :json

    assert_response :bad_request
  end

  test 'requires membership for update' do
    reset!
    patch tags_update_path(kitchen_slug: kitchen_slug),
          params: { renames: {}, deletes: [] },
          as: :json

    assert_response :forbidden
  end

  test 'requires membership for content' do
    reset!
    get tags_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end
end
