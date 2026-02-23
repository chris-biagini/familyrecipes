# frozen_string_literal: true

class MakeUserEmailRequired < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, name: :index_users_on_email
    change_column_null :users, :email, false
    add_index :users, :email, unique: true
  end
end
