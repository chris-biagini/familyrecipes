# Performance Optimization — Design Spec

**Date:** 2026-03-27

Comprehensive performance pass ahead of v1.0. Targets both back-end query
efficiency and front-end payload size. The app is a Turbo Drive SPA — after
the first page load, navigations are HTML-only with all assets cached, so
first-load size and per-request query cost are the two levers that matter
most.

## Profiling Baseline

Measured warm (second request, dev mode, single Puma worker):

| Page | Time | Queries | HTML size |
|------|------|---------|-----------|
| Homepage | 24ms | ~30 | 61 KB |
| Menu | 127ms | 82 (2 cached) | 116 KB |
| Groceries | 71ms | ~50 | 91 KB |

JS bundle: 765 KB minified / 356 KB gzipped (single file).
CSS: 93 KB raw / 18 KB gzipped (6 global files + 3 page-specific).

## 1. Back-End Optimizations

### 1a. Fix Menu Page N+1

`Recipe#own_ingredients_aggregated` (app/models/recipe.rb:46) uses the
`has_many :ingredients, through: :steps` association, which generates a fresh
SQL JOIN per recipe even when `steps: [:ingredients]` is already preloaded by
the controller. This produces ~40 redundant queries on the menu page.

**Fix:** Traverse preloaded associations directly:

```ruby
def own_ingredients_aggregated
  steps.flat_map(&:ingredients).group_by(&:name).transform_values do |group|
    IngredientAggregator.aggregate_amounts(group)
  end
end
```

Audit all call sites of `recipe.ingredients` to ensure none bypass preloaded
`steps: [:ingredients]` data. Note: `CrossReference#expanded_ingredients`
calls `target_recipe.own_ingredients_aggregated` — the menu controller's
preload tree already includes `cross_references: { target_recipe: { steps:
:ingredients } }`, so the fix propagates to cross-referenced recipes too.

**Expected impact:** Menu page drops from ~82 queries to ~40, saving ~40ms.

### 1b. Cache IngredientResolver per Request

`IngredientCatalog.resolver_for(kitchen)` loads all catalog entries (2 DB
queries) and builds a variant hash with O(n) regex inflections on every call.
Currently rebuilt fresh per call site — no caching at any level.

**Fix:** Memoize on `Current` (Rails CurrentAttributes):

```ruby
# In Current
attribute :resolver

# In IngredientCatalog or a concern
def self.resolver_for(kitchen)
  Current.resolver ||= build_resolver(kitchen)
end
```

Reset is automatic at end of request via CurrentAttributes lifecycle. Callers
that accept `resolver:` keyword continue working. `MealPlanWriteService` and
others that call `build_resolver` independently switch to the shared instance.

Background jobs (`RecipeNutritionJob`, `CascadeNutritionJob`) run outside the
request lifecycle — `Current` resets between jobs, so they correctly build
their own resolver.

**Expected impact:** Eliminates 2 queries + expensive hash construction on
every request that touches ingredient resolution (menu, groceries, write
actions). Saves ~5-10ms per request.

### 1c. Memoize `resolve_sole_kitchen`

`ApplicationController` calls `Kitchen.limit(2).to_a` in both
`set_kitchen_from_path` (line 38) and `auto_join_sole_kitchen` (line 98).
The double query only fires on a user's very first request (before they have
a membership) — after that, `auto_join_sole_kitchen` short-circuits at the
`memberships.exists?` check. Minor cleanup, not a hot path.

**Fix:** Memoize with `@sole_kitchen` instance variable so both before_actions
share a single query result.

### 1d. Configure Production Cache Store

`config.cache_store` is commented out in production.rb. Rails falls back to
file store, which has no TTL management and is slow for reads.
`SearchDataHelper` already uses `Rails.cache.fetch` — making the store
durable unlocks this.

**Fix:** Use `:memory_store` in production — simple, zero-dependency, no
migration needed. The app runs single-process Puma in a homelab Docker
container, so in-process memory cache is appropriate. The cache is warm
within one request of restart, and `SearchDataHelper` already invalidates
via kitchen `updated_at` in the cache key.

