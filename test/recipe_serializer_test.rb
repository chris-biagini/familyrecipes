# frozen_string_literal: true

require_relative 'test_helper'

class RecipeSerializerTest < Minitest::Test
  def parse(markdown)
    tokens = LineClassifier.classify(markdown)
    RecipeBuilder.new(tokens).build
  end

  def round_trip(markdown)
    ir = parse(markdown)
    serialized = Mirepoix::RecipeSerializer.serialize(ir)
    parse(serialized)
  end

  def assert_ir_equal(expected, actual)
    assert_equal expected[:title], actual[:title]
    assert_field_equal expected[:description], actual[:description]
    assert_equal expected[:front_matter], actual[:front_matter]
    assert_equal expected[:steps].size, actual[:steps].size

    expected[:steps].zip(actual[:steps]).each do |exp_step, act_step|
      assert_field_equal exp_step[:tldr], act_step[:tldr]
      assert_equal exp_step[:ingredients], act_step[:ingredients]
      assert_equal exp_step[:instructions], act_step[:instructions]
      assert_field_equal exp_step[:cross_reference], act_step[:cross_reference]
    end

    assert_field_equal expected[:footer], actual[:footer]
  end

  def assert_field_equal(expected, actual)
    if expected.nil?
      assert_nil actual
    else
      assert_equal expected, actual
    end
  end

  def test_simple_recipe_round_trip
    markdown = <<~MD
      # Chocolate Chip Cookies

      Chewy cookies the whole family loves.

      Serves: 6
      Category: Dessert
      Tags: baking, family-favorite

      ## Make the dough.

      - Flour, 250 g
      - Sugar, 100 g: Sifted.

      Cream butter and sugar. Add flour gradually.

      ## Bake.

      Preheat oven to 175C. Bake 12 minutes.
    MD

    original = parse(markdown)
    result = round_trip(markdown)

    assert_ir_equal original, result
  end

  def test_cross_reference_with_multiplier_and_prep
    markdown = <<~MD
      # Big Batch Pizza

      ## Make dough.

      > @[Pizza Dough], 0.5: Let rest 30 min.

      ## Add toppings.

      - Mozzarella, 200 g

      Top and bake.
    MD

    original = parse(markdown)
    result = round_trip(markdown)

    assert_ir_equal original, result
    assert_in_delta 0.5, result[:steps][0][:cross_reference][:multiplier]
    assert_equal 'Let rest 30 min.', result[:steps][0][:cross_reference][:prep_note]
  end

  def test_recipe_with_footer
    markdown = <<~MD
      # Simple Pasta

      ## Cook.

      - Pasta, 400 g

      Boil and serve.

      ---

      Pairs well with @[Simple Salad].
    MD

    original = parse(markdown)
    result = round_trip(markdown)

    assert_ir_equal original, result
    assert_equal 'Pairs well with @[Simple Salad].', result[:footer]
  end

  def test_recipe_with_makes
    markdown = <<~MD
      # Dinner Rolls

      Soft and fluffy.

      Makes: 12 rolls

      ## Mix.

      - Flour, 500 g
      - Yeast, 2 tsp

      Knead until smooth.
    MD

    original = parse(markdown)
    result = round_trip(markdown)

    assert_ir_equal original, result
    assert_equal '12 rolls', result[:front_matter][:makes]
  end

  def test_recipe_with_no_front_matter
    markdown = <<~MD
      # Quick Snack

      ## Prepare.

      - Crackers, 6
      - Cheese, 50 g

      Arrange crackers. Top with cheese.
    MD

    original = parse(markdown)
    result = round_trip(markdown)

    assert_ir_equal original, result
    assert_empty result[:front_matter]
  end

  def test_ingredient_with_only_name
    markdown = <<~MD
      # Buttered Toast

      ## Toast.

      - Bread
      - Butter

      Toast and butter.
    MD

    original = parse(markdown)
    serialized = Mirepoix::RecipeSerializer.serialize(original)

    refute_includes serialized, '- Bread,'
    refute_includes serialized, '- Bread:'
    refute_includes serialized, '- Butter,'
    refute_includes serialized, '- Butter:'

    result = round_trip(markdown)

    assert_ir_equal original, result
  end

  def test_ingredient_with_quantity_but_no_prep
    markdown = <<~MD
      # Rice

      ## Cook.

      - Rice, 200 g
      - Water, 400 ml

      Bring to boil. Simmer 15 minutes.
    MD

    original = parse(markdown)
    serialized = Mirepoix::RecipeSerializer.serialize(original)

    assert_includes serialized, '- Rice, 200 g'
    refute_includes serialized, '- Rice, 200 g:'

    result = round_trip(markdown)

    assert_ir_equal original, result
  end

  def test_cross_reference_without_prep_note
    markdown = <<~MD
      # Pasta Night

      ## Make sauce.

      > @[Simple Tomato Sauce]

      ## Cook pasta.

      - Spaghetti, 400 g

      Boil until al dente.
    MD

    original = parse(markdown)
    serialized = Mirepoix::RecipeSerializer.serialize(original)

    assert_includes serialized, '> @[Simple Tomato Sauce]'
    refute_includes serialized, '> @[Simple Tomato Sauce],'
    refute_includes serialized, '> @[Simple Tomato Sauce]:'

    result = round_trip(markdown)

    assert_ir_equal original, result
  end

  def test_cross_reference_with_default_multiplier
    markdown = <<~MD
      # Pasta Night

      ## Make sauce.

      > @[Simple Tomato Sauce], 1.0

      ## Cook pasta.

      - Spaghetti, 400 g

      Boil until al dente.
    MD

    original = parse(markdown)
    serialized = Mirepoix::RecipeSerializer.serialize(original)

    assert_includes serialized, '> @[Simple Tomato Sauce]'
    refute_match(/> @\[Simple Tomato Sauce\], 1/, serialized)

    result = round_trip(markdown)

    assert_ir_equal original, result
    assert_in_delta 1.0, result[:steps][0][:cross_reference][:multiplier]
  end

  def test_multiline_footer
    markdown = <<~MD
      # Recipe

      ## Step.

      Do it.

      ---

      First paragraph.

      Second paragraph.
    MD

    original = parse(markdown)
    result = round_trip(markdown)

    assert_ir_equal original, result
    assert_includes result[:footer], 'First paragraph.'
    assert_includes result[:footer], 'Second paragraph.'
  end

  def test_description_without_front_matter
    markdown = <<~MD
      # Simple Toast

      The simplest recipe there is.

      ## Toast.

      - Bread, 2 slices

      Toast until golden.
    MD

    original = parse(markdown)
    result = round_trip(markdown)

    assert_ir_equal original, result
    assert_equal 'The simplest recipe there is.', result[:description]
  end

  def test_no_trailing_whitespace
    markdown = <<~MD
      # Test Recipe

      Serves: 4

      ## Step.

      - Item, 1 cup

      Do it.
    MD

    serialized = Mirepoix::RecipeSerializer.serialize(parse(markdown))

    serialized.each_line do |line|
      assert_equal "#{line.rstrip}\n", line, "Line has trailing whitespace: #{line.inspect}"
    end
  end

  def test_cross_reference_with_string_multiplier
    ir = {
      title: 'Test',
      description: nil,
      front_matter: {},
      steps: [{ tldr: 'Make it.', ingredients: [], instructions: nil,
                cross_reference: { target_title: 'Sauce', multiplier: '2.0', prep_note: nil } }],
      footer: nil
    }

    serialized = Mirepoix::RecipeSerializer.serialize(ir)

    assert_includes serialized, '> @[Sauce], 2'
    refute_includes serialized, '> @[Sauce], 2.0'
  end

  def test_cross_reference_with_string_default_multiplier
    ir = {
      title: 'Test',
      description: nil,
      front_matter: {},
      steps: [{ tldr: 'Make it.', ingredients: [], instructions: nil,
                cross_reference: { target_title: 'Sauce', multiplier: '1.0', prep_note: nil } }],
      footer: nil
    }

    serialized = Mirepoix::RecipeSerializer.serialize(ir)

    assert_includes serialized, '> @[Sauce]'
    refute_match(/> @\[Sauce\], 1/, serialized)
  end

  def test_ends_with_single_newline
    markdown = <<~MD
      # Test Recipe

      ## Step.

      Do it.
    MD

    serialized = Mirepoix::RecipeSerializer.serialize(parse(markdown))

    assert serialized.end_with?("\n"), 'Output must end with a newline'
    refute serialized.end_with?("\n\n"), 'Output must not end with trailing blank lines'
  end
end
