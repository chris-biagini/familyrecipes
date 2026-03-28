# Framework Tax Audit — Design Spec

**Date:** 2026-03-28
**Issue:** #302

Automated investigation of the 500-700ms client-side framework tax — the
DomComplete difference between JS-enabled and JS-disabled page loads. The goal
is to identify exactly where the time goes so future optimization work targets
the right things. Investigation only; no fixes in this pass.

## Background

The performance-feel-optimization branch (now merged) addressed server-side
performance. Two client-side fixes were attempted and reverted:

1. `loading="lazy"` on turbo-frames inside `<dialog>` — IntersectionObserver
   never fires because `showModal()` renders in the browser's top layer.
2. Self-morph suppression via `turbo:before-stream-render` — too aggressive;
   swallowed broadcast refreshes needed after editor saves.

Both failed because we optimized based on assumptions, not measurements. This
spec establishes the measurement infrastructure first.

## What We're Measuring

The framework tax is the cost of running JavaScript on a page that would
otherwise render fine as static HTML+CSS. It includes:

- **Script parse + compile**: V8 parsing the 244 KB main bundle
- **Script execution**: Turbo Drive init, Stimulus boot + DOM scan, controller
  registration + connection, ActionCable WebSocket setup, event listener wiring
- **Script-triggered work**: layout recalculations, style invalidations, or
  additional network requests caused by JS execution

The CodeMirror editor chunk (242 KB) loads lazily via
`requestIdleCallback(() => import(...))` and is likely not a DomComplete
contributor — dynamic imports are not document subresources. The audit will
confirm or refute this.

## Approach

A standalone Playwright script that loads each page in two modes (JS enabled,
JS disabled) and captures timing data via native browser Performance APIs. No
CDP trace parsing — the built-in APIs are sufficient to identify the top
contributors.

### Pages Under Test

The same 5 pages from the original measurements:

| Page | Route | Why |
|------|-------|-----|
| Homepage | `/` | Baseline, has editor frames |
| Menu | `/menu` | Heaviest HTML, most interactive |
| Groceries | `/groceries` | High-frequency interactions |
| Ingredients | `/ingredients` | Large table, ingredient-table controller |
| Recipe | `/recipes/:slug` | Content page, wake-lock + scale-panel |

### Data Captured Per Page

**1. Navigation Timing** (`performance.getEntriesByType('navigation')[0]`)

| Metric | What It Tells Us |
|--------|-----------------|
| `responseEnd` | TTFB + transfer — server cost baseline |
| `domContentLoadedEventEnd` | HTML parsed, sync scripts executed |
| `domComplete` | All subresources loaded, scripts settled |
| `loadEventEnd` | Everything done including load handlers |

Captured with JS enabled and JS disabled. The `domComplete` difference is
the framework tax.

**2. Long Tasks** (`PerformanceObserver` for `longtask` type)

Any main-thread task exceeding 50ms. Each entry has `startTime`, `duration`,
and `attribution` (which script or context caused it). These are the specific
chunks of work blocking the main thread.

The observer must be installed before navigation (via `page.evaluateOnNewDocument`)
so it captures tasks during initial page load, not just after our script runs.

**3. Resource Timing** (`performance.getEntriesByType('resource')`)

Filtered to `initiatorType === 'script'` or entries matching `.js`. Shows:
- Which JS files loaded on the page
- Transfer size and decoded size
- Fetch start/end timing
- Whether the CodeMirror chunk loaded (confirms/refutes the prefetch theory)

**4. Script-vs-Rendering Split**

Derived from navigation timing:
- `responseEnd - fetchStart` = network time
- `domContentLoadedEventEnd - responseEnd` = HTML parse + sync script execution
- `domComplete - domContentLoadedEventEnd` = async work (deferred scripts,
  subresource loads, idle callbacks)
- `loadEventEnd - domComplete` = load event handlers

This breakdown identifies whether the tax is in synchronous execution (the
main bundle running) or async work (dynamic imports, ActionCable, etc.).

### Measurement Protocol

- **5 runs per page per mode** (JS enabled, JS disabled)
- **Median** of 5 runs, not average — ignores outliers from GC pauses, etc.
- **Full page load** each time — `page.goto()` with `waitUntil: 'load'`
- **Cold cache**: new browser context per run (no cached JS or connections)
- **Headless Chromium** via Playwright — same environment as the original
  measurements for comparability
- **Dev server must be running** on port 3030 with seed data

### Output

A markdown report written to `test/performance/results/framework-tax-audit.md`
with:

1. Per-page framework tax table (static vs JS DomComplete)
2. Per-page timing breakdown (network / parse+exec / async / load handlers)
3. Long task inventory (duration, start time, per page)
4. Resource loading table (which JS files loaded on which pages, sizes)
5. CodeMirror prefetch verdict (did the chunk load? did it affect DomComplete?)
6. Top contributors summary — ranked list of where the time goes

The raw timing data is also written as JSON to
`test/performance/results/framework-tax-raw.json` for programmatic comparison
in future runs.

### Bundle Analysis

Separate from the Playwright audit: run `npx esbuild-visualizer` (or
`esbuild --analyze`) to produce a treemap of what's in the 244 KB main bundle.
Save output to `test/performance/results/bundle-analysis.txt`. This pairs with
the resource timing data to connect "file X is N KB" with "file X took N ms."

## File Map

- Create: `test/performance/framework_tax_audit.js` — Playwright script
- Create: `test/performance/results/` — output directory (gitignored except
  for the committed report after the first run)
- Create: `test/performance/.gitkeep` — ensure directory exists

## Non-Goals

- Fixing anything. This is measurement only.
- CDP trace parsing or flamegraph generation. Native APIs first.
- CI integration. This is an on-demand diagnostic tool.
- Measuring Turbo Drive navigations (link clicks). Focus is on full page loads,
  which is where the measured 500-700ms tax lives.

## Success Criteria

The audit produces a clear, data-backed answer to: "What are the top 3
contributors to the 500-700ms client-side framework tax?" with enough
specificity to guide targeted optimization work in a follow-up issue.
