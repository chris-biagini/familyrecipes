# Framework Tax Audit Report

**Generated:** 2026-03-28 15:17:46
**Runs per page:** 5 (median reported)
**Server:** http://localhost:3030
**Browser:** Headless Chromium (Playwright)

## Seed (8 recipes)

### Framework Tax

| Page | Static DomComplete | JS DomComplete | Framework Tax | All JS runs (ms) |
|------|-------------------|----------------|---------------|------------------|
| Homepage | 97ms | 815ms | **718ms** | 780, 906, 912, 815, 248 |
| Menu | 124ms | 715ms | **591ms** | 776, 715, 733, 176, 577 |
| Groceries | 146ms | 1147ms | **1001ms** | 1148, 1147, 1117, 1160, 236 |
| Ingredients | 328ms | 666ms | **338ms** | 480, 666, 885, 672, 577 |
| Recipe | 137ms | 613ms | **476ms** | 613, 617, 902, 517, 444 |

### Timing Breakdown (JS enabled)

| Page | Network | Parse+Exec | Async Work | Load Handlers | Total |
|------|---------|------------|------------|---------------|-------|
| Homepage | 30ms | 254ms | 531ms | 0ms | 815ms |
| Menu | 55ms | 164ms | 496ms | 0ms | 715ms |
| Groceries | 66ms | 474ms | 607ms | 2ms | 1149ms |
| Ingredients | 115ms | 437ms | 114ms | 0ms | 666ms |
| Recipe | 24ms | 479ms | 110ms | 0ms | 613ms |

### Long Tasks (>50ms main thread blocks)

**Homepage:** 3 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 97 | 105 |
| 2 | 203 | 612 |
| 3 | 834 | 382 |

**Menu:** 3 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 139 | 85 |
| 2 | 225 | 490 |
| 3 | 735 | 424 |

**Groceries:** 3 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 142 | 342 |
| 2 | 484 | 105 |
| 3 | 592 | 552 |

**Ingredients:** 3 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 197 | 303 |
| 2 | 501 | 165 |
| 3 | 719 | 335 |

**Recipe:** 5 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 106 | 57 |
| 2 | 191 | 330 |
| 3 | 523 | 90 |
| 4 | 703 | 56 |
| 5 | 760 | 538 |

### JS Resources Loaded

**Homepage:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-62f1e35c.js | cached | 238.1 | 4 | 37 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 2 | 92 |
| src-VHY7BWOU.js | cached | 9.3 | 3 | 111 |
| editor_setup-55VNW5QV.js | cached | 236.2 | 33 | 177 |
| registry-Y22OGGUX.js | cached | 3.0 | 18 | 178 |
| auto_dash-DNFLZABB.js | cached | 0.4 | 23 | 178 |
| dist-2BJIGAD4.js | cached | 1.5 | 23 | 179 |
| chunk-3JPQEHXL.js | cached | 220.5 | 4 | 824 |
| chunk-I5URIM62.js | cached | 70.5 | 3 | 825 |

**Menu:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-62f1e35c.js | cached | 238.1 | 5 | 61 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 1 | 116 |
| src-VHY7BWOU.js | cached | 9.3 | 4 | 152 |
| editor_setup-55VNW5QV.js | cached | 236.2 | 9 | 737 |
| registry-Y22OGGUX.js | cached | 3.0 | 9 | 737 |
| auto_dash-DNFLZABB.js | cached | 0.4 | 9 | 738 |
| dist-2BJIGAD4.js | cached | 1.5 | 8 | 738 |
| chunk-I5URIM62.js | cached | 70.5 | 23 | 1164 |
| chunk-3JPQEHXL.js | cached | 220.5 | 9 | 1178 |

**Groceries:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-62f1e35c.js | cached | 238.1 | 7 | 74 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 2 | 122 |
| src-VHY7BWOU.js | cached | 9.3 | 2 | 500 |
| editor_setup-55VNW5QV.js | cached | 236.2 | 3 | 1483 |
| chunk-I5URIM62.js | cached | 70.5 | 3 | 1496 |
| chunk-3JPQEHXL.js | cached | 220.5 | 3 | 1496 |

