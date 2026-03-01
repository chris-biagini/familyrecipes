# frozen_string_literal: true

require 'test_helper'

class CrossReferenceUpdaterTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen

    Category.find_or_create_by!(slug: 'bread', kitchen: @kitchen) do |cat|
      cat.name = 'Bread'
      cat.position = 0
    end

    @dough = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Pizza Dough

      Category: Bread

      ## Mix (combine ingredients)

      - Flour, 3 cups

      Mix together.
    MD

    @pizza = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Margherita Pizza

      Category: Bread

      ## Make dough.
      >>> @[Pizza Dough], 1

      ## Assemble (put it together)

      - Mozzarella, 8 oz

      Stretch dough and top.
    MD
  end

  test 'rename_references updates @[Old] to @[New] in referencing recipes' do
    CrossReferenceUpdater.rename_references(old_title: 'Pizza Dough', new_title: 'Neapolitan Dough',
                                            kitchen: @kitchen)

    @pizza.reload

    assert_includes @pizza.markdown_source, '@[Neapolitan Dough]'
    assert_not_includes @pizza.markdown_source, '@[Pizza Dough]'
  end

  test 'rename_references returns titles of updated recipes' do
    updated = CrossReferenceUpdater.rename_references(old_title: 'Pizza Dough', new_title: 'Neapolitan Dough',
                                                      kitchen: @kitchen)

    assert_includes updated, 'Margherita Pizza'
  end
end
