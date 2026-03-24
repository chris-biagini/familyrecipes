# Morph Everywhere Design

Replace all targeted Turbo Stream broadcasts (`broadcast_replace_to`, `broadcast_append_to`) with a single `broadcast_refresh_to` on one kitchen-wide stream. Every page subscribes, every mutation triggers a morph, clients re-fetch and Turbo diffs the DOM. Delete/rename notifications remain targeted on a per-recipe stream.

## Stream Topology

**Before:** Two broadcast streams (`[kitchen, "recipes"]`, `[kitchen, :meal_plan_updates]`) plus per-recipe streams (`[recipe, "content"]`). Targeted replacements for recipe changes, page-refresh morphs for meal plan changes.

**After:** One broadcast stream (`[kitchen, :updates]`) plus per-recipe streams (`[recipe, "content"]` — delete/rename only). All updates are page-refresh morphs.

Every view switches to `turbo_stream_from current_kitchen, :updates`. Recipe show pages additionally keep `turbo_stream_from @recipe, "content"` for delete/rename.

## Broadcast Entry Point

```ruby
Kitchen#broadcast_update  # => broadcast_refresh_to(self, :updates)
```

Called from: `RecipeWriteService` (create/update/destroy), `MealPlanActions` (menu/grocery mutations), `CatalogWriteService` (catalog changes).

## Deletions

- **`RecipeBroadcaster`** — gut most of it. Delete: `broadcast`, `broadcast_destroy`, `broadcast_recipe_listings`, `broadcast_ingredients`, `broadcast_recipe_page`, `replace_recipe_content`, `broadcast_referencing_recipes`, `update_referencing_recipes`, `preload_categories`, `append_toast`. Keep: `notify_recipe_deleted`, `broadcast_rename` (targeted to `[recipe, "content"]`).
- **`RecipeBroadcastJob`** — delete entirely. `broadcast_refresh_to` is cheap (no partials to render), no need for an async job.
- **`upsert.turbo_stream.erb`** — delete. Nutrition editor returns JSON only.
- **Global `turbo:before-stream-render` hook** in `application.js` (lines 15-35) — delete. Per-controller `turbo:before-render` hooks already handle morph state preservation.
- **All non-critical toasts** — no "was updated" / "was created" notifications. Only delete/rename messages survive.

## Simplifications

- **`RecipeWriteService`** — calls `kitchen.broadcast_update` instead of `RecipeBroadcastJob.perform_later`. Still calls `RecipeBroadcaster.broadcast_rename` synchronously for slug changes, and passes recipe + parent info to `RecipeBroadcaster` for destroy notifications.
- **`CatalogWriteService`** — calls `kitchen.broadcast_update` instead of `MealPlan.broadcast_refresh`.
- **`MealPlanActions`** — `broadcast_meal_plan_refresh` becomes `current_kitchen.broadcast_update`.
- **`NutritionEntriesController`** — drops `respond_to` format branching; returns JSON only. The broadcast morph updates the ingredients page.

## Unchanged

- **Stimulus controllers** — `menu_controller.js`, `grocery_ui_controller.js`, `recipe_state_controller.js` keep their `turbo:before-render` hooks for morph state preservation (aisle collapse, expanded details, localStorage).
- **`nutrition_editor_controller.js`** — still saves via JSON, closes dialog. Loses turbo stream response path.
- **Delete/rename** — `notify_recipe_deleted` and `broadcast_rename` stay as targeted replacements on `[recipe, "content"]` because morph cannot express "this resource no longer exists."

## Toast Policy

Only severe notifications survive: recipe deleted while viewing it, recipe renamed (redirect link). All "was updated/created/deleted" toasts on listing pages are removed.

## Trade-offs

- **Spurious morphs** — a recipe edit triggers a morph on the groceries page even if unrelated to the shopping list. Cost is near-zero: client fetches page, Turbo diffs, finds nothing changed.
- **Per-client re-fetch** — N clients each make an HTTP request vs. one server-side render fanned out. Negligible at homelab scale; solvable with fragment caching if needed later.
- **Morph round-trip** — saving user sees their change after a morph round-trip rather than an instant targeted replacement. Imperceptible in practice.

## Test Impact

- `RecipeBroadcasterTest` — rewrite for slimmed-down class (delete/rename only).
- Controller tests stubbing `broadcast_replace_to` — simplify to assert `broadcast_refresh_to`.
- Nutrition entry tests — drop turbo stream format assertions; JSON-only responses.
