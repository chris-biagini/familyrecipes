# Web-Based Nutrition Editor — Design Document

**Date:** 2026-02-23
**Issue:** GH#63 (partial — nutrition editing slice)

## Overview

Add a web-based nutrition data editor to the ingredients page. Kitchen members can enter nutrition facts from product labels in a plaintext textarea that mirrors a US nutrition facts label. An overlay data model lets kitchens customize or supplement the built-in seed data without polluting the shared pool.

## Design Philosophy

The nutrition editor should feel at home in the app's "cookbook that learned new tricks" aesthetic. A plaintext textarea formatted like a nutrition label is the primary input — anyone who's read a cereal box knows the format. No structured form fields, no JavaScript-heavy interactions. The server parses and validates; the dialog opens and closes via the existing `editor-dialog` pattern.

## Data Model: Overlay Nutrition Entries

### The problem

The current `NutritionEntry` table uses `acts_as_tenant(:kitchen)` and seeds identical data into every kitchen. There's no concept of shared/built-in data vs. user-entered data, and no way to manage nutrition info from the web.

### The solution: global + kitchen overlay

**Global entries** (`kitchen_id = NULL`): Seeded from `nutrition-data.yaml`. Managed only via the YAML file and `db:seed` — never editable from the web UI. These are the curated, high-quality built-in entries.

**Kitchen entries** (`kitchen_id = <kitchen>`): Created via the web editor. Override globals by ingredient name (copy-on-write). Can be reset to fall back to global data.

This avoids the MyFitnessPal problem: sloppy user submissions can't corrupt shared data. Each kitchen's overrides are isolated.

### Schema changes

```ruby
# Migration
change_column_null :nutrition_entries, :kitchen_id, true

add_index :nutrition_entries, :ingredient_name,
          unique: true,
          where: 'kitchen_id IS NULL',
          name: 'index_nutrition_entries_global_unique'
```

The existing compound unique index on `(kitchen_id, ingredient_name)` stays for kitchen-scoped entries. The new partial index enforces uniqueness for global entries (PostgreSQL treats NULLs as distinct in regular unique indexes).

### Model changes

```ruby
class NutritionEntry < ApplicationRecord
  # Remove: acts_as_tenant :kitchen
  belongs_to :kitchen, optional: true

  scope :global, -> { where(kitchen_id: nil) }
  scope :for_kitchen, ->(kitchen) { where(kitchen_id: kitchen.id) }

  def global? = kitchen_id.nil?
  def custom? = kitchen_id.present?

  # Merged lookup: kitchen entries override globals by ingredient name
  def self.lookup_for(kitchen)
    global_entries  = global.index_by(&:ingredient_name)
    kitchen_entries = for_kitchen(kitchen).index_by(&:ingredient_name)
    global_entries.merge(kitchen_entries)
  end
end
```

### Seed changes

`db/seeds.rb` creates global entries (`kitchen_id: nil`) instead of per-kitchen entries. Kitchen-scoped overrides are preserved across re-seeds.

### Downstream updates

- `RecipeNutritionJob`: Replace `NutritionEntry.all` with `NutritionEntry.lookup_for(recipe.kitchen)`. Remove `ActsAsTenant.with_tenant` wrapper.
- `BuildValidator`: Use `NutritionEntry.lookup_for` to respect overlay when checking for missing ingredients.

## Ingredients Page Redesign

### Navigation and naming

The nav link changes from "Index" to "Ingredients". The page title changes from "Ingredient Index" to "Ingredients". Routes stay the same.

### Page layout

```
┌──────────────────────────────────────────┐
│  Ingredients                             │
│                                          │
│  ▶ 12 ingredients need nutrition data    │
│    Arugula · Basil · Bay leaves · ...    │
│                                          │
│  ────────────────────────────────────    │
│                                          │
│  Arugula  [!]  [+ Add nutrition]         │
│    Pizza Margherita                      │
│                                          │
│  Butter  [global]  [Edit]                │
│    Croissants · Pound Cake               │
│                                          │
│  Cream cheese  [custom]  [Edit] [Reset]  │
│    Cheesecake                            │
│                                          │
└──────────────────────────────────────────┘
```

### Controller changes

`IngredientsController` loads nutrition status by calling `NutritionEntry.lookup_for(current_kitchen)`. Each ingredient is tagged as:

- `:missing` — no nutrition data at all → shows `[!]` badge and "Add nutrition" link
- `:global` — has global (seed) data only → shows `[global]` badge and "Edit" link
- `:custom` — has kitchen-scoped override → shows `[custom]` badge, "Edit" and "Reset" links

`@missing_ingredients` is extracted for the top banner.

### Auth gating

Badges and edit/add/reset controls only visible to `current_kitchen.member?(current_user)`. Read-only visitors see the ingredient list with recipe links but no editing UI.

### Missing ingredients banner

A `<details>` element (collapsible, no JS). Only rendered when `@missing_ingredients` is non-empty. Each ingredient name is a clickable link that opens the editor dialog for that item.

## Nutrition Editor Dialog

### Dialog structure

A single `<dialog class="editor-dialog">` on the ingredients page. Uses the existing `recipe-editor.js` data-attribute pattern — no new JavaScript files.

Each ingredient's edit/add link carries `data-nutrition-text` (the pre-formatted label string) and `data-ingredient-name`. The existing click handler copies the text into the dialog's textarea and opens it.

