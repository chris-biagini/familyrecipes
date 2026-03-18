# frozen_string_literal: true

require 'test_helper'

class SmartTagsDisplayTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'recipe page renders smart tag classes when enabled' do
    result = RecipeWriteService.create(kitchen: @kitchen, markdown: "# Test\n\nStep 1", tags: ['vegetarian'])

    get recipe_path(result.recipe.slug, kitchen_slug:)

    assert_select 'button.tag-pill--green' do
      assert_select '.smart-icon', text: '🌿'
    end
  end

  test 'recipe page renders neutral pills when decorations disabled' do
    @kitchen.update!(decorate_tags: false)
    result = RecipeWriteService.create(kitchen: @kitchen, markdown: "# Test\n\nStep 1", tags: ['vegetarian'])

    get recipe_path(result.recipe.slug, kitchen_slug:)

    assert_select 'button.tag-pill--green', count: 0
    assert_select 'button.tag-pill--tag', text: 'vegetarian'
  end
end
