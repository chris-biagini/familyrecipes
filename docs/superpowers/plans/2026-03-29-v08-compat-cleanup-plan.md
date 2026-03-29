# v0.8 Alpha: Backward-Compatibility Cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all backward-compatibility code and consolidate migrations to establish the current state as the v0.8 alpha baseline.

**Architecture:** Four independent cleanup areas (migrations, Ruby compat, JS compat, tests) that can mostly be done in sequence. Migration consolidation is the largest task; the rest are small surgical edits.

**Tech Stack:** Rails 8.1, SQLite, Stimulus/JS, Minitest

---

### Task 1: Consolidate database migrations

Replace 15 migration files with a single `001_create_schema.rb` that creates
the current schema from scratch. The new migration reproduces `db/schema.rb`
exactly.

**Files:**
- Delete: `db/migrate/001_create_schema.rb` through `db/migrate/015_normalize_quick_bites.rb` (all 15 files)
- Create: `db/migrate/001_create_schema.rb` (new, single migration)

- [ ] **Step 1: Delete all existing migration files**

```bash
rm db/migrate/001_create_schema.rb \
   db/migrate/002_add_settings_to_kitchen.rb \
   db/migrate/003_migrate_cross_reference_syntax.rb \
   db/migrate/004_create_tags.rb \
   db/migrate/005_drop_markdown_source.rb \
   db/migrate/006_migrate_quick_bites_headers.rb \
   db/migrate/007_add_quantity_range_columns.rb \
   db/migrate/008_add_show_nutrition_to_kitchens.rb \
   db/migrate/009_add_anthropic_api_key_to_kitchens.rb \
   db/migrate/010_nullify_nutrition_data_for_recompute.rb \
   db/migrate/011_add_decorate_tags_to_kitchens.rb \
   db/migrate/012_convert_checked_off_to_on_hand.rb \
   db/migrate/013_migrate_custom_items_format.rb \
   db/migrate/014_decompose_meal_plan.rb \
   db/migrate/015_normalize_quick_bites.rb
```

- [ ] **Step 2: Create the consolidated migration**

Create `db/migrate/001_create_schema.rb`. This reproduces every
`create_table`, index, and `add_foreign_key` from the current `db/schema.rb`.
Use a `change` method so it's reversible. The version number is `1`.

