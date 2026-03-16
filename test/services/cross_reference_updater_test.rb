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
end
