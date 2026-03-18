# frozen_string_literal: true

class AddDecorateTagsToKitchens < ActiveRecord::Migration[8.0]
  def change
    add_column :kitchens, :decorate_tags, :boolean, default: true, null: false
  end
end
