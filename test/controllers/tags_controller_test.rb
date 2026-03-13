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

    assert_includes body['items'], 'vegan'
    assert_includes body['items'], 'quick'
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

  test 'requires membership for update' do
    reset!
    patch tags_update_path(kitchen_slug: kitchen_slug),
          params: { renames: {}, deletes: [] },
          as: :json

    assert_response :forbidden
  end
end
