# frozen_string_literal: true

class DropMarkdownSource < ActiveRecord::Migration[8.0]
  def change
    remove_column :recipes, :markdown_source, :text, null: false
  end
end
