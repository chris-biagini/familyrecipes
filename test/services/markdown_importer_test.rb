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

  test 'cross-reference step has no ingredients' do
    markdown_with_xref = <<~MARKDOWN
      # Pizza

      Category: Main

      ## Make dough.
      >>> @[Pizza Dough]

      ## Assemble (build the pizza)

      - Mozzarella, 8 oz: Shredded.
      - Tomato sauce, 1 cup

      Spread sauce on dough, top with cheese.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown_with_xref, kitchen: @kitchen)

    xref_step = recipe.steps.find_by(title: 'Make dough.')

    assert_equal 0, xref_step.ingredients.count
    assert_equal 1, xref_step.cross_references.count

    content_step = recipe.steps.find_by(title: 'Assemble (build the pizza)')

    assert_equal 2, content_step.ingredients.count
    assert_includes content_step.ingredients.map(&:name), 'Mozzarella'
    assert_includes content_step.ingredients.map(&:name), 'Tomato sauce'
  end

  test 'cross-references link to target recipes' do
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

      ## Make dough.
      >>> @[Pizza Dough]

      ## Assemble (build the pizza)

      - Mozzarella, 8 oz

      Spread sauce on dough, top with cheese.
    MARKDOWN

    MarkdownImporter.import(dough_markdown, kitchen: @kitchen)
    pizza = MarkdownImporter.import(pizza_markdown, kitchen: @kitchen)

    assert_equal 1, pizza.cross_references.count
    assert_equal 'pizza-dough', pizza.cross_references.first.target_slug
  end

  test 'creates pending cross-reference when target recipe is missing' do
    markdown_with_missing_ref = <<~MARKDOWN
      # Pasta

      Category: Main

      ## Make sauce.
      >>> @[Nonexistent Sauce]

      ## Cook (boil it)

      - Spaghetti, 1 lb

      Cook and serve.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown_with_missing_ref, kitchen: @kitchen)

    assert_equal 1, recipe.cross_references.count
    assert_predicate recipe.cross_references.first, :pending?
  end

  test 'creates pending cross-reference with correct slug and title' do
    markdown = <<~MARKDOWN
      # Pasta

      Category: Main

      ## Make sauce.
      >>> @[Nonexistent Sauce]

      ## Cook (boil it)

      - Spaghetti, 1 lb

      Cook and serve.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)
    ref = recipe.cross_references.first

    assert_equal 1, recipe.cross_references.count
    assert_equal 'nonexistent-sauce', ref.target_slug
    assert_equal 'Nonexistent Sauce', ref.target_title
    assert_nil ref.target_recipe_id
    assert_predicate ref, :pending?
  end

  test 'resolves pending cross-references when target is imported later' do
    pasta_md = <<~MARKDOWN
      # Pasta

      Category: Main

      ## Make sauce.
      >>> @[Marinara Sauce]

      ## Cook (boil it)

      - Spaghetti, 1 lb

      Cook and serve.
    MARKDOWN

    sauce_md = <<~MARKDOWN
      # Marinara Sauce

      Category: Sauce

      ## Cook (simmer)

      - Tomatoes, 1 can

      Simmer for 30 minutes.
    MARKDOWN

    pasta = MarkdownImporter.import(pasta_md, kitchen: @kitchen)

    assert_predicate pasta.cross_references.first, :pending?

    sauce = MarkdownImporter.import(sauce_md, kitchen: @kitchen)

    pasta.cross_references.first.reload

    assert_predicate pasta.cross_references.first, :resolved?
    assert_equal sauce.id, pasta.cross_references.first.target_recipe_id
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

  test 'imports cross-reference with multiplier and prep note via >>> syntax' do
    ActsAsTenant.with_tenant(@kitchen) do
      MarkdownImporter.import("# Dough\n\nCategory: Bread\n\n## Mix\n\n- Flour, 2 cups\n\nMix it.", kitchen: @kitchen)

      markdown = <<~MARKDOWN
        # Pizza

        Category: Bread

        ## Make dough.
        >>> @[Dough], 2: Let rest.

        ## Add toppings.

        - Cheese, 1 cup

        Assemble it.
      MARKDOWN

      recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)
      xref_step = recipe.steps.find_by(title: 'Make dough.')

      assert_equal 1, xref_step.cross_references.size

      ref = xref_step.cross_references.first

      assert_equal 'Dough', ref.target_title
      assert_in_delta 2.0, ref.multiplier
      assert_equal 'Let rest.', ref.prep_note
    end
  end

  test 'cross-reference and content steps get correct positions' do
    ActsAsTenant.with_tenant(@kitchen) do
      MarkdownImporter.import("# Sauce\n\nCategory: Bread\n\n## Mix\n\n- Tomato, 1 can\n\nMix.", kitchen: @kitchen)

      markdown = <<~MARKDOWN
        # Pizza

        Category: Bread

        ## Make sauce.
        >>> @[Sauce]

        ## Build (assemble)

        - Dough, 1 ball
        - Cheese, 2 cups

        Build it.
      MARKDOWN

      recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)

      assert_equal 0, recipe.steps.find_by(title: 'Make sauce.').position
      assert_equal 1, recipe.steps.find_by(title: 'Build (assemble)').position
    end
  end

  test 'stores processed_instructions with scalable number spans' do
    ActsAsTenant.with_tenant(@kitchen) do
      markdown = "# Bread\n\nCategory: Bread\n\n## Mix\n\n- Flour, 2 cups\n\nCombine 3* cups of water."
      recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)

      step = recipe.steps.first

      assert_includes step.processed_instructions, 'data-base-value="3.0"'
      assert_includes step.processed_instructions, 'scalable'
    end
  end

  test 'imports implicit step recipe without L2 headers' do
    markdown = <<~MARKDOWN
      # Nacho Cheese

      Worth the effort.

      Category: Snacks
      Makes: 1 cup
      Serves: 4

      - Cheddar, 225 g: Cut into small cubes.
      - Milk, 225 g
      - Sodium citrate, 8 g
      - Salt, 2 g
      - Pickled jalapeños, 40 g

      Combine all ingredients in saucepan.

      Warm over low heat, stirring occasionally, until cheese is mostly melted. Puree with immersion blender.

      ---

      Based on a recipe from ChefSteps.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)

    assert_equal 'Nacho Cheese', recipe.title
    assert_equal 1, recipe.steps.size

    step = recipe.steps.first

    assert_nil step.title
    assert_equal 0, step.position
    assert_equal 5, step.ingredients.count
    assert_equal 'Cheddar', step.ingredients.first.name
    assert_includes step.instructions, 'Combine all ingredients'
    assert_includes step.processed_instructions, 'Combine all ingredients'
    assert_includes recipe.footer, 'ChefSteps'
  end

  test 'imports cross-reference step with >>> syntax' do
    markdown = <<~MARKDOWN
      # Pizza

      Category: Main

      ## Make dough.
      >>> @[Pizza Dough]

      ## Top (add cheese)

      - Mozzarella, 8 oz

      Add cheese.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)
    xref_step = recipe.steps.find_by(title: 'Make dough.')

    assert_equal 1, xref_step.cross_references.size
    assert_equal 0, xref_step.ingredients.size
    assert_equal 'Pizza Dough', xref_step.cross_references.first.target_title
  end

  test 'cross-reference step has no instructions' do
    markdown = <<~MARKDOWN
      # Pizza

      Category: Main

      ## Make dough.
      >>> @[Pizza Dough]

      ## Top (add cheese)

      - Mozzarella, 8 oz

      Add cheese.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)
    xref_step = recipe.steps.find_by(title: 'Make dough.')

    assert_nil xref_step.instructions
    assert_nil xref_step.processed_instructions
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
