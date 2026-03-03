# Turbo Stream Morph Refactor — Design

## Problem

The groceries page has two parallel rendering paths: server-rendered ERB on
initial load and a full client-side DOM rebuild from JSON on every state update.
This duplication means every piece of rendering logic (`formatAmounts`,
`aisle_count_tag`, `shopping_list_count_text`, `updateAisleCounts`) exists in
both Ruby and JavaScript. Changes to one must be mirrored in the other, and
mismatches cause visible flashes (e.g. aisle count showing "(1)" before JS
replaces it with a checkmark).

The menu page has a lighter variant of the same pattern — it patches checkboxes
and availability dots from JSON rather than rebuilding DOM, but still relies on
the same JSON polling pipeline.

## Solution

Replace the JSON-to-JS rendering pipeline with Turbo Stream morphing. The server
becomes the single rendering path. Mutations return Turbo Stream morph responses;
cross-device sync uses Turbo Streams broadcasting. `MealPlanChannel`,
`MealPlanSync`, and all client-side rendering code are deleted.

## Scope

Both groceries and menu pages. `MealPlanSync` and `MealPlanChannel` are killed
entirely.

## Architecture

### Groceries Mutation Flow

```
checkbox click
  -> Stimulus optimistic toggle (checkbox.checked = true)
  -> fetch PATCH /groceries/check (Accept: text/vnd.turbo-stream.html)
  -> server mutates MealPlan state
  -> server broadcasts morph to [kitchen, "groceries"] stream
  -> server returns turbo_stream.action(:morph, "shopping-list", partial)
  -> Turbo morphs the acting client's DOM (no-op on checkbox, updates counts)
  -> broadcast morphs all other connected clients
```

Same pattern for custom item add/remove.

### Menu Mutation Flow

```
checkbox click
  -> Stimulus optimistic toggle
  -> fetch PATCH /menu/select (Accept: text/vnd.turbo-stream.html)
  -> server mutates MealPlan state
  -> server broadcasts morph to [kitchen, "menu"] stream
  -> server returns turbo_stream.action(:morph, "recipe-selector", partial)
  -> Turbo morphs all clients
```

Same pattern for select-all and clear.

### Broadcasting

All broadcasting uses `Turbo::StreamsChannel`. `MealPlanChannel` is deleted.

Pages subscribe in ERB:

```erb
<%# groceries/show.html.erb %>
<%= turbo_stream_from current_kitchen, "groceries" %>

<%# menu/show.html.erb (adds to existing recipe/menu_content streams) %>
<%= turbo_stream_from current_kitchen, "menu" %>
```

| Event | Broadcast target | Content |
|---|---|---|
| Check-off / custom item change | `[kitchen, "groceries"]` | Morph `#shopping-list` + `#custom-items-list` |
| Recipe select / clear | `[kitchen, "menu"]` | Morph `#recipe-selector` |
| Recipe/Quick Bites/aisle edit | `[kitchen, "groceries"]` | Morph `#shopping-list` |
| Recipe/Quick Bites edit | `[kitchen, "menu"]` | Morph `#recipe-selector` (existing `RecipeBroadcaster` path) |

The acting client receives the morph both in the HTTP response and via the
broadcast. The second morph is a no-op since the DOM already matches.

No toast notifications for remote updates in this iteration. Morphs silently
update the DOM. Toasts can be added later as a Stimulus enhancement.

### Optimistic UI

Stimulus toggles `checkbox.checked` immediately on click. When the morph arrives
from the server, it carries the same checked state — morph sees DOM and new HTML
agree, so it's a no-op on that element. If the server rejects the action (stale
lock, validation), the morph carries the corrected state and flips the checkbox
back. Self-correcting.

### Offline Queue

A lightweight Stimulus utility (~30-40 lines) replaces the 221-line
`MealPlanSync`:

1. Every mutation fetch is wrapped in try/catch
2. On network failure: push `{ url, params, method }` to localStorage
3. On `online` event: flush queue — POST each action to server
4. Server processes and broadcasts morphs

No version tracking, no heartbeat polling, no localStorage state cache.

The localStorage state cache is replaced by Turbo Drive's page cache (shows
cached HTML instantly on back-navigation, fetches fresh copy from server).

### MealPlanActions Concern

`mutate_and_respond` (renders JSON) is replaced by `mutate_plan` (returns the
updated MealPlan). Each controller decides the response format:

```ruby
def check
  plan = mutate_plan('check', item: params[:item], checked: params[:checked])
  broadcast_grocery_morph(plan)
  render_grocery_morph(plan)
end
```

Broadcasting and rendering helpers are extracted into a concern or module shared
by `GroceriesController` and `MenuController`.

### Availability Dots

Currently computed client-side from JSON in `menu_controller.js`. Moves to
server-side rendering in the menu partial. The availability data
(`ShoppingListBuilder` or similar) is computed at render time and dots are
included in the HTML. This eliminates JS availability rendering.

## Deleted Code

### Deleted entirely
- `app/javascript/utilities/meal_plan_sync.js` (221 lines)
- `app/javascript/controllers/grocery_sync_controller.js` (46 lines)
- `app/channels/meal_plan_channel.rb` + test
- `GroceriesController#state` action + route
- JS `formatAmounts` / `formatNumber` functions

### Gutted
- `grocery_ui_controller.js`: ~300 -> ~80 lines. Keeps: optimistic toggle,
  aisle collapse persistence, custom item input, offline queue
- `menu_controller.js`: ~197 -> ~100 lines. Keeps: optimistic toggle, popover,
  select-all/clear, offline queue
- `meal_plan_actions.rb`: `mutate_and_respond` replaced with simpler
  `mutate_plan`

### Deleted helpers
- `GroceriesHelper#aisle_count_tag` (partial is now the only rendering path)
- JS duplicates of all Ruby formatting helpers

## New Code

- Broadcasting concern/helper — methods to morph `#shopping-list`,
  `#custom-items-list`, `#recipe-selector` via Turbo Streams
- Offline queue utility (~30-40 lines of Stimulus JS)
- Availability dot rendering in menu ERB partial
- Updates to `RecipeBroadcaster` to broadcast grocery morphs on content changes

## Trade-offs

- **Morph maturity**: `turbo_stream.action(:morph)` is newer than `replace`.
  Page-level morph is well-proven; stream-level morph is less battle-tested.
  Mitigated by thorough testing.
- **Double morph**: Acting client gets morph from both HTTP response and
  broadcast. Second is a no-op. Acceptable.
- **Cold start**: No localStorage cache for instant render. Server must respond.
  Acceptable — Turbo Drive page cache handles back-navigation, and server
  response is fast.
- **No toast on remote updates**: Dropped for simplicity in this iteration.

## Key Decisions

- Turbo Stream morph over replace (preserves aisle collapse, scroll, checkbox
  state automatically)
- Keep offline action queue (localStorage + flush on reconnect)
- Drop localStorage state cache (Turbo Drive page cache is sufficient)
- Drop remote update toast (add back later if needed)
- Convert both groceries and menu in one pass (kill MealPlanSync entirely)
