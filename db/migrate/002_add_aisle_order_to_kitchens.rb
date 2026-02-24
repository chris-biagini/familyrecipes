# frozen_string_literal: true

class AddAisleOrderToKitchens < ActiveRecord::Migration[8.1]
  def change
    add_column :kitchens, :aisle_order, :text
  end
end
