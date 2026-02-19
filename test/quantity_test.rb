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

  def test_frozen
    q = Quantity[10, 'g']

    assert_predicate q, :frozen?
  end

  def test_deconstruct_for_pattern_matching
    q = Quantity[10, 'g']

    case q
    in [value, unit]
      assert_equal 10, value
      assert_equal 'g', unit
    end
  end

  def test_deconstruct_keys
    q = Quantity[10, 'g']

    case q
    in { value: v, unit: u }
      assert_equal 10, v
      assert_equal 'g', u
    end
  end
end
