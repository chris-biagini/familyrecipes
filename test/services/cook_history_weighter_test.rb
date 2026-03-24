# frozen_string_literal: true

require 'test_helper'

class CookHistoryWeighterTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
  end

  test 'empty history returns empty hash' do
    result = CookHistoryWeighter.call([])

    assert_empty(result)
  end

  test 'single recent cook produces reduced weight' do
    entries = [CookHistoryEntry.create!(kitchen: @kitchen, recipe_slug: 'tacos', cooked_at: 1.day.ago)]
    result = CookHistoryWeighter.call(entries)

    assert_operator result['tacos'], :<, 1.0
    assert_operator result['tacos'], :>, 0.0
  end

  test 'cook from today produces maximum penalty' do
    entries = [CookHistoryEntry.create!(kitchen: @kitchen, recipe_slug: 'tacos', cooked_at: Time.current)]
    result = CookHistoryWeighter.call(entries)

    assert_in_delta 0.5, result['tacos'], 0.05
  end

  test 'multiple cooks for same recipe compound penalty' do
    single = [CookHistoryEntry.create!(kitchen: @kitchen, recipe_slug: 'tacos', cooked_at: 5.days.ago)]
    double = [
      CookHistoryEntry.create!(kitchen: @kitchen, recipe_slug: 'tacos-2', cooked_at: 5.days.ago),
      CookHistoryEntry.create!(kitchen: @kitchen, recipe_slug: 'tacos-2', cooked_at: 10.days.ago)
    ]

    single_weight = CookHistoryWeighter.call(single)['tacos']
    double_weight = CookHistoryWeighter.call(double)['tacos-2']

    assert_operator double_weight, :<, single_weight
  end

  test 'cook at 89 days contributes near-zero penalty' do
    entries = [CookHistoryEntry.create!(kitchen: @kitchen, recipe_slug: 'tacos', cooked_at: 89.days.ago)]
    result = CookHistoryWeighter.call(entries)

    assert_operator result['tacos'], :>, 0.99
  end

  test 'mixed recipes produce independent weights' do
    entries = [
      CookHistoryEntry.create!(kitchen: @kitchen, recipe_slug: 'tacos', cooked_at: 1.day.ago),
      CookHistoryEntry.create!(kitchen: @kitchen, recipe_slug: 'tacos', cooked_at: 5.days.ago),
      CookHistoryEntry.create!(kitchen: @kitchen, recipe_slug: 'bagels', cooked_at: 60.days.ago)
    ]
    result = CookHistoryWeighter.call(entries)

    assert_operator result['tacos'], :<, result['bagels']
  end

  test 'uses quadratic decay curve' do
    entries = [CookHistoryEntry.create!(kitchen: @kitchen, recipe_slug: 'tacos', cooked_at: 45.days.ago)]
    result = CookHistoryWeighter.call(entries)

    assert_in_delta 0.8, result['tacos'], 0.02
  end
end
