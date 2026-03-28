# Performance Feel Optimization — Design Spec

**Date:** 2026-03-28

Systematic profiling and optimization of perceived performance ahead of v1.0.
The first optimization pass (2026-03-27) addressed server-side query counts and
front-end payload sizes. This spec targets what the user *feels* — input
responsiveness, navigation smoothness, morph jank, and general framework
overhead. Complements the profiling toolkit spec (2026-03-28) which established
measurement infrastructure.

## Current Baseline

Measured via `rake profile:baseline` on seed data (8 recipes):

| Page | Time (avg) | Queries | HTML size |
|------|-----------|---------|-----------|
| Homepage | 33ms | 9 | 61 KB |
| Menu | 209ms | 23 | 117 KB |
| Groceries | 116ms | 20 | 94 KB |
| Recipe | 31ms | 12 | 55 KB |

| Asset | Raw | Gzipped |
|-------|-----|---------|
| JS (main) | 238 KB | 62 KB |
| JS (CM chunk) | 542 KB | 188 KB |
| CSS (total) | 66 KB | 17 KB |

Server-side numbers are solid. The problem is *feel* — the app has four
perceptible symptoms of framework overhead compared to a pure static
HTML+CSS site:

1. **Flash/flicker on navigation** — content briefly reflows as Turbo swaps
   the page body.
2. **Morph jank on live updates** — ActionCable broadcasts trigger full-page
   DOM diffing that visibly reshuffles content.
3. **Input lag** — grocery checkboxes and meal plan toggles round-trip to the
   server before the UI reflects the change.
4. **General heaviness** — the app feels like it's doing more work than
   necessary for what's on screen.

## Goals

1. Make high-frequency interactions (grocery checks, meal plan toggles) feel
   instant — optimistic UI with no perceptible delay.
2. Eliminate visible morph jank on common mutations by replacing full-page
   morphs with targeted Turbo Stream updates.
3. Reduce framework tax on page load by deferring non-essential work.
4. Establish scaling limits with realistic data volumes so performance
   degrades predictably, not suddenly.

## Non-Goals

- Production APM or load testing (premature for homelab).
- Lazy-loading search data. The inline JSON approach gives zero-latency
  search. At ~250 bytes per recipe, it stays under 50 KB for any realistic
  single-kitchen dataset. Revisit if recipe count exceeds ~200 or if moving
  to hosted multi-tenant.
- Per-page Stimulus controller splitting. All 22 controllers are loaded
  eagerly but most are dormant — the parse/register cost is negligible
  compared to the feel issues above. Revisit if bundle analysis shows
  meaningful savings.
- Performance budgets or CI-enforced query limits. The existing size-limit
  CI gate and rack-mini-profiler badge are sufficient guardrails for v1.0.

## Framework Tax Inventory

Six concrete sources of overhead identified:

### 1. Full-page morph on every write

`Kitchen#broadcast_update` calls `broadcast_refresh_to`, which triggers
Turbo's morphing algorithm across the entire page DOM. On the menu page
(117 KB HTML), that's a significant diffing operation every time anyone
checks a box or makes a selection.

### 2. Eager editor frame preloading

Menu, Groceries, and Recipe show pages fire HTTP requests for editor Turbo
Frames immediately on page load — content the user may never open. That's
1-3 extra requests competing with the primary render.

### 3. Search data JSON on every page

The search overlay embeds the full recipe/ingredient corpus as inline JSON
on every page load. With seed data this is ~2-4 KB (negligible). At 200
recipes it approaches ~50 KB. The `SearchDataHelper` already caches per
kitchen via `Rails.cache.fetch` with `updated_at` invalidation. No change
needed — the architecture is correct for the scale.

### 4. Server round-trips before UI feedback

Grocery checkboxes and meal plan selections hit the server and wait for a
Turbo Stream response before the UI reflects the change. On a static site,
a checkbox just checks instantly.

### 5. Menu page computation cost

209ms is dominated by `RecipeAvailabilityCalculator` and
`CookHistoryWeighter` — both computed fresh on every request, neither
cached.

