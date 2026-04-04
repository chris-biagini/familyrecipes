# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class QuickBitesWriteServiceTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    setup_test_kitchen
  end

  test 'update_from_structure creates QuickBite records' do
    structure = {
      categories: [
        { name: 'Snacks', items: [
          { name: 'PB&J', ingredients: ['Bread', 'Peanut Butter', 'Jelly'] },
          { name: 'Goldfish', ingredients: %w[Goldfish] }
        ] }
      ]
    }

    QuickBitesWriteService.update_from_structure(kitchen: @kitchen, structure:)

    assert_equal 2, @kitchen.quick_bites.count
    pbj = @kitchen.quick_bites.find_by(title: 'PB&J')

    assert_equal ['Bread', 'Peanut Butter', 'Jelly'], pbj.quick_bite_ingredients.order(:position).pluck(:name)
    assert_equal 'Snacks', pbj.category.name
  end

  test 'update_from_structure replaces all existing QBs' do
    cat = Category.find_or_create_for(@kitchen, 'Snacks')
    QuickBite.create!(title: 'Old Item', category: cat, position: 0)

    structure = {
      categories: [
        { name: 'Snacks', items: [
          { name: 'New Item', ingredients: %w[Chips] }
        ] }
      ]
    }

    QuickBitesWriteService.update_from_structure(kitchen: @kitchen, structure:)

    assert_equal ['New Item'], @kitchen.quick_bites.pluck(:title)
  end

  test 'update with plaintext creates AR records' do
    content = "## Snacks\n- Hummus with Pretzels: Hummus, Pretzels\n- Goldfish\n"

    result = QuickBitesWriteService.update(kitchen: @kitchen, content:)

    assert_equal 2, @kitchen.quick_bites.count
    assert_empty result.warnings
  end

  test 'update with nil content clears all QBs' do
    cat = Category.find_or_create_for(@kitchen, 'Snacks')
    QuickBite.create!(title: 'Test', category: cat, position: 0)

    QuickBitesWriteService.update(kitchen: @kitchen, content: nil)

    assert_equal 0, @kitchen.quick_bites.count
  end

  test 'update_from_structure creates category if it does not exist' do
    structure = {
      categories: [
        { name: 'New Category', items: [
          { name: 'Test', ingredients: %w[Stuff] }
        ] }
      ]
    }

    QuickBitesWriteService.update_from_structure(kitchen: @kitchen, structure:)

    assert @kitchen.categories.exists?(name: 'New Category')
  end

  test 'update returns warnings from parser' do
    result = QuickBitesWriteService.update(
      kitchen: @kitchen, content: "## Snacks\n- Goldfish\ngarbage"
    )

    assert_equal 1, result.warnings.size
    assert_match(/line 3/i, result.warnings.first)
  end

  test 'update returns empty warnings for valid content' do
    result = QuickBitesWriteService.update(
      kitchen: @kitchen, content: "## Snacks\n- Goldfish"
    )

    assert_empty result.warnings
  end

  test 'update broadcasts to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      QuickBitesWriteService.update(kitchen: @kitchen, content: "## Snacks\n- Goldfish")
    end
  end

  test 'update_from_structure preserves meal plan selections across ID changes' do
    cat = Category.find_or_create_for(@kitchen, 'Snacks')
    qb1 = QuickBite.create!(title: 'PB&J', category: cat, position: 0)
    qb2 = QuickBite.create!(title: 'Goldfish', category: cat, position: 1)

    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'QuickBite', selectable_id: qb1.id.to_s)
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'QuickBite', selectable_id: qb2.id.to_s)

    structure = {
      categories: [
        { name: 'Snacks', items: [
          { name: 'PB&J', ingredients: ['Bread', 'Peanut Butter'] },
          { name: 'Goldfish', ingredients: %w[Goldfish] },
          { name: 'Trail Mix', ingredients: %w[Nuts Raisins] }
        ] }
      ]
    }

    QuickBitesWriteService.update_from_structure(kitchen: @kitchen, structure:)

    new_pbj = @kitchen.quick_bites.find_by(title: 'PB&J')
    new_goldfish = @kitchen.quick_bites.find_by(title: 'Goldfish')
    selected_ids = MealPlanSelection.quick_bite_ids_for(@kitchen).to_set

    assert_includes selected_ids, new_pbj.id
    assert_includes selected_ids, new_goldfish.id
    assert_equal 2, selected_ids.size
  end

  test 'update preserves meal plan selections for renamed quick bites that still exist' do
    cat = Category.find_or_create_for(@kitchen, 'Snacks')
    qb = QuickBite.create!(title: 'Old Name', category: cat, position: 0)
    MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'QuickBite', selectable_id: qb.id.to_s)

    structure = {
      categories: [
        { name: 'Snacks', items: [
          { name: 'New Name', ingredients: %w[Stuff] }
        ] }
      ]
    }

    QuickBitesWriteService.update_from_structure(kitchen: @kitchen, structure:)

    selected_ids = MealPlanSelection.quick_bite_ids_for(@kitchen)

    assert_empty selected_ids, 'selection for deleted quick bite should not persist'
  end

  test 'update skips broadcast when batching' do
    broadcast_count = 0
    @kitchen.define_singleton_method(:broadcast_update) { broadcast_count += 1 }
    Kitchen.stub(:batching?, true) do
      QuickBitesWriteService.update(kitchen: @kitchen, content: "## Snacks\n- Goldfish")
    end

    assert_equal 0, broadcast_count
  end
end
