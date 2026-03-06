# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class RecipeWriteServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    setup_test_kitchen
    Recipe.destroy_all
    Category.destroy_all
  end

  BASIC_MARKDOWN = <<~MD
    # Focaccia

    A simple flatbread.

    Serves: 8

    ## Make the dough (combine ingredients)

    - Flour, 3 cups
    - Salt, 1 tsp

    Mix everything together.
  MD

  test 'create imports recipe and returns Result' do
    result = RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    assert_instance_of RecipeWriteService::Result, result
    assert_equal 'Focaccia', result.recipe.title
    assert_empty result.updated_references
  end

  test 'create sets edited_at' do
    result = RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    assert_not_nil result.recipe.edited_at
  end

  test 'create cleans up orphan categories' do
    Category.create!(name: 'Empty', slug: 'empty', position: 99, kitchen: @kitchen)

    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    assert_nil Category.find_by(slug: 'empty')
  end

  test 'create raises on invalid markdown' do
    assert_raises(RuntimeError) do
      RecipeWriteService.create(markdown: 'not a recipe at all', kitchen: @kitchen)
    end
  end

  test 'create defaults to Miscellaneous when category_name is blank' do
    result = RecipeWriteService.create(
      markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: ''
    )
    assert_equal 'Miscellaneous', result.recipe.category.name
  end

  test 'update imports recipe and returns Result' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    updated = <<~MD
      # Focaccia

      A revised flatbread.

      Serves: 12

      ## Make the dough (combine ingredients)

      - Flour, 4 cups

      Mix everything.
    MD

    result = RecipeWriteService.update(slug: 'focaccia', markdown: updated, kitchen: @kitchen, category_name: 'Bread')

    assert_equal 'Focaccia', result.recipe.title
    assert_equal 'A revised flatbread.', result.recipe.description
    assert_empty result.updated_references
  end

  test 'update with title rename returns updated_references' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    bread = @kitchen.categories.find_by!(slug: 'bread')
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: bread)
      # Panzanella

      ## Make bread.
      >>> @[Focaccia], 1

      ## Assemble (put it together)

      - Tomatoes, 3

      Tear bread and toss.
    MD

    renamed = <<~MD
      # Rosemary Focaccia

      Serves: 8

      ## Make the dough (combine ingredients)

      - Flour, 4 cups

      Mix everything.
    MD

    result = RecipeWriteService.update(slug: 'focaccia', markdown: renamed, kitchen: @kitchen, category_name: 'Bread')

    assert_includes result.updated_references, 'Panzanella'
    assert_equal 'rosemary-focaccia', result.recipe.slug
  end

  test 'update with slug change destroys old record' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    renamed = <<~MD
      # Rosemary Focaccia

      ## Make (do it)

      - Flour, 4 cups

      Mix.
    MD

    RecipeWriteService.update(slug: 'focaccia', markdown: renamed, kitchen: @kitchen, category_name: 'Bread')

    assert_nil Recipe.find_by(slug: 'focaccia')
    assert Recipe.find_by(slug: 'rosemary-focaccia')
  end

  test 'update cleans up orphan categories' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    recategorized = <<~MD
      # Focaccia

      ## Make (do it)

      - Flour, 3 cups

      Mix.
    MD

    RecipeWriteService.update(slug: 'focaccia', markdown: recategorized, kitchen: @kitchen, category_name: 'Pastry')

    assert_nil Category.find_by(slug: 'bread')
    assert Category.find_by(slug: 'pastry')
  end

  test 'destroy removes recipe and returns Result' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    result = RecipeWriteService.destroy(slug: 'focaccia', kitchen: @kitchen)

    assert_equal 'Focaccia', result.recipe.title
    assert_nil Recipe.find_by(slug: 'focaccia')
  end

  test 'destroy cleans up orphan categories' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    RecipeWriteService.destroy(slug: 'focaccia', kitchen: @kitchen)

    assert_nil Category.find_by(slug: 'bread')
  end

  test 'destroy nullifies inbound cross-references' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    bread = @kitchen.categories.find_by!(slug: 'bread')
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: bread)
      # Panzanella

      ## Make bread.
      >>> @[Focaccia], 1

      ## Assemble (put it together)

      - Tomatoes, 3

      Tear bread and toss.
    MD

    panzanella = Recipe.find_by!(slug: 'panzanella')
    xref_step = panzanella.steps.find_by!(title: 'Make bread.')
    xref = xref_step.cross_references.find_by!(target_title: 'Focaccia')

    RecipeWriteService.destroy(slug: 'focaccia', kitchen: @kitchen)

    assert_nil xref.reload.target_recipe_id
  end

  test 'create broadcasts to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')
    end
  end

  test 'update broadcasts to kitchen updates stream' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      RecipeWriteService.update(slug: 'focaccia', markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')
    end
  end

  test 'destroy broadcasts to kitchen updates stream' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      RecipeWriteService.destroy(slug: 'focaccia', kitchen: @kitchen)
    end
  end
end
