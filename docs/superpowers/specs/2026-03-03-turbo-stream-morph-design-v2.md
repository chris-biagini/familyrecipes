# Turbo Stream Morph Refactor — Design (v2)

Revision of `2026-03-03-turbo-stream-morph-design.md`. Simplifies the
original plan based on a second-pass review.

## Problem

The groceries page has two parallel rendering paths: server-rendered ERB on
initial load and a full client-side DOM rebuild from JSON on every state update.
Every piece of rendering logic (`formatAmounts`, `aisle_count_tag`,
`shopping_list_count_text`, `updateAisleCounts`) exists in both Ruby and
JavaScript. Changes to one must be mirrored in the other, and mismatches cause
visible flashes.

The menu page has a lighter variant — it patches checkboxes and availability
dots from JSON rather than rebuilding DOM, but relies on the same JSON polling
pipeline (`MealPlanSync`).

## Solution

Replace the JSON+JS rendering pipeline with Turbo Stream morphing. Server-
rendered ERB is the single rendering path. Mutations return inline Turbo Stream
morph responses (fast for the acting client on cellular) and broadcast morphs to
other devices. `MealPlanChannel`, `MealPlanSync`, `grocery_sync_controller`, and
all client-side rendering/formatting code are deleted.

## Scope

Both groceries and menu pages. `MealPlanSync` and `MealPlanChannel` are deleted
entirely. The ingredient popover on the menu page is dropped.

## Changes from v1 Design

| v1 Plan | v2 |
|---|---|
| `MealPlanBroadcasting` controller concern | `MealPlanBroadcaster` standalone service |
| `OfflineQueue` utility (~50 lines) | Dropped. Simple fetch retry instead. |
| `_custom_items_list_items.html.erb` partial | Dropped. Morph the whole `#custom-items-section`. |
| Ingredient popover preserved | Dropped. Dots convey enough. |
| `RecipeBroadcaster` uses `replace` on `#recipe-selector` | Switches to morph (preserves checkbox state). |
| Gradual transition with deprecated methods | Clean cut-over of `MealPlanActions`. |
| Toast notifications deferred | Confirmed dropped. |
| Inline `sendAction` in each controller | Shared `turbo_fetch.js` utility. |

## Architecture

### Mutation Flow

```
User clicks checkbox
  → Stimulus: optimistic toggle (checkbox.checked = true/false)
  → fetch PATCH (Accept: text/vnd.turbo-stream.html)
  → Server: mutate MealPlan
  → Server: MealPlanBroadcaster.broadcast_grocery_morph(kitchen)
            and/or broadcast_menu_morph(kitchen)
  → Server: render turbo_stream morph response (inline, for acting client)
  → Turbo: renderStreamMessage(html) applies morph to actor's DOM
  → Broadcast: morphs all other connected clients
               (no-op for actor since DOM already matches)
```

Same pattern for custom item add/remove, select-all, clear, aisle order.

### Fetch Retry

On fetch failure, retry up to 3 times with exponential backoff (1s, 2s, 4s).
This covers momentary cellular hiccups at the grocery store. Without retry, a
broadcast from another device could morph the acting client's DOM back to server
state, reverting an optimistic toggle the server never received.

After all retries exhaust (~7 seconds), the action is lost. The optimistic
toggle persists until the next page load or broadcast corrects it. This requires
sustained outage plus concurrent changes from another device — a narrow edge
case.

### Broadcasting

All broadcasting uses `Turbo::StreamsChannel`. `MealPlanChannel` is deleted.

Pages subscribe in ERB:

```erb
<%# groceries/show.html.erb %>
<%= turbo_stream_from current_kitchen, "groceries" %>

<%# menu/show.html.erb (adds to existing recipe/menu_content streams) %>
<%= turbo_stream_from current_kitchen, "menu" %>
```

### Cross-Broadcast Matrix

| Action | Groceries stream | Menu stream |
|---|:---:|:---:|
| `groceries#check` | yes | yes (availability dots) |
| `groceries#update_custom_items` | yes | no |
| `groceries#update_aisle_order` | yes | no |
| `menu#select` | yes | yes |
| `menu#select_all` | yes | yes |
| `menu#clear` | yes | yes |
| `menu#update_quick_bites` | yes | yes (via RecipeBroadcaster) |
| Recipe CRUD | yes | yes (via RecipeBroadcaster) |

### MealPlanBroadcaster Service

Standalone service with class methods. Shared by controllers and
`RecipeBroadcaster`. Takes `kitchen` as a parameter.

```ruby
MealPlanBroadcaster.broadcast_grocery_morph(kitchen)
MealPlanBroadcaster.broadcast_menu_morph(kitchen)
MealPlanBroadcaster.broadcast_all(kitchen)
```

Each method loads the `MealPlan`, builds the full locals hash (via
`ShoppingListBuilder`, `RecipeAvailabilityCalculator`, etc.), and calls
`Turbo::StreamsChannel.broadcast_action_to` with `action: :morph`.

`broadcast_menu_morph` includes selection state and availability data so the
morphed HTML has correct checkboxes and dots.

### MealPlanActions Concern (Rewritten)

