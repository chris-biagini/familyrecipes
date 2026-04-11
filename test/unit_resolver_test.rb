# frozen_string_literal: true

require_relative 'test_helper'

class UnitResolverTest < Minitest::Test
  def setup
    @flour = IngredientCatalog.new(
      ingredient_name: 'Flour (all-purpose)',
      basis_grams: 30, calories: 109.2, protein: 3.099, fat: 0.294,
      saturated_fat: 0.05, carbs: 22.893, fiber: 0.81, sodium: 0.6,
      density_grams: 125, density_volume: 1, density_unit: 'cup'
    )
    @eggs = IngredientCatalog.new(
      ingredient_name: 'Eggs',
      basis_grams: 50, calories: 71.5, protein: 6.28, fat: 4.755,
      portions: { '~unitless' => 50 }
    )
    @butter = IngredientCatalog.new(
      ingredient_name: 'Butter',
      basis_grams: 14, calories: 100.38, fat: 11.3554,
      density_grams: 227, density_volume: 1, density_unit: 'cup',
      portions: { 'stick' => 113.0 }
    )
    @olive_oil = IngredientCatalog.new(
      ingredient_name: 'Olive oil',
      basis_grams: 14, calories: 123.76, fat: 14,
      density_grams: 14, density_volume: 1, density_unit: 'tbsp'
    )
    @aisle_only = IngredientCatalog.new(
      ingredient_name: 'Celery', aisle: 'Produce'
    )
  end

  # --- to_grams: weight units ---

  def test_grams_passthrough
    resolver = Mirepoix::UnitResolver.new(@flour)

    assert_in_delta 500.0, resolver.to_grams(500, 'g')
  end

  def test_oz_conversion
    resolver = Mirepoix::UnitResolver.new(@butter)

    assert_in_delta 113.398, resolver.to_grams(4, 'oz'), 0.01
  end

  def test_lb_conversion
    resolver = Mirepoix::UnitResolver.new(@flour)

    assert_in_delta 453.592, resolver.to_grams(1, 'lb'), 0.01
  end

  def test_kg_conversion
    resolver = Mirepoix::UnitResolver.new(@flour)

    assert_in_delta 1000.0, resolver.to_grams(1, 'kg')
  end

  def test_weight_unit_case_insensitive
    resolver = Mirepoix::UnitResolver.new(@flour)

    assert_in_delta 500.0, resolver.to_grams(500, 'G')
  end

  # --- to_grams: bare count (nil unit) ---

  def test_bare_count_with_unitless_portion
    resolver = Mirepoix::UnitResolver.new(@eggs)

    assert_in_delta 150.0, resolver.to_grams(3, nil)
  end

  def test_bare_count_without_unitless_portion
    resolver = Mirepoix::UnitResolver.new(@flour)

    assert_nil resolver.to_grams(4, nil)
  end

  # --- to_grams: named portions ---

  def test_named_portion
    resolver = Mirepoix::UnitResolver.new(@butter)

    assert_in_delta 113.0, resolver.to_grams(1, 'stick')
  end

  def test_named_portion_case_insensitive
    resolver = Mirepoix::UnitResolver.new(@butter)

    assert_in_delta 113.0, resolver.to_grams(1, 'Stick')
  end

  # --- to_grams: volume with density ---

  def test_volume_with_density
    resolver = Mirepoix::UnitResolver.new(@flour)
    expected = 236.588 * (125.0 / 236.588)

    assert_in_delta expected, resolver.to_grams(1, 'cup'), 0.1
  end

  def test_volume_tbsp_with_density
    resolver = Mirepoix::UnitResolver.new(@olive_oil)
    expected = 2 * 14.787 * (14.0 / 14.787)

    assert_in_delta expected, resolver.to_grams(2, 'tbsp'), 0.1
  end

  def test_volume_without_density_returns_nil
    entry = IngredientCatalog.new(
      ingredient_name: 'NoDensity', basis_grams: 100, calories: 50
    )
    resolver = Mirepoix::UnitResolver.new(entry)

    assert_nil resolver.to_grams(1, 'cup')
  end

  # --- to_grams: unresolvable ---

  def test_unknown_unit_returns_nil
    resolver = Mirepoix::UnitResolver.new(@flour)

    assert_nil resolver.to_grams(2, 'bushels')
  end

  # --- resolvable? ---

  def test_resolvable_with_weight_unit
    resolver = Mirepoix::UnitResolver.new(@flour)

    assert resolver.resolvable?(1, 'g')
    assert resolver.resolvable?(1, 'cup')
  end

  def test_resolvable_bare_count_with_unitless
    resolver = Mirepoix::UnitResolver.new(@eggs)

    assert resolver.resolvable?(1, nil)
  end

  def test_not_resolvable_with_unknown_unit
    resolver = Mirepoix::UnitResolver.new(@flour)

    refute resolver.resolvable?(1, 'bushel')
  end

  def test_resolvable_with_density
    resolver = Mirepoix::UnitResolver.new(@olive_oil)

    assert resolver.resolvable?(1, 'cup')
  end

  def test_bare_count_not_resolvable_without_unitless
    resolver = Mirepoix::UnitResolver.new(@flour)

    refute resolver.resolvable?(1, nil)
  end

  # --- density ---

  def test_density_returns_grams_per_ml
    resolver = Mirepoix::UnitResolver.new(@flour)

    assert_in_delta 125.0 / 236.588, resolver.density, 0.001
  end

  def test_density_nil_without_density_fields
    resolver = Mirepoix::UnitResolver.new(@eggs)

    assert_nil resolver.density
  end

  def test_density_nil_with_zero_volume
    entry = IngredientCatalog.new(
      ingredient_name: 'Bad', basis_grams: 100,
      density_grams: 100, density_volume: 0, density_unit: 'cup'
    )
    resolver = Mirepoix::UnitResolver.new(entry)

    assert_nil resolver.density
  end

  # --- nil entry ---

  def test_nil_entry_weight_still_resolves
    resolver = Mirepoix::UnitResolver.new(nil)

    assert_in_delta 500.0, resolver.to_grams(500, 'g')
  end

  def test_nil_entry_non_weight_returns_nil
    resolver = Mirepoix::UnitResolver.new(nil)

    assert_nil resolver.to_grams(1, 'cup')
    assert_nil resolver.to_grams(1, nil)
    assert_nil resolver.to_grams(1, 'stick')
  end

  def test_nil_entry_resolvable_only_for_weight
    resolver = Mirepoix::UnitResolver.new(nil)

    assert resolver.resolvable?(1, 'g')
    refute resolver.resolvable?(1, 'cup')
    refute resolver.resolvable?(1, nil)
  end

  def test_nil_entry_density_is_nil
    resolver = Mirepoix::UnitResolver.new(nil)

    assert_nil resolver.density
  end

  # --- class predicates ---

  def test_weight_unit_predicate
    assert Mirepoix::UnitResolver.weight_unit?('g')
    assert Mirepoix::UnitResolver.weight_unit?('OZ')
    refute Mirepoix::UnitResolver.weight_unit?('cup')
    refute Mirepoix::UnitResolver.weight_unit?(nil)
  end

  def test_volume_unit_predicate
    assert Mirepoix::UnitResolver.volume_unit?('cup')
    assert Mirepoix::UnitResolver.volume_unit?('TSP')
    assert Mirepoix::UnitResolver.volume_unit?('fl oz')
    refute Mirepoix::UnitResolver.volume_unit?('g')
    refute Mirepoix::UnitResolver.volume_unit?(nil)
  end
end