### 6. SM-2 reconciliation patterns

`OnHandEntry.reconcile!` loads all on-hand entries and loops with individual
`update!` calls. The per-item algorithm cost is negligible (arithmetic +
date comparison), but the ActiveRecord patterns around it may not scale.
Reconcile also runs on every write operation via `Kitchen.finalize_writes`,
not just grocery writes.

## Phase 1: Feel Fixes (Framework Tax Reduction)

### 1a. Optimistic UI for checkboxes and selections

Update the DOM immediately on click (check the box, apply the visual state),
then send the server request in the background. If the server rejects it,
roll back.

**Where it applies:**
- Grocery checkboxes (to-buy items)
- Grocery "Have It" / "Need It" buttons (inventory check)
- Meal plan selection toggles (recipe/Quick Bite checkboxes on menu)

These are the highest-frequency interactions in the app. Every grocery trip
involves dozens of checkbox taps. Making those feel instant is the single
biggest win for perceived performance.

### 1b. Targeted Turbo Stream replacements instead of full-page morphs

For the most common mutations (check/uncheck grocery item, toggle meal plan
selection), replace the full-page morph with targeted Turbo Stream actions
that update only the affected DOM elements. The controller action responds
with a Turbo Stream (server-rendered partial for the changed element) and
the broadcast sends the same targeted update to other connected clients
instead of a blanket page refresh.

Keep full-page morph as a fallback for less common operations (recipe
create/delete, category reorder, settings changes) where targeted updates
would be complex and the operation is infrequent enough that the morph cost
is acceptable.

### 1c. Defer editor frame loading

Change the editor frames from eager preload (`src=` on page load) to lazy
load (set `src` only when the user opens the dialog). The dialog open
handler sets the frame's `src` attribute, which triggers the fetch.

**Trade-off:** First editor open pays a ~50-100ms delay while the frame
loads. Acceptable because editing is less frequent than reading, and the
"Loading..." placeholder is already in place.

### 1d. Reduce Turbo Drive navigation flicker

Two investigations:
1. **Turbo Drive preview from cache.** Verify cached snapshots display
   instantly on back/forward navigation. If pages are excluded from the
   cache inadvertently, re-enable them.
2. **Morph vs. replace on cross-page navigations.** The app has
   `turbo-refresh-method="morph"` globally. Verify this helps same-page
   refreshes without adding flicker on navigations between different pages.
   If morphing causes more disruption than the default replace behavior on
   page transitions, scope it to same-page refreshes only.

## Phase 2: Server-Side Optimization (Slow Page Deep Dives)

### 2a. Menu page (209ms)

**`RecipeAvailabilityCalculator`** — recomputed fresh on every page load.
The result only changes when on-hand entries or recipes change — both go
through `Kitchen.finalize_writes`. Cache via `Rails.cache.fetch` with the
kitchen's `updated_at` as the cache key.

**`CookHistoryWeighter`** — computes dinner picker weights on every page
load, but only used when the user clicks "Pick dinner." Move to a small
JSON endpoint that the `dinner-picker` controller fetches on demand.

### 2b. Groceries page (116ms)

Flamegraph to determine the split between Ruby computation
(ShoppingListBuilder, IngredientResolver) and template rendering
(`_shopping_list.html.erb`, 137 lines — largest single partial).

**If computation-bound:** The resolver is already cached per-request via
`Current.resolver`. Profile `ShoppingListBuilder` internals.

**If template-bound:** Extract helper methods for repetitive per-item
rendering to reduce template complexity and make rendering more cacheable.

**Double query fix:** The groceries controller runs the `active` scope
(one query) then loads all entries again via `index_by` (second query).
Consolidate to a single load.

### 2c. Homepage and Recipe pages (33ms / 31ms)

Already fast. No optimization needed — include in baseline to catch
regressions.

## Phase 3: Stress Testing with Realistic Data

### 3a. Data generator

A rake task (`rake profile:generate_stress_data`) that populates a test
kitchen with configurable scale:

- **Recipes:** 200 by default, distributed across 12 categories, 1-4 steps
  and 3-12 ingredients each
