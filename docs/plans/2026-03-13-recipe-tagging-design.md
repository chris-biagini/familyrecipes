# Recipe Tagging Design

## Overview

Add a tagging system to recipes as a cross-cutting dimension supplemental to
the existing category hierarchy. Tags are single-word, kitchen-scoped labels
(e.g., "vegan", "quick", "weeknight") that enable faceted search filtering and
recipe discovery without disrupting the category-based homepage structure.

## Goals

- Tag recipes with arbitrary single-word labels for dietary restrictions, prep
  style, or any other cross-cutting concern
- Filter recipes by tag (and category) in the search overlay via colored pills
- Display tags on recipe detail pages as clickable filters
- Provide a management dialog for renaming and deleting tags kitchen-wide
- Autocomplete existing tags in the editor to promote consistency

## Non-Goals

- Replacing categories with tags — categories remain the primary homepage
  structure
- Multi-word tags — use hyphens or underscores instead
- Tag hierarchy or nesting
- Tag-based homepage grouping (future redesign may add this)

## Data Model

### New Tables

```
tags
  id            integer PK
  kitchen_id    integer FK (acts_as_tenant)
  name          string  (single-word, no whitespace, lowercase)
  created_at    datetime

  unique index on [kitchen_id, name]
```

```
recipe_tags
  id            integer PK
  recipe_id     integer FK
  tag_id        integer FK

  unique index on [recipe_id, tag_id]
```

### Model Relationships

- `Tag` — `acts_as_tenant :kitchen`, `has_many :recipe_tags, dependent:
  :destroy`, `has_many :recipes, through: :recipe_tags`
- `Recipe` — `has_many :recipe_tags, dependent: :destroy`, `has_many :tags,
  through: :recipe_tags`
- `RecipeTag` — `belongs_to :recipe`, `belongs_to :tag`

### Tag Name Rules

- Characters restricted to `[a-zA-Z-]` (letters and hyphens only)
- Stored and displayed lowercase (downcased on save)
- No slug column — for single-word lowercase tags, the name itself serves as
  the identifier in any URL context
- Kitchen-scoped uniqueness on name
- Validated server-side on the `Tag` model; client-side the tag input field
  rejects disallowed characters on keypress

### Orphan Cleanup

`Tag.cleanup_orphans(kitchen)` deletes tags with no recipe associations,
following the same pattern as `Category.cleanup_orphans`.

## Search Overlay

### Data Changes

`SearchDataHelper#search_data_json` expands to include:
- A `tags` array on each recipe entry
- Top-level `all_tags` and `all_categories` arrays for pill recognition

```json
{
  "all_tags": ["vegan", "quick", "weeknight", "kosher", "gluten-free"],
  "all_categories": ["Breads", "Soups", "Desserts"],
  "recipes": [
    {
      "title": "Miso Soup", "slug": "miso-soup",
      "description": "A warming bowl...",
      "category": "Soups",
      "tags": ["vegan", "quick"],
      "ingredients": ["dashi stock", "miso paste"]
    }
  ]
}
```

### DOM Strategy

The existing search `<input>` cannot contain child elements (pills). Replace
it with a wrapper `<div>` containing pill `<span>` elements and a real
`<input>` for the text portion. The wrapper is styled to look like a single
input field. Pills are built with `createElement`/`textContent` (no
`innerHTML`) to satisfy CSP. The hidden real input stays focused for keyboard
events.

This is the same pattern used by the editor tag input — the search overlay
version is simpler since pills are only added via recognition, not
autocomplete.

### Pill Recognition Flow

1. On each keystroke, check if the current word-being-typed is a prefix of any
   known tag or category name
2. On exact match: show a subtle visual hint (underline or color change)
3. On space/enter after exact match: convert word to a colored pill
   - Tag pills: warm neutral (`--tag-bg` / `--tag-text`)
   - Category pills: sage green (`--cat-bg` / `--cat-text`)
4. Backspace at pill boundary: dissolve pill back to plain text
5. Click × on pill: remove entirely

### Filtering Logic

- **No pills:** Existing behavior — tiered substring matching across all
  fields
- **With pills:** Each pill matches recipes that have the tag/category OR
  contain the pill's text in any searchable field (title, description,
  ingredients). All pills must match (AND). Remaining free text is
  substring-matched as before.
- Tier ranking still applies within the filtered set

The OR-text rule prevents surprising exclusions: a recipe called "Vegan Soup"
appears for a `[vegan]` pill even if not tagged, because "vegan" appears in
its title.

### No Server Endpoint

Search remains fully client-side. The JSON blob grows slightly (tag arrays)
but stays well within payload budget.

**Breaking change:** The search data format changes from a flat array of
recipe objects to a top-level object with `all_tags`, `all_categories`, and
`recipes` keys. The `search_overlay_controller` must be updated to parse the
new structure (`data.recipes` instead of `data` directly).

## Editor Tag Input

### Desktop Layout: Side Panel

The editor dialog gains a right side panel (~200px) on desktop that groups
recipe metadata:

