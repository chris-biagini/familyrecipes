require_relative 'test_helper'

class IngredientTest < Minitest::Test
  # Pluralization tests
  def test_pluralize_regular_word
    assert_equal ["apples"], Ingredient.pluralize("apple")
  end

  def test_pluralize_word_ending_in_s
    assert_equal ["glasses"], Ingredient.pluralize("glass")
  end

  def test_pluralize_word_ending_in_x
    assert_equal ["boxes"], Ingredient.pluralize("box")
  end

  def test_pluralize_word_ending_in_ch
    assert_equal ["peaches"], Ingredient.pluralize("peach")
  end

  def test_pluralize_word_ending_in_sh
    assert_equal ["dishes"], Ingredient.pluralize("dish")
  end

  def test_pluralize_word_ending_in_consonant_y
    assert_equal ["berries"], Ingredient.pluralize("berry")
  end

  def test_pluralize_word_ending_in_vowel_y
    assert_equal ["days"], Ingredient.pluralize("day")
  end

  def test_pluralize_word_ending_in_consonant_o
    assert_equal ["potatoes"], Ingredient.pluralize("potato")
  end

  def test_pluralize_irregular_leaf
    assert_equal ["leaves"], Ingredient.pluralize("leaf")
  end

  def test_pluralize_nil
    assert_equal [nil], Ingredient.pluralize(nil)
  end

  def test_pluralize_empty
    assert_equal [""], Ingredient.pluralize("")
  end

  # Singularization tests
  def test_singularize_regular_plural
    assert_equal ["apple"], Ingredient.singularize("apples")
  end

  def test_singularize_word_ending_in_ies
    assert_equal ["berry"], Ingredient.singularize("berries")
  end

  def test_singularize_word_ending_in_es_after_s
    assert_equal ["glass"], Ingredient.singularize("glasses")
  end

  def test_singularize_word_ending_in_es_after_ch
    assert_equal ["peach"], Ingredient.singularize("peaches")
  end

  def test_singularize_word_ending_in_oes
    assert_equal ["potato"], Ingredient.singularize("potatoes")
  end

  def test_singularize_irregular_leaves
    assert_equal ["leaf"], Ingredient.singularize("leaves")
  end

  # Quantity parsing tests
  def test_quantity_value_simple_number
    ingredient = Ingredient.new(name: "Flour", quantity: "250 g")
    assert_equal "250", ingredient.quantity_value
  end

  def test_quantity_value_decimal
    ingredient = Ingredient.new(name: "Salt", quantity: "3.5 g")
    assert_equal "3.5", ingredient.quantity_value
  end

  def test_quantity_value_fraction_half
    ingredient = Ingredient.new(name: "Butter", quantity: "1/2 cup")
    assert_equal "0.5", ingredient.quantity_value
  end

  def test_quantity_value_fraction_quarter
    ingredient = Ingredient.new(name: "Oil", quantity: "1/4 cup")
    assert_equal "0.25", ingredient.quantity_value
  end

  def test_quantity_value_range_takes_high_end
    ingredient = Ingredient.new(name: "Eggs", quantity: "2-3")
    assert_equal "3", ingredient.quantity_value
  end

  def test_quantity_value_nil_when_no_quantity
    ingredient = Ingredient.new(name: "Salt")
    assert_nil ingredient.quantity_value
  end

  def test_quantity_value_nil_when_empty_quantity
    ingredient = Ingredient.new(name: "Salt", quantity: "  ")
    assert_nil ingredient.quantity_value
  end

  def test_quantity_unit
    ingredient = Ingredient.new(name: "Flour", quantity: "250 g")
    assert_equal "g", ingredient.quantity_unit
  end

  def test_quantity_unit_passes_through_singular_clove
    ingredient = Ingredient.new(name: "Garlic", quantity: "4 clove")
    assert_equal "clove", ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_cloves_to_clove
    ingredient = Ingredient.new(name: "Garlic", quantity: "4 cloves")
    assert_equal "clove", ingredient.quantity_unit
  end

  def test_quantity_unit_nil_when_no_unit
    ingredient = Ingredient.new(name: "Eggs", quantity: "4")
    assert_nil ingredient.quantity_unit
  end

  # Fraction tests - 1/3, 2/3, 3/4
  def test_quantity_value_fraction_third
    ingredient = Ingredient.new(name: "Cream", quantity: "1/3 cup")
    assert_equal "0.333", ingredient.quantity_value
  end

  def test_quantity_value_fraction_two_thirds
    ingredient = Ingredient.new(name: "Cream", quantity: "2/3 cup")
    assert_equal "0.667", ingredient.quantity_value
  end

  def test_quantity_value_fraction_three_quarters
    ingredient = Ingredient.new(name: "Cream", quantity: "3/4 cup")
    assert_equal "0.75", ingredient.quantity_value
  end

  # Unit normalization tests - ounce/ounces -> oz
  def test_quantity_unit_normalizes_ounce
    ingredient = Ingredient.new(name: "Cheese", quantity: "3 ounce")
    assert_equal "oz", ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_ounces
    ingredient = Ingredient.new(name: "Cheese", quantity: "10 ounces")
    assert_equal "oz", ingredient.quantity_unit
  end

  # Expanded unit normalization tests
  def test_quantity_unit_downcases
    ingredient = Ingredient.new(name: "Butter", quantity: "2 Tbsp")
    assert_equal "tbsp", ingredient.quantity_unit
  end

  def test_quantity_unit_strips_trailing_period
    ingredient = Ingredient.new(name: "Salt", quantity: "1 tsp.")
    assert_equal "tsp", ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_tablespoon
    ingredient = Ingredient.new(name: "Oil", quantity: "2 tablespoons")
    assert_equal "tbsp", ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_teaspoon
    ingredient = Ingredient.new(name: "Salt", quantity: "1 teaspoon")
    assert_equal "tsp", ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_cups
    ingredient = Ingredient.new(name: "Flour", quantity: "2 cups")
    assert_equal "cup", ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_grams
    ingredient = Ingredient.new(name: "Sugar", quantity: "100 grams")
    assert_equal "g", ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_pounds
    ingredient = Ingredient.new(name: "Beef", quantity: "2 pounds")
    assert_equal "lb", ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_lbs
    ingredient = Ingredient.new(name: "Beef", quantity: "1 lbs")
    assert_equal "lb", ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_slices
    ingredient = Ingredient.new(name: "Bread", quantity: "2 slices")
    assert_equal "slice", ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_sticks
    ingredient = Ingredient.new(name: "Butter", quantity: "2 sticks")
    assert_equal "stick", ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_small_slices
    ingredient = Ingredient.new(name: "Bread", quantity: "8 small slices")
    assert_equal "slice", ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_tortillas
    ingredient = Ingredient.new(name: "Tortillas (corn)", quantity: "4 tortillas")
    assert_equal "tortilla", ingredient.quantity_unit
  end

  # Normalized name tests
  def test_normalized_name_returns_original_when_no_alias
    ingredient = Ingredient.new(name: "Flour")
    assert_equal "Flour", ingredient.normalized_name
  end

  def test_normalized_name_returns_canonical_when_alias_exists
    alias_map = { "flour (all-purpose)" => "Flour" }
    ingredient = Ingredient.new(name: "Flour (all-purpose)")
    assert_equal "Flour", ingredient.normalized_name(alias_map)
  end
end
