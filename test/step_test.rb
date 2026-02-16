require_relative 'test_helper'

class StepTest < Minitest::Test
  def test_valid_with_ingredients_and_instructions
    step = Step.new(
      tldr: "Mix dough",
      ingredients: [Ingredient.new(name: "Flour", quantity: "250 g")],
      instructions: "Combine everything."
    )

    assert_equal "Mix dough", step.tldr
    assert_equal 1, step.ingredients.size
    assert_equal "Combine everything.", step.instructions
  end

  def test_valid_with_ingredients_only
    step = Step.new(
      tldr: "Prep ingredients",
      ingredients: [Ingredient.new(name: "Salt")],
      instructions: nil
    )

    assert_equal "Prep ingredients", step.tldr
    assert_equal 1, step.ingredients.size
    assert_nil step.instructions
  end

  def test_valid_with_instructions_only
    step = Step.new(
      tldr: "Preheat oven",
      ingredients: [],
      instructions: "Preheat oven to 400F."
    )

    assert_equal "Preheat oven", step.tldr
    assert_empty step.ingredients
    assert_equal "Preheat oven to 400F.", step.instructions
  end

  def test_raises_on_nil_tldr
    assert_raises(ArgumentError) do
      Step.new(tldr: nil, ingredients: [Ingredient.new(name: "Salt")], instructions: "Season.")
    end
  end

  def test_raises_on_blank_tldr
    assert_raises(ArgumentError) do
      Step.new(tldr: "  ", ingredients: [Ingredient.new(name: "Salt")], instructions: "Season.")
    end
  end

  def test_raises_when_no_ingredients_and_no_instructions
    assert_raises(ArgumentError) do
      Step.new(tldr: "Empty step", ingredients: [], instructions: nil)
    end
  end

  def test_raises_when_no_ingredients_and_blank_instructions
    assert_raises(ArgumentError) do
      Step.new(tldr: "Empty step", ingredients: [], instructions: "   ")
    end
  end
end
