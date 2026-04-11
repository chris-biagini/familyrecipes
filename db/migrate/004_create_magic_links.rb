# frozen_string_literal: true

class CreateMagicLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :magic_links do |t|
      t.references :user, null: false, foreign_key: true
      t.references :kitchen, null: true, foreign_key: true
      t.string :code, null: false, limit: 6
      t.integer :purpose, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.string :request_ip
      t.string :request_user_agent
      t.timestamps
    end

    add_index :magic_links, :code, unique: true
    add_index :magic_links, :expires_at
  end
end
