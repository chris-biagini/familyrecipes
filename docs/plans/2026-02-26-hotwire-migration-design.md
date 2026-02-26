# Hotwire Migration Design

## Summary

Introduce Stimulus + Turbo (Hotwire) to replace vanilla JavaScript with structured controllers and eliminate the full-page-reload requirement when grocery page content changes. Hybrid approach: keep the existing GrocerySync version-polling system for list state changes (recipe selection, check-offs, custom items), add Turbo Streams only for content changes (quick bites edited, aisle order changed).

## Goals

- Convert all vanilla JS to Stimulus controllers for Turbo Drive compatibility and better organization
- Enable Turbo Drive app-wide for instant page navigation
- Replace the "Recipes or ingredients have changed — Reload" notification with live Turbo Stream updates
- Zero visual regressions — the app must look and behave identically after migration
- Pass the multi-agent concurrent stress test on the grocery page

## Non-Goals

- Turbo Frames (future enhancement for inline editing)
- Turbo morphing mode (too new, risk to grocery page DOM state)
- Moving all grocery list rendering server-side (future pass — only content_changed rendering moves server-side now)
- CSS framework changes

## Infrastructure

### Gems and Asset Pipeline

Add `turbo-rails`, `stimulus-rails`, and `importmap-rails`. Run their installers to create `config/importmap.rb`, `app/javascript/application.js`, and `app/javascript/controllers/`. Pin Stimulus and Turbo in the importmap (vendored, no CDN).

Propshaft remains the asset pipeline. No Node, no build step.

### Layout Change

Replace per-page `javascript_include_tag` calls and `content_for(:scripts)` blocks with a single `javascript_include_tag "application"` in the layout. Stimulus auto-discovers controllers.

### CSP Compatibility

Importmap-rails generates a single external script. No inline JS required. Existing CSP policy (`'self'` only) works without modification.

## Stimulus Controller Mapping

| Current File | Becomes | Type |
|---|---|---|
| `notify.js` | `app/javascript/utilities/notify.js` | Module (not a controller) |
| `wake-lock.js` | `wake_lock_controller.js` | Controller |
| `editor-framework.js` + `editor-utils.js` | `editor_controller.js` + `app/javascript/utilities/editor_utils.js` | Controller + module |
| `nutrition-editor.js` | `nutrition_editor_controller.js` | Controller |
| `recipe-state-manager.js` | `recipe_state_controller.js` | Controller |
| `groceries.js` (GrocerySync) | `grocery_sync_controller.js` | Controller |
| `groceries.js` (GroceryUI) | `grocery_ui_controller.js` | Controller |
| `sw-register.js` | `app/javascript/utilities/sw_register.js` | Module |

Vulgar fraction helpers from `recipe-state-manager.js` become an imported utility module.

### Why Notify stays a module

Notify creates its own DOM element and is called from many controllers (wake lock, grocery sync, editor). Cross-controller communication in Stimulus is possible but awkward. A simple imported module is cleaner.

## Turbo Drive

Enabled app-wide. Safe because all JS moves to Stimulus controllers where `connect()`/`disconnect()` replace `DOMContentLoaded`.

### Compatibility notes

- **Page-specific CSS** (`content_for(:head)`): Turbo Drive merges `<head>`, adds new stylesheets automatically.
- **Body data attributes** (`data-recipe-id`, etc.): Updated on each Turbo navigation. Controllers read them in `connect()`.
- **Extra nav content** (`content_for(:extra_nav)`): Body replacement updates nav correctly.
- **Service Worker**: Network-first HTML strategy serves Turbo Drive fetches correctly.
- **ActionCable**: Grocery sync controller subscribes in `connect()`, unsubscribes in `disconnect()`.
- **`location.reload()`**: Still works (bypasses Turbo). Editor success handlers keep using it initially.
- **`target="_blank"` links**: Turbo Drive ignores these.

## Turbo Streams for content_changed

### Current problem

When quick bites or aisle order are edited, all clients receive `{ type: 'content_changed' }` over ActionCable and show a persistent "Reload" notification requiring a full page refresh.

### Solution

Push Turbo Stream HTML fragments over ActionCable to replace targeted DOM sections:
- Quick bites edited: replace `#recipe-selector` with re-rendered partial
- Aisle order edited: replace `#shopping-list` with re-rendered partial