```ruby
# frozen_string_literal: true

class CreateSchema < ActiveRecord::Migration[8.1]
  def change
    create_table "categories", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.integer "kitchen_id", null: false
      t.string "name", null: false
      t.integer "position", default: 0, null: false
      t.string "slug", null: false
      t.datetime "updated_at", null: false
      t.index ["kitchen_id", "name"], name: "index_categories_on_kitchen_id_and_name", unique: true
      t.index ["kitchen_id", "slug"], name: "index_categories_on_kitchen_id_and_slug", unique: true
      t.index ["kitchen_id"], name: "index_categories_on_kitchen_id"
      t.index ["position"], name: "index_categories_on_position"
    end

    create_table "cook_history_entries", force: :cascade do |t|
      t.datetime "cooked_at", null: false
      t.integer "kitchen_id", null: false
      t.string "recipe_slug", null: false
      t.index ["kitchen_id", "recipe_slug", "cooked_at"], name: "idx_cook_history_entries_lookup"
    end

    create_table "cross_references", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.integer "kitchen_id", null: false
      t.decimal "multiplier", precision: 8, scale: 2, default: "1.0", null: false
      t.integer "position", null: false
      t.string "prep_note"
      t.integer "step_id", null: false
      t.integer "target_recipe_id"
      t.string "target_slug", null: false
      t.string "target_title", null: false
      t.datetime "updated_at", null: false
      t.index ["kitchen_id"], name: "index_cross_references_on_kitchen_id"
      t.index ["step_id", "position"], name: "index_cross_references_on_step_id_and_position", unique: true
      t.index ["step_id"], name: "index_cross_references_on_step_id"
      t.index ["target_recipe_id"], name: "index_cross_references_on_target_recipe_id"
    end

    create_table "custom_grocery_items", force: :cascade do |t|
      t.string "aisle", default: "Miscellaneous", null: false
      t.datetime "created_at", null: false
      t.integer "kitchen_id", null: false
      t.date "last_used_at", null: false
      t.string "name", null: false, collation: "NOCASE"
      t.date "on_hand_at"
      t.index ["kitchen_id", "name"], name: "idx_custom_grocery_items_unique", unique: true
    end

    create_table "ingredient_catalog", force: :cascade do |t|
      t.decimal "added_sugars"
      t.string "aisle"
      t.json "aliases", default: []
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
      t.string "ingredient_name", null: false, collation: "NOCASE"
      t.integer "kitchen_id"
      t.boolean "omit_from_shopping", default: false, null: false
      t.json "portions", default: {}
      t.decimal "protein"
      t.decimal "saturated_fat"
      t.decimal "sodium"
      t.json "sources", default: []
      t.decimal "total_sugars"
      t.decimal "trans_fat"
      t.datetime "updated_at", null: false
      t.index ["ingredient_name"], name: "index_ingredient_catalog_global_unique", unique: true, where: "kitchen_id IS NULL"
      t.index ["kitchen_id", "ingredient_name"], name: "index_ingredient_catalog_on_kitchen_id_and_ingredient_name", unique: true
      t.index ["kitchen_id"], name: "index_ingredient_catalog_on_kitchen_id"
    end

    create_table "ingredients", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.string "name", null: false
      t.integer "position", null: false
      t.string "prep_note"
      t.string "quantity"
      t.decimal "quantity_high"
      t.decimal "quantity_low"
      t.integer "step_id", null: false
      t.string "unit"
      t.datetime "updated_at", null: false
      t.index ["step_id", "position"], name: "index_ingredients_on_step_id_and_position", unique: true
      t.index ["step_id"], name: "index_ingredients_on_step_id"
    end

    create_table "kitchens", force: :cascade do |t|
      t.text "aisle_order"
      t.string "anthropic_api_key"
      t.datetime "created_at", null: false
      t.boolean "decorate_tags", default: true, null: false
      t.string "homepage_heading", default: "Our Recipes"
      t.string "homepage_subtitle", default: "A collection of our family's favorite recipes."
      t.string "name", null: false
      t.boolean "show_nutrition", default: false, null: false
      t.string "site_title", default: "Family Recipes"
      t.string "slug", null: false
      t.datetime "updated_at", null: false
      t.string "usda_api_key"
      t.index ["slug"], name: "index_kitchens_on_slug", unique: true
    end

    create_table "meal_plan_selections", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.integer "kitchen_id", null: false
      t.string "selectable_id", null: false
      t.string "selectable_type", null: false
      t.index ["kitchen_id", "selectable_type", "selectable_id"], name: "idx_meal_plan_selections_unique", unique: true
    end

    create_table "meal_plans", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.integer "kitchen_id", null: false
      t.datetime "updated_at", null: false
      t.index ["kitchen_id"], name: "index_meal_plans_on_kitchen_id", unique: true
    end

    create_table "memberships", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.integer "kitchen_id", null: false
      t.string "role", default: "member", null: false
      t.datetime "updated_at", null: false
      t.integer "user_id", null: false
      t.index ["kitchen_id", "user_id"], name: "index_memberships_on_kitchen_id_and_user_id", unique: true
      t.index ["kitchen_id"], name: "index_memberships_on_kitchen_id"
      t.index ["user_id"], name: "index_memberships_on_user_id"
    end

    create_table "on_hand_entries", force: :cascade do |t|
      t.date "confirmed_at", null: false
      t.datetime "created_at", null: false
      t.date "depleted_at"
      t.float "ease"
      t.string "ingredient_name", null: false, collation: "NOCASE"
      t.float "interval"
      t.integer "kitchen_id", null: false
      t.date "orphaned_at"
      t.datetime "updated_at", null: false
      t.index ["kitchen_id", "ingredient_name"], name: "idx_on_hand_entries_unique", unique: true
    end

    create_table "quick_bite_ingredients", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.string "name", null: false
      t.integer "position", default: 0, null: false
      t.integer "quick_bite_id", null: false
      t.datetime "updated_at", null: false
      t.index ["quick_bite_id"], name: "index_quick_bite_ingredients_on_quick_bite_id"
    end

    create_table "quick_bites", force: :cascade do |t|
      t.integer "category_id", null: false
      t.datetime "created_at", null: false
      t.integer "kitchen_id", null: false
      t.integer "position", default: 0, null: false
      t.string "title", null: false
      t.datetime "updated_at", null: false
      t.index ["kitchen_id", "category_id"], name: "index_quick_bites_on_kitchen_id_and_category_id"
      t.index ["kitchen_id", "title"], name: "index_quick_bites_on_kitchen_id_and_title", unique: true
    end

    create_table "recipe_tags", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.integer "recipe_id", null: false
      t.integer "tag_id", null: false
      t.datetime "updated_at", null: false
      t.index ["recipe_id", "tag_id"], name: "index_recipe_tags_on_recipe_id_and_tag_id", unique: true
      t.index ["recipe_id"], name: "index_recipe_tags_on_recipe_id"
      t.index ["tag_id"], name: "index_recipe_tags_on_tag_id"
    end

    create_table "recipes", force: :cascade do |t|
      t.integer "category_id", null: false
      t.datetime "created_at", null: false
      t.text "description"
      t.datetime "edited_at"
      t.text "footer"
      t.integer "kitchen_id", null: false
      t.decimal "makes_quantity"
      t.string "makes_unit_noun"
      t.json "nutrition_data"
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
      t.integer "user_id", null: false
      t.index ["user_id"], name: "index_sessions_on_user_id"
    end

    create_table "steps", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.text "instructions"
      t.integer "position", null: false
      t.text "processed_instructions"
      t.integer "recipe_id", null: false
      t.string "title"
      t.datetime "updated_at", null: false
      t.index ["recipe_id", "position"], name: "index_steps_on_recipe_id_and_position", unique: true
      t.index ["recipe_id"], name: "index_steps_on_recipe_id"
    end

    create_table "tags", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.integer "kitchen_id", null: false
      t.string "name", null: false
      t.datetime "updated_at", null: false
      t.index ["kitchen_id", "name"], name: "index_tags_on_kitchen_id_and_name", unique: true
      t.index ["kitchen_id"], name: "index_tags_on_kitchen_id"
    end

    create_table "users", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.string "email", null: false
      t.string "name", null: false
      t.datetime "updated_at", null: false
      t.index ["email"], name: "index_users_on_email", unique: true
    end

    add_foreign_key "categories", "kitchens"
    add_foreign_key "cross_references", "kitchens"
    add_foreign_key "cross_references", "recipes", column: "target_recipe_id"
    add_foreign_key "cross_references", "steps"
    add_foreign_key "ingredient_catalog", "kitchens"
    add_foreign_key "ingredients", "steps"
    add_foreign_key "meal_plans", "kitchens"
    add_foreign_key "memberships", "kitchens"
    add_foreign_key "memberships", "users"
    add_foreign_key "recipe_tags", "recipes"
    add_foreign_key "recipe_tags", "tags"
    add_foreign_key "recipes", "categories"
    add_foreign_key "recipes", "kitchens"
    add_foreign_key "sessions", "users"
    add_foreign_key "steps", "recipes"
    add_foreign_key "tags", "kitchens"
  end
end
```

