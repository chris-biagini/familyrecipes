# DRY ActionCable Sync Extraction

**Date:** 2026-02-28
**Issue:** #116

## Problem

`menu_controller.js` and `grocery_sync_controller.js` share ~100 lines of nearly identical ActionCable synchronization logic: WebSocket subscription setup, version-based state polling, heartbeat management, localStorage caching, CSRF-aware action dispatch, and Turbo Stream render interception.

## Decision

Extract a standalone `MealPlanSync` utility class in `app/javascript/utilities/meal_plan_sync.js`. Controllers create an instance in `connect()` and pass a config object with callbacks. The utility owns the transport layer; controllers own only UI logic.

Rejected alternatives:
- **Stimulus mixin** (`Object.assign` on prototype) — namespace pollution, no formal Stimulus pattern, harder to reason about method origins.
- **Base controller class** — Stimulus registers controllers by file, awkward for a base that's never mounted. Combines transport + UI into one inheritance chain.

## `MealPlanSync` API

```js
new MealPlanSync({
  slug: "my-kitchen",
  stateUrl: "/menu/state",
  cachePrefix: "menu-state",
  onStateUpdate(data) { /* apply state to DOM */ },
  remoteUpdateMessage: "Menu updated."
})
```

### Constructor behavior

- Initializes version, state, awaitingOwnAction, initialFetch flags
- Loads cached state from localStorage, calls `onStateUpdate` if cache exists
- Loads pending action queue from localStorage
- Fetches fresh state from server
- Opens ActionCable subscription to `MealPlanChannel`
- Starts 30-second heartbeat poll
- Flushes any pending offline actions
- Registers `turbo:before-stream-render` listener

### Public methods

- `sendAction(url, params, method = "PATCH")` — optimistic action dispatch with offline queuing. Sets `awaitingOwnAction` flag, makes fetch request, re-polls state on success. On network failure, queues the action in localStorage for retry.
- `disconnect()` — full teardown: abort in-flight fetch, clear heartbeat interval, unsubscribe from ActionCable, disconnect consumer, remove Turbo Stream listener.

### Internal behavior

- **Version-based polling:** Only applies state when server version >= local version. Detects remote updates (version bumped by another client) and shows toast notification.
- **`content_changed` handling:** Force-fetches state and always shows notification (unified on grocery's current behavior — content changes always warrant user notification).
- **Turbo Stream interception:** Re-fires `onStateUpdate` after Turbo Stream DOM replacements to restore checkbox/selection state.
- **Offline queue:** Failed `sendAction` calls (network errors only, not HTTP errors) are queued in localStorage keyed by `${cachePrefix}-pending-${slug}`. Queue flushes on ActionCable reconnect and on initial construction.

## Controller changes

### `menu_controller.js` (~352 → ~200 lines)

- `connect()` creates `MealPlanSync` with `onStateUpdate` calling `syncCheckboxes` + `syncAvailability`
- `sendAction` calls become `this.sync.sendAction(url, params, method)`
- `clear()` passes `"DELETE"` as method: `this.sync.sendAction(this.urls.clear, {}, "DELETE")`
- Gains offline queue support (new)
- All transport methods removed: `subscribe`, `fetchState`, `startHeartbeat`, `saveCache`, `loadCache`, `handleStreamRender`

### `grocery_sync_controller.js` (~245 → ~40 lines)

- `connect()` creates `MealPlanSync` with `onStateUpdate` delegating to `uiController.applyState`
- All transport methods removed
- `fetchStateWithNotification` removed (unified into utility's `content_changed` handling)

### `grocery_ui_controller.js`

Unchanged.

### `importmap.rb`

Unchanged — `pin_all_from 'app/javascript/utilities'` already covers the new file.

## Testing

Pure JS refactoring — Ruby backend untouched. Existing controller and integration tests cover server-side behavior. Manual smoke testing: menu selections sync across tabs, grocery check-offs sync, offline queue flushes on reconnect.
