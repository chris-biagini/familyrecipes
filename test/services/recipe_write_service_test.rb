# frozen_string_literal: true

require 'test_helper'

class RecipeWriteServiceTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    Recipe.destroy_all
    Category.destroy_all
  end

  BASIC_MARKDOWN = <<~MD
    # Focaccia

    A simple flatbread.

    Category: Bread
    Serves: 8

    ## Make the dough (combine ingredients)

    - Flour, 3 cups
    - Salt, 1 tsp

    Mix everything together.
  MD

  test 'create imports recipe and returns Result' do
    result = RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

    assert_instance_of RecipeWriteService::Result, result
    assert_equal 'Focaccia', result.recipe.title
    assert_empty result.updated_references
  end

  test 'create sets edited_at' do
    result = RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

    assert_not_nil result.recipe.edited_at
  end

  test 'create cleans up orphan categories' do
    Category.create!(name: 'Empty', slug: 'empty', position: 99, kitchen: @kitchen)

    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

    assert_nil Category.find_by(slug: 'empty')
  end

  test 'create raises on invalid markdown' do
    assert_raises(RuntimeError) do
      RecipeWriteService.create(markdown: 'not a recipe at all', kitchen: @kitchen)
    end
  end
end
