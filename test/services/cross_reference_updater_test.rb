# frozen_string_literal: true

require 'test_helper'

class CrossReferenceUpdaterTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category(name: 'Bread')

    @dough = MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category).recipe
      # Pizza Dough


      ## Mix (combine ingredients)

      - Flour, 3 cups

      Mix together.
    MD

    @pizza = MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category).recipe
      # Margherita Pizza


      ## Make dough.
      > @[Pizza Dough], 1

      ## Assemble (put it together)

      - Mozzarella, 8 oz

      Stretch dough and top.
    MD
  end

  test 'rename_references updates cross-reference target titles in referencing recipes' do
    CrossReferenceUpdater.rename_references(old_title: 'Pizza Dough', new_title: 'Neapolitan Dough',
                                            kitchen: @kitchen)

    @pizza.reload
    xref = @pizza.cross_references.find_by(target_title: 'Neapolitan Dough')

    assert xref, 'cross-reference to Neapolitan Dough should exist'
    assert_nil @pizza.cross_references.find_by(target_title: 'Pizza Dough')
  end

  test 'rename_references returns titles of updated recipes' do
    updated = CrossReferenceUpdater.rename_references(old_title: 'Pizza Dough', new_title: 'Neapolitan Dough',
                                                      kitchen: @kitchen)

    assert_includes updated, 'Margherita Pizza'
  end

  test 'rename_references matches when cross-reference has curly apostrophe' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Grandma's Dough

      ## Mix

      - Flour, 3 cups

      Mix together.
    MD

    # Simulate a cross-reference stored with curly apostrophe in target_title.
    # RecipeSerializer will emit @[Grandma\u2019s Dough] in the generated
    # markdown, but @recipe.title is "Grandma's Dough" (straight).
    pizza = MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category).recipe
      # Sunday Pizza

      ## Make dough
      > @[Grandma's Dough], 1

      ## Assemble

      - Cheese, 8 oz

      Top it.
    MD

    xref = pizza.steps.flat_map(&:cross_references).first
    xref.update_column(:target_title, "Grandma\u2019s Dough")

    CrossReferenceUpdater.rename_references(old_title: "Grandma's Dough",
                                            new_title: "Nana's Dough",
                                            kitchen: @kitchen)

    pizza.reload
    assert pizza.cross_references.find_by(target_title: "Nana's Dough"),
           'cross-reference should be updated despite apostrophe mismatch'
  end

  test 'rename_references preserves non-cross-reference prose unchanged' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Grandma's Dough

      ## Mix

      - Flour, 3 cups

      Mix together.
    MD

    pizza = MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category).recipe
      # Sunday Pizza

      ## Make dough
      > @[Grandma's Dough], 1

      ## Assemble

      - Cheese, 8 oz

      Grandma\u2019s tip: stretch gently.
    MD

    xref = pizza.steps.flat_map(&:cross_references).first
    xref.update_column(:target_title, "Grandma\u2019s Dough")

    CrossReferenceUpdater.rename_references(old_title: "Grandma's Dough",
                                            new_title: "Nana's Dough",
                                            kitchen: @kitchen)

    pizza.reload
    step = pizza.steps.find_by(title: 'Assemble')
    assert_includes step.instructions, "\u2019",
                    'curly apostrophe in prose should be preserved'
  end
end
