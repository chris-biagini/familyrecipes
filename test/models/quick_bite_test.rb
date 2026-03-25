# frozen_string_literal: true

require 'test_helper'

class QuickBiteTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    @category = Category.find_or_create_for(@kitchen, 'Snacks')
  end

  test 'requires title' do
    qb = QuickBite.new(category: @category, position: 0)

    assert_not qb.valid?
    assert_includes qb.errors[:title], "can't be blank"
  end

  test 'requires category' do
    qb = QuickBite.new(title: 'Test', position: 0)

    assert_not qb.valid?
    assert_includes qb.errors[:category], 'must exist'
  end

  test 'enforces unique title within kitchen' do
    QuickBite.create!(title: 'PB&J', category: @category, position: 0)
    dup = QuickBite.new(title: 'PB&J', category: @category, position: 1)

    assert_not dup.valid?
  end

  test 'ingredients_with_quantities returns name-nil pairs' do
    qb = QuickBite.create!(title: 'PB&J', category: @category, position: 0)
    qb.quick_bite_ingredients.create!(name: 'Bread', position: 0)
    qb.quick_bite_ingredients.create!(name: 'Peanut Butter', position: 1)

    expected = [['Bread', [nil]], ['Peanut Butter', [nil]]]

    assert_equal expected, qb.ingredients_with_quantities
  end

  test 'all_ingredient_names returns unique names' do
    qb = QuickBite.create!(title: 'PB&J', category: @category, position: 0)
    qb.quick_bite_ingredients.create!(name: 'Bread', position: 0)
    qb.quick_bite_ingredients.create!(name: 'Bread', position: 1)
    qb.quick_bite_ingredients.create!(name: 'Peanut Butter', position: 2)

    assert_equal ['Bread', 'Peanut Butter'], qb.all_ingredient_names
  end

  test 'all_ingredient_names preserves position order' do
    qb = QuickBite.create!(title: 'PB&J', category: @category, position: 0)
    qb.quick_bite_ingredients.create!(name: 'Peanut Butter', position: 0)
    qb.quick_bite_ingredients.create!(name: 'Bread', position: 1)

    assert_equal ['Peanut Butter', 'Bread'], qb.all_ingredient_names
  end

  test 'scoped to kitchen via acts_as_tenant' do
    QuickBite.create!(title: 'Tacos', category: @category, position: 0)

    other_kitchen = nil
    with_multi_kitchen do
      other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    end
    ActsAsTenant.current_tenant = other_kitchen

    assert_empty QuickBite.all
  end
end
