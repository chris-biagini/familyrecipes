# Multi-Word AND Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split search queries into tokens and require all tokens to match somewhere in the recipe (AND logic) with best-tier scoring.

**Architecture:** Tokenize the query in `performSearch`, pass the token array through `rankResults` to `matchTier`. `matchTier` loops over tokens, finds each token's best tier, returns the minimum. If any token has no match, recipe is excluded.

**Tech Stack:** JavaScript (Stimulus controller), Node test runner

**Spec:** `docs/superpowers/specs/2026-03-22-multi-word-search-design.md`

---

### Task 1: Extract search matching logic into a testable utility

The matching logic (`matchTier`, `tokenMatchTier`) is pure — no DOM dependencies. Extract it so it can be unit tested with Node's test runner.

**Files:**
- Create: `app/javascript/utilities/search_match.js`
- Test: `test/javascript/search_match_test.mjs`
- Modify: `app/javascript/controllers/search_overlay_controller.js:235-258`

- [ ] **Step 1: Write the failing tests**

Create `test/javascript/search_match_test.mjs` with tests for the new tokenized matching:

```js
import assert from "node:assert/strict"
import { test } from "node:test"
import { matchTier } from "../../app/javascript/utilities/search_match.js"

function makeRecipe({ title = "", description = "", category = "", tags = [], ingredients = [] }) {
  return {
    _title: title.toLowerCase(),
    _description: description.toLowerCase(),
    _category: category.toLowerCase(),
    _tags: tags.map(t => t.toLowerCase()),
    _ingredients: ingredients.map(i => i.toLowerCase())
  }
}

const pancakes = makeRecipe({
  title: "Pancakes",
  description: "Fluffy buttermilk pancakes",
  category: "Breakfast",
  tags: ["sweet", "quick"],
  ingredients: ["flour", "buttermilk", "eggs", "sugar"]
})

const tacos = makeRecipe({
  title: "Fish Tacos",
  description: "Crispy battered fish tacos",
  category: "Mexican",
  tags: ["quick", "seafood"],
  ingredients: ["cod", "tortillas", "cabbage", "lime"]
})

// Single token — backward compatible
test("single token matching title returns tier 0", () => {
  assert.equal(matchTier(pancakes, ["pancakes"]), 0)
})

test("single token matching description returns tier 1", () => {
  assert.equal(matchTier(pancakes, ["fluffy"]), 1)
})

test("single token matching category returns tier 2", () => {
  assert.equal(matchTier(pancakes, ["breakfast"]), 2)
})

test("single token matching tag returns tier 3", () => {
  assert.equal(matchTier(pancakes, ["sweet"]), 3)
})

test("single token matching ingredient returns tier 4", () => {
  assert.equal(matchTier(pancakes, ["flour"]), 4)
})

test("single token matching nothing returns tier 5", () => {
  assert.equal(matchTier(pancakes, ["xyzzy"]), 5)
})

// Multi-token AND — the new behavior
test("multi-token: all match returns best tier", () => {
  // "pancakes" → title (0), "sweet" → tag (3) → best = 0
  assert.equal(matchTier(pancakes, ["pancakes", "sweet"]), 0)
})

test("multi-token: one unmatched token excludes recipe", () => {
  assert.equal(matchTier(pancakes, ["pancakes", "xyzzy"]), 5)
})

test("multi-token: both match low-priority fields", () => {
  // "flour" → ingredient (4), "eggs" → ingredient (4) → best = 4
  assert.equal(matchTier(pancakes, ["flour", "eggs"]), 4)
})

test("multi-token: matches across different field types", () => {
  // "fish" → title (0), "seafood" → tag (3), "lime" → ingredient (4) → best = 0
  assert.equal(matchTier(tacos, ["fish", "seafood", "lime"]), 0)
})

test("multi-token: partial title match with tag", () => {
  // "tacos" → title (0), "quick" → tag (3) → best = 0
  assert.equal(matchTier(tacos, ["tacos", "quick"]), 0)
})

// Empty tokens
test("empty token array returns tier 0 (no constraints)", () => {
  assert.equal(matchTier(pancakes, []), 0)
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test`
Expected: FAIL — `search_match.js` does not exist yet.