Clean cut-over. Two methods:

- `mutate_plan { |plan| ... }` — loads plan, retries on optimistic lock,
  returns plan
- `apply_plan(action_type, **params)` — calls `mutate_plan` + `apply_action` +
  prune-on-deselect

Controllers call `apply_plan`, then `MealPlanBroadcaster`, then render their own
inline Turbo Stream morph response.

### Controller Response Pattern

Both controllers render inline morph responses via private
`render_grocery_morph` / `render_menu_morph` methods. These build the same
locals hash as the broadcaster and render `turbo_stream.action(:morph, ...)`.
The controller renders (returns to the actor) while the broadcaster broadcasts
(pushes to all subscribers).

### Optimistic UI

Stimulus toggles `checkbox.checked` immediately on click. When the inline morph
arrives from the server, it carries the same checked state — morph sees DOM and
new HTML agree, so it's a no-op on that element. If the server rejects the
action (stale lock, validation), the morph carries the corrected state and flips
the checkbox back. Self-correcting.

### Availability Dots

Moved from client-side JS rendering to server-side ERB in the recipe selector
partial. Each recipe gets a `<span class="availability-dot">` with
`data-missing="0|1|2|3+"` and an `aria-label` with the count. Quick bites get
binary dots (`"0"` or `"3+"`). No popover — the dots alone convey status.

### Aisle Collapse Preservation

Server renders all `<details>` with `open`. Morph would re-open collapsed
aisles. The Stimulus controller intercepts `turbo:before-stream-render`,
snapshots collapse state, lets the morph run, then restores. ~10 lines.

## View Changes

### Groceries

- `show.html.erb`: Add `turbo_stream_from`, remove `grocery-sync` controller
  and `data-state-url`
- `_shopping_list.html.erb`: No changes (already correct)
- `_custom_items.html.erb`: Add `id="custom-items-section"` to outer div

### Menu

- `show.html.erb`: Add `turbo_stream_from` for `"menu"` stream, remove
  `data-state-url`, remove `#ingredient-popover` div
- `_recipe_selector.html.erb`: Add `availability: {}` to locals, render
  availability dots after each recipe checkbox

### Service Worker

Remove `state` from API_PATTERN for both groceries and menu routes.

## Stimulus Controllers

### `grocery_ui_controller.js` (~60 lines)

Keeps: optimistic checkbox toggle, aisle count update, custom item input
binding, aisle collapse persistence, morph collapse preservation.

Deleted: `renderShoppingList`, `renderCustomItems`, `syncCheckedOff`,
`renderItemCount`, `updateAisleCounts`, `applyState`, `syncController` getter,
`formatAmounts`, `formatNumber`.

### `menu_controller.js` (~40 lines)

Keeps: optimistic checkbox toggle, select-all/clear button handlers.

Deleted: `syncCheckboxes`, `syncAvailability`, `showIngredientPopover`,
`populatePopover`, `positionPopover`, `MealPlanSync` import, popover target,
popover event listeners.

### Shared `turbo_fetch.js` utility

```javascript
export function sendAction(url, params, method = "PATCH", retries = 3) {
  // fetch with Accept: text/vnd.turbo-stream.html
  // on success: Turbo.renderStreamMessage(html)
  // on failure: retry with exponential backoff (1s, 2s, 4s)
  // after all retries exhausted: give up silently
}
```

## Deleted Code

### Files deleted entirely
- `app/javascript/utilities/meal_plan_sync.js` (221 lines)
- `app/javascript/controllers/grocery_sync_controller.js` (46 lines)
- `app/channels/meal_plan_channel.rb` (36 lines)
- `test/channels/meal_plan_channel_test.rb`

### Code removed from existing files
- `GroceriesController#state` + route
- `MenuController#state` + route
- `MealPlanActions#apply_and_respond`, `#mutate_and_respond`
- All `MealPlanChannel` references
- `grocery_ui_controller.js`: ~240 lines of rendering/formatting code
- `menu_controller.js`: ~150 lines of sync/availability/popover code
- `#ingredient-popover` div and popover CSS

## New Code

- `app/services/meal_plan_broadcaster.rb` + test
- `app/javascript/utilities/turbo_fetch.js` (~20 lines)

## Net Change

~600 lines deleted, ~150 lines added. Two rendering paths become one. One custom
ActionCable channel eliminated. One 221-line sync engine eliminated.

## Trade-offs

- **Morph maturity**: Stream-level morph is newer than page-level morph. Less
  battle-tested. Mitigated by thorough testing and simple partials.
- **No cold-start cache**: Without localStorage state cache, no instant render
  from cache on page load. Server must respond. Turbo Drive page cache handles
  back-navigation.
- **Retry exhaustion**: If all 3 retries fail (~7s), the check is lost. Requires
  sustained outage plus concurrent broadcast to cause visible reversion.
- **Double morph**: Acting client gets morph from both HTTP response and
  broadcast. Second is a no-op. Tiny wasted work, no visible effect.
- **RecipeBroadcaster coupling**: Now calls `MealPlanBroadcaster` instead of
  `MealPlanChannel`. Service-to-service dependency is cleaner than the old
  service-to-channel dependency.