**Ingredients:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-62f1e35c.js | cached | 238.1 | 6 | 119 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 3 | 174 |
| src-VHY7BWOU.js | cached | 9.3 | 2 | 212 |
| editor_setup-55VNW5QV.js | cached | 236.2 | 2 | 1058 |
| chunk-I5URIM62.js | cached | 70.5 | 2 | 1069 |
| chunk-3JPQEHXL.js | cached | 220.5 | 2 | 1070 |

**Recipe:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-62f1e35c.js | cached | 238.1 | 13 | 86 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 2 | 188 |
| src-VHY7BWOU.js | cached | 9.3 | 4 | 580 |

### CodeMirror Prefetch Analysis

- **Homepage:** Loaded chunk-RNFM7RMJ.js, editor_setup-55VNW5QV.js, chunk-3JPQEHXL.js, chunk-I5URIM62.js. Last response at 828ms, DomComplete at 815ms. AFTER DomComplete — contributes to framework tax
- **Menu:** Loaded chunk-RNFM7RMJ.js, editor_setup-55VNW5QV.js, chunk-I5URIM62.js, chunk-3JPQEHXL.js. Last response at 1188ms, DomComplete at 715ms. AFTER DomComplete — contributes to framework tax
- **Groceries:** Loaded chunk-RNFM7RMJ.js, editor_setup-55VNW5QV.js, chunk-I5URIM62.js, chunk-3JPQEHXL.js. Last response at 1499ms, DomComplete at 1147ms. AFTER DomComplete — contributes to framework tax
- **Ingredients:** Loaded chunk-RNFM7RMJ.js, editor_setup-55VNW5QV.js, chunk-I5URIM62.js, chunk-3JPQEHXL.js. Last response at 1072ms, DomComplete at 666ms. AFTER DomComplete — contributes to framework tax
- **Recipe:** Loaded chunk-RNFM7RMJ.js. Last response at 190ms, DomComplete at 613ms. BEFORE DomComplete — may contribute to framework tax

## Stress (200 recipes)

### Framework Tax

| Page | Static DomComplete | JS DomComplete | Framework Tax | All JS runs (ms) |
|------|-------------------|----------------|---------------|------------------|
| Homepage | 447ms | 748ms | **301ms** | 837, 748, 740, 709, 754 |
| Menu | 212ms | 409ms | **197ms** | 376, 445, 409, 500, 363 |
| Groceries | 140ms | 771ms | **631ms** | 771, 795, 729, 819, 720 |
| Ingredients | 828ms | 2179ms | **1351ms** | 1934, 2286, 2185, 2179, 1910 |
| Recipe | 103ms | 614ms | **511ms** | 756, 550, 796, 151, 614 |

### Timing Breakdown (JS enabled)

| Page | Network | Parse+Exec | Async Work | Load Handlers | Total |
|------|---------|------------|------------|---------------|-------|
| Homepage | 40ms | 165ms | 543ms | 0ms | 748ms |
| Menu | 128ms | 270ms | 11ms | 0ms | 409ms |
| Groceries | 67ms | 190ms | 514ms | 1ms | 772ms |
| Ingredients | 531ms | 1626ms | 22ms | 0ms | 2179ms |
| Recipe | 23ms | 224ms | 367ms | 1ms | 615ms |

### Long Tasks (>50ms main thread blocks)

**Homepage:** 2 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 142 | 606 |
| 2 | 765 | 345 |

**Menu:** 4 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 155 | 56 |
| 2 | 220 | 68 |
| 3 | 292 | 105 |
| 4 | 414 | 52 |

**Groceries:** 3 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 168 | 88 |
| 2 | 258 | 513 |
| 3 | 787 | 321 |

**Ingredients:** 8 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 702 | 80 |
| 2 | 793 | 54 |
| 3 | 875 | 93 |
| 4 | 979 | 104 |
| 5 | 1094 | 105 |
| 6 | 1247 | 54 |
| 7 | 1301 | 856 |
| 8 | 2262 | 89 |

**Recipe:** 3 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 426 | 172 |
| 2 | 634 | 56 |
| 3 | 717 | 777 |

### JS Resources Loaded

