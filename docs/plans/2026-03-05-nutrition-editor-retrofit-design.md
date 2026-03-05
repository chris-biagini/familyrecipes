# Nutrition Editor Retrofit Design

Retrofit the nutrition editor to use the shared `editor_dialog` layout, fixing validation issues and consolidating CSS along the way. Addresses GH #182.

## Context

The nutrition editor has its own bespoke dialog HTML in `ingredients/index.html.erb` that duplicates the structure of `shared/_editor_dialog.html.erb`. The shared editor controller (`editor_controller.js`) already provides lifecycle events (`editor:collect`, `editor:save`, `editor:modified`, `editor:reset`) designed for custom dialogs to hook into. The nutrition editor should use these instead of reimplementing dialog lifecycle management.

## Changes

### 1. View: Shared Dialog Layout

Replace the hand-rolled `<dialog>` in `ingredients/index.html.erb` (lines 24-49) with `render layout: 'shared/editor_dialog'`. The yield block contains the Turbo Frame for the form.

Key locals:
- `title: 'Edit Nutrition'` (dynamically updated by JS when an ingredient is selected)
- `dialog_data: { extra_controllers: 'nutrition-editor', editor_on_success: 'close' }`
- `extra_data` carries `nutrition-editor-base-url-value` and `nutrition-editor-edit-url-value`

No `editor_open` selector — the nutrition controller handles opening via global click delegation on `[data-open-editor]` buttons.

### 2. JS: Companion Controller via Lifecycle Events

The nutrition controller (~440 lines) becomes a companion (~250 lines) that delegates dialog lifecycle to the editor controller.

**Event hooks provided by nutrition controller:**
- `editor:collect` — collects form data (nutrients, density, portions, aisle, aliases)
- `editor:save` — validates collected data; returns synthetic 422 Response if invalid, real fetch POST if valid
- `editor:modified` — compares current form snapshot to original
- `editor:reset` — clears `currentIngredient` and `originalSnapshot`

**Open flow:** The nutrition controller sets up the Turbo Frame src and title, then calls the editor controller's `open()` via `this.application.getControllerForElementAndIdentifier(this.element, 'editor')`. The editor's `open()` clears errors, resets the save button, and calls `showModal()`.

**Removed from nutrition controller:** `dialog` target (use `this.element`), `saveButton`/`errors` targets, save button state management, error display during save, close-with-confirmation, cancel event interception.

**Kept:** Open with click delegation, prefetch, portion/alias/aisle form management, reset-to-built-in, form data collection.

### 3. Validation Fix (Sodium)

Client-side validation rejects sodium > 10,000 but `NutritionConstraints::NUTRIENT_MAX` allows 50,000 (salt has sodium of 38,758).

Three-layer fix:
- **HTML:** Dynamic `max` attribute per nutrient from `NUTRIENT_MAX[key.to_s]`
- **JS:** Each nutrient input gets `data-nutrient-max` attribute; `validateForm()` reads it per field instead of hardcoding 10,000
- **Server:** Already correct, no changes needed

### 4. CSS Consolidation

Drop `.nutrition-editor-dialog` entirely. The shared layout uses `.editor-dialog`.

- Promote sticky header/footer and scrollable body to `.editor-dialog` (no-op for textarea editors which handle their own scroll)
- Scope narrow width to `#nutrition-editor { width: min(90vw, 550px); }`

### 5. Save & Next

No Save & Next button exists in the current UI (`next_needing_attention` infrastructure exists but is unused). The shared dialog provides Cancel + Save. Nothing to remove or add.

## Files Changed

| File | Change |
|---|---|
| `app/views/ingredients/index.html.erb` | Replace bespoke dialog with shared layout |
| `app/views/ingredients/_editor_form.html.erb` | Dynamic `max` and `data-nutrient-max` attributes |
| `app/javascript/controllers/nutrition_editor_controller.js` | Slim to companion; event hooks instead of standalone lifecycle |
| `app/assets/stylesheets/style.css` | Drop `.nutrition-editor-dialog`, promote sticky/scroll, scope `#nutrition-editor` width |
| `app/javascript/controllers/editor_controller.js` | No changes expected |
