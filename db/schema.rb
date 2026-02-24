# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_24_191000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "kitchen_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["kitchen_id", "slug"], name: "index_categories_on_kitchen_id_and_slug", unique: true
    t.index ["kitchen_id"], name: "index_categories_on_kitchen_id"
    t.index ["position"], name: "index_categories_on_position"
  end

  create_table "connected_services", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["provider", "uid"], name: "index_connected_services_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_connected_services_on_user_id"
  end

  create_table "cross_references", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "kitchen_id", null: false
    t.decimal "multiplier", precision: 8, scale: 2, default: "1.0", null: false
    t.integer "position", null: false
    t.string "prep_note"
    t.bigint "step_id", null: false
    t.bigint "target_recipe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["kitchen_id"], name: "index_cross_references_on_kitchen_id"
    t.index ["step_id", "position"], name: "index_cross_references_on_step_id_and_position", unique: true
    t.index ["step_id"], name: "index_cross_references_on_step_id"
    t.index ["target_recipe_id"], name: "index_cross_references_on_target_recipe_id"
  end

  create_table "grocery_lists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "kitchen_id", null: false
    t.jsonb "state", default: {}, null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 0, null: false
    t.index ["kitchen_id"], name: "index_grocery_lists_on_kitchen_id", unique: true
  end

  create_table "ingredient_profiles", force: :cascade do |t|
    t.decimal "added_sugars"
    t.string "aisle"
    t.decimal "basis_grams"
    t.decimal "calories"
    t.decimal "carbs"
    t.decimal "cholesterol"
    t.datetime "created_at", null: false
    t.decimal "density_grams"
    t.string "density_unit"
    t.decimal "density_volume"
    t.decimal "fat"
    t.decimal "fiber"
    t.string "ingredient_name", null: false
    t.bigint "kitchen_id"
    t.jsonb "portions", default: {}
    t.decimal "protein"
    t.decimal "saturated_fat"
    t.decimal "sodium"
    t.jsonb "sources", default: []
    t.decimal "total_sugars"
    t.decimal "trans_fat"
    t.datetime "updated_at", null: false
    t.index ["ingredient_name"], name: "index_ingredient_profiles_global_unique", unique: true, where: "(kitchen_id IS NULL)"
    t.index ["kitchen_id", "ingredient_name"], name: "index_ingredient_profiles_on_kitchen_id_and_ingredient_name", unique: true
    t.index ["kitchen_id"], name: "index_ingredient_profiles_on_kitchen_id"
  end

  create_table "ingredients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.string "prep_note"
    t.string "quantity"
    t.bigint "step_id", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["step_id"], name: "index_ingredients_on_step_id"
  end

  create_table "kitchens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_kitchens_on_slug", unique: true
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "kitchen_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["kitchen_id", "user_id"], name: "index_memberships_on_kitchen_id_and_user_id", unique: true
    t.index ["kitchen_id"], name: "index_memberships_on_kitchen_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "recipe_dependencies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "kitchen_id", null: false
    t.bigint "source_recipe_id", null: false
    t.bigint "target_recipe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["kitchen_id"], name: "index_recipe_dependencies_on_kitchen_id"
    t.index ["source_recipe_id", "target_recipe_id"], name: "idx_on_source_recipe_id_target_recipe_id_1fa016f4c7", unique: true
    t.index ["source_recipe_id"], name: "index_recipe_dependencies_on_source_recipe_id"
    t.index ["target_recipe_id"], name: "index_recipe_dependencies_on_target_recipe_id"
  end

  create_table "recipes", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "edited_at"
    t.text "footer"
    t.bigint "kitchen_id", null: false
    t.decimal "makes_quantity"
    t.string "makes_unit_noun"
    t.text "markdown_source", null: false
    t.jsonb "nutrition_data"
    t.integer "serves"
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_recipes_on_category_id"
    t.index ["kitchen_id", "slug"], name: "index_recipes_on_kitchen_id_and_slug", unique: true
    t.index ["kitchen_id"], name: "index_recipes_on_kitchen_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "site_documents", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.bigint "kitchen_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["kitchen_id", "name"], name: "index_site_documents_on_kitchen_id_and_name", unique: true
    t.index ["kitchen_id"], name: "index_site_documents_on_kitchen_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "steps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "instructions"
    t.integer "position", null: false
    t.text "processed_instructions"
    t.bigint "recipe_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["recipe_id"], name: "index_steps_on_recipe_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "categories", "kitchens"
  add_foreign_key "connected_services", "users"
  add_foreign_key "cross_references", "kitchens"
  add_foreign_key "cross_references", "recipes", column: "target_recipe_id"
  add_foreign_key "cross_references", "steps"
  add_foreign_key "grocery_lists", "kitchens"
  add_foreign_key "ingredient_profiles", "kitchens"
  add_foreign_key "ingredients", "steps"
  add_foreign_key "memberships", "kitchens"
  add_foreign_key "memberships", "users"
  add_foreign_key "recipe_dependencies", "kitchens"
  add_foreign_key "recipe_dependencies", "recipes", column: "source_recipe_id"
  add_foreign_key "recipe_dependencies", "recipes", column: "target_recipe_id"
  add_foreign_key "recipes", "categories"
  add_foreign_key "recipes", "kitchens"
  add_foreign_key "sessions", "users"
  add_foreign_key "site_documents", "kitchens"
  add_foreign_key "steps", "recipes"
end
