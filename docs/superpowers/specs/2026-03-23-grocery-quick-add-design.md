# Grocery Quick-Add via Search Overlay

**Date:** 2026-03-23
**Status:** Draft

## Problem

Adding an ingredient to the grocery list requires navigating to the grocery
page, scrolling to find the item, and unchecking it. This is slow when you
just remembered you're out of milk and want to fire-and-forget from wherever
you are in the app.

## Solution

Extend the global search overlay (`/` hotkey) with a grocery action row.
When the user types an ingredient name, the top result is a "Need it?"
action that adds the item to the grocery list with a single Enter keystroke.
No new keywords, no new UI surfaces — the search overlay gains a new result
type.

## Design Decisions

- **No magic keyword.** The grocery action row appears automatically when the
  search term matches an ingredient. No "need" prefix required.
- **Default selection.** The grocery action row is the first result and
  pre-selected — Enter fires it immediately. Arrow down reaches recipe results.
- **Client-side matching only (v1).** All matching is against the search data
  blob already embedded in the page. No server round-trip for autocomplete.
  Server-side catalog search is a future enhancement if the local corpus
  proves too thin.
- **Unified custom item corpus.** The grocery page's custom item input and the
  search overlay share the same pool of remembered custom items. Both entry
  points read and write the same data.
- **Custom items in MealPlan state.** Custom items are stored as structured
  entries in the MealPlan JSON state, not a separate AR model. The dataset is
  small (capped by 45-day aging) and the lifecycle is inherently grocery state.

## Search Overlay UX

### Grocery action row

When the user types a term that fuzzy-matches an ingredient, a grocery action
row appears at the top of results with distinct styling (green-tinted
background, cart icon). It is the default selection.

```
┌─────────────────────────────────────────────┐
│  🛒 Need milk?                           ↵  │  ← grocery action (selected)
│     also: mint, miso paste, mixed greens     │  ← alternate matches
├─────────────────────────────────────────────┤
│  Overnight Oats              — milk          │  ← recipe results
│  Béchamel Sauce              — milk          │
│  Tres Leches Cake            — milk          │
└─────────────────────────────────────────────┘
```

### Autocomplete behavior

- As the user types, the grocery action row updates with the best ingredient
  match from the client-side corpus.
- Below the top match, a subtle line shows alternate ingredient matches
  (e.g., "also: mint, miso paste, mixed greens").
- Clicking an alternate replaces the top match AND fills the search input
  with that ingredient's name, re-filtering recipe results to match.
- If nothing matches, the row shows the raw text as a custom item candidate:
  `🛒 Need "birthday ca..."?`
- Previously-used custom items appear in autocomplete with their remembered
  aisle shown in muted text: `🛒 Need birthday candles? Party Supplies`

### State-aware feedback

- **Item not on grocery list:** `🛒 Need milk?` — Enter adds it.
- **Item already in To Buy:** `✓ milk is already on your list` — row shown
  with amber tint, no action available.
- **Item currently On Hand:** `🛒 Need milk?` — Enter marks it depleted,
  moves it to To Buy.
- **Item in Inventory Check:** `🛒 Need milk?` — Enter confirms depletion
  (same as "Need It" button on grocery page), moves item to To Buy.

### Confirmation

On Enter, the grocery action row flashes green with "Added!" (or
"Already on your list"), then the overlay auto-closes after ~500ms. The
whole flow: `/milk↵` → flash → back to what you were doing.

## Autocomplete Data

### Search data blob additions

`SearchDataHelper#search_data_json` gains two new top-level keys:

- **`ingredients`** — deduplicated, sorted list of all ingredient names from
  recipes in the kitchen, merged with on-hand item names. Pre-flattened to
  avoid per-keystroke deduplication across recipes on the client.
- **`custom_items`** — array of `{ name, aisle }` objects from the custom
  item corpus. Includes items used within the last 45 days.

### Matching algorithm

Client-side fuzzy match against the combined ingredient + custom item list.
On-hand items are not ranked differently — a simple prefix/substring match
is sufficient for v1. The top match by string similarity is shown in the
grocery action row; remaining matches appear as alternates.

## Server Endpoint

### `POST /groceries/need`

Accepts `{ item: "milk" }` or `{ item: "birthday candles", aisle: "Party Supplies" }`.

Logic:

