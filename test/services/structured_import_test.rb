# frozen_string_literal: true

require 'test_helper'

class StructuredImportTest < ActiveSupport::TestCase
  setup do
    create_kitchen_and_user
  end

  test 'import_from_structure creates recipe from IR hash' do
    ir = {
      title: 'Structured Recipe',
      description: 'Created from JSON.',
      front_matter: { serves: '4', category: 'Basics', tags: %w[test] },
      steps: [
        {
          tldr: 'Mix.',
          ingredients: [
            { name: 'Flour', quantity: '2 cups', prep_note: nil },
            { name: 'Salt', quantity: nil, prep_note: nil }
          ],
          instructions: 'Combine dry ingredients.',
          cross_reference: nil
        }
      ],
      footer: nil
    }

    result = MarkdownImporter.import_from_structure(ir, kitchen: @kitchen, category: nil)
    recipe = result.recipe

    assert_equal 'Structured Recipe', recipe.title
    assert_equal 'Created from JSON.', recipe.description
    assert_equal 4, recipe.serves
    assert_equal 1, recipe.steps.size
    assert_equal 2, recipe.steps.first.ingredients.size
    assert_equal 'Flour', recipe.steps.first.ingredients.first.name
    assert_equal '2', recipe.steps.first.ingredients.first.quantity
    assert_equal 'cups', recipe.steps.first.ingredients.first.unit
    assert_includes recipe.markdown_source, '# Structured Recipe'
    assert_includes recipe.markdown_source, '- Flour, 2 cups'
  end

  test 'import_from_structure resolves category from front matter' do
    ir = {
      title: 'Categorized',
      description: nil,
      front_matter: { category: 'Desserts' },
      steps: [
        { tldr: 'Bake.', ingredients: [{ name: 'Sugar', quantity: nil, prep_note: nil }],
          instructions: 'Bake.', cross_reference: nil }
      ],
      footer: nil
    }

    result = MarkdownImporter.import_from_structure(ir, kitchen: @kitchen, category: nil)

    assert_equal 'Desserts', result.recipe.category.name
  end

  test 'import_from_structure handles cross-reference steps' do
    ir = {
      title: 'With Xref',
      description: nil,
      front_matter: {},
      steps: [
        {
          tldr: 'Import dough.',
          ingredients: [],
          instructions: nil,
          cross_reference: { target_title: 'Pizza Dough', multiplier: 0.5, prep_note: 'Halve.' }
        }
      ],
      footer: nil
    }

    result = MarkdownImporter.import_from_structure(ir, kitchen: @kitchen, category: nil)
    xref = result.recipe.steps.first.cross_references.first

    assert_equal 'Pizza Dough', xref.target_title
    assert_in_delta 0.5, xref.multiplier
    assert_equal 'Halve.', xref.prep_note
  end

  test 'import_from_structure generates valid markdown_source' do
    ir = {
      title: 'Round Trip',
      description: 'Test round-trip.',
      front_matter: { makes: '12 rolls', serves: '4' },
      steps: [
        { tldr: 'Mix.', ingredients: [{ name: 'Flour', quantity: '3 cups', prep_note: nil }],
          instructions: 'Mix well.', cross_reference: nil }
      ],
      footer: 'Notes here.'
    }

    result = MarkdownImporter.import_from_structure(ir, kitchen: @kitchen, category: nil)
    source = result.recipe.markdown_source

    assert source.start_with?('# Round Trip')
    assert_includes source, 'Makes: 12 rolls'
    assert_includes source, 'Serves: 4'
    assert_includes source, '## Mix.'
    assert_includes source, '- Flour, 3 cups'
    assert_includes source, '---'
    assert_includes source, 'Notes here.'
  end
end