- **Left:** Markdown textarea (full height, unchanged)
- **Right:** Side panel with `surface-alt` background containing:
  - Category dropdown (moved from bottom row)
  - Tag input area: existing tags as pills with × to remove, text input
    with autocomplete for adding new tags

Dialog width increases from `50rem` to approximately `56rem`.

### Mobile Layout: Collapsible Drawer

On mobile (narrow viewports), the side panel collapses into a toggle bar
between the textarea and footer:

- **Collapsed (default):** "Category & Tags" label with tiny pill previews of
  current tags. Textarea keeps full height.
- **Expanded:** Category dropdown and tag input area, same as desktop side
  panel content but stacked vertically.

### Tag Input Interaction

- Type in the tag field → autocomplete dropdown shows matching existing tags
  with recipe counts
- Enter/Tab/click to select from autocomplete → renders as pill
- Type a new word + Enter → added as pill (tag created on save)
- Click × on pill → tag removed from recipe
- Autocomplete data: kitchen's full tag list, embedded as a data attribute on
  the tag row element (client-side, no server round-trip)
- **Loading existing tags:** The recipe's current tags are embedded as a JSON
  data attribute on the tag input element in the server-rendered editor
  template (e.g., `data-tag-input-tags-value='["vegan","quick"]'`). The
  `tag_input_controller` reads this on connect to render initial pills.

### Stimulus Architecture

New `tag_input_controller`:
- Manages the tag input field, autocomplete dropdown, and pill rendering
- Exposes a `tags` getter that returns the current tag name array
- Exposes a `modified` getter that returns whether tags have changed from
  their initial state
- Listens to `editor:reset` to restore original tags on cancel
- Autocomplete queries kitchen's tag list from embedded data attribute

**Event coordination:** `recipe_editor_controller` remains the sole handler
for `editor:collect`. It is modified to also gather tags from
`tag_input_controller` (accessed via Stimulus outlet or DOM query) and include
them in the `event.detail.data` object alongside `markdown_source` and
`category`. This avoids multiple controllers competing for the same event.

**Dirty checking:** `recipe_editor_controller` already handles
`editor:modified`. It is modified to also check `tag_input_controller.modified`
and set `event.detail.modified = true` when tags have changed. This ensures
the unsaved-changes guard fires when tags are added or removed.

## Recipe Detail Page

Tags display in the existing `recipe-meta` line after category and
serves/makes metadata:

```
SOUPS · Serves 4 · vegan · quick
```

- Tag pills use the same warm neutral colors as in search and editor
- Rendered at the smaller `recipe-meta` size, matching existing typography
- No × buttons — tag removal is editor-only
- Each tag pill is clickable: opens search overlay pre-filtered to that tag
- The `with_full_tree` scope on Recipe is updated to `includes(:tags)` so
  tag data is eager-loaded for rendering

## Tag Management

### Dialog

Accessible from the homepage alongside "Edit Categories." Reuses the
`ordered_list_editor_controller` with a new "no ordering" mode:

- List of all tags in the kitchen, sorted alphabetically
- Each row: tag name (click to rename inline), delete button (×)
- No reordering arrows (tags are unordered)
- Same visual row style, rename input, and deleted/renamed state highlighting
  as aisle and category list editors

The "no ordering" mode is activated via a data attribute on the controller
element. This requires changes to the shared `ordered_list_editor_utils.js`:
`buildControls` must conditionally skip up/down arrow creation, and
`buildRowElement` must pass the ordering flag through. The controller passes
the flag from its data attribute into the utility functions.

### Operations

- **Rename:** Updates `tags.name`. All recipe associations remain intact via
  foreign keys. Validates uniqueness of new name within the kitchen.
- **Delete:** Destroys the tag record. `recipe_tags` cascade via
  `dependent: :destroy`.

## Write Service Integration

### RecipeWriteService

Gains tag handling in the recipe save flow:
- Accepts a `tags:` parameter (array of tag name strings from the editor)
- Finds or creates `Tag` records for each name in the kitchen
- Syncs the recipe's tag associations (add new, remove absent)
- Calls `Tag.cleanup_orphans(kitchen)` after removal to garbage-collect
  unused tags

**Params flow:** The `editor:collect` event produces a data object with
`markdown_source`, `category`, and `tags` keys. `RecipesController` forwards
`params[:tags]` (a JSON array of strings) to `RecipeWriteService` alongside
the existing `markdown_source` and `category` params.

### TagWriteService (New)

Service for the management dialog. Follows the same changeset pattern as
`CategoryWriteService` — the management dialog submits a single changeset:
- `update(renames:, deletes:)` — processes all rename and delete operations
  in one call
- Validates uniqueness of renamed tag names within the kitchen
- Broadcasts `Kitchen#broadcast_update` after mutations

### TagsController (New)

Thin CRUD controller for the management dialog. Delegates to
`TagWriteService`. Kitchen-scoped via `current_kitchen`.

### Broadcast

Tag mutations broadcast via the existing kitchen-wide `broadcast_update`
pattern. Clients re-fetch their current page and Turbo morphs the result. No
new ActionCable channels needed.

## Open Questions

None — all key decisions resolved during brainstorming.
