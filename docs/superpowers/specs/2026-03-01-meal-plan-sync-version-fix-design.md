# MealPlanSync Version Fix

**Issue:** [#138](https://github.com/chris-biagini/familyrecipes/issues/138)
**Date:** 2026-03-01

## Problem

When the database is recreated (container rebuild, fresh seed), `MealPlanSync` silently ignores all server state. The browser's localStorage cache holds a stale `lock_version` higher than the new database's version, causing the version comparison in `fetchState()` to reject every server response.

Three coupled failures:

1. **`fetchState()` version gate** — `data.version >= this.version` fails when the server version (e.g., 2) is lower than the cached version (e.g., 200). All server state is silently dropped.
2. **ActionCable version check** — `data.version > this.version` also fails, so version broadcasts never trigger a fetch.
3. **`awaitingOwnAction` stuck true** — only reset inside the version-gate `if` block. Once the gate fails, the flag is permanently stuck after the first user action.

## Design

### Remove version gating from `fetchState()`

The `AbortController` already aborts previous in-flight fetches (line 97), making out-of-order responses impossible. The version gate is redundant and harmful. Remove the conditional — always apply server state, always reset `awaitingOwnAction` and `initialFetch`.

Keep the `isRemoteUpdate` computation (for the notification toast) but compute it before updating `this.version`.

Also reset `awaitingOwnAction` in the `.catch()` handler, which currently swallows errors silently and leaves the flag stuck if the fetch itself fails.

### Fix ActionCable version comparison

Change `data.version > this.version` to `data.version !== this.version`. This triggers a fetch on both version increases (normal) and decreases (DB reset).

### Fix `MealPlan.for_kitchen` race condition

Separate bug found during investigation: `MealPlan.for_kitchen` uses `find_or_create_by!` which isn't atomic. When the HTTP `state` request and the MealPlanChannel subscription both call it concurrently on first visit, one fails with `ActiveRecord::RecordInvalid — Kitchen has already been taken`. Fix by rescuing `RecordInvalid`/`RecordNotUnique` and retrying with a `find_by!`.

## Files Changed

- `app/javascript/utilities/meal_plan_sync.js` — remove version gate, fix ActionCable check, fix catch handler
- `app/models/meal_plan.rb` — make `for_kitchen` race-safe
