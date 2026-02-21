# frozen_string_literal: true

require_relative 'test_helper'

class InflectorTest < Minitest::Test
  # --- singular ---

  def test_singular_regular_s
    assert_equal 'carrot', FamilyRecipes::Inflector.singular('carrots')
  end

  def test_singular_ies_to_y
    assert_equal 'berry', FamilyRecipes::Inflector.singular('berries')
  end

  def test_singular_ses
    assert_equal 'glass', FamilyRecipes::Inflector.singular('glasses')
  end

  def test_singular_ches
    assert_equal 'peach', FamilyRecipes::Inflector.singular('peaches')
  end

  def test_singular_shes
    assert_equal 'dish', FamilyRecipes::Inflector.singular('dishes')
  end

  def test_singular_xes
    assert_equal 'box', FamilyRecipes::Inflector.singular('boxes')
  end

  def test_singular_zes
    assert_equal 'buzz', FamilyRecipes::Inflector.singular('buzzes')
  end

  def test_singular_oes
    assert_equal 'potato', FamilyRecipes::Inflector.singular('potatoes')
  end

  def test_singular_irregular_leaves
    assert_equal 'leaf', FamilyRecipes::Inflector.singular('leaves')
  end

  def test_singular_irregular_loaves
    assert_equal 'loaf', FamilyRecipes::Inflector.singular('loaves')
  end

  def test_singular_already_singular
    assert_equal 'carrot', FamilyRecipes::Inflector.singular('carrot')
  end

  def test_singular_preserves_capitalization
    assert_equal 'Carrot', FamilyRecipes::Inflector.singular('Carrots')
  end

  def test_singular_irregular_preserves_capitalization
    assert_equal 'Leaf', FamilyRecipes::Inflector.singular('Leaves')
  end

  def test_singular_nil
    assert_nil FamilyRecipes::Inflector.singular(nil)
  end

  def test_singular_empty
    assert_equal '', FamilyRecipes::Inflector.singular('')
  end

  def test_singular_uncountable_unchanged
    assert_equal 'butter', FamilyRecipes::Inflector.singular('butter')
  end

  def test_singular_ss_unchanged
    assert_equal 'grass', FamilyRecipes::Inflector.singular('grass')
  end

  # --- plural ---

  def test_plural_regular_s
    assert_equal 'carrots', FamilyRecipes::Inflector.plural('carrot')
  end

  def test_plural_consonant_y_to_ies
    assert_equal 'berries', FamilyRecipes::Inflector.plural('berry')
  end

  def test_plural_vowel_y_adds_s
    assert_equal 'days', FamilyRecipes::Inflector.plural('day')
  end

  def test_plural_sibilant_s
    assert_equal 'glasses', FamilyRecipes::Inflector.plural('glass')
  end

  def test_plural_sibilant_x
    assert_equal 'boxes', FamilyRecipes::Inflector.plural('box')
  end

  def test_plural_sibilant_z
    assert_equal 'buzzes', FamilyRecipes::Inflector.plural('buzz')
  end

  def test_plural_sibilant_ch
    assert_equal 'peaches', FamilyRecipes::Inflector.plural('peach')
  end

  def test_plural_sibilant_sh
    assert_equal 'dishes', FamilyRecipes::Inflector.plural('dish')
  end

  def test_plural_consonant_o
    assert_equal 'potatoes', FamilyRecipes::Inflector.plural('potato')
  end

  def test_plural_irregular_leaf
    assert_equal 'leaves', FamilyRecipes::Inflector.plural('leaf')
  end

  def test_plural_irregular_loaf
    assert_equal 'loaves', FamilyRecipes::Inflector.plural('loaf')
  end

  def test_plural_irregular_taco
    assert_equal 'tacos', FamilyRecipes::Inflector.plural('taco')
  end

  def test_plural_abbreviated_form_unchanged
    assert_equal 'ml', FamilyRecipes::Inflector.plural('ml')
  end

  def test_plural_preserves_capitalization
    assert_equal 'Carrots', FamilyRecipes::Inflector.plural('Carrot')
  end

  def test_plural_irregular_preserves_capitalization
    assert_equal 'Leaves', FamilyRecipes::Inflector.plural('Leaf')
  end

  def test_plural_nil
    assert_nil FamilyRecipes::Inflector.plural(nil)
  end

  def test_plural_empty
    assert_equal '', FamilyRecipes::Inflector.plural('')
  end

  def test_plural_uncountable_unchanged
    assert_equal 'butter', FamilyRecipes::Inflector.plural('butter')
  end

  # --- uncountable? ---

  def test_uncountable_true_for_butter
    assert FamilyRecipes::Inflector.uncountable?('butter')
  end

  def test_uncountable_true_case_insensitive
    assert FamilyRecipes::Inflector.uncountable?('Butter')
  end

  def test_uncountable_true_for_flour
    assert FamilyRecipes::Inflector.uncountable?('flour')
  end

  def test_uncountable_true_for_cream_cheese
    assert FamilyRecipes::Inflector.uncountable?('cream cheese')
  end

  def test_uncountable_true_for_heavy_cream
    assert FamilyRecipes::Inflector.uncountable?('heavy cream')
  end

  def test_uncountable_false_for_carrot
    refute FamilyRecipes::Inflector.uncountable?('carrot')
  end

  def test_uncountable_false_for_egg
    refute FamilyRecipes::Inflector.uncountable?('egg')
  end

  # --- normalize_unit ---

  def test_normalize_unit_grams_to_g
    assert_equal 'g', FamilyRecipes::Inflector.normalize_unit('grams')
  end

  def test_normalize_unit_gram_to_g
    assert_equal 'g', FamilyRecipes::Inflector.normalize_unit('gram')
  end

  def test_normalize_unit_g_to_g
    assert_equal 'g', FamilyRecipes::Inflector.normalize_unit('g')
  end

  def test_normalize_unit_tablespoons_to_tbsp
    assert_equal 'tbsp', FamilyRecipes::Inflector.normalize_unit('tablespoons')
  end

  def test_normalize_unit_tablespoon_to_tbsp
    assert_equal 'tbsp', FamilyRecipes::Inflector.normalize_unit('tablespoon')
  end

  def test_normalize_unit_tbsp_passthrough
    assert_equal 'tbsp', FamilyRecipes::Inflector.normalize_unit('tbsp')
  end

  def test_normalize_unit_teaspoons_to_tsp
    assert_equal 'tsp', FamilyRecipes::Inflector.normalize_unit('teaspoons')
  end

  def test_normalize_unit_teaspoon_to_tsp
    assert_equal 'tsp', FamilyRecipes::Inflector.normalize_unit('teaspoon')
  end

  def test_normalize_unit_ounces_to_oz
    assert_equal 'oz', FamilyRecipes::Inflector.normalize_unit('ounces')
  end

  def test_normalize_unit_ounce_to_oz
    assert_equal 'oz', FamilyRecipes::Inflector.normalize_unit('ounce')
  end

  def test_normalize_unit_pounds_to_lb
    assert_equal 'lb', FamilyRecipes::Inflector.normalize_unit('pounds')
  end

  def test_normalize_unit_lbs_to_lb
    assert_equal 'lb', FamilyRecipes::Inflector.normalize_unit('lbs')
  end

  def test_normalize_unit_liters_to_l
    assert_equal 'l', FamilyRecipes::Inflector.normalize_unit('liters')
  end

  def test_normalize_unit_liter_to_l
    assert_equal 'l', FamilyRecipes::Inflector.normalize_unit('liter')
  end

  def test_normalize_unit_ml_passthrough
    assert_equal 'ml', FamilyRecipes::Inflector.normalize_unit('ml')
  end

  def test_normalize_unit_discrete_plural_cloves
    assert_equal 'clove', FamilyRecipes::Inflector.normalize_unit('cloves')
  end

  def test_normalize_unit_discrete_plural_cups
    assert_equal 'cup', FamilyRecipes::Inflector.normalize_unit('cups')
  end

  def test_normalize_unit_discrete_plural_slices
    assert_equal 'slice', FamilyRecipes::Inflector.normalize_unit('slices')
  end

  def test_normalize_unit_singular_passthrough
    assert_equal 'cup', FamilyRecipes::Inflector.normalize_unit('cup')
  end

  def test_normalize_unit_strips_trailing_period
    assert_equal 'tsp', FamilyRecipes::Inflector.normalize_unit('tsp.')
  end

  def test_normalize_unit_downcases
    assert_equal 'tbsp', FamilyRecipes::Inflector.normalize_unit('Tbsp')
  end

  def test_normalize_unit_special_chars_go
    assert_equal 'go', FamilyRecipes::Inflector.normalize_unit('gō')
  end

  def test_normalize_unit_multi_word_small_slices
    assert_equal 'slice', FamilyRecipes::Inflector.normalize_unit('small slices')
  end

  def test_normalize_unit_strips_whitespace
    assert_equal 'g', FamilyRecipes::Inflector.normalize_unit('  grams  ')
  end

  def test_normalize_unit_discrete_plural_cans
    assert_equal 'can', FamilyRecipes::Inflector.normalize_unit('cans')
  end

  def test_normalize_unit_discrete_plural_bunches
    assert_equal 'bunch', FamilyRecipes::Inflector.normalize_unit('bunches')
  end

  def test_normalize_unit_discrete_plural_tortillas
    assert_equal 'tortilla', FamilyRecipes::Inflector.normalize_unit('tortillas')
  end

  def test_normalize_unit_discrete_plural_pieces
    assert_equal 'piece', FamilyRecipes::Inflector.normalize_unit('pieces')
  end

  def test_normalize_unit_discrete_plural_stalks
    assert_equal 'stalk', FamilyRecipes::Inflector.normalize_unit('stalks')
  end

  def test_normalize_unit_discrete_plural_sticks
    assert_equal 'stick', FamilyRecipes::Inflector.normalize_unit('sticks')
  end

  def test_normalize_unit_discrete_plural_items
    assert_equal 'item', FamilyRecipes::Inflector.normalize_unit('items')
  end

  # --- unit_display ---

  def test_unit_display_abbreviated_never_pluralizes
    assert_equal 'g', FamilyRecipes::Inflector.unit_display('g', 100)
  end

  def test_unit_display_abbreviated_singular
    assert_equal 'g', FamilyRecipes::Inflector.unit_display('g', 1)
  end

  def test_unit_display_tbsp_never_pluralizes
    assert_equal 'tbsp', FamilyRecipes::Inflector.unit_display('tbsp', 3)
  end

  def test_unit_display_oz_never_pluralizes
    assert_equal 'oz', FamilyRecipes::Inflector.unit_display('oz', 8)
  end

  def test_unit_display_lb_never_pluralizes
    assert_equal 'lb', FamilyRecipes::Inflector.unit_display('lb', 2)
  end

  def test_unit_display_full_word_plural
    assert_equal 'cups', FamilyRecipes::Inflector.unit_display('cup', 2)
  end

  def test_unit_display_full_word_singular
    assert_equal 'cup', FamilyRecipes::Inflector.unit_display('cup', 1)
  end

  def test_unit_display_clove_plural
    assert_equal 'cloves', FamilyRecipes::Inflector.unit_display('clove', 4)
  end

  def test_unit_display_clove_singular
    assert_equal 'clove', FamilyRecipes::Inflector.unit_display('clove', 1)
  end

  def test_unit_display_slice_plural
    assert_equal 'slices', FamilyRecipes::Inflector.unit_display('slice', 3)
  end

  # --- name_for_grocery ---

  def test_name_for_grocery_countable_becomes_plural
    assert_equal 'Carrots', FamilyRecipes::Inflector.name_for_grocery('Carrot')
  end

  def test_name_for_grocery_uncountable_unchanged
    assert_equal 'Butter', FamilyRecipes::Inflector.name_for_grocery('Butter')
  end

  def test_name_for_grocery_flour_uncountable
    assert_equal 'Flour', FamilyRecipes::Inflector.name_for_grocery('Flour')
  end

  def test_name_for_grocery_qualified_uncountable
    assert_equal 'Flour (all-purpose)', FamilyRecipes::Inflector.name_for_grocery('Flour (all-purpose)')
  end

  def test_name_for_grocery_qualified_countable
    assert_equal 'Tomatoes (fresh)', FamilyRecipes::Inflector.name_for_grocery('Tomato (fresh)')
  end

  def test_name_for_grocery_irregular
    assert_equal 'Loaves', FamilyRecipes::Inflector.name_for_grocery('Loaf')
  end

  # --- name_for_count ---

  def test_name_for_count_singular_at_one
    assert_equal 'carrot', FamilyRecipes::Inflector.name_for_count('carrot', 1)
  end

  def test_name_for_count_plural_at_two
    assert_equal 'carrots', FamilyRecipes::Inflector.name_for_count('carrot', 2)
  end

  def test_name_for_count_plural_at_zero
    assert_equal 'carrots', FamilyRecipes::Inflector.name_for_count('carrot', 0)
  end

  def test_name_for_count_uncountable_unchanged_at_any_count
    assert_equal 'butter', FamilyRecipes::Inflector.name_for_count('butter', 5)
  end

  def test_name_for_count_uncountable_unchanged_at_one
    assert_equal 'butter', FamilyRecipes::Inflector.name_for_count('butter', 1)
  end

  def test_name_for_count_irregular
    assert_equal 'loaves', FamilyRecipes::Inflector.name_for_count('loaf', 2)
  end

  def test_name_for_count_preserves_case
    assert_equal 'Carrots', FamilyRecipes::Inflector.name_for_count('Carrot', 2)
  end

  def test_name_for_count_qualified_uncountable
    assert_equal 'Flour (all-purpose)', FamilyRecipes::Inflector.name_for_count('Flour (all-purpose)', 5)
  end

  def test_name_for_count_qualified_countable
    assert_equal 'Tomatoes (fresh)', FamilyRecipes::Inflector.name_for_count('Tomato (fresh)', 2)
  end

  def test_name_for_count_qualified_countable_singular
    assert_equal 'Tomato (fresh)', FamilyRecipes::Inflector.name_for_count('Tomato (fresh)', 1)
  end
end
