require_relative 'test_helper'

class LineClassifierTest < Minitest::Test
  def test_classifies_title
    type, content = LineClassifier.classify_line("# Chocolate Chip Cookies")
    assert_equal :title, type
    assert_equal ["Chocolate Chip Cookies"], content
  end

  def test_classifies_step_header
    type, content = LineClassifier.classify_line("## Mix the dough")
    assert_equal :step_header, type
    assert_equal ["Mix the dough"], content
  end

  def test_classifies_ingredient
    type, content = LineClassifier.classify_line("- Flour, 250 g")
    assert_equal :ingredient, type
    assert_equal ["Flour, 250 g"], content
  end

  def test_classifies_ingredient_with_prep_note
    type, content = LineClassifier.classify_line("- Walnuts, 75 g: Roughly chop.")
    assert_equal :ingredient, type
    assert_equal ["Walnuts, 75 g: Roughly chop."], content
  end

  def test_classifies_divider
    type, _content = LineClassifier.classify_line("---")
    assert_equal :divider, type
  end

  def test_classifies_divider_with_trailing_spaces
    type, _content = LineClassifier.classify_line("---   ")
    assert_equal :divider, type
  end

  def test_classifies_blank_line
    type, _content = LineClassifier.classify_line("")
    assert_equal :blank, type
  end

  def test_classifies_whitespace_only_as_blank
    type, _content = LineClassifier.classify_line("   ")
    assert_equal :blank, type
  end

  def test_classifies_prose
    type, content = LineClassifier.classify_line("Mix everything together until combined.")
    assert_equal :prose, type
    assert_equal "Mix everything together until combined.", content
  end

  def test_classify_full_recipe
    recipe_text = <<~RECIPE
      # Test Recipe

      A simple description.

      ## First step

      - Ingredient one, 100 g
      - Ingredient two

      Do the thing.

      ---

      Footer notes here.
    RECIPE

    tokens = LineClassifier.classify(recipe_text)

    assert_equal :title, tokens[0].type
    assert_equal 1, tokens[0].line_number

    assert_equal :blank, tokens[1].type

    assert_equal :prose, tokens[2].type
    assert_equal "A simple description.", tokens[2].content

    assert_equal :step_header, tokens[4].type
    assert_equal ["First step"], tokens[4].content

    assert_equal :ingredient, tokens[6].type
    assert_equal :ingredient, tokens[7].type

    assert_equal :prose, tokens[9].type

    assert_equal :divider, tokens[11].type

    assert_equal :prose, tokens[13].type
  end

  def test_preserves_line_numbers
    tokens = LineClassifier.classify("# Title\n\n## Step")

    assert_equal 1, tokens[0].line_number
    assert_equal 2, tokens[1].line_number
    assert_equal 3, tokens[2].line_number
  end
end
