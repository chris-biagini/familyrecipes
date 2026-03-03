# Turbo Morph Meta Tags — Design

## Problem

Turbo Drive page navigations (link clicks, back button) replace the entire
`<body>`, causing visual flashing (nav re-renders), scroll position loss, and
unnecessary ActionCable subscription teardown/reconnect cycles.

## Solution

Add two meta tags to the application layout enabling Turbo's page-refresh
morphing globally:

```html
<meta name="turbo-refresh-method" content="morph">
<meta name="turbo-refresh-scroll" content="preserve">
```

These tell Turbo to morph the body (via idiomorph) instead of replacing it on
every Drive navigation. Elements that didn't change stay untouched; scroll
position is preserved automatically.

## Scope

Application layout only. No changes to controllers, JS, or existing Turbo
Stream morph broadcasts. The meta tags affect Turbo Drive navigations; our
targeted stream morphs (`action: :update, attributes: { method: :morph }`) are
independent and coexist without conflict.

## Decisions

- **Global, not per-page.** All pages benefit from morph. If any page behaves
  badly, a per-page `<meta name="turbo-refresh-method" content="replace">`
  override can be added.
- **No `data-turbo-permanent` on nav.** The nav has dynamic state (current page
  highlighting). Page-level morph already handles it without flashing.
- **No change to broadcast mechanism.** Targeted stream morphs remain for
  ActionCable real-time updates. Page-refresh broadcasts (`broadcast_refreshes_to`)
  explored but deferred — extra HTTP round-trip is a worse fit for spotty
  mobile connections at the grocery store.

## Future exploration

See GitHub issue for additional morph-related improvements:
- Page-refresh broadcasts to simplify MealPlanBroadcaster
- Redirect-after-POST pattern for editor dialogs
- `data-turbo-permanent` for specific elements
