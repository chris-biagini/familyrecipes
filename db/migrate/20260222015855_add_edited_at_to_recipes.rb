class AddEditedAtToRecipes < ActiveRecord::Migration[8.1]
  def change
    add_column :recipes, :edited_at, :datetime
  end
end