**Homepage:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-62f1e35c.js | cached | 238.1 | 6 | 45 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 1 | 96 |
| src-VHY7BWOU.js | cached | 9.3 | 1 | 112 |
| editor_setup-55VNW5QV.js | cached | 236.2 | 7 | 136 |
| registry-Y22OGGUX.js | cached | 3.0 | 6 | 137 |
| auto_dash-DNFLZABB.js | cached | 0.4 | 6 | 137 |
| dist-2BJIGAD4.js | cached | 1.5 | 6 | 137 |
| chunk-I5URIM62.js | cached | 70.5 | 50 | 754 |
| chunk-3JPQEHXL.js | cached | 220.5 | 50 | 754 |

**Menu:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-62f1e35c.js | cached | 238.1 | 3 | 137 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 2 | 289 |
| src-VHY7BWOU.js | cached | 9.3 | 2 | 310 |

**Groceries:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-62f1e35c.js | cached | 238.1 | 7 | 76 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 2 | 141 |
| src-VHY7BWOU.js | cached | 9.3 | 2 | 181 |
| editor_setup-55VNW5QV.js | cached | 236.2 | 3 | 1136 |
| chunk-I5URIM62.js | cached | 70.5 | 3 | 1153 |
| chunk-3JPQEHXL.js | cached | 220.5 | 3 | 1153 |

**Ingredients:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-62f1e35c.js | cached | 238.1 | 9 | 613 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 2 | 783 |
| src-VHY7BWOU.js | cached | 9.3 | 3 | 1369 |
| editor_setup-55VNW5QV.js | cached | 236.2 | 2 | 2205 |
| chunk-I5URIM62.js | cached | 70.5 | 2 | 2216 |
| chunk-3JPQEHXL.js | cached | 220.5 | 2 | 2216 |

**Recipe:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-62f1e35c.js | cached | 238.1 | 7 | 29 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 2 | 72 |
| src-VHY7BWOU.js | cached | 9.3 | 2 | 446 |
| editor_setup-55VNW5QV.js | cached | 236.2 | 105 | 730 |
| registry-Y22OGGUX.js | cached | 3.0 | 103 | 731 |
| auto_dash-DNFLZABB.js | cached | 0.4 | 103 | 732 |
| dist-2BJIGAD4.js | cached | 1.5 | 102 | 733 |

### CodeMirror Prefetch Analysis

- **Homepage:** Loaded chunk-RNFM7RMJ.js, editor_setup-55VNW5QV.js, chunk-I5URIM62.js, chunk-3JPQEHXL.js. Last response at 805ms, DomComplete at 748ms. AFTER DomComplete — contributes to framework tax
- **Menu:** Loaded chunk-RNFM7RMJ.js. Last response at 291ms, DomComplete at 409ms. BEFORE DomComplete — may contribute to framework tax
- **Groceries:** Loaded chunk-RNFM7RMJ.js, editor_setup-55VNW5QV.js, chunk-I5URIM62.js, chunk-3JPQEHXL.js. Last response at 1156ms, DomComplete at 771ms. AFTER DomComplete — contributes to framework tax
- **Ingredients:** Loaded chunk-RNFM7RMJ.js, editor_setup-55VNW5QV.js, chunk-I5URIM62.js, chunk-3JPQEHXL.js. Last response at 2218ms, DomComplete at 2179ms. AFTER DomComplete — contributes to framework tax
- **Recipe:** Loaded chunk-RNFM7RMJ.js, editor_setup-55VNW5QV.js. Last response at 835ms, DomComplete at 614ms. AFTER DomComplete — contributes to framework tax

## Top Contributors (Analysis)

### 1. Main bundle parse + execute (238 KB application.js)

The single largest contributor. The Parse+Exec column shows 164–1626ms
depending on page and kitchen size. This phase includes Turbo Drive init,
Stimulus `Application.start()` (which creates a MutationObserver and scans the
entire DOM for `data-controller` attributes), 22 eager controller registrations,
and controller `connect()` callbacks.

The Ingredients page is the extreme case: with 200 recipes in the stress
kitchen, Stimulus scans a massive DOM table. Parse+Exec alone is 1626ms — the
framework tax is almost entirely synchronous main-thread blocking. Long tasks
confirm this: 8 long tasks including an 856ms block.

Even on the seed kitchen, Parse+Exec ranges from 164ms (Menu) to 479ms
(Recipe), indicating that the bundle's synchronous execution cost is substantial
regardless of DOM size.

### 2. CodeMirror prefetch on every page

