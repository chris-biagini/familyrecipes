# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email

      t.timestamps
    end

    add_index :users, :email, unique: true, where: 'email IS NOT NULL'
  end
end
