# Caching Architecture Fix

**Date:** 2026-02-28
**Status:** Approved

## Problem

The app has two aggressive caching layers that both default to "cache everything":

1. **Cloudflare** edge-caches all static files with a 1-year `max-age` from Rails' production config. Non-fingerprinted files in `public/` (error pages, icons, `service-worker.js`) get stuck in Cloudflare's cache across deploys.

2. **The service worker** has a `cacheFirst` catch-all (line 61) that permanently caches any GET request not matching an explicit skip-list (`API_PATTERN`). Every new endpoint is a ticking time bomb unless added to the pattern.

The interaction is deadly: Cloudflare caches the SW script itself, so even when the SW source is updated with new skip-list entries, browsers never see the update. This caused the menu selection bug — the production SW was stuck on `v1` (missing all `menu/` routes) while the source was on `v4`.

### Recent attempted fixes that didn't stick

- `Cache-Control: no-store` on JSON responses (commit `79ea415`) — correct for browser HTTP cache but ignored by the SW's `cache.put()`
- Moving `service-worker.js` to a Rails route with `no-cache` headers — fixes the SW staleness but doesn't address the structural catch-all problem

## Design

### 1. Service worker — flip the catch-all default

Replace the `cacheFirst` catch-all with `return` (pass-through to browser). The SW only intercepts requests it has an explicit strategy for:

| Request | Strategy | Why |
|---|---|---|
| `/assets/*` | cache-first | Propshaft-fingerprinted, immutable |
| `/icons/*` | cache-first | Versioned via query param |
| HTML navigation (`Accept: text/html`) | network-first + offline fallback | PWA offline support |
| `/manifest.json` | network-first | PWA metadata updates |
| Everything else | **pass-through** | Browser handles normally |

The `API_PATTERN` skip-list is retained as documentation and defense-in-depth, but the default is now safe — unrecognized requests hit the network.

### 2. Rails static file headers — lower default TTL

Change `config/environments/production.rb`:

```ruby
# Before: 1 year for everything in public/
config.public_file_server.headers = { 'cache-control' => "public, max-age=#{1.year.to_i}" }

# After: 1 hour default (Propshaft sets its own headers for /assets/*)
config.public_file_server.headers = { 'cache-control' => "public, max-age=#{1.hour.to_i}" }
```

Propshaft-fingerprinted assets are unaffected — Propshaft's middleware sets its own far-future headers. This only changes the TTL for non-fingerprinted files: error pages, `robots.txt`, icons.

### 3. Explicit Cache-Control on controller responses

**Member-only pages** (menu, groceries, ingredients): `Cache-Control: private, no-cache`. These contain user-specific content and must always revalidate. The `private` directive prevents Cloudflare from edge-caching them.

**JSON API responses**: keep `no-store` via the existing `prevent_api_caching` before_action. This is defense-in-depth for the browser HTTP cache.

**Public pages** (recipes, homepage): no explicit header. Rails defaults + SW network-first handle freshness. Adding explicit headers here would prevent Cloudflare from caching recipe pages, which is fine for a homelab app but suboptimal for the future hosted version.

**Manifest endpoint**: explicit `no-cache` instead of inheriting `no-store` from the JSON format check. Allows Cloudflare to cache with revalidation.

### 4. Document Cloudflare cache purge

Add the `curl` command to CLAUDE.md's deployment section. Not automated in CI — run manually when deploying changes to non-fingerprinted static files.

## Files changed

- `app/views/pwa/service_worker.js.erb` — remove catch-all, add pass-through
- `config/environments/production.rb` — lower `public_file_server` TTL to 1 hour
- `app/controllers/application_controller.rb` — add `prevent_html_caching` for member-only pages
- `app/controllers/pwa_controller.rb` — explicit `no-cache` on manifest
- `app/controllers/menu_controller.rb` — apply `prevent_html_caching` to `show`
- `app/controllers/groceries_controller.rb` — apply `prevent_html_caching` to `show`
- `app/controllers/ingredients_controller.rb` — apply `prevent_html_caching` to `index`
- `CLAUDE.md` — document Cloudflare purge command, update caching architecture notes
