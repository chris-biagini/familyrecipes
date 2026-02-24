# frozen_string_literal: true

class AddAisleToIngredientProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :ingredient_profiles, :aisle, :string
    change_column_null :ingredient_profiles, :basis_grams, true
  end
end
