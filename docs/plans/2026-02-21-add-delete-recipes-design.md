# Add/Delete Recipe Workflow Design

## Overview

Add create and delete workflows for recipes, plus cross-reference maintenance when recipes are renamed or deleted.

## Routes & Controller Actions

Add `create` and `destroy` to `RecipesController`:

```ruby
resources :recipes, only: %i[show create update destroy], param: :slug
```

- **POST /recipes** — validate markdown, import via `MarkdownImporter`, return redirect URL to new recipe page.
- **DELETE /recipes/:slug** — clean up cross-references, destroy recipe, clean up empty categories, return redirect URL to homepage.

Both return JSON matching the existing update pattern (`{ redirect_url: ... }`). The JS handles the redirect.

## Shared Editor Dialog Partial

Extract `app/views/recipes/_editor_dialog.html.erb` from the current inline markup in `recipes/show.html.erb`. Parameters:

- `mode:` — `:create` or `:edit`
- `content:` — textarea content (template for create, `markdown_source` for edit)
- `action_url:` — POST target for create, PATCH target for edit
- `recipe:` — recipe object (edit mode only, for delete button context)

Renders:

- Header: "New Recipe" or "Edit Recipe"
- Textarea with content
- Error display area
- Footer: Cancel + Save (both modes); Delete button (edit mode only, bottom-left, danger styling)
- Data attributes for HTTP method and cross-reference info

## Homepage "New" Button

Use `content_for(:extra_nav)` in `homepage/show.html.erb` to add a "+ New" button — same pattern as Edit/Scale on recipe pages. Opens the editor dialog with this template:

```
# Recipe Title

Optional description.

Category:
Makes:
Serves:

## Step Name (short summary)

- Ingredient, quantity: prep note

Instructions here.

---

Optional notes or source.
```

## Delete Flow

Delete button in the editor dialog footer, bottom-left, visually separated from Cancel/Save. Styled as danger (dark red, distinct from `btn-primary`).

Flow:

1. User clicks Delete in the edit dialog.
2. JS builds a confirm message. If the recipe has inbound cross-references (embedded as `data-referencing-recipes` on the delete button), the message lists them: *"Delete [Title]? Cross-references in [Recipe A], [Recipe B] will be converted to plain text."* Otherwise: *"Delete [Title]? This cannot be undone."*
3. Native `confirm()` dialog — no custom UI.
4. On confirm, JS sends `DELETE /recipes/:slug` with CSRF token.
5. Controller calls `CrossReferenceUpdater.strip_references(recipe)`, then `recipe.destroy!`, then cleans up empty categories.
6. Returns `{ redirect_url: root_path }`.
7. JS navigates to homepage.

## CrossReferenceUpdater Service

New service at `app/services/cross_reference_updater.rb`:

- **`strip_references(recipe)`** — for each recipe that references this one, replace `@[Recipe Title]` with plain `Recipe Title` in `markdown_source`, then re-import via `MarkdownImporter`. Used before deletion.

- **`rename_references(old_title:, new_title:)`** — for each recipe referencing the old title, replace `@[Old Title]` with `@[New Title]` in `markdown_source`, then re-import. Returns list of updated recipe titles (for the toast). Called from the update action when the title changes.

Both work on raw `markdown_source` text. Re-import via `MarkdownImporter` keeps the database consistent.

## Recipe Editor JS Updates

`recipe-editor.js` gains:

- A `mode` concept read from `data-editor-mode` on the dialog: `create` sends POST to `/recipes`, `edit` sends PATCH to `/recipes/:slug`.
- Delete button handler: reads `data-referencing-recipes` for the confirm message, sends DELETE on confirm.
- Cross-reference info is server-rendered into the data attribute (avoids an extra fetch).

## Toast for Cross-Reference Updates on Rename

When the update action detects a title change and `CrossReferenceUpdater.rename_references` updates other recipes, the JSON response includes `updated_references: ["Recipe A", "Recipe B"]`. The recipe show page reads a flash/param on load and shows a brief toast via `notify.js`.

## Dependency Constraint Change

`Recipe.inbound_dependencies` currently uses `dependent: :restrict_with_error`, which prevents deletion. Since the new flow explicitly strips references before destroying, change this to `dependent: :destroy` — by the time `recipe.destroy!` runs, inbound dependencies should already be gone, but `:destroy` acts as a safety net rather than a hard block.

## Empty Category Cleanup

Both `create` (no cleanup needed — categories are created on demand) and `destroy` reuse the existing pattern from the update action: delete categories with zero recipes after the operation.
