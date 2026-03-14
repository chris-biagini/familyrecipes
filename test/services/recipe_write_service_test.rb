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
      > @[Focaccia], 1

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
      > @[Focaccia], 1

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

  test 'create skips broadcast when batching' do
    broadcast_count = 0
    @kitchen.define_singleton_method(:broadcast_update) { broadcast_count += 1 }

    Kitchen.stub(:batching?, true) do
      RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')
    end

    assert_equal 0, broadcast_count
  end

  test 'destroy prunes deleted recipe from meal plan selections' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    RecipeWriteService.destroy(slug: 'focaccia', kitchen: @kitchen)

    plan.reload

    assert_not_includes plan.state['selected_recipes'], 'focaccia'
  end

  test 'update with rename prunes old slug from meal plan selections' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    renamed = <<~MD
      # Rosemary Focaccia

      ## Make (do it)

      - Flour, 4 cups

      Mix.
    MD

    RecipeWriteService.update(slug: 'focaccia', markdown: renamed, kitchen: @kitchen, category_name: 'Bread')

    plan.reload

    assert_not_includes plan.state['selected_recipes'], 'focaccia'
  end

  test 'create raises SlugCollisionError when slug collides with different title' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    colliding = BASIC_MARKDOWN.sub('# Focaccia', '# Focaccia!')

    assert_raises(MarkdownImporter::SlugCollisionError) do
      RecipeWriteService.create(markdown: colliding, kitchen: @kitchen, category_name: 'Bread')
    end
  end

  test 'update raises SlugCollisionError when renamed title collides with another recipe' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

    other_md = <<~MD
      # Ciabatta

      ## Mix (combine)

      - Flour, 4 cups

      Mix.
    MD
    RecipeWriteService.create(markdown: other_md, kitchen: @kitchen, category_name: 'Bread')

    renamed = other_md.sub('# Ciabatta', '# Focaccia!')

    assert_raises(MarkdownImporter::SlugCollisionError) do
      RecipeWriteService.update(slug: 'ciabatta', markdown: renamed, kitchen: @kitchen, category_name: 'Bread')
    end
  end

  test 'slug reuse after delete does not auto-select' do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    RecipeWriteService.destroy(slug: 'focaccia', kitchen: @kitchen)

    new_markdown = <<~MD
      # Focaccia

      A different focaccia.

      ## Make (do it)

      - Flour, 2 cups

      Mix.
    MD
    RecipeWriteService.create(markdown: new_markdown, kitchen: @kitchen, category_name: 'Bread')

    plan.reload

    assert_not_includes plan.state['selected_recipes'], 'focaccia'
  end

  test 'create uses front matter tags when tags param is nil' do
    md = "# FM Tags\n\nTags: quick, breakfast\n\n## Step\n\n- Eggs, 2\n\nScramble."
    result = RecipeWriteService.create(markdown: md, kitchen: @kitchen)

    assert_equal %w[breakfast quick], result.recipe.tags.pluck(:name).sort
  end

  test 'explicit tags param overrides front matter tags' do
    md = "# FM Tags Override\n\nTags: breakfast, quick\n\n## Step\n\n- Eggs, 2\n\nScramble."
    result = RecipeWriteService.create(markdown: md, kitchen: @kitchen, tags: %w[dinner])

    assert_equal %w[dinner], result.recipe.tags.pluck(:name)
  end

  test 'create uses front matter category when category_name is blank' do
    md = "# FM Category\n\nCategory: Desserts\n\n## Step\n\n- Sugar, 1 cup\n\nMix."
    result = RecipeWriteService.create(markdown: md, kitchen: @kitchen, category_name: '')

    assert_equal 'Desserts', result.recipe.category.name
  end

  test 'update uses front matter tags when tags param is nil' do
    md = "# FM Update Tags\n\nTags: lunch\n\n## Step\n\n- Bread, 2 slices\n\nToast."
    RecipeWriteService.create(markdown: md, kitchen: @kitchen)
    updated = "# FM Update Tags\n\nTags: dinner, fancy\n\n## Step\n\n- Bread, 2 slices\n\nToast."
    result = RecipeWriteService.update(slug: 'fm-update-tags', markdown: updated, kitchen: @kitchen)

    assert_equal %w[dinner fancy], result.recipe.tags.pluck(:name).sort
  end
end