The `requestIdleCallback(() => import("./codemirror/editor_setup"))` in
`application.js` fires on every page load. This loads `editor_setup` (236 KB)
plus transitive chunks totaling ~530 KB decoded. The fetch itself is fast
(cached), but **module evaluation blocks the main thread** — it shows up as
300–600ms long tasks.

Resource timing confirms CodeMirror chunks load on every page tested, including
Groceries and Ingredients which have no editor. On most pages, chunk loading
finishes AFTER DomComplete (meaning the chunks themselves don't inflate
DomComplete), but the evaluation long tasks that precede them DO block the main
thread during the DomComplete window.

Notable: the Recipe page on the seed kitchen did NOT load editor_setup (only
the small chunk-RNFM7RMJ.js), while the stress kitchen Recipe page did. This
suggests the prefetch timing is non-deterministic — `requestIdleCallback` fires
whenever the browser finds idle time, which varies with main-thread contention.

### 3. Async Work phase (DOMContentLoaded → DomComplete)

The Async Work column shows 367–607ms on several pages (Homepage, Menu,
Groceries, Recipe). This phase includes deferred script evaluation, dynamic
imports (CodeMirror prefetch), ActionCable WebSocket connection setup, service
worker registration, and Turbo Stream subscription initialization.

Pages with large Async Work values correlate with pages where CodeMirror chunks
appear in the resource list — the prefetch evaluation is the likely driver. The
stress kitchen Menu page has only 11ms of Async Work (CodeMirror didn't load on
that run), while the seed kitchen Menu page has 496ms (CodeMirror did load).

### Scaling observations

| Metric | Seed (8 recipes) | Stress (200 recipes) | Scaling |
|--------|-----------------|---------------------|---------|
| Ingredients DomComplete | 666ms | 2179ms | **3.3x** — superlinear |
| Ingredients Parse+Exec | 437ms | 1626ms | **3.7x** — superlinear |
| Homepage DomComplete | 815ms | 748ms | ~1x (noise) |
| Menu DomComplete | 715ms | 409ms | Faster (less async work) |
| Recipe DomComplete | 613ms | 614ms | ~1x |

The Ingredients page scales superlinearly with content — Stimulus DOM scanning
cost grows with element count. Other pages are relatively stable, suggesting
the framework tax is dominated by fixed costs (bundle eval, prefetch) rather
than per-element costs.

### Recommendations for follow-up (#302)

1. **Scope CodeMirror prefetch** to pages with editors only (Homepage, Recipe
   show, Menu). Eliminating the prefetch on Groceries and Ingredients should
   cut 300-600ms of main-thread blocking on those pages.
2. **Investigate Stimulus DOM scan cost** on the Ingredients page. With 200
   ingredients, the table DOM is large. Consider whether `ingredient-table`
   controller could use a more targeted connection strategy.
3. **Consider lazy Stimulus controller loading** for page-specific controllers.
   Only 3 of 22 controllers are global (`search-overlay`, `nav-menu`, `toast`).
   The remaining 19 are loaded and registered on every page but only connect on
   pages that use them. While registration is cheap, the module evaluation
   (parsing 100+ KB of controller code) contributes to Parse+Exec.

## Bundle Composition

Top entries from `esbuild --analyze` (raw, pre-minification):

| Module | Size | % of bundle |
|--------|------|-------------|
| @codemirror/view | 387 KB | 24.3% |
| @hotwired/turbo | 181 KB | 11.4% |
| @codemirror/state | 127 KB | 8.0% |
| @codemirror/language | 89 KB | 5.6% |
| @hotwired/stimulus | 83 KB | 5.2% |
| @lezer/javascript | 80 KB | 5.0% |
| @lezer/markdown | 79 KB | 4.9% |
| @lezer/common | 74 KB | 4.6% |
| @lezer/lr | 64 KB | 4.0% |
| @codemirror/commands | 52 KB | 3.3% |

CodeMirror + Lezer account for ~65% of the total bundle (pre-split). After
code splitting, these are in the lazy chunk — but the prefetch loads them on
every page anyway, negating the splitting benefit.

Turbo (181 KB) + Stimulus (83 KB) + ActionCable (~18 KB) = 282 KB raw framework
code that must load on every page. This is the irreducible framework floor.