- [ ] **Step 3: Verify from scratch**

Delete the existing database and rebuild from the new single migration:

```bash
RAILS_ENV=test bin/rails db:drop db:create db:migrate
```

Expected: migration runs cleanly, `db/schema.rb` is regenerated with
`version: 1` and identical table definitions.

- [ ] **Step 4: Run the full test suite**

```bash
rake test
```

Expected: all tests pass. The schema is identical so nothing should break.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/
git commit -m "Consolidate 15 migrations into single schema migration

Replaces all incremental migrations (001-015) with a single
001_create_schema.rb that creates the current schema from scratch.
No data migration logic — the old formats no longer exist.
Resolves #216"
```

---

### Task 2: Simplify `IngredientCatalog.aisle_attrs_from_yaml`

Remove the `aisle == 'omit'` backward-compat detection. The current YAML
uses `omit_from_shopping: true` exclusively.

**Files:**
- Modify: `app/models/ingredient_catalog.rb:75-80`
- Delete test: `test/services/catalog_write_service_test.rb:375-384`

- [ ] **Step 1: Simplify the method**

In `app/models/ingredient_catalog.rb`, replace lines 75-80:

```ruby
  # Backward compat: old-format imports use aisle='omit' instead of the boolean
  def self.aisle_attrs_from_yaml(entry)
    aisle = entry['aisle']
    omit = entry['omit_from_shopping'] || aisle == 'omit'
    { aisle: (aisle == 'omit' ? nil : aisle), omit_from_shopping: omit || false }
  end
