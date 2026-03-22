# Multi-Word AND Search

**Date:** 2026-03-22
**Status:** Approved

## Problem

The search overlay treats the entire query as a single substring. Typing
"pancakes sweet" looks for the literal substring `"pancakes sweet"` in recipe
fields — it doesn't match a recipe titled "Pancakes" with tag "sweet" because
no single field contains that exact phrase.

## Design

Token-level AND matching with best-tier scoring. All changes are in
`search_overlay_controller.js`; no server-side or data-shape changes.

### Tokenization

`performSearch()` splits the normalized query on whitespace:

```js
const tokens = query.split(/\s+/).filter(Boolean)
```

Single-word queries produce a one-element array — identical behavior to today.
Empty queries (pills only) produce an empty array and skip ranking entirely,
preserving current pill-only filtering.

### Matching — `matchTier(recipe, tokens)`

Current signature: `matchTier(recipe, query)` — checks `field.includes(query)`
against title (tier 0), description (1), category (2), tags (3), ingredients (4).

New signature: `matchTier(recipe, tokens)` — for each token, find its best
tier using the same field priority. If **any** token has no match (tier 5),
return 5 (recipe excluded). Otherwise return the **minimum** tier across all
tokens (best-tier scoring).

Example: "pancakes sweet" → `["pancakes", "sweet"]`
- "pancakes" matches title → tier 0
- "sweet" matches tag → tier 3
- Result: tier 0 (best of the two)

### Ranking — `rankResults`

Passes the token array to `matchTier` instead of the raw string. Sort logic
(tier ascending, then alphabetical) is unchanged.

### What doesn't change

- Pill auto-conversion: still only fires when the entire input matches a
  known tag/category (no mid-query recognition)
- Pill filtering (`matchesPill`): unaffected
- `textContains`: unaffected (only used by `matchesPill`)
- Result rendering, keyboard navigation, hint underline: unaffected
- Search data shape (server-side `SearchDataHelper`): unaffected

## Edge Cases

| Input | Behavior |
|-------|----------|
| `"pancakes"` | One token — identical to current behavior |
| `"  pancakes  sweet  "` | Normalized to `["pancakes", "sweet"]` — extra whitespace ignored |
| `""` with pills active | Empty token array — pill-only filtering, no ranking |
| `"xyzzy foo"` | If either token matches nothing, recipe excluded |

## Files Changed

- `app/javascript/controllers/search_overlay_controller.js` — `performSearch`,
  `rankResults`, `matchTier`
