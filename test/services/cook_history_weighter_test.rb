# frozen_string_literal: true

require 'test_helper'

class CookHistoryWeighterTest < ActiveSupport::TestCase
  test 'empty history returns empty hash' do
    result = CookHistoryWeighter.call([])

    assert_empty(result)
  end

  test 'single recent cook produces reduced weight' do
    history = [{ 'slug' => 'tacos', 'at' => 1.day.ago.iso8601 }]
    result = CookHistoryWeighter.call(history)

    assert_operator result['tacos'], :<, 1.0
    assert_operator result['tacos'], :>, 0.0
  end

  test 'cook from today produces maximum penalty' do
    history = [{ 'slug' => 'tacos', 'at' => Time.current.iso8601 }]
    result = CookHistoryWeighter.call(history)

    assert_in_delta 0.5, result['tacos'], 0.05
  end

  test 'multiple cooks for same recipe compound penalty' do
    single = [{ 'slug' => 'tacos', 'at' => 5.days.ago.iso8601 }]
    double = [
      { 'slug' => 'tacos', 'at' => 5.days.ago.iso8601 },
      { 'slug' => 'tacos', 'at' => 10.days.ago.iso8601 }
    ]

    single_weight = CookHistoryWeighter.call(single)['tacos']
    double_weight = CookHistoryWeighter.call(double)['tacos']

    assert_operator double_weight, :<, single_weight
  end

  test 'cook at 89 days contributes near-zero penalty' do
    history = [{ 'slug' => 'tacos', 'at' => 89.days.ago.iso8601 }]
    result = CookHistoryWeighter.call(history)

    assert_operator result['tacos'], :>, 0.99
  end

  test 'mixed recipes produce independent weights' do
    history = [
      { 'slug' => 'tacos', 'at' => 1.day.ago.iso8601 },
      { 'slug' => 'tacos', 'at' => 5.days.ago.iso8601 },
      { 'slug' => 'bagels', 'at' => 60.days.ago.iso8601 }
    ]
    result = CookHistoryWeighter.call(history)

    assert_operator result['tacos'], :<, result['bagels']
  end

  test 'uses quadratic decay curve' do
    # At 45 days, (90-45)/90 = 0.5, squared = 0.25
    # weight = 1/(1+0.25) = 0.8
    history = [{ 'slug' => 'tacos', 'at' => 45.days.ago.iso8601 }]
    result = CookHistoryWeighter.call(history)

    assert_in_delta 0.8, result['tacos'], 0.02
  end
end
