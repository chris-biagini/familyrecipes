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

  test 'update imports recipe and returns Result' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

    updated = <<~MD
      # Focaccia

      A revised flatbread.

      Category: Bread
      Serves: 12

      ## Make the dough (combine ingredients)

      - Flour, 4 cups

      Mix everything.
    MD

    result = RecipeWriteService.update(slug: 'focaccia', markdown: updated, kitchen: @kitchen)

    assert_equal 'Focaccia', result.recipe.title
    assert_equal 'A revised flatbread.', result.recipe.description
    assert_empty result.updated_references
  end

  test 'update with title rename returns updated_references' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Panzanella

      Category: Bread

      ## Make bread.
      >>> @[Focaccia], 1

      ## Assemble (put it together)

      - Tomatoes, 3

      Tear bread and toss.
    MD

    renamed = <<~MD
      # Rosemary Focaccia

      Category: Bread
      Serves: 8

      ## Make the dough (combine ingredients)

      - Flour, 4 cups

      Mix everything.
    MD

    result = RecipeWriteService.update(slug: 'focaccia', markdown: renamed, kitchen: @kitchen)

    assert_includes result.updated_references, 'Panzanella'
    assert_equal 'rosemary-focaccia', result.recipe.slug
  end

  test 'update with slug change destroys old record' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

    renamed = <<~MD
      # Rosemary Focaccia

      Category: Bread

      ## Make (do it)

      - Flour, 4 cups

      Mix.
    MD

    RecipeWriteService.update(slug: 'focaccia', markdown: renamed, kitchen: @kitchen)

    assert_nil Recipe.find_by(slug: 'focaccia')
    assert Recipe.find_by(slug: 'rosemary-focaccia')
  end

  test 'update cleans up orphan categories' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

    recategorized = <<~MD
      # Focaccia

      Category: Pastry

      ## Make (do it)

      - Flour, 3 cups

      Mix.
    MD

    RecipeWriteService.update(slug: 'focaccia', markdown: recategorized, kitchen: @kitchen)

    assert_nil Category.find_by(slug: 'bread')
    assert Category.find_by(slug: 'pastry')
  end
end
