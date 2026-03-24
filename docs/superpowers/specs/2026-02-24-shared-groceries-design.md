# Shared Groceries Redesign

## Summary

Transform the groceries page from a static, local-storage-based tool into a live shared
inventory for all kitchen members. State moves to the server, changes sync in real time via
ActionCable, and offline use is supported by a local write buffer. The `NutritionEntry` model
is renamed to `IngredientProfile` and gains an `aisle` column, replacing the markdown aisle
blob entirely. The server takes over ingredient aggregation, and the client becomes a thin
rendering layer.

## Motivation

The current groceries page is a holdover from the static-site era. State lives in local
storage and is shared via URL-encoded QR codes. This means each household member has their
own isolated view, changes don't propagate, and there's no way for someone at home to update
the list while someone else is at the store.

## Design Decisions

### Real-time transport: ActionCable + heartbeat poll

ActionCable (WebSockets) provides instant push notifications. A 30-second heartbeat poll
acts as a safety net for missed broadcasts (dropped connections, mobile dead zones). Solid
Cable adapter backed by PostgreSQL — no Redis dependency.

The channel broadcasts only version numbers (`{ version: 48 }`), not state. Clients that
see a version ahead of their own fetch the full state via HTTP. This keeps the channel
trivial and puts all state delivery through one code path.

Sync flow:
1. User action sends a PATCH to the server
2. Server updates state, bumps version, broadcasts version on ActionCable
3. Other clients receive broadcast, compare versions, fetch if stale
4. Heartbeat poll (every 30s) catches anything missed
5. On WebSocket reconnect, client does an immediate version check

### Conflict resolution: last write wins

Each user action is an independent, idempotent operation (add/remove recipe, check/uncheck
item). No conflict resolution UI. If a checked-off item disappears because the underlying
recipe was deselected by someone else, the check-off is silently discarded.

### Shared vs. personal state

Shared (server, synced across all kitchen members):
- Selected recipes
- Selected quick bites
- Custom items
- Checked-off grocery items

Personal (local storage, per device):
- Aisle collapse/expand state
- Any future UI preferences

### One list per kitchen

A kitchen has exactly one grocery list. To start a new shopping trip, clear the list.
Multiple named lists could be added later if needed.

## IngredientProfile Model (rename from NutritionEntry)

Rename the `nutrition_entries` table and model to `ingredient_profiles`. All references
updated throughout the codebase (model, jobs, controllers, CLI tool, tests, CLAUDE.md).

New column: `aisle` (string, nullable). Stores the aisle name directly: `"Refrigerated"`,
`"Baking"`, `"Produce"`, etc. The sentinel value `"omit"` replaces the old
`Omit_From_List` aisle — these ingredients are excluded from the shopping list.

`basis_grams` becomes nullable to support aisle-only rows (ingredients that have an aisle
assignment but no nutrition data yet).

The overlay model is preserved: global rows (`kitchen_id: nil`) provide defaults, kitchen
rows override. `IngredientProfile.lookup_for(kitchen)` works as before, now returning aisle
alongside nutrition.

Aliases are eliminated entirely. No alias map, no normalization layer. Direct ingredient
name lookup only.

Seeding: a migration reads `grocery-info.yaml` to populate `aisle` columns on existing rows
and creates aisle-only rows for ingredients without nutrition data. After migration,
`grocery-info.yaml` is no longer needed at runtime.

The `grocery_aisles` SiteDocument and its web editor are removed. Aisle names are derived
from the data: `IngredientProfile.distinct.pluck(:aisle).compact`.

## GroceryList Model

New model: `GroceryList` belongs to a kitchen. One row per kitchen, created lazily.

```
grocery_lists
  id             bigint PK
  kitchen_id     bigint FK, unique, not null
  version        integer, not null, default: 0
  state          jsonb, not null, default: {}
  updated_at     datetime
```

State shape:

```json
{
  "selected_recipes": ["pizza-dough", "focaccia"],
  "selected_quick_bites": ["movie-night-snacks"],
  "custom_items": ["birthday candles", "paper towels"],
  "checked_off": ["flour-all-purpose", "eggs", "birthday candles"]
}
```

All arrays of strings. Recipes/quick bites identified by slug. Checked-off items and custom
items are normalized ingredient names (lowercased, trimmed). Version counter increments on
every write.

Writes are targeted operations (not full-state replacement) to avoid clobbering concurrent
changes. Each operation is idempotent.

## Server API

Endpoints (all kitchen-scoped):

```
GET    /groceries              HTML page
GET    /groceries/state        JSON: state + version + computed shopping list
PATCH  /groceries/select       Add/remove recipe or quick bite
PATCH  /groceries/check        Check/uncheck grocery item
PATCH  /groceries/custom_items Add/remove custom item
DELETE /groceries/clear        Reset list for new shopping trip
```