### Textarea format — blank skeleton (new entry)

```
Serving size:

Calories
Total Fat
  Saturated Fat
  Trans Fat
Cholesterol
Sodium
Total Carbs
  Dietary Fiber
  Total Sugars
    Added Sugars
Protein
```

### Textarea format — populated (existing entry)

```
Serving size: 1/4 cup (30g)

Calories          110
Total Fat         0g
  Saturated Fat   0g
  Trans Fat       0g
Cholesterol       0mg
Sodium            0mg
Total Carbs       23g
  Dietary Fiber   1g
  Total Sugars    0g
    Added Sugars  0g
Protein           3g

Portions:
  stick: 113g
  ~unitless: 50g
```

### Formatting rules

- Serving size line is always first. Entries with density render as `volume unit (Xg)` (e.g., `1/4 cup (30g)`). Entries without density show just the gram weight (e.g., `30g`).
- Nutrient values include their unit (`g`, `mg`, or bare for calories). Indentation matches FDA label hierarchy.
- Portions section only appears when portions exist. Omitted from the blank skeleton.
- The parser is forgiving: missing values default to 0, unknown lines are ignored.

### Copy-on-write behavior

When editing a global entry, the form submits as a new kitchen-scoped entry pre-filled with the global values. The original global entry is untouched. The UI shows the ingredient as `[custom]` after saving.

### Reset behavior

A "Reset" control on `[custom]` entries sends a DELETE request that destroys the kitchen override. The ingredient falls back to global data.

## NutritionLabelParser Service

**Location:** `app/services/nutrition_label_parser.rb`

### Parsing

```ruby
result = NutritionLabelParser.parse(text)
result.success?   #=> true/false
result.nutrients   #=> { basis_grams: 30.0, calories: 110.0, ... }
result.density     #=> { grams: 30.0, volume: 0.25, unit: "cup" } or nil
result.portions    #=> { "stick" => 113.0 } or {}
result.errors      #=> ["Serving size is required"] (on failure)
```

**Parse strategy:**

1. **Serving size line** — required. Delegates to `NutritionEntryHelpers.parse_serving_size` (existing code in `lib/familyrecipes/`). Extracts gram weight, optional volume (→ density), optional discrete unit (→ auto-portion).

2. **Nutrient lines** — matches known names case-insensitively, strips unit suffixes, extracts numeric values. Missing lines default to 0.

3. **Portions section** — optional. If a `Portions:` header is found, parses indented `name: Xg` pairs.

**Nutrient name mapping:**

| Label text | Field |
|---|---|
| Calories | calories |
| Total Fat | fat |
| Saturated Fat | saturated_fat |
| Trans Fat | trans_fat |
| Cholesterol | cholesterol |
| Sodium | sodium |
| Total Carbs / Total Carbohydrate | carbs |
| Dietary Fiber / Fiber | fiber |
| Total Sugars | total_sugars |
| Added Sugars | added_sugars |
| Protein | protein |

**Validation:**
- Serving size line must be present and parseable (gram weight required)
- `basis_grams` must be > 0
- Nutrient values must be non-negative (or blank → 0)
- Forgiving by default — no other requirements

### Formatting (reverse direction)

`NutritionLabelParser.format(entry)` takes a `NutritionEntry` and produces the plaintext label string for pre-filling the textarea.

### Code reuse

`NutritionEntryHelpers.parse_serving_size` (already in `lib/familyrecipes/nutrition_entry_helpers.rb`) handles the serving size line. No changes needed — the web parser calls it directly. Nutrient line parsing is new but trivial (regex + `to_f`).

## Controller & Routes

### New controller: `NutritionEntriesController`

All actions guarded by `require_membership`.

**`upsert`** — POST `/kitchens/:kitchen_slug/nutrition_entries/:ingredient_name`:
1. Parse `params[:label_text]` via `NutritionLabelParser.parse`
2. On failure: redirect to `ingredients_path` with flash error
3. On success: `NutritionEntry.find_or_initialize_by(kitchen: current_kitchen, ingredient_name:)`
4. Assign parsed attributes + source `[{ "type" => "web", "note" => "Entered via ingredients page" }]`
5. Save, recalculate affected recipes via `RecipeNutritionJob.perform_now`
6. Redirect to `ingredients_path` with flash success

**`destroy`** — DELETE `/kitchens/:kitchen_slug/nutrition_entries/:ingredient_name`:
1. Find kitchen-scoped entry (not global). 404 if not found.
2. Destroy. Recalculate affected recipes (they fall back to global data).
3. Redirect to `ingredients_path` with flash confirmation.

### Recipe recalculation

After upsert or destroy, the controller finds recipes containing the affected ingredient and runs `RecipeNutritionJob.perform_now` for each. Synchronous for now — natural `perform_later` candidate if it becomes slow.

### Source provenance

Kitchen entries are silently tagged with `[{ "type" => "web", "note" => "Entered via ingredients page" }]`. This enables future UI to show provenance without exposing a source editing interface in v1.

## Out of Scope (v1)

- USDA API search from the web UI (future enhancement)
- Source provenance editing in the dialog
- Bulk import/export of nutrition data
- Nutrition data sharing between kitchens
- The broader "tidy up" tab from GH#63 (this is just the nutrition slice)