```

with:

```ruby
  def self.aisle_attrs_from_yaml(entry)
    { aisle: entry['aisle'], omit_from_shopping: entry['omit_from_shopping'] || false }
  end
```

- [ ] **Step 2: Delete the old-format test**

In `test/services/catalog_write_service_test.rb`, delete the test block at
lines 375-384:

```ruby
  test 'bulk_import converts old aisle omit to omit_from_shopping' do
    CatalogWriteService.bulk_import(kitchen: @kitchen, entries_hash: {
                                      'vanilla' => { 'aisle' => 'omit' }
                                    })

    entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'vanilla')

    assert entry.omit_from_shopping
    assert_nil entry.aisle
  end
```

- [ ] **Step 3: Run tests**

```bash
ruby -Itest test/services/catalog_write_service_test.rb
```

Expected: all remaining tests pass.

- [ ] **Step 4: Commit**

```bash
git add app/models/ingredient_catalog.rb test/services/catalog_write_service_test.rb
git commit -m "Remove aisle='omit' compat from IngredientCatalog

The old YAML format no longer exists — all entries use
omit_from_shopping: true. Simplify aisle_attrs_from_yaml and
delete the compat test."
```

---

### Task 3: Inline `Kitchen::MAX_AISLE_NAME_LENGTH`

Replace the alias constant with direct references to the canonical
`FamilyRecipes::NutritionConstraints::AISLE_MAX_LENGTH`.

**Files:**
- Modify: `app/models/kitchen.rb:33`
- Modify: `app/services/aisle_write_service.rb:33,35`
- Modify: `test/services/aisle_write_service_test.rb:89,91`

- [ ] **Step 1: Update AisleWriteService**

In `app/services/aisle_write_service.rb`, replace both references on lines
33 and 35:

```ruby
                   max_name_length: Kitchen::MAX_AISLE_NAME_LENGTH,
```
→
```ruby
                   max_name_length: FamilyRecipes::NutritionConstraints::AISLE_MAX_LENGTH,
```

```ruby
      validate_renames_length(renames, Kitchen::MAX_AISLE_NAME_LENGTH)
```
→
```ruby
      validate_renames_length(renames, FamilyRecipes::NutritionConstraints::AISLE_MAX_LENGTH)
```

- [ ] **Step 2: Update the test**

In `test/services/aisle_write_service_test.rb`, replace the reference on
line 91:

```ruby
    long_name = 'a' * (Kitchen::MAX_AISLE_NAME_LENGTH + 1)
```
→
```ruby
    long_name = 'a' * (FamilyRecipes::NutritionConstraints::AISLE_MAX_LENGTH + 1)
```

- [ ] **Step 3: Delete the constant from Kitchen**

In `app/models/kitchen.rb`, delete line 33:

```ruby
  MAX_AISLE_NAME_LENGTH = FamilyRecipes::NutritionConstraints::AISLE_MAX_LENGTH
```

- [ ] **Step 4: Run tests**

```bash
ruby -Itest test/services/aisle_write_service_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/kitchen.rb app/services/aisle_write_service.rb test/services/aisle_write_service_test.rb
git commit -m "Inline Kitchen::MAX_AISLE_NAME_LENGTH

Replace the compat alias with direct references to the canonical
NutritionConstraints::AISLE_MAX_LENGTH constant."
```

---

### Task 4: Remove JS localStorage/sessionStorage compat code

Remove four pieces of dead compat code from three Stimulus controllers.

**Files:**
- Modify: `app/javascript/controllers/grocery_ui_controller.js:24-25,200-204,264-266,297-301`
- Modify: `app/javascript/controllers/recipe_state_controller.js:103`
- Modify: `app/javascript/controllers/nutrition_editor_controller.js:640-641`

- [ ] **Step 1: Remove `cleanupOldStorage` from grocery_ui_controller**

In `app/javascript/controllers/grocery_ui_controller.js`:

Delete the call on line 24:
```javascript
    this.cleanupOldStorage()
