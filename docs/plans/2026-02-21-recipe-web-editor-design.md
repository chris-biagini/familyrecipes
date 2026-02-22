# Recipe Web Editor — Design Document

**Date:** 2026-02-21
**Status:** Approved

## Overview

Add a web-based recipe editor to the Rails app. Users click an Edit button on any recipe page, which opens a `<dialog>` modal containing the raw markdown source. They edit the markdown, click Save, and the page reloads with the updated content. No authentication for v1 — this is a homelab app.

## Decisions

- **After save:** Full page reload (not DOM swap or Turbo). Simple, reliable, no stale state.
- **Validation:** Validate before save, block on errors. Warnings (nutrition gaps) are non-blocking.
- **Title edits:** Allowed. Title changes produce new slugs/URLs. Old URL 404s — no redirect mapping for v1.
- **Source of truth:** Database. Markdown files on disk are the initial seed only. `db:seed` skips recipes with `edited_at` timestamps.
- **Access control:** Deferred. Anyone who can reach the page can edit.

## UI & Interaction Flow

Edit button sits next to the existing Scale button in the nav, styled identically (`.btn` class):

```html
<div>
  <button type="button" id="edit-button" class="btn">Edit</button>
  <button type="button" id="scale-button" class="btn">Scale</button>
</div>
```

Clicking Edit opens a native `<dialog>` via `showModal()`. The dialog contains:

- Header bar with recipe title and close button (X)
- Error area (hidden by default, shows validation errors)
- Textarea pre-filled with `markdown_source` (monospace, generous height)
- Footer bar with Cancel and Save buttons

The `::backdrop` pseudo-element dims the page behind the dialog. The dialog itself uses the cream/paper background — aesthetically, it's the "notes page" at the back of the cookbook.

**Save flow:**
1. User clicks Save
2. JS sends `PATCH /recipes/:slug` with JSON body `{ markdown_source: "..." }`
3. Controller validates markdown via parser pipeline
4. On success: responds with `{ redirect_url: "/recipes/new-slug" }`
5. JS does `window.location = redirect_url` (full page reload)
6. On 422: responds with `{ errors: [...] }`, JS renders errors, dialog stays open

**Cancel/Close:** Closes the dialog. If textarea has been modified, intercepts the `cancel` event and shows a `confirm()` prompt to prevent accidental loss.

**Unsaved changes protection:** `beforeunload` listener added while dialog is open, removed on close.

## Backend

### Route

```ruby
resources :recipes, only: [:show, :update], param: :slug
```

Adds `PATCH /recipes/:slug` → `RecipesController#update`.

### Controller

```ruby
def update
  @recipe = Recipe.find_by!(slug: params[:slug])
  markdown_source = params[:markdown_source]

  errors = validate_markdown(markdown_source)
  if errors.any?
    render json: { errors: errors }, status: :unprocessable_entity
    return
  end

  recipe = MarkdownImporter.import(markdown_source)
  recipe.update!(edited_at: Time.current)
  render json: { redirect_url: recipe_path(recipe.slug) }
end
```

### Validation

A private method (or small service) that parses the markdown without saving:

- Runs `LineClassifier.classify` + `RecipeBuilder.new(tokens).build`
- Checks for required `Category:` front matter
- Checks that the parsed title produces a valid slug
- Parse errors return as human-readable strings

Cross-reference targets that don't exist are warnings, not errors — the target recipe might not exist yet.

### CSRF

Add `<%= csrf_meta_tags %>` to the layout `<head>`. The editor JS reads the token from `meta[name="csrf-token"]` and includes it in fetch headers.

## Database Changes

### Migration: add `edited_at` to recipes

```ruby
add_column :recipes, :edited_at, :datetime, null: true
```

Null means "never edited via the web" (i.e., came from a seed file). Set by `RecipesController#update`, never by `MarkdownImporter`.

### `db:seed` protection

Seeds check `edited_at` before importing:

```ruby
existing = Recipe.find_by(slug: FamilyRecipes.slugify(title))
next if existing&.edited_at.present?
```

## JavaScript

New file: `app/assets/javascripts/recipe-editor.js`, included on recipe pages via `content_for(:scripts)`.

Responsibilities:
- Edit button click → `dialog.showModal()`
- Close/Cancel → `dialog.close()` (with unsaved-changes confirmation)
- Save → `fetch('PATCH')` with JSON body and CSRF token
- On success → `window.location = redirect_url`
- On 422 → render errors into the error div
- Disable Save button during request (prevent double-submit)
- `beforeunload` listener while dialog is open

Reads recipe slug from `document.body.dataset.recipeId` (already present).

## CSS

Minimal additions to `style.css`:
- `dialog::backdrop` — semi-transparent dark overlay
- Dialog gets cream/paper background, matching the cookbook page
- Textarea: monospace, full-width, generous height
- Error area: red text between header and textarea
- `btn-primary` variant for Save: warm red accent
- Responsive: dialog goes nearly full-screen on mobile

## Edge Cases

### Empty categories
After save, clean up categories with zero recipes:
```ruby
Category.left_joins(:recipes).where(recipes: { id: nil }).destroy_all
```

### `recipe_map` from disk
`RecipesController#calculate_nutrition` currently builds `recipe_map` by parsing all `.md` files from disk. Once the database is the source of truth, this must come from the database instead. Fix as part of this work.

### Scale state invalidation
A save changes the `data-version-hash` (SHA256 of markdown source). On reload, `RecipeStateManager` detects the hash mismatch and resets scale factor and crossed-off state. This is intentional — ingredient quantities may have changed.

### Nutrition data gaps
If an edit adds an ingredient not in `nutrition-data.yaml`, the nutrition table renders with missing data. Same behavior as today during seeding. User can run `bin/nutrition --missing` to fill gaps.

### Cross-reference integrity
If a recipe is renamed, cross-references from other recipes to this one break (they reference the old slug). Acceptable for v1 — user edits the referencing recipes to fix. Future enhancement: warn about inbound references before allowing title changes.

### Concurrent edits
No locking or conflict detection for v1. Last save wins. Acceptable for homelab scale.
