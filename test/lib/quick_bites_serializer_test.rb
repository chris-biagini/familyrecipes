# frozen_string_literal: true

require 'test_helper'

class QuickBitesSerializerFromRecordsTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
  end

  test 'from_records produces IR from AR models' do
    category = Category.find_or_create_for(@kitchen, 'Snacks')
    qb1 = QuickBite.create!(title: 'Hummus with Pretzels', category:, position: 0)
    qb1.quick_bite_ingredients.create!(
      [
        { name: 'Hummus', position: 0 },
        { name: 'Pretzels', position: 1 }
      ]
    )
    qb2 = QuickBite.create!(title: 'Goldfish', category:, position: 1)
    qb2.quick_bite_ingredients.create!(name: 'Goldfish', position: 0)

    ir = FamilyRecipes::QuickBitesSerializer.from_records(@kitchen)

    assert_equal 1, ir[:categories].size
    cat = ir[:categories].first

    assert_equal 'Snacks', cat[:name]
    assert_equal 2, cat[:items].size
    assert_equal({ name: 'Hummus with Pretzels', ingredients: %w[Hummus Pretzels] }, cat[:items].first)
    assert_equal({ name: 'Goldfish', ingredients: %w[Goldfish] }, cat[:items].last)
  end

  test 'from_records round-trips through serialize' do
    category = Category.find_or_create_for(@kitchen, 'Snacks')
    qb = QuickBite.create!(title: 'PB&J', category:, position: 0)
    qb.quick_bite_ingredients.create!(
      [
        { name: 'Bread', position: 0 },
        { name: 'Peanut Butter', position: 1 },
        { name: 'Jelly', position: 2 }
      ]
    )

    ir = FamilyRecipes::QuickBitesSerializer.from_records(@kitchen)
    plaintext = FamilyRecipes::QuickBitesSerializer.serialize(ir)

    assert_includes plaintext, '## Snacks'
    assert_includes plaintext, '- PB&J: Bread, Peanut Butter, Jelly'
  end
end