- [ ] **Step 3: Create `search_match.js` with tokenized `matchTier`**

Create `app/javascript/utilities/search_match.js`:

```js
// Tiered recipe matching for the search overlay.
//
// Scores a recipe against search tokens using AND logic — every token must
// match somewhere. Returns the best (lowest) tier across all tokens.
// Tier 0 = title, 1 = description, 2 = category, 3 = tag, 4 = ingredient,
// 5 = no match (recipe excluded).
//
// Collaborators:
//   - search_overlay_controller.js (sole consumer)

function tokenTier(recipe, token) {
  if (recipe._title.includes(token)) return 0
  if (recipe._description.includes(token)) return 1
  if (recipe._category.includes(token)) return 2
  if (recipe._tags?.some(t => t.includes(token))) return 3
  if (recipe._ingredients.some(i => i.includes(token))) return 4
  return 5
}

export function matchTier(recipe, tokens) {
  if (tokens.length === 0) return 0

  let best = 5
  for (const token of tokens) {
    const tier = tokenTier(recipe, token)
    if (tier === 5) return 5
    if (tier < best) best = tier
  }
  return best
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test`
Expected: All search_match tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/utilities/search_match.js test/javascript/search_match_test.mjs
git commit -m "Add tokenized matchTier utility with tests"
```

### Task 2: Wire tokenized matching into search overlay controller

Replace the inline `matchTier` and update `performSearch`/`rankResults` to
tokenize the query and pass tokens through.

**Files:**
- Modify: `app/javascript/controllers/search_overlay_controller.js:200-258`

- [ ] **Step 1: Update `performSearch` to tokenize the query**

In `search_overlay_controller.js`, change `performSearch`:

```js
// Before:
const results = query ? this.rankResults(query, candidates) : candidates

// After:
const tokens = query ? query.split(/\s+/).filter(Boolean) : []
const results = tokens.length ? this.rankResults(tokens, candidates) : candidates
```

- [ ] **Step 2: Update `rankResults` to accept tokens**

```js
// Before:
rankResults(query, candidates = this.recipes) {
  const scored = []
  for (const recipe of candidates) {
    const tier = this.matchTier(recipe, query)
    if (tier < 5) scored.push({ recipe, tier })
  }
  scored.sort((a, b) => {
    if (a.tier !== b.tier) return a.tier - b.tier
    return a.recipe.title.localeCompare(b.recipe.title)
  })
  return scored.map(s => s.recipe)
}

// After:
rankResults(tokens, candidates = this.recipes) {
  const scored = []
  for (const recipe of candidates) {
    const tier = matchTier(recipe, tokens)
    if (tier < 5) scored.push({ recipe, tier })
  }
  scored.sort((a, b) => {
    if (a.tier !== b.tier) return a.tier - b.tier
    return a.recipe.title.localeCompare(b.recipe.title)
  })
  return scored.map(s => s.recipe)
}
```

- [ ] **Step 3: Remove the inline `matchTier` method and add import**

Add at the top of the file with the other imports:

```js
import { matchTier } from "../utilities/search_match"
```

Delete the `matchTier(recipe, query)` method (lines 251–258).

- [ ] **Step 4: Build and verify**

Run: `npm run build`
Expected: Build succeeds with no errors.

- [ ] **Step 5: Run all tests**

Run: `npm test && rake test`
Expected: All JS and Ruby tests pass. The integration tests in
`test/integration/search_overlay_test.rb` verify the search data
structure is intact (they don't test client-side matching logic).

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/search_overlay_controller.js
git commit -m "Wire tokenized multi-word AND matching into search overlay"
```
