# PWA Design

## Goal

Make the site installable as a Progressive Web App — acts like a native app, retains all live-updating ability of the groceries page, works offline for the core "at the store" shopping flow.

## Decisions

- **Approach:** Runtime caching (no precache manifest). Propshaft's fingerprinted asset URLs make this natural — cache `/assets/*` on first encounter, they're valid forever.
- **Offline depth:** Service worker cache only. No pre-caching of unvisited pages, no client-side shopping list computation. The groceries JS already caches state in localStorage and queues actions for retry — the service worker just adds the HTML shell.
- **Icons:** Generated at build time from `favicon.svg` using `rsvg-convert`. No binary assets in the repo.
- **Update strategy:** Silent update on navigation. `skipWaiting()` + `clients.claim()` — new service worker activates immediately, next navigation gets fresh content.
- **Offline fallback:** Self-contained `offline.html` page for never-visited URLs.

## Service Worker

**File:** `public/service-worker.js` (root scope covers entire site)

**Registration:** `app/assets/javascripts/sw-register.js` included in the layout `<head>`. External file required by CSP (no inline scripts).

### Caching strategies

| Request type | Strategy | Rationale |
|---|---|---|
| `/assets/*` | Cache-first | Propshaft fingerprints = immutable URLs, cache forever |
| HTML pages | Network-first, cache fallback | Always fresh online; cached version offline |
| `/icons/*`, manifest | Cache-first | Static, rarely change |
| API endpoints (state, select, check, etc.) | Network-only (skip) | Groceries JS manages localStorage caching |
| `/cable` WebSocket | Skip | ActionCable manages its own connection |
| Non-GET requests | Skip | Mutations go to the server |

### Lifecycle

1. **Install:** Cache `offline.html` fallback page. Call `skipWaiting()`.
2. **Activate:** Clean up old caches (keyed by version). Call `clients.claim()`.
3. **Fetch:** Route by strategy table above. On HTML cache miss while offline, serve `offline.html`.

Old fingerprinted asset entries become dead weight after deploys but are small. Cache cleanup can be added later if needed.

## Manifest

Updated `public/manifest.json`:

```json
{
  "name": "Family Recipes",
  "short_name": "Recipes",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#cd4754",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable" }
  ],
  "shortcuts": [
    { "name": "Grocery List", "short_name": "Groceries", "url": "/groceries" }
  ]
}
```

The gingham pattern fills the full frame and looks good at any crop, so the 512 icon doubles as `any maskable` — no separate maskable file needed. Shortcut URL `/groceries` works with the optional kitchen scope when one kitchen exists.

## Icon Generation

### Rake task: `pwa:icons`

Uses `rsvg-convert` (from `librsvg2-bin`) to generate PNGs from `app/assets/images/favicon.svg`.

| Output file | Size | Purpose |
|---|---|---|
| `public/icons/icon-192.png` | 192x192 | PWA manifest |
| `public/icons/icon-512.png` | 512x512 | PWA manifest + splash |
| `public/icons/apple-touch-icon.png` | 180x180 | iOS home screen (PNG required) |
| `public/icons/favicon-32.png` | 32x32 | Favicon fallback for Safari |

Generated files land in `public/icons/` — automatically gitignored by the existing `*.png` rule.

### Integration

- **Dockerfile builder stage:** Add `librsvg2-bin` to apt packages. Run `rake pwa:icons` after `assets:precompile`.
- **`bin/setup`:** Run `rake pwa:icons` before starting the dev server.
- **CI:** Add `librsvg2-bin` to test runner packages (or skip icon generation in CI).

### Repo cleanup

Remove tracked binary assets:
- `git rm app/assets/images/apple-touch-icon.png`
- `git rm app/assets/images/favicon.ico`

`favicon.svg` stays in `app/assets/images/` as the single source of truth.

## Layout Changes

Updated `<head>` in `application.html.erb`:

```erb
<link rel="icon" type="image/svg+xml" href="<%= asset_path('favicon.svg') %>">
<link rel="icon" type="image/png" sizes="32x32" href="/icons/favicon-32.png">
<link rel="apple-touch-icon" href="/icons/apple-touch-icon.png">
<link rel="manifest" href="/manifest.json">
<%= javascript_include_tag 'sw-register', defer: true %>
```

SVG favicon stays Propshaft-managed (fingerprinted). Generated PNGs use static `/icons/` paths — regenerated on each build, no fingerprinting needed.

## Offline Fallback Page

`public/offline.html` — self-contained with inline styles matching the app's gingham aesthetic. Uses the desert island emoji as its character piece. Static files from `public/` bypass the CSP middleware, so inline styles work without CSP changes.

## Files Changed

| What | Where |
|---|---|
| Service worker | `public/service-worker.js` |
| SW registration | `app/assets/javascripts/sw-register.js` |
| Manifest update | `public/manifest.json` |
| Icon rake task | `lib/tasks/pwa.rake` |
| Offline page | `public/offline.html` |
| Layout update | `app/views/layouts/application.html.erb` |
| Dockerfile | `Dockerfile` |
| Dev setup | `bin/setup` |
| Remove binaries | `app/assets/images/apple-touch-icon.png`, `favicon.ico` |

## What Stays the Same

- Groceries JS — already offline-capable (localStorage state + pending action queue)
- Wake lock — already active on groceries and recipe pages in all modes
- ActionCable — unaffected, service worker skips WebSocket
- CSP policy — no changes needed (SW registration is an external script, offline page bypasses CSP)
