# frozen_string_literal: true

require_relative '../test_helper'

class MarkdownImporterTest < ActiveSupport::TestCase
  BASIC_RECIPE = <<~MARKDOWN
    # Focaccia

    A simple Italian flatbread.

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
    setup_test_kitchen
    Recipe.destroy_all
    Category.destroy_all
    @bread = @kitchen.categories.create!(name: 'Bread', slug: 'bread', position: 0)
    @main = @kitchen.categories.create!(name: 'Main', slug: 'main', position: 1)
  end

  test 'imports a basic recipe from markdown' do
    recipe = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread).recipe

    assert_equal 'Focaccia', recipe.title
    assert_equal 'focaccia', recipe.slug
    assert_equal 'A simple Italian flatbread.', recipe.description
    assert_equal @bread, recipe.category
    assert_equal 'Adapted from a classic Italian recipe.', recipe.footer
    assert_predicate recipe, :persisted?
  end

  test 'imports steps with correct positions' do
    recipe = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread).recipe

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
    recipe = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread).recipe

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
    recipe = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread).recipe

    assert_in_delta(1.0, recipe.makes_quantity)
    assert_equal 'loaf', recipe.makes_unit_noun
    assert_equal 8, recipe.serves
  end

  test 'idempotent import updates instead of duplicating' do
    first = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread).recipe
    first_id = first.id

    updated_source = BASIC_RECIPE.sub('A simple Italian flatbread.', 'The best flatbread ever.')
    second = MarkdownImporter.import(updated_source, kitchen: @kitchen, category: @bread).recipe

    assert_equal first_id, second.id
    assert_equal 'The best flatbread ever.', second.description
    assert_equal 1, Recipe.where(slug: 'focaccia').count
  end

  test 'idempotent import replaces steps cleanly' do
    MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread)

    assert_equal 2, Recipe.find_by(slug: 'focaccia').steps.count

    MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread)

    assert_equal 2, Recipe.find_by(slug: 'focaccia').steps.count
  end

  test 'cross-reference step has no ingredients' do
    markdown_with_xref = <<~MARKDOWN
      # Pizza

      ## Make dough.
      > @[Pizza Dough]

      ## Assemble (build the pizza)

      - Mozzarella, 8 oz: Shredded.
      - Tomato sauce, 1 cup

      Spread sauce on dough, top with cheese.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown_with_xref, kitchen: @kitchen, category: @main).recipe

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

      ## Mix (combine ingredients)

      - Flour, 3 cups
      - Water, 1 cup

      Mix flour and water.
    MARKDOWN

    pizza_markdown = <<~MARKDOWN
      # Pizza

      ## Make dough.
      > @[Pizza Dough]

      ## Assemble (build the pizza)

      - Mozzarella, 8 oz

      Spread sauce on dough, top with cheese.
    MARKDOWN

    MarkdownImporter.import(dough_markdown, kitchen: @kitchen, category: @bread)
    pizza = MarkdownImporter.import(pizza_markdown, kitchen: @kitchen, category: @main).recipe
    xref_step = pizza.steps.find_by!(title: 'Make dough.')

    assert_equal 1, xref_step.cross_references.count
    assert_equal 'pizza-dough', xref_step.cross_references.first.target_slug
  end

  test 'creates pending cross-reference when target recipe is missing' do
    markdown_with_missing_ref = <<~MARKDOWN
      # Pasta

      ## Make sauce.
      > @[Nonexistent Sauce]

      ## Cook (boil it)

      - Spaghetti, 1 lb

      Cook and serve.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown_with_missing_ref, kitchen: @kitchen, category: @main).recipe
    xref_step = recipe.steps.find_by!(title: 'Make sauce.')

    assert_equal 1, xref_step.cross_references.count
    assert_predicate xref_step.cross_references.first, :pending?
  end

  test 'creates pending cross-reference with correct slug and title' do
    markdown = <<~MARKDOWN
      # Pasta

      ## Make sauce.
      > @[Nonexistent Sauce]

      ## Cook (boil it)

      - Spaghetti, 1 lb

      Cook and serve.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @main).recipe
    xref_step = recipe.steps.find_by!(title: 'Make sauce.')
    ref = xref_step.cross_references.first

    assert_equal 1, xref_step.cross_references.count
    assert_equal 'nonexistent-sauce', ref.target_slug
    assert_equal 'Nonexistent Sauce', ref.target_title
    assert_nil ref.target_recipe_id
    assert_predicate ref, :pending?
  end

  test 'resolves pending cross-references when target is imported later' do
    pasta_md = <<~MARKDOWN
      # Pasta

      ## Make sauce.
      > @[Marinara Sauce]

      ## Cook (boil it)

      - Spaghetti, 1 lb

      Cook and serve.
    MARKDOWN

    sauce_md = <<~MARKDOWN
      # Marinara Sauce

      ## Cook (simmer)

      - Tomatoes, 1 can

      Simmer for 30 minutes.
    MARKDOWN

    pasta = MarkdownImporter.import(pasta_md, kitchen: @kitchen, category: @main).recipe
    xref_step = pasta.steps.find_by!(title: 'Make sauce.')
    xref = xref_step.cross_references.first

    assert_predicate xref, :pending?

    sauce = MarkdownImporter.import(sauce_md, kitchen: @kitchen, category: @main).recipe
    xref.reload

    assert_predicate xref, :resolved?
    assert_equal sauce.id, xref.target_recipe_id
  end

  test 'quantity splitting handles various formats' do
    assert_equal [nil, nil], Mirepoix::Ingredient.split_quantity(nil)
    assert_equal [nil, nil], Mirepoix::Ingredient.split_quantity('')
    assert_equal [nil, nil], Mirepoix::Ingredient.split_quantity('  ')
    assert_equal %w[2 cups], Mirepoix::Ingredient.split_quantity('2 cups')
    assert_equal %w[500 g], Mirepoix::Ingredient.split_quantity('500 g')
    assert_equal ['4', nil], Mirepoix::Ingredient.split_quantity('4')
    assert_equal ['2 1/2', 'cups'], Mirepoix::Ingredient.split_quantity('2 1/2 cups')
  end

  test 'recipe without makes or serves' do
    simple_markdown = <<~MARKDOWN
      # Simple Salad

      ## Toss (mix it up)

      - Lettuce, 1 head

      Toss the lettuce.
    MARKDOWN

    recipe = MarkdownImporter.import(simple_markdown, kitchen: @kitchen, category: @main).recipe

    assert_nil recipe.makes_quantity
    assert_nil recipe.makes_unit_noun
    assert_nil recipe.serves
  end

  test 'recipe without description or footer' do
    minimal_markdown = <<~MARKDOWN
      # Toast

      ## Toast it (golden brown)

      - Bread, 2 slices

      Put the bread in the toaster.
    MARKDOWN

    recipe = MarkdownImporter.import(minimal_markdown, kitchen: @kitchen, category: @bread).recipe

    assert_nil recipe.description
    assert_nil recipe.footer
  end

  test 'imports cross-reference with multiplier and prep note via > syntax' do
    ActsAsTenant.with_tenant(@kitchen) do
      MarkdownImporter.import("# Dough\n\n## Mix\n\n- Flour, 2 cups\n\nMix it.", kitchen: @kitchen, category: @bread)

      markdown = <<~MARKDOWN
        # Pizza

        ## Make dough.
        > @[Dough], 2: Let rest.

        ## Add toppings.

        - Cheese, 1 cup

        Assemble it.
      MARKDOWN

      recipe = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @bread).recipe
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
      MarkdownImporter.import("# Sauce\n\n## Mix\n\n- Tomato, 1 can\n\nMix.", kitchen: @kitchen, category: @bread)

      markdown = <<~MARKDOWN
        # Pizza

        ## Make sauce.
        > @[Sauce]

        ## Build (assemble)

        - Dough, 1 ball
        - Cheese, 2 cups

        Build it.
      MARKDOWN

      recipe = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @bread).recipe

      assert_equal 0, recipe.steps.find_by(title: 'Make sauce.').position
      assert_equal 1, recipe.steps.find_by(title: 'Build (assemble)').position
    end
  end

  test 'stores processed_instructions with scalable number spans' do
    ActsAsTenant.with_tenant(@kitchen) do
      markdown = "# Bread\n\n## Mix\n\n- Flour, 2 cups\n\nCombine 3* cups of water."
      recipe = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @bread).recipe

      step = recipe.steps.first

      assert_includes step.processed_instructions, 'data-base-value="3.0"'
      assert_includes step.processed_instructions, 'scalable'
    end
  end

  test 'imports implicit step recipe without L2 headers' do
    markdown = <<~MARKDOWN
      # Nacho Cheese

      Worth the effort.

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

    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @main).recipe

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

  test 'imports cross-reference step with > syntax' do
    markdown = <<~MARKDOWN
      # Pizza

      ## Make dough.
      > @[Pizza Dough]

      ## Top (add cheese)

      - Mozzarella, 8 oz

      Add cheese.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @main).recipe
    xref_step = recipe.steps.find_by(title: 'Make dough.')

    assert_equal 1, xref_step.cross_references.size
    assert_equal 0, xref_step.ingredients.size
    assert_equal 'Pizza Dough', xref_step.cross_references.first.target_title
  end

  test 'cross-reference step has no instructions' do
    markdown = <<~MARKDOWN
      # Pizza

      ## Make dough.
      > @[Pizza Dough]

      ## Top (add cheese)

      - Mozzarella, 8 oz

      Add cheese.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @main).recipe
    xref_step = recipe.steps.find_by(title: 'Make dough.')

    assert_nil xref_step.instructions
    assert_nil xref_step.processed_instructions
  end

  test 'raises SlugCollisionError when slug matches but title differs' do
    MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread)

    colliding_markdown = BASIC_RECIPE.sub('# Focaccia', '# Focaccia!')

    error = assert_raises(MarkdownImporter::SlugCollisionError) do
      MarkdownImporter.import(colliding_markdown, kitchen: @kitchen, category: @bread)
    end
    assert_includes error.message, 'Focaccia'
  end

  test 'same-title reimport still works after collision check' do
    first = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread).recipe
    second = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread).recipe

    assert_equal first.id, second.id
  end

  test 'assigns the passed category to the recipe' do
    bread1 = <<~MARKDOWN
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix everything.
    MARKDOWN

    bread2 = <<~MARKDOWN
      # Ciabatta

      ## Mix (combine)

      - Flour, 4 cups

      Mix everything.
    MARKDOWN

    MarkdownImporter.import(bread1, kitchen: @kitchen, category: @bread)
    MarkdownImporter.import(bread2, kitchen: @kitchen, category: @bread)

    assert_equal 2, @bread.recipes.count
  end

  test 'uses front matter category when no category argument given' do
    md = "# Front Matter Cat\n\nCategory: Desserts\n\n## Step\n\n- Sugar, 1 cup\n\nMix."
    result = MarkdownImporter.import(md, kitchen: @kitchen, category: nil)

    assert_equal 'Desserts', result.recipe.category.name
  end

  test 'explicit category argument overrides front matter' do
    md = "# Override Cat\n\nCategory: Desserts\n\n## Step\n\n- Sugar, 1 cup\n\nMix."
    category = @kitchen.categories.create!(name: 'Breads', slug: 'breads', position: 2)
    result = MarkdownImporter.import(md, kitchen: @kitchen, category: category)

    assert_equal 'Breads', result.recipe.category.name
  end

  test 'import returns ImportResult with recipe and front_matter_tags' do
    md = "# Tagged Recipe\n\nTags: quick, breakfast\n\n## Step\n\n- Eggs, 2\n\nScramble."
    result = MarkdownImporter.import(md, kitchen: @kitchen, category: @main)

    assert_instance_of MarkdownImporter::ImportResult, result
    assert_equal 'Tagged Recipe', result.recipe.title
    assert_equal %w[breakfast quick], result.front_matter_tags.sort
  end

  test 'import returns nil front_matter_tags when no tags in front matter' do
    result = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread)

    assert_nil result.front_matter_tags
  end

  test 'imports ingredient with range quantity' do
    markdown = "# Test\n\n## Step\n\n- Eggs, 2-3\n\nScramble them."
    result = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @bread)
    ingredient = result.recipe.steps.first.ingredients.first

    assert_equal 'Eggs', ingredient.name
    assert_equal '2-3', ingredient.quantity
    assert_in_delta 2.0, ingredient.quantity_low
    assert_in_delta 3.0, ingredient.quantity_high
    assert_nil ingredient.unit
  end

  test 'imports ingredient with fractional range' do
    markdown = "# Test\n\n## Step\n\n- Butter, 1/2-1 stick\n\nMelt it."
    result = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @bread)
    ingredient = result.recipe.steps.first.ingredients.first

    assert_in_delta 0.5, ingredient.quantity_low
    assert_in_delta 1.0, ingredient.quantity_high
    assert_equal 'stick', ingredient.unit
  end

  test 'normalizes vulgar fractions on import' do
    markdown = "# Test\n\n## Step\n\n- Butter, \u00bd cup\n\nMelt it."
    result = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @bread)
    ingredient = result.recipe.steps.first.ingredients.first

    assert_equal '1/2', ingredient.quantity
    assert_in_delta 0.5, ingredient.quantity_low
    assert_nil ingredient.quantity_high
  end

  test 'imports non-numeric quantity with nil range columns' do
    markdown = "# Test\n\n## Step\n\n- Basil, a few leaves\n\nAdd."
    result = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @bread)
    ingredient = result.recipe.steps.first.ingredients.first

    assert_equal 'a few leaves', ingredient.quantity
    assert_nil ingredient.quantity_low
    assert_nil ingredient.quantity_high
  end
end