- **Ingredient catalog:** 150 entries with nutrition data, aisles, variants
- **Meal plan:** 15 recipes selected, 8 Quick Bites
- **Grocery state:** Mix of inventory check, to-buy, and on-hand items
  across all aisles
- **Cook history:** 6 months of entries (dinner picker weight distribution)
- **Tags:** 20 tags distributed across recipes
- **On-hand entries:** 200+ items with varied intervals and ease factors
  (SM-2 scaling test)

The generator produces plausible data — real-looking recipe titles, varied
ingredient lists, realistic category distribution. Not random gibberish,
because HTML size and rendering cost depend on content length.

### 3b. Stress baseline

Run `rake profile:baseline` against the stress kitchen and compare to the
seed kitchen baseline. Key questions:

- Does the menu page scale linearly with recipe count? 200 recipes means
  200 availability checks, 200 selection states.
- Does the groceries page scale with ingredient count? More selections
  means more grocery items across more aisles.
- Does search data JSON stay under 50 KB? At 200 recipes with ingredients,
  the inline JSON approaches the threshold.
- Does Turbo morph get slow with large pages? A 200-recipe menu page could
  produce 300+ KB of HTML.

### 3c. SM-2 reconciliation at scale

Specific investigation of `OnHandEntry.reconcile!` with 200+ entries:

- Measure reconcile time with individual `update!` calls in a loop.
- If slow, batch the UPDATEs instead of looping.
- Profile whether reconcile needs to run on non-grocery writes, or if it
  can be scoped to avoid unnecessary work.

### 3d. Scaling thresholds

Document the scaling profile based on stress results:
- At what recipe count does the menu page exceed 500ms?
- At what point does search JSON warrant lazy-loading?
- At what HTML size does Turbo morph become perceptible?
- At what on-hand entry count does reconcile become a bottleneck?

These are guardrails for "when to revisit" — not things to fix now, but
tripwires for the future.

## Methodology

### Feel Audit

Structured walkthrough of every page and interaction, scored:

- **Instant** — feels like static HTML. No perceptible delay or disruption.
- **Smooth** — brief delay but no jank. Acceptable.
- **Sluggish** — noticeable pause or visual glitch. Needs investigation.
- **Broken** — delay long enough to feel wrong, or visible reflow/flash.

Surfaces to audit:

**Pages:** Homepage, Recipe show, Menu, Groceries, Settings.

**Interactions:** Editor dialog open/close, CodeMirror editing, grocery
checkboxes, meal plan toggles, search overlay, ActionCable live updates,
Turbo Drive page-to-page navigation.

Each surface scored with DevTools Performance tab recording: time to visual
complete, layout shifts, input delay, morph disruption.

### Static Baseline Comparison

For the worst-scoring pages, generate a static reference:

1. `curl` the fully rendered HTML from the dev server.
2. Save as a static `.html` file with CSS/JS links intact.
3. Open both versions side by side — static file (browser renders directly)
   vs. live app (Turbo Drive renders).
4. Measure the gap: first contentful paint, time to interactive, layout
   shift score.

The difference is the framework tax for that page. This gives a concrete
floor — we can't beat the static version, but we can close the gap.

### Measurement Tools

All already installed or built-in:

- **rack-mini-profiler** — server timing and query counts
- **Bullet** — N+1 detection
- **`?pp=flamegraph`** — CPU profiling via stackprof
- **Chrome DevTools Performance tab** — client-side rendering, layout
  shifts, input delay
- **Chrome DevTools Lighthouse** — one-off manual audits
- **`rake profile:baseline`** — automated server-side numbers

No new tools needed.

### Execution Order

1. Feel audit — score every page and interaction
2. Static baseline — measure framework tax on the worst pages
3. Phase 1 fixes — optimistic UI, targeted streams, deferred frames,
   navigation smoothing
4. Re-audit — verify improvements match expectations
5. Flamegraph remaining slow pages — Phase 2 server-side investigation
6. Stress test — Phase 3, scale up data, find the limits
7. Final baseline — run `rake profile:baseline`, document the v1.0 numbers