### New server-side partials

Extract from `groceries/show.html.erb`:
- `groceries/_recipe_selector.html.erb` — categories, recipes, quick bites checkboxes
- `groceries/_shopping_list.html.erb` — aisles, items, counts (new — currently JS-rendered)
- `groceries/_custom_items.html.erb` — custom item chips (new — currently JS-rendered)

### Preserving client state during Turbo Stream replace

- **Checkbox states**: Server knows selected recipes/quick bites from `GroceryList.state`. Partial renders correct checked state.
- **Aisle collapse state**: Stored in localStorage. Grocery UI controller re-applies after Turbo Stream replace via a `turbo:before-stream-render` callback or MutationObserver.
- **Check-off state**: Server knows this from `GroceryList.state.checked_off`. Partial renders correct state.
- **Item counts**: Re-calculated after replace.

### Hybrid coexistence

The two systems share one ActionCable channel:
- `{ version: N }` — consumed by grocery sync controller JS (existing behavior)
- `<turbo-stream>` HTML — consumed by Turbo automatically (new)

GrocerySync stops handling `type: 'content_changed'` messages (Turbo Streams replace that path).

### Dual rendering during transition

The shopping list renders in two paths:
1. Server-side partial (initial page load + Turbo Stream pushes)
2. Client-side JS (GroceryUI for version-polling state updates)

Both must produce identical HTML. Playwright screenshots verify visual parity.

## Migration Order

Each step leaves the app fully working and independently deployable.

1. **Infrastructure** — Add gems, configure importmap, add application.js to layout alongside existing script tags
2. **Leaf controllers** — Convert notify (module), wake-lock, sw-register. Remove their old script tags.
3. **Editor system** — Convert editor-framework, editor-utils, nutrition-editor. Update dialog partial and all views.
4. **Recipe state manager** — Convert to controller. Extract fraction utilities.
5. **Grocery sync + UI** — Direct port to two Stimulus controllers. Highest risk step.
6. **Remove legacy** — Delete old JS files, remove `content_for(:scripts)` blocks
7. **Turbo Streams** — Extract partials, server-render shopping list, add Turbo Stream broadcasts, remove reload notification
8. **Stress test + final verification** — Screenshot comparison, concurrent stress test, performance check

## Testing Strategy

### Layer 1: Minitest regression gate

`rake test` + `rake lint` after every step. 500+ existing tests must pass.

### Layer 2: Playwright visual regression

Baseline screenshots before any changes:
- Homepage (logged in, logged out)
- Recipe page (with/without nutrition, scaled state)
- Ingredients page (with nutrition badges)
- Groceries page in multiple states (empty, recipes selected, items checked off, aisles collapsed, custom items, "all done")

Re-screenshot after each step. Goal: pixel-identical unless intentionally fixing a bug.

Functional Playwright tests:
- Turbo Drive navigation between pages
- Editor dialog lifecycle (open, edit, save, cancel, dirty-check)
- Grocery checkbox toggle and shopping list update
- ActionCable subscription establishment

### Layer 3: Concurrent stress test

Multi-agent test hammering the grocery page:
- Rapid recipe selection/deselection across concurrent sessions
- Simultaneous check-offs
- Custom item adds/removes interleaved
- Quick bites and aisle order edits during active selections
- Verify: no state corruption, no lost updates, optimistic locking retries succeed

### Test execution order

1. Baseline screenshots before code changes
2. After infrastructure: `rake test`, verify boot, screenshot all pages
3. After each controller conversion: `rake test`, screenshot affected page
4. After Turbo Streams: `rake test`, screenshot groceries in all states, run stress test
5. Final: full screenshot comparison, full stress test, page weight comparison

## Risks

| Risk | Mitigation |
|---|---|
| Dual rendering produces different HTML | Playwright screenshot comparison after step 7 |
| Turbo Drive breaks existing page behavior | Each page converted individually with tests between |
| Aisle collapse state lost on Turbo Stream replace | Controller re-applies from localStorage after replace |
| ActionCable race between version broadcast and Turbo Stream | Version polling ignores stale data; Turbo Stream is additive |
| Stress test regression | Run identical stress test before and after migration |
| Page weight increase from Stimulus + Turbo JS | Measure before/after; expect ~20KB gzipped overhead total |
