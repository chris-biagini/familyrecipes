# frozen_string_literal: true

class AddJoinCodeToKitchens < ActiveRecord::Migration[8.0]
  def up
    add_column :kitchens, :join_code, :string

    Kitchen.reset_column_information
    Kitchen.find_each do |kitchen|
      kitchen.update!(join_code: JoinCodeGenerator.generate)
    end

    change_column_null :kitchens, :join_code, false
    add_index :kitchens, :join_code, unique: true
  end

  def down
    remove_column :kitchens, :join_code
  end
end
