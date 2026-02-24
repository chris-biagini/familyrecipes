# frozen_string_literal: true

class CreateSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :kitchens do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :quick_bites_content
      t.timestamps
      t.index :slug, unique: true
    end

    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.timestamps
      t.index :email, unique: true
    end

    create_table :memberships do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: 'member'
      t.timestamps
      t.index %i[kitchen_id user_id], unique: true
    end

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end

    create_table :connected_services do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.timestamps
      t.index %i[provider uid], unique: true
    end

    create_table :categories do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index %i[kitchen_id slug], unique: true
      t.index :position
    end

    create_table :recipes do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug, null: false
      t.text :description
      t.text :footer
      t.text :markdown_source, null: false
      t.decimal :makes_quantity
      t.string :makes_unit_noun
      t.integer :serves
      t.json :nutrition_data
      t.datetime :edited_at
      t.timestamps
      t.index %i[kitchen_id slug], unique: true
    end

    create_table :steps do |t|
      t.references :recipe, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :position, null: false
      t.text :instructions
      t.text :processed_instructions
      t.timestamps
    end

    create_table :ingredients do |t|
      t.references :step, null: false, foreign_key: true
      t.string :name, null: false
      t.string :quantity
      t.string :unit
      t.string :prep_note
      t.integer :position, null: false
      t.timestamps
    end

    create_table :cross_references do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.references :step, null: false, foreign_key: true
      t.references :target_recipe, null: false, foreign_key: { to_table: :recipes }
      t.decimal :multiplier, precision: 8, scale: 2, null: false, default: 1.0
      t.string :prep_note
      t.integer :position, null: false
      t.timestamps
      t.index %i[step_id position], unique: true
    end

    create_table :ingredient_catalog do |t|
      t.references :kitchen, foreign_key: true
      t.string :ingredient_name, null: false
      t.string :aisle
      t.decimal :basis_grams
      t.decimal :calories
      t.decimal :fat
      t.decimal :saturated_fat
      t.decimal :trans_fat
      t.decimal :cholesterol
      t.decimal :sodium
      t.decimal :carbs
      t.decimal :fiber
      t.decimal :total_sugars
      t.decimal :added_sugars
      t.decimal :protein
      t.decimal :density_grams
      t.decimal :density_volume
      t.string :density_unit
      t.json :portions, default: {}
      t.json :sources, default: []
      t.timestamps
      t.index :ingredient_name, unique: true, where: 'kitchen_id IS NULL',
              name: 'index_ingredient_catalog_global_unique'
      t.index %i[kitchen_id ingredient_name], unique: true
    end

    create_table :grocery_lists do |t|
      t.references :kitchen, null: false, foreign_key: true, index: { unique: true }
      t.json :state, null: false, default: {}
      t.integer :version, null: false, default: 0
      t.timestamps
    end
  end
end
