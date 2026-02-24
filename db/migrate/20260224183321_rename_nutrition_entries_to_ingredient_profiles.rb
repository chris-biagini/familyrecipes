# frozen_string_literal: true

class RenameNutritionEntriesToIngredientProfiles < ActiveRecord::Migration[8.1]
  def change
    rename_table :nutrition_entries, :ingredient_profiles
    rename_index :ingredient_profiles, 'index_nutrition_entries_global_unique',
                 'index_ingredient_profiles_global_unique'
  end
end
