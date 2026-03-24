# Search Overlay Grocery Ranking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed-position "Need X?" grocery row with a floating grocery section containing full-sized ingredient rows, positioned above or below recipes based on match quality.

**Architecture:** The search overlay controller determines the best recipe match tier from `search_match.js`, then delegates to a rewritten `grocery_action.js` to build a section with a header and full-height rows. The section is inserted before or after recipe results based on the tier threshold (tiers 0-1 = below, tiers 2+ = above). Recipe results are capped at 8. Keyboard navigation treats all rows as one flat list.

**Tech Stack:** Stimulus controller (JS), CSS, Node.js test runner

**Spec:** `docs/superpowers/specs/2026-03-23-search-overlay-grocery-ranking-design.md`

---

### Task 1: Export best match tier from rankResults

Modify `rankResults` in the search overlay controller to return both the ranked recipes and the best tier across all results. Currently it discards tier info after sorting.

**Files:**
- Modify: `app/javascript/controllers/search_overlay_controller.js:249-263`
- Test: `test/javascript/search_match_test.mjs` (existing tests still pass — no API change to `matchTier`)

- [ ] **Step 1: Modify rankResults to return { recipes, bestTier }**

In `search_overlay_controller.js`, change `rankResults` (lines 249-263) from:

```javascript
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

to:

```javascript
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

  const bestTier = scored.length > 0 ? scored[0].tier : 5
  return { recipes: scored.map(s => s.recipe), bestTier }
}
```

- [ ] **Step 2: Update performSearch to destructure the new return value**

In `performSearch` (line 223), change:

```javascript
const results = tokens.length ? this.rankResults(tokens, candidates) : candidates
```

to:

```javascript
let results, bestTier
if (tokens.length) {
  ({ recipes: results, bestTier } = this.rankResults(tokens, candidates))
} else {
  results = candidates
  bestTier = 5
}
```

Also update the `renderResultsWithGrocery` call (line 228) to pass `bestTier`:

```javascript
this.renderResultsWithGrocery(results, ingredientMatches, query, bestTier)
```

- [ ] **Step 3: Update renderResultsWithGrocery signature**

Change the method signature from:

```javascript
renderResultsWithGrocery(recipes, ingredientMatches, query) {
```

to:

```javascript
renderResultsWithGrocery(recipes, ingredientMatches, query, bestTier = 5) {
```

The `bestTier` parameter is unused for now — it will be consumed in Task 3.

- [ ] **Step 4: Run existing tests to verify nothing breaks**

Run: `npm test`
Expected: All search_match and ingredient_match tests pass.

Run: `npm run build`
Expected: Clean build with no errors.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/search_overlay_controller.js
git commit -m "Export best match tier from rankResults for grocery positioning"
```

---

### Task 2: Rewrite grocery_action.js to build a section with full-height rows

Replace `buildGroceryActionRow` (single row + alternates) with `buildGrocerySection` that produces a container `<li>` with a header label and multiple full-height ingredient rows.

**Files:**
- Modify: `app/javascript/utilities/grocery_action.js`
- Modify: `app/javascript/controllers/search_overlay_controller.js` (update import and call site)

- [ ] **Step 1: Replace buildGroceryActionRow with buildGrocerySection**

Rewrite `grocery_action.js`. Keep `postNeedAction`, `flashAndClose`, and `buildAlreadyNeededRow` unchanged. Replace `buildGroceryActionRow` with:

```javascript
export function buildGrocerySection(matches, query, { customItems = [] } = {}) {
  const ingredients = matches.length > 0 ? matches.slice(0, 4) : [query]

  const section = document.createElement("li")
  section.className = "grocery-section"

  const header = document.createElement("div")
  header.className = "grocery-section-header"
  header.textContent = "Add to grocery list"
  section.appendChild(header)

  const rows = []
  ingredients.forEach(name => {
    const row = document.createElement("div")
    row.className = "search-result grocery-item-row"
    row.setAttribute("role", "option")
    row.dataset.groceryAction = "true"
    row.dataset.ingredient = name

    const title = document.createElement("span")
    title.className = "search-result-title"
    title.textContent = name

    row.appendChild(title)

    const custom = customItems.find(c => c.name.toLowerCase() === name.toLowerCase())
    if (custom && custom.aisle && custom.aisle !== "Miscellaneous") {
      const aisle = document.createElement("span")
      aisle.className = "search-result-category"
      aisle.textContent = custom.aisle
      row.appendChild(aisle)
    }

    section.appendChild(row)
    rows.push(row)
  })

  return { section, rows }
}
```

Key changes from old API:
- Returns `{ section, rows }` instead of an array of `<li>` elements
- `section` is a single `<li>` container wrapping all rows
- `rows` is an array of the inner `<div>` elements (used for click handlers and navigation)
- Uses `search-result-title` and `search-result-category` classes for consistency with recipe rows
- No more 🛒 emoji, "Need X?" text, or compact alternates row

- [ ] **Step 2: Update the import in search_overlay_controller.js**

Change line 6 from:

```javascript
import { buildGroceryActionRow, postNeedAction, flashAndClose } from "../utilities/grocery_action"
```

to:

```javascript
import { buildGrocerySection, postNeedAction, flashAndClose } from "../utilities/grocery_action"
```

- [ ] **Step 3: Update renderResultsWithGrocery to use buildGrocerySection**

Replace the grocery rendering block in `renderResultsWithGrocery` (lines 276-296). The full rewritten method:

```javascript
renderResultsWithGrocery(recipes, ingredientMatches, query, bestTier = 5) {
  this.clearResults()
  const list = this.resultsTarget
  this.groceryRows = []

  const showGrocery = this.needUrl &&
    (ingredientMatches.length > 0 || (query && this.activePills.length === 0))

  let grocerySectionEl = null
  if (showGrocery) {
    const { section, rows } = buildGrocerySection(
      ingredientMatches, query, { customItems: this.customItems }
    )
    grocerySectionEl = section
    this.groceryRows = rows

    rows.forEach(row => {
      row.addEventListener("click", () => this.executeGroceryAction(row))
    })
  }

  const cappedRecipes = recipes.slice(0, 8)

  // Position: groceries above if no strong recipe match (tier 2+), below otherwise
  const groceryAbove = bestTier > 1

  if (grocerySectionEl && groceryAbove) {
    grocerySectionEl.classList.add("grocery-section--above")
    list.appendChild(grocerySectionEl)
  }

  this.renderRecipeItems(cappedRecipes, groceryAbove ? this.groceryRows.length : 0)

  if (grocerySectionEl && !groceryAbove) {
    grocerySectionEl.classList.add("grocery-section--below")
    list.appendChild(grocerySectionEl)
  }

  if (!grocerySectionEl && cappedRecipes.length === 0) {
    const li = document.createElement("li")
    li.className = "search-no-results"
    li.textContent = "No matches"
    li.setAttribute("role", "option")
    list.appendChild(li)
  }
}
```

- [ ] **Step 4: Update renderRecipeItems to accept an offset parameter**

Change:

```javascript
renderRecipeItems(recipes) {
  const list = this.resultsTarget
  const offset = this.groceryRowCount
```

to:

```javascript
renderRecipeItems(recipes, offset = 0) {
  const list = this.resultsTarget
```

- [ ] **Step 5: Update moveSelection to navigate grocery rows**

The `moveSelection` and `selectFirst` methods use `querySelectorAll(".search-result")` which already matches both recipe rows and the new grocery item rows (since they have `class="search-result grocery-item-row"`). However, these rows are now nested inside the `grocery-section` `<li>`, so the query needs to search deeper.

Change `moveSelection` to query all `.search-result` elements within the results list (including nested ones — the `querySelectorAll` already does this since it searches descendants). Verify this works by checking that `.search-result` divs inside the `.grocery-section` li are found by `this.resultsTarget.querySelectorAll(".search-result")`.

No code change needed — `querySelectorAll` already searches all descendants. But verify this in Step 7.

- [ ] **Step 6: Update executeGroceryAction to find aisle from customItems**

The current `executeGroceryAction` already reads `row.dataset.ingredient` and looks up the custom item. No change needed since the new rows still set `dataset.ingredient`.

- [ ] **Step 7: Run build and manual smoke test**

Run: `npm run build`
Expected: Clean build with no errors.

Run: `npm test`
Expected: All tests pass (no behavioral changes to `matchTier` or `matchIngredients`).

- [ ] **Step 8: Commit**

```bash
git add app/javascript/utilities/grocery_action.js app/javascript/controllers/search_overlay_controller.js
git commit -m "Rewrite grocery section with full-height ingredient rows and floating position"
```

---

### Task 3: CSS for the grocery section

Replace the old grocery action row styles with new grocery section styles.

**Files:**
- Modify: `app/assets/stylesheets/navigation.css:405-476`

- [ ] **Step 1: Replace grocery action CSS**

Replace everything from the `/* Grocery Action Row */` comment (line 405) through end of `.grocery-already-needed` (line 476) with:

```css
/************************/
/* Grocery Section      */
/************************/

.grocery-section {
  list-style: none;
  background: color-mix(in srgb, var(--smart-green-text) 6%, var(--ground));
}

.grocery-section--above {
  border-bottom: 2px solid color-mix(in srgb, var(--smart-green-text) 25%, var(--rule));
  padding-bottom: 0.25rem;
  margin-bottom: 0.25rem;
}

.grocery-section--below {
  border-top: 2px solid color-mix(in srgb, var(--smart-green-text) 25%, var(--rule));
  padding-top: 0.25rem;
  margin-top: 0.25rem;
}

.grocery-section-header {
  font-size: 0.7rem;
  font-weight: 600;
  color: color-mix(in srgb, var(--smart-green-text) 70%, var(--text-soft));
  text-transform: uppercase;
  letter-spacing: 0.5px;
  padding: 0.4rem 1.1rem 0.15rem;
}

.grocery-item-row.selected {
  background: color-mix(in srgb, var(--smart-green-text) 18%, var(--ground));
}

.grocery-item-row:hover:not(.selected) {
  background: color-mix(in srgb, var(--smart-green-text) 10%, var(--ground));
}

.grocery-action-flash {
  color: var(--smart-green-text);
  font-weight: 500;
  transition: opacity 300ms ease;
}

.grocery-already-needed {
  background: color-mix(in srgb, var(--smart-amber-text) 8%, var(--ground));
  border: 1px solid color-mix(in srgb, var(--smart-amber-text) 20%, var(--rule));
  border-radius: 6px;
  padding: 8px 12px;
  color: var(--smart-amber-text);
  font-size: 0.9rem;
}
```

Key decisions:
- Green selected state for grocery rows (not the red used for recipe rows)
- Green hover state to keep visual cohesion within the section
- Section header is small uppercase label, visually subordinate
- Border direction indicates section position (bottom border = above recipes, top border = below)

- [ ] **Step 2: Override `.search-result.selected` color for grocery rows**

The default `.search-result.selected` sets `background: var(--red)` and `color: white`. Grocery rows should use green instead. The `.grocery-item-row.selected` rule above handles background, but we also need to prevent the white text:

Add after the `.grocery-item-row.selected` rule:

```css
.grocery-item-row.selected .search-result-title {
  color: var(--text);
}

.grocery-item-row.selected .search-result-category {
  color: var(--text-soft);
}
```

- [ ] **Step 3: Run build and verify**

Run: `npm run build`
Expected: Clean build.

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/navigation.css
git commit -m "Style grocery section with green tint, directional borders, and section header"
```

---

### Task 4: Update html_safe_allowlist if needed

The `html_safe_allowlist.yml` uses `file:line_number` keys. CSS changes can shift line numbers in other files. Check if any allowlisted entries in `navigation.css` need updating.

**Files:**
- Check: `config/html_safe_allowlist.yml`

- [ ] **Step 1: Check allowlist for navigation.css references**

Run: `grep navigation config/html_safe_allowlist.yml`

If no hits, skip this task — no allowlist entries reference navigation.css.

- [ ] **Step 2: Run lint to verify**

Run: `bundle exec rake lint:html_safe`
Expected: Pass.

- [ ] **Step 3: Commit if changes needed**

Only commit if the allowlist was updated.

---

### Task 5: Cap ingredient match count to 4

The current call passes `max: 6` to `matchIngredients`. Update to `max: 4` per spec.

**Files:**
- Modify: `app/javascript/controllers/search_overlay_controller.js:226`

- [ ] **Step 1: Change max from 6 to 4**

In `performSearch`, change:

```javascript
? matchIngredients(query, this.ingredientCorpus, { customItems: this.customItems, max: 6 })
```

to:

```javascript
? matchIngredients(query, this.ingredientCorpus, { customItems: this.customItems, max: 4 })
```

- [ ] **Step 2: Run tests**

Run: `npm test`
Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/search_overlay_controller.js
git commit -m "Cap grocery ingredient suggestions at 4 rows"
```

---

### Task 6: Clean up removed exports and dead CSS

Remove any now-unused exports from `grocery_action.js` and verify no other files reference the old API.

**Files:**
- Check: `app/javascript/utilities/grocery_action.js`
- Check: all JS files for references to `buildGroceryActionRow`

- [ ] **Step 1: Search for old references**

Run: `grep -r "buildGroceryActionRow\|grocery-action-row\|grocery-action-left\|grocery-action-aisle\|grocery-action-hint\|grocery-alternates\|grocery-alternate-btn" app/`

Any hits (other than CSS, which was already replaced) indicate stale references that need cleanup.

- [ ] **Step 2: Clean up any stale references found**

Fix any remaining references. If none found, this step is a no-op.

- [ ] **Step 3: Run full test suite**

Run: `bundle exec rake test && npm test`
Expected: All Ruby and JS tests pass.

Run: `bundle exec rubocop`
Expected: No offenses.

- [ ] **Step 4: Commit if changes were made**

```bash
git commit -m "Remove stale references to old grocery action row"
```