```

Delete the method definition at lines 200-204:
```javascript
  cleanupOldStorage() {
    try {
      localStorage.removeItem(`grocery-aisles-${this.element.dataset.kitchenSlug}`)
    } catch { /* ignore */ }
  }
```

- [ ] **Step 2: Remove `cleanupCartStorage` from grocery_ui_controller**

Delete the call on line 25:
```javascript
    this.cleanupCartStorage()
```

Delete the method definition at lines 297-301:
```javascript
  cleanupCartStorage() {
    try {
      sessionStorage.removeItem(`grocery-in-cart-${this.element.dataset.kitchenSlug}`)
    } catch { /* ignore */ }
  }
```

- [ ] **Step 3: Remove boolean collapse format conversion**

In the same file, replace lines 263-266:
```javascript
      let entry = state[aisle]
      if (typeof entry === "boolean") {
        entry = { to_buy: true, on_hand: entry }
      }
```

with:
```javascript
      const entry = state[aisle]
```

- [ ] **Step 4: Remove string scaleFactor coercion from recipe_state_controller**

In `app/javascript/controllers/recipe_state_controller.js`, replace line 103:
```javascript
      const factor = typeof scaleFactor === 'string' ? parseFloat(scaleFactor) : scaleFactor
```

with:
```javascript
      const factor = scaleFactor
```

- [ ] **Step 5: Remove stale sessionStorage cleanup from nutrition_editor_controller**

In `app/javascript/controllers/nutrition_editor_controller.js`, delete lines
640-641:
```javascript
    const staleKeys = ["density", "portions", "recipe-units", "grocery-aisle", "aliases", "nutrition-conversions"]
    staleKeys.forEach(key => sessionStorage.removeItem(`editor:section:${key}`))
```

- [ ] **Step 6: Rebuild JS bundle**

```bash
npm run build
```

Expected: builds cleanly with no errors.

- [ ] **Step 7: Run JS tests**

```bash
npm test
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js \
       app/javascript/controllers/recipe_state_controller.js \
       app/javascript/controllers/nutrition_editor_controller.js \
       app/assets/builds/
git commit -m "Remove localStorage/sessionStorage compat code

Drop cleanupOldStorage, cleanupCartStorage, boolean collapse
format conversion, string scaleFactor coercion, and stale
sessionStorage key cleanup. All dead code from formats that
no longer exist."
```

---

### Task 5: Clean up compat-flavored test names and comments

Cosmetic cleanup — rename a test and remove a misleading comment.

**Files:**
- Modify: `test/vulgar_fractions_test.rb:156`
- Modify: `test/javascript/search_match_test.mjs:31`

- [ ] **Step 1: Rename the VulgarFractions test**

In `test/vulgar_fractions_test.rb`, replace line 156:
```ruby
  def test_backward_compatible_without_unit
```

with:
```ruby
  def test_format_without_unit
```

- [ ] **Step 2: Remove the backward-compatible comment**

In `test/javascript/search_match_test.mjs`, replace line 31:
```javascript
// Single token — backward compatible
```

with:
```javascript
// Single token
```

- [ ] **Step 3: Run both test suites**

```bash
ruby -Itest test/vulgar_fractions_test.rb && npm test
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/vulgar_fractions_test.rb test/javascript/search_match_test.mjs
git commit -m "Clean up compat-flavored test names and comments"
```

---

### Task 6: Full verification

Run the complete test suite and linter to confirm nothing is broken.

- [ ] **Step 1: Run rake (lint + tests)**

```bash
rake
```

Expected: 0 RuboCop offenses, all tests pass.

- [ ] **Step 2: Verify fresh DB setup**

```bash
RAILS_ENV=test bin/rails db:drop db:create db:migrate db:seed
```

Expected: database created, single migration applied, seeds run cleanly.

- [ ] **Step 3: Verify schema version**

```bash
grep 'version:' db/schema.rb
```

Expected: `version: 1`
