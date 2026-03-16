# frozen_string_literal: true

require 'test_helper'

class RecipeSerializerIntegrationTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
  end

  test 'round-trips range ingredient through serializer' do
    markdown = "# Range Test\n\n## Step\n\n- Eggs, 2-3\n- Flour, 1/2-1 cup\n\nMix."
    recipe = create_recipe(markdown)
    ir = FamilyRecipes::RecipeSerializer.from_record(recipe.reload)
    serialized = FamilyRecipes::RecipeSerializer.serialize(ir)

    assert_includes serialized, '- Eggs, 2-3'
    assert_includes serialized, '- Flour, 1/2-1 cup'
  end

  test 'serializes non-range ingredient from numeric columns' do
    markdown = "# Simple Test\n\n## Step\n\n- Flour, 2 cups\n\nMix."
    recipe = create_recipe(markdown)
    ir = FamilyRecipes::RecipeSerializer.from_record(recipe.reload)
    serialized = FamilyRecipes::RecipeSerializer.serialize(ir)

    assert_includes serialized, '- Flour, 2 cups'
  end

  test 'serializes non-numeric quantity as-is' do
    markdown = "# Freeform Test\n\n## Step\n\n- Basil, a few leaves\n\nAdd."
    recipe = create_recipe(markdown)
    ir = FamilyRecipes::RecipeSerializer.from_record(recipe.reload)
    serialized = FamilyRecipes::RecipeSerializer.serialize(ir)

    assert_includes serialized, '- Basil, a few leaves'
  end
end
