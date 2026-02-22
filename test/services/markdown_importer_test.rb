# frozen_string_literal: true

require_relative '../test_helper'

class MarkdownImporterTest < ActiveSupport::TestCase
  BASIC_RECIPE = <<~MARKDOWN
    # Focaccia

    A simple Italian flatbread.

    Category: Bread
    Makes: 1 loaf
    Serves: 8

    ## Make the dough (mix dry and wet)

    - Flour, 3 cups: Sifted.
    - Olive oil, 2 tbsp
    - Salt, 1 tsp

    Combine flour and salt in a large bowl. Add olive oil and mix until a shaggy dough forms.

    ## Bake (golden brown)

    - Rosemary, 2 sprigs: Chopped.

    Dimple the dough with your fingers. Top with rosemary and bake at 425 for 20 minutes.

    ---

    Adapted from a classic Italian recipe.
  MARKDOWN

  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    Recipe.destroy_all
    Category.destroy_all
  end

  test 'imports a basic recipe from markdown' do
    recipe = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen)

    assert_equal 'Focaccia', recipe.title
    assert_equal 'focaccia', recipe.slug
    assert_equal 'A simple Italian flatbread.', recipe.description
    assert_equal 'Bread', recipe.category.name
    assert_equal 'bread', recipe.category.slug
    assert_equal 'Adapted from a classic Italian recipe.', recipe.footer
    assert_equal BASIC_RECIPE, recipe.markdown_source
    assert_predicate recipe, :persisted?
  end

  test 'imports steps with correct positions' do
    recipe = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen)

    assert_equal 2, recipe.steps.size

    first_step = recipe.steps.first

    assert_equal 'Make the dough (mix dry and wet)', first_step.title
    assert_equal 0, first_step.position
    assert_includes first_step.instructions, 'Combine flour and salt'

    second_step = recipe.steps.second

    assert_equal 'Bake (golden brown)', second_step.title
    assert_equal 1, second_step.position
  end

  test 'imports ingredients with quantity, unit, and prep note' do
    recipe = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen)

    flour = recipe.steps.first.ingredients.find_by(name: 'Flour')

    assert flour
    assert_equal '3', flour.quantity
    assert_equal 'cups', flour.unit
    assert_equal 'Sifted.', flour.prep_note
    assert_equal 0, flour.position

    olive_oil = recipe.steps.first.ingredients.find_by(name: 'Olive oil')

    assert olive_oil
    assert_equal '2', olive_oil.quantity
    assert_equal 'tbsp', olive_oil.unit
    assert_nil olive_oil.prep_note

    salt = recipe.steps.first.ingredients.find_by(name: 'Salt')

    assert salt
    assert_equal '1', salt.quantity
    assert_equal 'tsp', salt.unit
  end

  test 'imports makes and serves from front matter' do
    recipe = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen)

    assert_in_delta(1.0, recipe.makes_quantity)
    assert_equal 'loaf', recipe.makes_unit_noun
    assert_equal 8, recipe.serves
  end

  test 'idempotent import updates instead of duplicating' do
    first = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen)
    first_id = first.id

    updated_source = BASIC_RECIPE.sub('A simple Italian flatbread.', 'The best flatbread ever.')
    second = MarkdownImporter.import(updated_source, kitchen: @kitchen)

    assert_equal first_id, second.id
    assert_equal 'The best flatbread ever.', second.description
    assert_equal 1, Recipe.where(slug: 'focaccia').count
  end

  test 'idempotent import replaces steps cleanly' do
    MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen)

    assert_equal 2, Recipe.find_by(slug: 'focaccia').steps.count

    MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen)

    assert_equal 2, Recipe.find_by(slug: 'focaccia').steps.count
  end

  test 'cross-references are skipped as ingredients' do
    markdown_with_xref = <<~MARKDOWN
      # Pizza

      Category: Main

      ## Assemble (build the pizza)

      - @[Pizza Dough], 1
      - Mozzarella, 8 oz: Shredded.
      - Tomato sauce, 1 cup

      Spread sauce on dough, top with cheese.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown_with_xref, kitchen: @kitchen)

    step = recipe.steps.first

    assert_equal 2, step.ingredients.count

    ingredient_names = step.ingredients.map(&:name)

    assert_includes ingredient_names, 'Mozzarella'
    assert_includes ingredient_names, 'Tomato sauce'
  end

  test 'recipe dependencies are created for cross-references' do
    dough_markdown = <<~MARKDOWN
      # Pizza Dough

      Category: Bread

      ## Mix (combine ingredients)

      - Flour, 3 cups
      - Water, 1 cup

      Mix flour and water.
    MARKDOWN

    pizza_markdown = <<~MARKDOWN
      # Pizza

      Category: Main

      ## Assemble (build the pizza)

      - @[Pizza Dough], 1
      - Mozzarella, 8 oz

      Spread sauce on dough, top with cheese.
    MARKDOWN

    MarkdownImporter.import(dough_markdown, kitchen: @kitchen)
    pizza = MarkdownImporter.import(pizza_markdown, kitchen: @kitchen)

    assert_equal 1, pizza.outbound_dependencies.count
    assert_equal 'pizza-dough', pizza.referenced_recipes.first.slug
  end

  test 'dependencies are not created when target recipe is missing' do
    markdown_with_missing_ref = <<~MARKDOWN
      # Pasta

      Category: Main

      ## Cook (boil it)

      - @[Nonexistent Sauce]
      - Spaghetti, 1 lb

      Cook and serve.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown_with_missing_ref, kitchen: @kitchen)

    assert_equal 0, recipe.outbound_dependencies.count
  end

  test 'quantity splitting handles various formats' do
    importer = MarkdownImporter.new("# Dummy\n\nCategory: Test\n\n## Step\n\n- Salt\n\nText.", kitchen: @kitchen)

    assert_equal [nil, nil], importer.send(:split_quantity, nil)
    assert_equal [nil, nil], importer.send(:split_quantity, '')
    assert_equal [nil, nil], importer.send(:split_quantity, '  ')
    assert_equal %w[2 cups], importer.send(:split_quantity, '2 cups')
    assert_equal %w[500 g], importer.send(:split_quantity, '500 g')
    assert_equal ['4', nil], importer.send(:split_quantity, '4')
  end

  test 'recipe without makes or serves' do
    simple_markdown = <<~MARKDOWN
      # Simple Salad

      Category: Side

      ## Toss (mix it up)

      - Lettuce, 1 head

      Toss the lettuce.
    MARKDOWN

    recipe = MarkdownImporter.import(simple_markdown, kitchen: @kitchen)

    assert_nil recipe.makes_quantity
    assert_nil recipe.makes_unit_noun
    assert_nil recipe.serves
  end

  test 'recipe without description or footer' do
    minimal_markdown = <<~MARKDOWN
      # Toast

      Category: Breakfast

      ## Toast it (golden brown)

      - Bread, 2 slices

      Put the bread in the toaster.
    MARKDOWN

    recipe = MarkdownImporter.import(minimal_markdown, kitchen: @kitchen)

    assert_nil recipe.description
    assert_nil recipe.footer
  end

  test 'imports cross-references with multiplier and prep_note' do
    ActsAsTenant.with_tenant(@kitchen) do
      MarkdownImporter.import("# Dough\n\nCategory: Bread\n\n## Mix\n\n- Flour, 2 cups\n\nMix it.", kitchen: @kitchen)

      markdown = "# Pizza\n\nCategory: Bread\n\n## Assemble\n\n" \
                 "- @[Dough], 2: Let rest.\n- Cheese, 1 cup\n\nAssemble it."
      recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)

      step = recipe.steps.first

      assert_equal 1, step.cross_references.size

      ref = step.cross_references.first

      assert_equal 'Dough', ref.target_title
      assert_in_delta 2.0, ref.multiplier
      assert_equal 'Let rest.', ref.prep_note
    end
  end

  test 'cross-references and ingredients share position sequence' do
    ActsAsTenant.with_tenant(@kitchen) do
      MarkdownImporter.import("# Sauce\n\nCategory: Bread\n\n## Mix\n\n- Tomato, 1 can\n\nMix.", kitchen: @kitchen)

      markdown = "# Pizza\n\nCategory: Bread\n\n## Build\n\n- Dough, 1 ball\n- @[Sauce]\n- Cheese, 2 cups\n\nBuild it."
      recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)

      step = recipe.steps.first
      items = step.ingredient_list_items

      assert_equal 3, items.size
      assert_equal 'Dough', items[0].name
      assert_respond_to items[1], :target_slug
      assert_equal 'Cheese', items[2].name
    end
  end

  test 'category is reused when it already exists' do
    bread1 = <<~MARKDOWN
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix everything.
    MARKDOWN

    bread2 = <<~MARKDOWN
      # Ciabatta

      Category: Bread

      ## Mix (combine)

      - Flour, 4 cups

      Mix everything.
    MARKDOWN

    MarkdownImporter.import(bread1, kitchen: @kitchen)
    MarkdownImporter.import(bread2, kitchen: @kitchen)

    assert_equal 1, Category.where(name: 'Bread').count
    assert_equal 2, Category.find_by(name: 'Bread').recipes.count
  end
end
