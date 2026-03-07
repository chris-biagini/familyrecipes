# Categories Refinement Design

GitHub Issue: #185

## Summary

Move recipe categories from front matter (`Category: Bread`) to a purely structural concept: categories are DB records with a position column, assigned via a dropdown in the recipe editor, and managed through a dedicated "Edit Categories" dialog on the homepage. This is a clean break — `Category:` is removed from the parser, markdown source, and seed files. The design also extracts shared ordered-list-editor logic from the existing aisle editor to avoid duplication.

## Decisions

- **Category is structural, not embedded.** Markdown source no longer contains `Category:`. Export uses folder names; future import (#186) infers category from folder.
- **"Miscellaneous" is the fallback.** New recipes default to it. Deleted categories reassign their recipes to it.
- **Clean break, no backwards compat.** `Category:` in front matter becomes a parser error, not a silently ignored line. All stored markdown is migrated.
- **Shared utility module (Approach B).** Extract ordered-list logic into `ordered_list_editor_utils.js` and a Rails `OrderedListEditor` concern. Each editor (aisle, category) remains a standalone Stimulus controller delegating to the shared utility.
- **Category position column retained.** Categories use the existing `position` integer column on the model, not a text column on Kitchen.

## Data Model Changes

No schema changes. `Category` already has `name`, `slug`, `position`, `kitchen_id`. `Recipe` already has `category_id`.

`Category.cleanup_orphans` is simplified or removed — category deletion reassigns recipes rather than orphaning them, so orphans can't occur through normal operations.

## Parser Pipeline Changes

- **`LineClassifier`** — front matter regex narrows from `(Category|Makes|Serves)` to `(Makes|Serves)`.
- **`RecipeBuilder`** — `parse_front_matter` drops the `category` field.
- **`FamilyRecipes::Recipe`** — remove `category` from `validate_front_matter`.
- **`MarkdownImporter`** — remove `find_or_create_category`. Category assignment moves to `RecipeWriteService`.
- **`MarkdownValidator`** — remove the `Category is required` validation.
- **Recipe editor JS** — remove `Category` from syntax highlighter regex and placeholder text.
- **Seed files** — strip `Category: X` lines from `db/seeds/recipes/`. Seeder infers category from directory name.

## Write Path Changes

`RecipeWriteService` gains a `category_name:` keyword parameter on `create` and `update`:

- Finds or creates the category by name in the kitchen.
- If blank/nil, defaults to "Miscellaneous".
- `RecipesController` extracts `params[:category]` from the form and passes it through.

`db/seeds.rb` infers category from the parent directory name rather than front matter.

## Category Editor Dialog

**Placement:** "Edit Categories" button in the homepage navbar (members only), next to "Add Recipe" (renamed from "Add New Recipe").

**UX:** Identical to the aisle editor:
- Dialog with category list in position order.
- Each row: name (click to rename inline), up/down/delete/undo buttons.
- Visual states: renamed (yellow), deleted (strikethrough, faded), new (green).
- "Add category" input at the bottom. Cancel/Save footer. Dirty-check guard.

**Delete behavior:** Recipes reassigned to "Miscellaneous" (created if needed). Deleting "Miscellaneous" itself is prevented if recipes would be orphaned.

**Backend:**
- `GET categories/order_content` — returns categories as JSON (name, position, recipe count).
- `PATCH categories/order` — receives `{ category_order, renames, deletes }`, cascades in a transaction.

**Cascade operations:**
- Rename: updates `Category.name` and `Category.slug`.
- Delete: reassigns recipes to "Miscellaneous", destroys the category.
- Reorder: updates `position` on each category.

## Recipe Editor Category Dropdown

**Location:** Bottom-left of the editor dialog chrome, outside the textarea.

**Contents:** All existing categories (alphabetically), separator, "New category..." sentinel.

**"New category..." flow:** Selecting the sentinel reveals a text input (same as the aisle dropdown pattern). Name submitted with the form; `RecipeWriteService` creates the category on save.

**Defaults:** Existing recipe pre-selects its current category. New recipe defaults to "Miscellaneous".

**Saves with the recipe** — no independent PATCH for category assignment.

## Shared Utility Module

### JavaScript: `ordered_list_editor_utils.js`

Extracted from `aisle_order_editor_controller.js`:
- Changeset tracking: item state `{ originalName, currentName, deleted }`, `isModified()`.
- Row rendering: HTML generation with visual state classes.
- Inline rename: click-to-edit, Enter/Escape/blur.
- Reorder animation: swap with CSS transitions.
- Disabled state: first/last row button management.
- Payload building: serializes to `{ order, renames, deletes }`.
- Duplicate checking: case-insensitive collision detection.

Each Stimulus controller owns: targets, values, lifecycle, fetch calls, domain-specific behavior (e.g., recipe counts on category rows).

### Rails: `OrderedListEditor` concern

- Shared validation (max items, max name length, duplicates).
- Transaction wrapper for cascade operations.
- `broadcast_update` after save.
- Each controller defines: which model/column to cascade, what to do on delete.

**Refactor sequence:** Extract from existing aisle editor first, verify it works, then build category editor on top.

## Data Migration

- Strip `Category: X` lines from `markdown_source` on all Recipe records (idempotent).
- Remove `Category: X` lines from seed files in `db/seeds/recipes/`.
- Update `db/seeds.rb` to infer category from directory name.

## Export/Import

**Export:** No change. `ExportService` already uses `recipe.category.name` as folder name.

**Import (#186):** Forward-compatible. ZIP import reads folder names as categories, passes `category_name:` to `RecipeWriteService.create`.