`solid_cache` is not in the Gemfile and would require a gem addition,
migration, and database.yml changes — overkill for this use case.

```ruby
# config/environments/production.rb
config.cache_store = :memory_store, { size: 16.megabytes }
```

**Expected impact:** Search data helper avoids rebuilding its JSON blob on
every first request after restart. Modest but free.

## 2. Front-End — JS Code Splitting

### 2a. Split CodeMirror into a Lazy Chunk

CodeMirror + Lezer packages account for 513 KB minified (67% of the bundle).
They are used exclusively by `plaintext_editor_controller`, which itself
loads inside lazy Turbo Frames (editors open on demand, not on page load).

**Architecture:**

Two logical entry points managed by esbuild with code splitting:

- **Main bundle** (`application.js`): Core frameworks (Turbo 92KB, Stimulus
  44KB, ActionCable 8KB) + all Stimulus controllers + utilities. ~252 KB
  minified → ~176 KB gzipped.
- **CodeMirror chunk** (auto-extracted by esbuild): All `@codemirror/*` and
  `@lezer/*` packages + `app/javascript/codemirror/` integration files.
  ~513 KB minified → ~180 KB gzipped.

**Mechanism:** `plaintext_editor_controller` uses dynamic `import()` to load
the CodeMirror setup module. esbuild's `splitting: true` with `format: "esm"`
automatically extracts CM dependencies into a separate chunk.

```javascript
// plaintext_editor_controller.js
async connect() {
  const { createEditor } = await import("../codemirror/editor_setup.js")
  // ... proceed as before
}
```

**ESM format change:** Code splitting requires `format: "esm"`. The layout's
`<script>` tag changes from `defer` to `type="module"`. All modern browsers
support ESM (the app already requires modern browsers via
`allow_browser versions: :modern`).

### 2b. Prefetch the Editor Chunk

After the main page loads and goes idle, prefetch the CM chunk so it's cached
before the user opens an editor:

```javascript
// In application.js
const prefetch = () => import("../codemirror/editor_setup.js")
if (typeof requestIdleCallback === "function") {
  requestIdleCallback(prefetch)
} else {
  setTimeout(prefetch, 1000) // Safari < 16.4 fallback
}
```

On fast networks the chunk is cached within 1-2 seconds of page load. The
editor-open latency penalty (~95ms on fast WiFi, ~450ms on mobile 4G) only
applies if the user opens an editor faster than the prefetch completes.

### 2c. esbuild Configuration and Propshaft Integration

**The problem:** esbuild's dynamic `import()` hardcodes chunk URLs (e.g.
`/assets/chunks/codemirror-ABC123.js`). Propshaft re-fingerprints filenames
by appending its own digest, so the hardcoded URL would 404.

**Solution:** Write chunks to `public/assets/chunks/` — bypassing Propshaft
entirely. Files in `public/` are served directly by the web server with no
fingerprinting. esbuild's own `[hash]` in chunk names provides cache-busting.
Set `Cache-Control` for chunks via the existing `public_file_server.headers`
config (already set to `max-age=3600` in production).

```javascript
// esbuild.config.mjs
const config = {
  entryPoints: ["app/javascript/application.js"],
  bundle: true,
  splitting: true,        // enable code splitting
  format: "esm",          // required for splitting
  sourcemap: true,
  outdir: "app/assets/builds",          // main bundle (Propshaft)
  publicPath: "/assets",
  chunkNames: "../../../public/assets/chunks/[name]-[hash]",
}
```

The `chunkNames` path is relative to `outdir`. The main entry point
(`application.js`) stays in `app/assets/builds/` for Propshaft to
fingerprint and serve. Chunks land in `public/assets/chunks/` where they're
served directly. Add `public/assets/chunks/` to `.gitignore` (build
artifacts, like `app/assets/builds/`).

**ESM `type="module"` notes:** Modules are deferred by default (the existing
`defer: true` becomes redundant but harmless). Modules have strict CORS
requirements, but all assets are same-origin so no issue. The CSP
`script-src` already uses nonces; ESM modules respect `nonce` attributes on
the `<script type="module">` tag.

