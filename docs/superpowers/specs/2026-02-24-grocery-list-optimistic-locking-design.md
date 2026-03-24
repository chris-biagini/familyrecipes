# GroceryList Optimistic Locking

**Issue:** #86 — concurrent grocery list mutations lose updates
**Date:** 2026-02-24

## Problem

Every grocery list mutation follows a read-modify-write pattern on the JSON `state`
column without any locking. Two concurrent requests (e.g., two household members
selecting recipes simultaneously) both read the same state, modify their local copy,
and the second `save!` overwrites the first's changes.

The `version` counter detects staleness client-side (via ActionCable) but doesn't
prevent server-side data loss.

## Approach: Optimistic Locking with Retry

Rails built-in optimistic locking via `lock_version` column. On save, Rails checks
that `lock_version` hasn't changed since the record was loaded; if it has, it raises
`ActiveRecord::StaleObjectError`. A retry loop reloads and re-applies the mutation.

### Why this approach

- **No contention on the happy path.** One SELECT + one UPDATE, same as today.
  Conflicts are rare for a household grocery app.
- **Rails-idiomatic.** No custom SQL, no raw locks, well-documented behavior.
- **Safe retries.** Each mutation is a small, idempotent toggle (add/remove an item
  from an array). Re-applying after reload always produces the correct result.

### Alternatives considered

- **Pessimistic locking (`with_lock`):** Row lock on every mutation even without
  contention. Overkill for a household app with SQLite's single-writer model.
- **Atomic SQL (`json_insert`/`json_remove`):** True single-statement atomicity but
  ties code to SQLite JSON functions, produces raw SQL strings, and breaks the AR
  model pattern.

## Design

### 1. Migration

Rename `version` to `lock_version`:

```ruby
rename_column :grocery_lists, :version, :lock_version
```

Rails automatically recognizes `lock_version` for optimistic locking. The column
keeps its integer type and default of 0.

### 2. Model changes (GroceryList)

- Remove manual `increment(:version)` from `bump_and_save!` and `clear!`. Rails
  auto-increments `lock_version` on every `save`.
- `bump_and_save!` simplifies to `save!`.
- Add `with_optimistic_retry(max_attempts: 3)` that catches `StaleObjectError`,
  reloads the record, and yields again. Raises after exhausting attempts.

### 3. Controller changes (GroceriesController)

- `apply_and_respond` wraps `apply_action` in the retry mechanism.
- `clear` gets the same treatment.
- On retry exhaustion, return 409 Conflict.
- Broadcast `list.lock_version` (aliased as `version` in JSON for client
  compatibility).

### 4. Client/channel changes

- `GroceryListChannel.broadcast_version` reads `lock_version` from the model.
- JSON response keeps the key name `version` — clients treat it as an opaque
  incrementing integer for staleness detection. No JS changes needed.

### 5. Tests

- Update existing tests referencing `list.version` to use `list.lock_version`.
- Simulate stale object: load two instances, mutate both, verify second retries
  and succeeds.
- Verify retry exhaustion returns 409 Conflict.
