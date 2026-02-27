# frozen_string_literal: true

class RenameGroceryListsToMealPlans < ActiveRecord::Migration[8.0]
  def change
    rename_table :grocery_lists, :meal_plans
  end
end
