# Quick Bites & Grocery Aisles in the Database

**Date:** 2026-02-22
**Status:** Approved

## Problem

Quick Bites and grocery aisle mappings are the last two user-facing features still read from flat files at runtime. Quick Bites (`recipes/Quick Bites.md`) are parsed on the fly but never displayed in the Rails app — the groceries page lost its Quick Bites section during the static-to-Rails migration. Grocery aisle data lives in `resources/grocery-info.yaml`. Neither is editable through the web UI.

## Goals

1. Store both documents in the database so they're editable via the web.
2. Restore the Quick Bites section on the groceries page.
3. Convert grocery aisles from YAML to a markdown format consistent with the rest of the app.
4. Drop the alias system (only one entry uses it; the `Inflector` handles singular/plural already).
5. Reuse the existing dialog/editor infrastructure — no new UI patterns.

## Non-goals

- Structured editing UI (forms, drag-and-drop). Both documents are edited as plain text in a textarea.
- Authentication or access control. Same as the recipe editor: open to whoever can reach the page.
- Nutrition data migration. Stays in YAML files — separate concern.

## Schema

One new table, two rows:

```ruby
create_table :site_documents do |t|
  t.string :name, null: false  # "quick_bites" or "grocery_aisles"
  t.text :content, null: false
  t.timestamps
end
add_index :site_documents, :name, unique: true
```

Model: `SiteDocument` with a uniqueness validation on `name`.

## Grocery aisles format

The YAML format is retired. The new format is markdown:

```markdown
## Produce
- Apples
- Garlic
- Lemons

## Refrigerated
- Butter
- Eggs
- Milk

## Omit From List
- Water
- Sourdough starter
```

`## Heading` is an aisle name. `- Item` is an ingredient in that aisle. `Omit From List` replaces `Omit_From_List`. Aliases are dropped entirely.

## Quick Bites format

Unchanged — already markdown. The existing format is stored as-is in the `content` column:

```markdown
# Quick Bites

## Snacks
  - Peanut Butter on Bread: Peanut butter, Bread
  - Goldfish
```

## Parser changes

### `FamilyRecipes.parse_grocery_aisles_markdown(content)`

New method. Parses the markdown format into the same `{ aisle => [{ name: ... }] }` structure the app already expects, minus the `:aliases` key.

### `FamilyRecipes.parse_quick_bites_content(content)`

New method. Same logic as the existing `parse_quick_bites` but takes a string instead of a directory path. The file-based version becomes a thin wrapper (or is retired once seeding is updated).

### `FamilyRecipes.build_alias_map`

Simplified. With aliases dropped, it maps each canonical ingredient name (and its singular form via `Inflector`) to itself. Same return type, simpler internals.

### `FamilyRecipes.parse_grocery_info`

Retained temporarily for the YAML-to-markdown migration in seeds. Can be removed once the YAML file is no longer needed.

## Controller

`GroceriesController` gains two actions:

- **`update_quick_bites`** — receives `{ content: "..." }`, parses to validate, upserts `SiteDocument`, returns JSON.
- **`update_grocery_aisles`** — same pattern.

The `show` action loads both documents from `SiteDocument` instead of from files. It passes parsed Quick Bites (grouped by subsection) to the view.

Validation: the content must parse without error. For aisles, that means at least one `## Heading` with at least one `- Item`. For quick bites, the existing `QuickBite` parser is tolerant by design — any content that doesn't crash is valid.

## Routes

```ruby
get  'groceries',              to: 'groceries#show', as: :groceries
patch 'groceries/quick_bites',  to: 'groceries#update_quick_bites'
patch 'groceries/grocery_aisles', to: 'groceries#update_grocery_aisles'
```

## View

### Edit buttons

Two buttons in the groceries header: "Edit Quick Bites" and "Edit Aisles". Each opens its corresponding `<dialog>`.

### Dialogs

Two new `<dialog>` elements on the groceries page — lightweight variants of the recipe editor dialog. Structure:

```
<dialog data-editor-url="/groceries/quick_bites">
  header (title + close button)
  error display area
  textarea (pre-filled with current document content)
  footer (cancel + save)
</dialog>
```

No delete button. No rename. Same CSS as the recipe editor dialog (`.editor-header`, `.editor-footer`, etc.).

### Quick Bites section (restored)

Below the recipe categories in the recipe selector, matching the old static template:

```html
<div class="quick-bites">
  <h2>Quick Bites</h2>
  <div class="subsections">
    <div class="subsection">
      <h3>Snacks</h3>
      <ul>
        <li>
          <input type="checkbox" data-title="..." data-ingredients="...">
          <label>Peanut Butter on Bread</label>
        </li>
      </ul>
    </div>
  </div>
</div>
```

CSS restored from the old static `groceries.css`: separator, uppercase headings, subsection grid, responsive 3-column layout, print styles.

## JavaScript

### Unified dialog handler

`recipe-editor.js` is generalized to handle all editor dialogs, not just the recipe editor. The existing code is already partially data-driven (`data-editor-mode`, `data-editor-url`). Changes:

- The script finds all `<dialog>` elements with editor data attributes (or a shared class/data attribute).
- Each dialog is independently wired: open button, close, cancel, save, unsaved-changes guard.
- Recipe-specific behavior (delete button, cross-reference toasts, redirect-after-create) is gated on the presence of those elements/attributes — unchanged from today.
- Grocery dialog save behavior: on success, reload the page. The grocery list HTML is server-rendered, so a reload is the simplest way to reflect changes.

This prevents drift: when live-saving or other features are added later, all dialogs get them.

### `groceries.js`

The shopping list JS (`groceries.js`) is unchanged. Quick Bites items use the same `data-ingredients` attribute as regular recipes, so the existing selection/aggregation/sharing logic works without modification.

## Seeding

`db/seeds.rb` gains two upserts:

1. Read `recipes/Quick Bites.md`, store as `SiteDocument(name: "quick_bites")`.
2. Read `resources/grocery-info.yaml`, convert to markdown format (stripping aliases), store as `SiteDocument(name: "grocery_aisles")`.

After seeding, the original files remain in the repo as reference but are no longer read at runtime.

## Migration path

1. Add `site_documents` table.
2. Add `SiteDocument` model.
3. Update parsers (new markdown-based methods).
4. Update seeds to populate `site_documents`.
5. Update `GroceriesController#show` to load from DB.
6. Add `update_quick_bites` and `update_grocery_aisles` actions + routes.
7. Generalize `recipe-editor.js` for multiple dialogs.
8. Add dialogs and edit buttons to the groceries view.
9. Restore Quick Bites section in the groceries view with CSS.
10. Tests for parsing, controller actions, and integration.

## What doesn't change

- **`FamilyRecipes::QuickBite`** — same parser, fed from DB content instead of a file.
- **`groceries.js`** — shopping list logic is data-attribute-driven, doesn't care about data source.
- **`IngredientAggregator`** — unchanged, works on the same `Ingredient` objects.
- **Nutrition data** — stays in YAML, separate concern entirely.
- **Recipe editor** — gains no new behavior, just shares its JS infrastructure.
