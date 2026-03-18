class NullifyNutritionDataForRecompute < ActiveRecord::Migration[8.0]
  def up
    execute "UPDATE recipes SET nutrition_data = NULL"
  end

  def down
    # No rollback needed — nutrition_data is recomputed on every recipe save
  end
end
