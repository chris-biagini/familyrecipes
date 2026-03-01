# frozen_string_literal: true

require_relative 'test_helper'

class StepTest < Minitest::Test
  def test_valid_with_ingredients_and_instructions
    step = FamilyRecipes::Step.new(
      tldr: 'Mix dough',
      ingredient_list_items: [FamilyRecipes::Ingredient.new(name: 'Flour', quantity: '250 g')],
      instructions: 'Combine everything.'
    )

    assert_equal 'Mix dough', step.tldr
    assert_equal 1, step.ingredients.size
    assert_equal 'Combine everything.', step.instructions
  end

  def test_valid_with_ingredients_only
    step = FamilyRecipes::Step.new(
      tldr: 'Prep ingredients',
      ingredient_list_items: [FamilyRecipes::Ingredient.new(name: 'Salt')],
      instructions: nil
    )

    assert_equal 'Prep ingredients', step.tldr
    assert_equal 1, step.ingredients.size
    assert_nil step.instructions
  end

  def test_valid_with_instructions_only
    step = FamilyRecipes::Step.new(
      tldr: 'Preheat oven',
      ingredient_list_items: [],
      instructions: 'Preheat oven to 400F.'
    )

    assert_equal 'Preheat oven', step.tldr
    assert_empty step.ingredients
    assert_equal 'Preheat oven to 400F.', step.instructions
  end

  def test_valid_with_nil_tldr
    step = FamilyRecipes::Step.new(
      tldr: nil,
      ingredient_list_items: [FamilyRecipes::Ingredient.new(name: 'Salt')],
      instructions: 'Season.'
    )

    assert_nil step.tldr
    assert_equal 1, step.ingredients.size
  end

  def test_raises_on_blank_tldr
    assert_raises(ArgumentError) do
      FamilyRecipes::Step.new(
        tldr: '  ', ingredient_list_items: [FamilyRecipes::Ingredient.new(name: 'Salt')],
        instructions: 'Season.'
      )
    end
  end

  def test_raises_when_no_ingredients_and_no_instructions
    assert_raises(ArgumentError) do
      FamilyRecipes::Step.new(tldr: 'Empty step', ingredient_list_items: [], instructions: nil)
    end
  end

  def test_raises_when_no_ingredients_and_blank_instructions
    assert_raises(ArgumentError) do
      FamilyRecipes::Step.new(tldr: 'Empty step', ingredient_list_items: [], instructions: '   ')
    end
  end

  def test_derives_ingredients_and_cross_references
    flour = FamilyRecipes::Ingredient.new(name: 'Flour', quantity: '500 g')
    xref = FamilyRecipes::CrossReference.new(target_title: 'Pizza Dough')
    salt = FamilyRecipes::Ingredient.new(name: 'Salt')

    step = FamilyRecipes::Step.new(
      tldr: 'Mix',
      ingredient_list_items: [flour, xref, salt],
      instructions: 'Combine.'
    )

    assert_equal [flour, salt], step.ingredients
    assert_equal [xref], step.cross_references
    assert_equal [flour, xref, salt], step.ingredient_list_items
  end
end
