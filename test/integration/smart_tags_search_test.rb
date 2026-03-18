# frozen_string_literal: true

require 'test_helper'

class SmartTagsSearchTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'layout embeds smart tags JSON when enabled' do
    RecipeWriteService.create(kitchen: @kitchen, markdown: "# Test\n\nStep 1")

    get kitchen_root_path(kitchen_slug:)

    assert_select 'script[data-smart-tags]'
  end

  test 'layout omits smart tags JSON when disabled' do
    @kitchen.update!(decorate_tags: false)
    RecipeWriteService.create(kitchen: @kitchen, markdown: "# Test\n\nStep 1")

    get kitchen_root_path(kitchen_slug:)

    assert_select 'script[data-smart-tags]', count: 0
  end
end
