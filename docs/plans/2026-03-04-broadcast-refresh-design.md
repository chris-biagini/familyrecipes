# Broadcast Refresh & Editor Redirect-After-POST — Design

GitHub issue: #171

## Problem

`MealPlanBroadcaster` (~107 lines) renders partials server-side and pushes
full HTML over WebSocket to specific DOM targets. Each broadcast runs 16-20
queries to build shopping lists, recipe selectors, and availability data.
The aisle-order and quick-bites editors use custom JS fetch + JSON response
patterns instead of standard Turbo form submission.

## Change: Replace MealPlanBroadcaster with page-refresh broadcasts

Replace all `MealPlanBroadcaster.broadcast_*` calls with
`Turbo::StreamsChannel.broadcast_refresh_to(kitchen, :meal_plan_updates)`.

When clients receive the refresh signal, Turbo Drive re-fetches the current
page and morphs the result (using the existing `turbo-refresh-method: morph`
meta tag). Each page renders its own content — groceries page gets groceries,
menu page gets menu.

**What changes:**

- Delete `app/services/meal_plan_broadcaster.rb` and its test file
- Delete `test/services/meal_plan_broadcaster_test.rb`
- Replace all `MealPlanBroadcaster.broadcast_*` calls in controllers and
  services with `broadcast_meal_plan_refresh(current_kitchen)` (a one-line
  private helper in `MealPlanActions` concern)
- In `RecipeBroadcaster#broadcast`, replace `MealPlanBroadcaster.broadcast_all`
  with direct `Turbo::StreamsChannel.broadcast_refresh_to`
- Change view subscriptions:
  - `groceries/show.html.erb`: `turbo_stream_from current_kitchen, "groceries"`
    → `turbo_stream_from current_kitchen, :meal_plan_updates`
  - `menu/show.html.erb`: drop `turbo_stream_from current_kitchen, "menu"`,
    add `turbo_stream_from current_kitchen, :meal_plan_updates`
    (keep `turbo_stream_from current_kitchen, "recipes"` for RecipeBroadcaster)
- Update broadcast assertions in controller tests:
  `assert_turbo_stream_broadcasts` → check for refresh on the new stream name
- `grocery_ui_controller.js`: add `turbo:before-render` listener to preserve
  aisle collapse state during page-level morph (same localStorage pattern,
  different event)

**Trade-off:** Each update adds one HTTP round-trip per connected client.
The WebSocket signal is tiny (vs. pushing full rendered HTML today). If
WebSocket is connected, HTTP will work too. Turbo debounces rapid refresh
signals into a single fetch.

## Decisions

- **No model-level `broadcasts_refreshes_to`**: explicit calls are clearer
  and don't create hidden save→broadcast coupling
- **Single stream name**: `:meal_plan_updates` for both groceries and menu
  pages — any meal plan change refreshes both (idempotent, harmless)
- **Keep RecipeBroadcaster targeted broadcasts**: recipe-specific streams
  (show page, cross-references, toast notifications) don't fit the refresh
  pattern. Only the meal plan refresh call changes.
- **Editor dialogs unchanged**: aisle-order and quick-bites editors keep
  their JS fetch + `editor_on_success: 'close'` pattern. The refresh
  broadcast handles cross-device sync.
- **Skip `data-turbo-permanent`**: no meaningful candidates in this app
- **Aisle collapse preservation**: listen to `turbo:before-render` for
  page-level morph (same localStorage pattern as current
  `turbo:before-stream-render` handler)

## Files affected

**Delete:**
- `app/services/meal_plan_broadcaster.rb`
- `test/services/meal_plan_broadcaster_test.rb`

**Modify (server):**
- `app/controllers/concerns/meal_plan_actions.rb` — add `broadcast_meal_plan_refresh` helper
- `app/controllers/groceries_controller.rb` — use refresh helper
- `app/controllers/menu_controller.rb` — use refresh helper
- `app/controllers/nutrition_entries_controller.rb` — use refresh helper
- `app/services/recipe_broadcaster.rb` — replace MealPlanBroadcaster call
- `app/views/groceries/show.html.erb` — change stream subscription
- `app/views/menu/show.html.erb` — change stream subscription
- `test/controllers/groceries_controller_test.rb` — update broadcast assertions
- `test/controllers/menu_controller_test.rb` — update broadcast assertions
- `test/services/recipe_broadcaster_test.rb` — update broadcast assertion

**Modify (client):**
- `app/javascript/controllers/grocery_ui_controller.js` — add page-morph aisle preservation

**Update (docs):**
- `CLAUDE.md` — update ActionCable section
- Header comments on modified files
