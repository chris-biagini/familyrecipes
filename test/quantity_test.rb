# frozen_string_literal: true

require_relative 'test_helper'

class QuantityTest < Minitest::Test
  def test_creates_with_value_and_unit
    q = Quantity[10, 'g']

    assert_equal 10, q.value
    assert_equal 'g', q.unit
  end

  def test_creates_with_nil_unit
    q = Quantity[3, nil]

    assert_equal 3, q.value
    assert_nil q.unit
  end

  def test_equality
    assert_equal Quantity[10, 'g'], Quantity[10, 'g']
    refute_equal Quantity[10, 'g'], Quantity[10, 'oz']
    refute_equal Quantity[10, 'g'], Quantity[5, 'g']
  end

  def test_to_json_serializes_as_array
    require 'json'

    assert_equal [10, 'g'].to_json, Quantity[10, 'g'].to_json
  end
end
