# frozen_string_literal: true

require_relative 'test_helper'

class RecipeBuilderTest < Minitest::Test
  def build_recipe(text)
    tokens = LineClassifier.classify(text)
    RecipeBuilder.new(tokens).build
  end

  def test_builds_minimal_recipe
    text = <<~RECIPE
      # Simple Recipe

      ## Step one

      Do the thing.
    RECIPE

    result = build_recipe(text)

    assert_equal 'Simple Recipe', result[:title]
    assert_nil result[:description]
    assert_equal 1, result[:steps].size
    assert_nil result[:footer]
  end

  def test_builds_recipe_with_description
    text = <<~RECIPE
      # Cookies

      Delicious chocolate chip cookies.

      ## Mix ingredients

      Mix them well.
    RECIPE

    result = build_recipe(text)

    assert_equal 'Cookies', result[:title]
    assert_equal 'Delicious chocolate chip cookies.', result[:description]
    assert_equal 1, result[:steps].size
  end

  def test_parses_step_tldr
    text = <<~RECIPE
      # Recipe

      ## Prepare the dough

      Do the thing.
    RECIPE

    result = build_recipe(text)

    assert_equal 'Prepare the dough', result[:steps][0][:tldr]
  end

  def test_parses_step_ingredients
    text = <<~RECIPE
      # Recipe

      ## Mix ingredients

      - Flour, 250 g
      - Sugar, 100 g

      Mix together.
    RECIPE

    result = build_recipe(text)
    ingredients = result[:steps][0][:ingredients]

    assert_equal 2, ingredients.size
    assert_equal 'Flour', ingredients[0][:name]
    assert_equal '250 g', ingredients[0][:quantity]
    assert_equal 'Sugar', ingredients[1][:name]
  end

  def test_parses_step_instructions
    text = <<~RECIPE
      # Recipe

      ## Mix ingredients

      - Flour

      Mix everything together.

      Stir until combined.
    RECIPE

    result = build_recipe(text)

    assert_includes result[:steps][0][:instructions], 'Mix everything together.'
    assert_includes result[:steps][0][:instructions], 'Stir until combined.'
  end

  def test_builds_multiple_steps
    text = <<~RECIPE
      # Recipe

      ## Step one

      First thing.

      ## Step two

      Second thing.

      ## Step three

      Third thing.
    RECIPE

    result = build_recipe(text)

    assert_equal 3, result[:steps].size
    assert_equal 'Step one', result[:steps][0][:tldr]
    assert_equal 'Step two', result[:steps][1][:tldr]
    assert_equal 'Step three', result[:steps][2][:tldr]
  end

  def test_builds_recipe_with_footer
    text = <<~RECIPE
      # Recipe

      ## Step

      Do it.

      ---

      This is a footer note.
    RECIPE

    result = build_recipe(text)

    assert_equal 'This is a footer note.', result[:footer]
  end

  def test_builds_recipe_with_multiline_footer
    text = <<~RECIPE
      # Recipe

      ## Step

      Do it.

      ---

      First paragraph.

      Second paragraph.
    RECIPE

    result = build_recipe(text)

    assert_includes result[:footer], 'First paragraph.'
    assert_includes result[:footer], 'Second paragraph.'
  end

  def test_raises_error_when_title_missing
    text = "## Step without title\n\nDo the thing."

    error = assert_raises(StandardError) do
      build_recipe(text)
    end

    assert_includes error.message, 'first line must be a level-one header'
  end

  def test_handles_empty_step
    text = <<~RECIPE
      # Recipe

      ## Empty step

      ## Second step

      Content here.
    RECIPE

    result = build_recipe(text)

    assert_equal 2, result[:steps].size
    assert_equal '', result[:steps][0][:instructions]
  end

  def test_parses_ingredient_with_prep_note
    text = <<~RECIPE
      # Recipe

      ## Step

      - Walnuts, 75 g: Roughly chop.
    RECIPE

    result = build_recipe(text)
    ingredient = result[:steps][0][:ingredients][0]

    assert_equal 'Walnuts', ingredient[:name]
    assert_equal '75 g', ingredient[:quantity]
    assert_equal 'Roughly chop.', ingredient[:prep_note]
  end

  # --- Front matter parsing ---

  def test_parses_category
    text = <<~RECIPE
      # Cookies

      Delicious cookies.

      Category: Dessert

      ## Mix

      Mix them.
    RECIPE

    result = build_recipe(text)

    assert_equal 'Dessert', result[:front_matter][:category]
  end

  def test_parses_makes_with_unit_noun
    text = <<~RECIPE
      # Cookies

      Delicious cookies.

      Category: Dessert
      Makes: 32 cookies

      ## Mix

      Mix them.
    RECIPE

    result = build_recipe(text)

    assert_equal '32 cookies', result[:front_matter][:makes]
  end

  def test_parses_serves
    text = <<~RECIPE
      # Beans

      A hearty dish.

      Category: Mains
      Serves: 4

      ## Cook

      Cook them.
    RECIPE

    result = build_recipe(text)

    assert_equal '4', result[:front_matter][:serves]
  end

  def test_parses_all_front_matter_fields
    text = <<~RECIPE
      # Pizza Dough

      Basic dough.

      Category: Pizza
      Makes: 6 dough balls
      Serves: 4

      ## Mix

      Mix.
    RECIPE

    result = build_recipe(text)

    assert_equal 'Pizza', result[:front_matter][:category]
    assert_equal '6 dough balls', result[:front_matter][:makes]
    assert_equal '4', result[:front_matter][:serves]
  end

  def test_front_matter_without_description
    text = <<~RECIPE
      # Pizza

      Category: Pizza

      ## Make dough

      Do it.
    RECIPE

    result = build_recipe(text)

    assert_nil result[:description]
    assert_equal 'Pizza', result[:front_matter][:category]
  end

  def test_no_front_matter_returns_empty_hash
    text = <<~RECIPE
      # Simple Recipe

      ## Step one

      Do the thing.
    RECIPE

    result = build_recipe(text)

    assert_empty result[:front_matter]
  end

  def test_description_not_consumed_as_front_matter
    text = <<~RECIPE
      # Cookies

      Delicious chocolate chip cookies.

      Category: Dessert

      ## Mix

      Mix them.
    RECIPE

    result = build_recipe(text)

    assert_equal 'Delicious chocolate chip cookies.', result[:description]
    assert_equal 'Dessert', result[:front_matter][:category]
  end

  def test_typo_in_front_matter_key_parsed_as_prose
    text = <<~RECIPE
      # Cookies

      Categroy: Dessert

      ## Mix

      Mix them.
    RECIPE

    result = build_recipe(text)

    assert_equal 'Categroy: Dessert', result[:description]
  end

  def test_consecutive_blank_lines_ignored
    text = <<~RECIPE
      # Recipe


      ## Step one

      First thing.



      ## Step two

      Second thing.
    RECIPE

    result = build_recipe(text)

    assert_equal 2, result[:steps].size
    assert_equal 'Step one', result[:steps][0][:tldr]
    assert_equal 'Step two', result[:steps][1][:tldr]
  end
end
