# frozen_string_literal: true

class RenameGroceryListVersionToLockVersion < ActiveRecord::Migration[8.0]
  def change
    rename_column :grocery_lists, :version, :lock_version
  end
end
