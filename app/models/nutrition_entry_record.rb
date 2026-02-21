# frozen_string_literal: true

class NutritionEntryRecord < ApplicationRecord
  self.table_name = 'nutrition_entries'

  validates :ingredient_name, presence: true, uniqueness: true
  validates :basis_grams, :calories, :fat, :saturated_fat, :trans_fat,
            :cholesterol, :sodium, :carbs, :fiber, :total_sugars,
            :added_sugars, :protein, presence: true
end