## 3. Front-End Cleanup

### 3a. Delete Unused Self-Hosted Fonts

Remove `public/fonts/source-sans-3/` (~60 KB total). Zero references in any
CSS file — these fonts are never loaded. Since they're in `public/` they
don't affect page load (only served if directly requested), but they're dead
weight in the repo and Docker image.

### 3b. Add `media="print"` to print.css

Change the layout's `stylesheet_link_tag 'print'` to include
`media: "print"`. The browser won't fetch the file until printing, saving
1.2 KB gzipped and one HTTP request on every page load.

### 3c. Replace paper-noise.png with SVG Noise Filter

An existing design spec covers this:
`docs/superpowers/specs/2026-03-20-svg-paper-texture-design.md`

The approach uses an inline `<filter id="paper-texture">` element with
`feTurbulence` + `feDiffuseLighting`, referenced via `url(#paper-texture)`
in CSS. This avoids CSP violations (a `data:` URI approach would violate
`img_src :self`). Implement per the existing spec.

Eliminates one HTTP request and 34 KB.

### 3d. CSS Minification

Propshaft serves CSS files as-is with no transformation. Add a lightweight
build step: an npm script that runs `lightningcss` (fast, zero-config CSS
minifier) over the stylesheets directory, writing minified output to
`app/assets/builds/` alongside the JS bundle. Propshaft already serves
`app/assets/builds/` — the minified CSS files there will take precedence
over the originals in `app/assets/stylesheets/` since Propshaft resolves
from `builds/` first.

```json
"scripts": {
  "build:css": "lightningcss --minify --bundle app/assets/stylesheets/*.css --output-dir app/assets/builds/",
  "build": "node esbuild.config.mjs && npm run build:css"
}
```

Update `Procfile.dev` to watch CSS files too (`--watch` flag).

93 KB raw → ~70-75 KB raw, improving gzipped transfer by ~2-3 KB total.
Small win, clean integration.

## Expected Results

### First Page Load (gzipped transfer)

| Asset | Current | After | Notes |
|-------|---------|-------|-------|
| JS (main, render-blocking) | 356 KB | ~176 KB | CodeMirror split out |
| JS (CM prefetch, non-blocking) | — | ~180 KB | Background fetch |
| CSS (render-blocking) | 18.1 KB | ~16 KB | Minified, print deferred |
| paper-noise.png (non-blocking) | 34 KB | 0 | SVG filter per existing spec |
| **Render-blocking total** | **~374 KB** | **~192 KB** |

### Page Load Times (estimated)

| Scenario | Current | After | Improvement |
|----------|---------|-------|-------------|
| Fast WiFi (50Mbps) | ~320ms | ~240ms | 25% faster |
| Slow WiFi (10Mbps) | ~680ms | ~460ms | 32% faster |
| Mobile 4G (5Mbps) | ~1.4s | ~940ms | 33% faster |

### Menu Page Server Time

| Metric | Current | After |
|--------|---------|-------|
| Queries | 82 | ~40 |
| Response time | 127ms | ~70ms |

### Editor Open Latency (new cost, mitigated by prefetch)

| Scenario | Without prefetch | With prefetch (typical) |
|----------|-----------------|------------------------|
| Fast WiFi | ~95ms | 0ms (already cached) |
| Slow WiFi | ~190ms | 0ms |
| Mobile 4G | ~450ms | 0ms |

## Out of Scope

- Full per-page code splitting (Option C) — diminishing returns over A,
  significant Stimulus lazy-loading complexity.
- HTTP/2 push — requires reverse proxy configuration, not an app concern.
- Fragment caching — the app's pages are dynamic per-kitchen; Turbo Drive
  already provides client-side caching of navigations.
- Database index additions — the existing composite indexes on
  `custom_grocery_items` and `on_hand_entries` cover the query patterns
  adequately. SQLite's small dataset size means the index miss penalty is
  sub-millisecond. Not worth the migration churn for v1.0.
- Additional SQLite pragmas — current WAL + mmap + cache config is solid.