Reads are public (consistent with `allow_unauthenticated_access`). Writes require
`require_membership`.

Write endpoints accept targeted operations:

```
PATCH /groceries/select       { type: "recipe", slug: "pizza-dough", selected: true }
PATCH /groceries/check        { item: "flour-all-purpose", checked: true }
PATCH /groceries/custom_items { item: "paper towels", action: "add" }
DELETE /groceries/clear
```

Each write: applies change to jsonb, increments version, saves, broadcasts version on
ActionCable, returns new version in response.

## Server-Computed Shopping List

The `GET /groceries/state` response includes a fully computed, aisle-organized shopping list:

```json
{
  "version": 47,
  "selected_recipes": ["pizza-dough", "focaccia"],
  "selected_quick_bites": [],
  "custom_items": ["birthday candles"],
  "checked_off": ["flour-all-purpose"],
  "shopping_list": {
    "Baking": [
      { "name": "Flour (all-purpose)", "amounts": [[3.5, "cup"]] },
      { "name": "Sugar", "amounts": [[0.25, "cup"]] }
    ],
    "Refrigerated": [
      { "name": "Eggs", "amounts": [[4, null]] }
    ],
    "Miscellaneous": [
      { "name": "birthday candles", "amounts": [] }
    ]
  }
}
```

Server-side flow:
1. Look up selected recipes and quick bites from the kitchen
2. Aggregate ingredients using `IngredientAggregator`
3. Look up each ingredient's aisle from `IngredientProfile.lookup_for(kitchen)`
4. Group by aisle; unmapped ingredients fall to "Miscellaneous"
5. Omit ingredients with `aisle: "omit"`
6. Custom items go into "Miscellaneous" with no amounts

The client no longer carries `data-ingredients` JSON on checkboxes or performs any
aggregation. Checkbox toggles send a PATCH; the response (or subsequent state fetch)
provides the recomputed shopping list.

## Offline Support

Local storage serves as a cache and write buffer, not the source of truth.

Stored locally:

```json
{
  "version": 47,
  "state": { "selected_recipes": [...], ... },
  "pending": [
    { "action": "check", "item": "milk", "checked": true },
    { "action": "check", "item": "butter", "checked": true }
  ]
}
```

`state` is the last server-confirmed snapshot. `pending` is a queue of unacknowledged
actions.

Write flow:
1. User action applied optimistically to local rendered state (instant feedback)
2. Action appended to `pending` queue in local storage
3. PATCH fires to server
4. On success: remove from `pending`, update local `version` and `state`
5. On failure (offline/timeout): action stays in `pending`, retries later

Reconnect/reload flow:
1. Render immediately from local `state` + `pending` applied on top
2. Flush `pending` queue to server (sequential, in order)
3. Fetch server state; if server version > local, update local state
4. Show toast if incoming state differs from what was rendered

Pending actions are idempotent, so replaying them against a server that already has the
changes is harmless.

## Notifications

Lightweight toast via existing `notify.js`: "List updated — 2 items changed." Non-blocking,
fades after 4 seconds. Shown when a state fetch (triggered by broadcast or heartbeat)
reveals changes the client didn't initiate.

## What Gets Removed

**JavaScript:**
- URL state encoding/decoding (base-26, `encodeState`/`decodeState`)
- QR code generation (`qrcodegen.js` — file deleted)
- Share button, Web Share API, clipboard logic
- `parseStateFromUrl` and URL-differs-from-local notification
- Client-side ingredient aggregation (`updateGroceryList`, `aggregateQuantities`)
- `data-ingredients` JSON parsing

**View/HTML:**
- Share section (QR display, URL, copy/share button)
- `qrcodegen.js` script include
- Aisle editor dialog (markdown blob editor for `grocery_aisles` SiteDocument)
- `data-ingredients` attributes on recipe/quick-bite checkboxes

**Server:**
- `GroceriesController#update_grocery_aisles` endpoint and route
- `FamilyRecipes.build_alias_map`
- `FamilyRecipes.parse_grocery_info` (YAML parser)
- `FamilyRecipes.parse_grocery_aisles_markdown`
- `grocery-info.yaml` (after migration)
- SiteDocument `grocery_aisles`

**What stays:**
- Quick Bites SiteDocument and its editor dialog
- `notify.js` (reused for "List updated" toast)
- `wake-lock.js` (useful while shopping)
- `recipe-editor.js` (handles Quick Bites editor dialog)
- Aisle collapse/expand animation
- Print styles (adapted for new structure)
- `IngredientAggregator` (used server-side now)
