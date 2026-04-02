class AddMissingForeignKeys < ActiveRecord::Migration[8.0]
  def change
    add_foreign_key :cook_history_entries, :kitchens
    add_foreign_key :custom_grocery_items, :kitchens
    add_foreign_key :meal_plan_selections, :kitchens
    add_foreign_key :on_hand_entries, :kitchens
    add_foreign_key :quick_bites, :kitchens
    add_foreign_key :quick_bites, :categories
    add_foreign_key :quick_bite_ingredients, :quick_bites
  end
end