1. Resolve the item name via `IngredientResolver` (canonicalize if possible).
2. Check if item is already in To Buy — uses
   `ShoppingListBuilder.visible_names` (the lightweight method already used
   by reconciliation) to determine whether the resolved name is on the
   current shopping list, then checks on-hand state. If visible and not
   on-hand → return `{ status: "already_needed" }`.
3. Check if item is currently On Hand or in Inventory Check → mark depleted
   via existing `apply_need_it` logic → return `{ status: "moved_to_buy" }`.
4. Otherwise, add as a custom item → return `{ status: "added" }`.

Validates item name is present and ≤ 100 characters (matching existing
`MAX_CUSTOM_ITEM_LENGTH`). Returns `{ status: "error", message: "..." }`
on validation failure.

Delegates to `MealPlanWriteService`. Triggers `Kitchen.finalize_writes` for
broadcast/reconciliation.

### `@aisle` hint parsing

Follows the same rules as the existing grocery page custom item input: split
on the last `@`, trim both sides. `"birthday candles@Party Supplies"` →
name: "birthday candles", aisle: "Party Supplies".

## Custom Item Data Model

### MealPlan state structure

Replace the flat `custom_items` string array with a structured hash:

```json
{
  "custom_items": {
    "birthday candles": {
      "aisle": "Party Supplies",
      "last_used_at": "2026-03-23",
      "on_hand_at": null
    },
    "paper towels": {
      "aisle": "Miscellaneous",
      "last_used_at": "2026-03-20",
      "on_hand_at": "2026-03-23"
    }
  }
}
```

Fields:

- **`aisle`** — remembered aisle from `@` hint or "Miscellaneous" default.
- **`last_used_at`** — ISO 8601 date, updated every time the item is added.
  Used for 45-day aging.
- **`on_hand_at`** — ISO 8601 date when checked off, or null. Items with
  a non-null `on_hand_at` appear in On Hand with bold-today styling for the
  remainder of the day, then disappear.

### Custom item lifecycle

1. **Add** (search bar or grocery page input) → entry created/updated in
   `custom_items` hash with `last_used_at: today`, `on_hand_at: nil`.
   Appears in To Buy under the appropriate aisle.
2. **Check off** on grocery page → `on_hand_at` set to today. Moves to
   On Hand zone with bold-today styling, same-day undo window.
3. **Next day** → item has `on_hand_at` in the past, not visible on grocery
   page. Still in the hash for autocomplete.
4. **45 days without re-use** → `last_used_at` older than 45 days, pruned
   from the hash during reconciliation. No longer autocompletes.

### Migration from current format

The current `custom_items` array (`["birthday candles@Party Supplies"]`) is
migrated to the structured hash format. A data migration parses each string,
extracts the `@aisle` hint, and creates the structured entry with
`last_used_at: today` and `on_hand_at: nil`.

### Removal affordance

Custom items in the **To Buy** zone keep a lightweight remove affordance (X
button or swipe-to-dismiss) so typos and accidental adds can be corrected.
Removing a custom item from To Buy deletes it from the `custom_items` hash
entirely (no autocomplete memory for typos).

Custom items in the **On Hand** zone have no remove affordance — they
disappear the next day automatically. The same-day undo window (unchecking)
moves them back to To Buy.

## Grocery Page Integration

The grocery page's existing custom item input continues to work but shares
the unified custom item corpus:

- Typing in the grocery page input autocompletes against the same
  `custom_items` pool (previously-used items with aisle memory).
- Submitting a new custom item writes to the same `custom_items` hash in
  MealPlan state.
- The grocery page renders custom items from the structured hash instead of
  the flat array.

## Scope Boundaries

### In scope (v1)

- Grocery action row in search overlay with distinct styling
- Client-side autocomplete against recipe ingredients + on-hand + custom items
- Alternate match display with click-to-replace
- `POST /groceries/need` endpoint
- Structured custom item hash in MealPlan state
- Custom item lifecycle (add → To Buy → On Hand for a day → gone)
- 45-day autocomplete aging
- Data migration from flat array to structured hash
- Flash-and-close confirmation UX
- Grocery page custom input reads from shared corpus

### Out of scope (future)

- Server-side catalog search (tier 2 fallback)
- Quantity support in quick-add ("need 2 lbs butter")
- Keyboard shortcut to jump directly to grocery action row
- Custom item management UI (edit aisle, rename, etc.)
