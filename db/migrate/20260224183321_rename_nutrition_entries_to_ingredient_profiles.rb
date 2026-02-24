# frozen_string_literal: true

class RenameNutritionEntriesToIngredientProfiles < ActiveRecord::Migration[8.1]
  def change
    rename_table :nutrition_entries, :ingredient_profiles
  end
end
