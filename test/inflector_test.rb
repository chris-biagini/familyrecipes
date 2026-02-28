# frozen_string_literal: true

require_relative 'test_helper'

class InflectorTest < Minitest::Test
  # --- safe_plural ---

  def test_safe_plural_known_unit
    assert_equal 'cups', FamilyRecipes::Inflector.safe_plural('cup')
  end

  def test_safe_plural_known_ingredient
    assert_equal 'eggs', FamilyRecipes::Inflector.safe_plural('egg')
  end

  def test_safe_plural_known_yield_noun
    assert_equal 'loaves', FamilyRecipes::Inflector.safe_plural('loaf')
  end

  def test_safe_plural_unknown_word_passes_through
    assert_equal 'oregano', FamilyRecipes::Inflector.safe_plural('oregano')
  end

  def test_safe_plural_preserves_capitalization
    assert_equal 'Eggs', FamilyRecipes::Inflector.safe_plural('Egg')
  end

  def test_safe_plural_already_plural_passes_through
    assert_equal 'eggs', FamilyRecipes::Inflector.safe_plural('eggs')
  end

  def test_safe_plural_abbreviated_passes_through
    assert_equal 'g', FamilyRecipes::Inflector.safe_plural('g')
  end

  def test_safe_plural_nil
    assert_nil FamilyRecipes::Inflector.safe_plural(nil)
  end

  def test_safe_plural_empty
    assert_equal '', FamilyRecipes::Inflector.safe_plural('')
  end

  # --- safe_singular ---

  def test_safe_singular_known_unit
    assert_equal 'cup', FamilyRecipes::Inflector.safe_singular('cups')
  end

  def test_safe_singular_known_ingredient
    assert_equal 'egg', FamilyRecipes::Inflector.safe_singular('eggs')
  end

  def test_safe_singular_known_yield_noun
    assert_equal 'loaf', FamilyRecipes::Inflector.safe_singular('loaves')
  end

  def test_safe_singular_unknown_word_passes_through
    assert_equal 'paprikas', FamilyRecipes::Inflector.safe_singular('paprikas')
  end

  def test_safe_singular_preserves_capitalization
    assert_equal 'Egg', FamilyRecipes::Inflector.safe_singular('Eggs')
  end

  def test_safe_singular_already_singular_passes_through
    assert_equal 'cup', FamilyRecipes::Inflector.safe_singular('cup')
  end

  def test_safe_singular_nil
    assert_nil FamilyRecipes::Inflector.safe_singular(nil)
  end

  def test_safe_singular_empty
    assert_equal '', FamilyRecipes::Inflector.safe_singular('')
  end

  # --- display_name ---

  def test_display_name_pluralizes_known_ingredient
    assert_equal 'Eggs', FamilyRecipes::Inflector.display_name('Egg', 2)
  end

  def test_display_name_singularizes_known_ingredient
    assert_equal 'Egg', FamilyRecipes::Inflector.display_name('Eggs', 1)
  end

  def test_display_name_unknown_ingredient_passes_through
    assert_equal 'Oregano', FamilyRecipes::Inflector.display_name('Oregano', 5)
  end

  def test_display_name_multi_word_inflects_last
    assert_equal 'Egg yolks', FamilyRecipes::Inflector.display_name('Egg yolk', 2)
  end

  def test_display_name_qualifier_preserved
    assert_equal 'Tomatoes (canned)', FamilyRecipes::Inflector.display_name('Tomato (canned)', 2)
  end

  def test_display_name_nil
    assert_nil FamilyRecipes::Inflector.display_name(nil, 2)
  end

  def test_display_name_empty
    assert_equal '', FamilyRecipes::Inflector.display_name('', 2)
  end

  def test_display_name_already_correct_form_passes_through
    assert_equal 'Egg', FamilyRecipes::Inflector.display_name('Egg', 1)
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

  def test_normalize_unit_preserves_macron
    assert_equal 'gō', FamilyRecipes::Inflector.normalize_unit('gō')
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

  # --- ingredient_variants ---

  def test_ingredient_variants_plural_to_singular
    assert_equal ['Egg'], FamilyRecipes::Inflector.ingredient_variants('Eggs')
  end

  def test_ingredient_variants_singular_to_plural
    assert_equal ['Eggs'], FamilyRecipes::Inflector.ingredient_variants('Egg')
  end

  def test_ingredient_variants_mass_noun_returns_variant
    assert_equal ['Butters'], FamilyRecipes::Inflector.ingredient_variants('Butter')
  end

  def test_ingredient_variants_mass_noun_with_qualifier_returns_variant
    assert_equal ['Flours (all-purpose)'], FamilyRecipes::Inflector.ingredient_variants('Flour (all-purpose)')
  end

  def test_ingredient_variants_qualified_name_inflects_base
    assert_equal ['Tomato (canned)'], FamilyRecipes::Inflector.ingredient_variants('Tomatoes (canned)')
  end

  def test_ingredient_variants_multi_word_inflects_last_word
    assert_equal ['Egg yolk'], FamilyRecipes::Inflector.ingredient_variants('Egg yolks')
  end

  def test_ingredient_variants_multi_word_singular_to_plural
    assert_equal ['Egg yolks'], FamilyRecipes::Inflector.ingredient_variants('Egg yolk')
  end

  def test_ingredient_variants_nil_returns_empty
    assert_empty FamilyRecipes::Inflector.ingredient_variants(nil)
  end

  def test_ingredient_variants_empty_returns_empty
    assert_empty FamilyRecipes::Inflector.ingredient_variants('')
  end

  # Rules produce imperfect variants for catalog matching — lookup keys, never displayed
  def test_ingredient_variants_irregular_leaves_via_rules
    assert_equal ['Bay leave'], FamilyRecipes::Inflector.ingredient_variants('Bay leaves')
  end

  def test_ingredient_variants_irregular_leaf_via_rules
    assert_equal ['Bay leafs'], FamilyRecipes::Inflector.ingredient_variants('Bay leaf')
  end

  def test_ingredient_variants_already_both_forms_same
    assert_empty FamilyRecipes::Inflector.ingredient_variants('grass')
  end
end
