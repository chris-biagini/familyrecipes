# frozen_string_literal: true

class DropConnectedServices < ActiveRecord::Migration[8.1]
  def change
    drop_table :connected_services do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.timestamps
      t.index %i[provider uid], unique: true
    end
  end
end
