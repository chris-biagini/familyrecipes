# Batch Writes: Coordinated Broadcast & Reconciliation

**GH #211** — Write services broadcast and reconcile independently with no
coordination. Importing 30 recipes fires 31 broadcasts and 30
reconciliations. Quick bites bypass the service layer. `select_all` and
`clear` skip reconciliation.

## Approach: `Kitchen.batch_writes` Block Scope (Option B)

A block-scoped mechanism using `Current` attributes defers broadcast and
reconciliation until the block exits. Services check `Kitchen.batching?`
and skip their own finalization when inside a batch. Standalone calls
(no block) work exactly as today.

## Components

### 1. `Kitchen.batch_writes` + `Current.batching_kitchen`

`Current` gains `attribute :batching_kitchen`. `Kitchen.batch_writes` is a
class method:

```ruby
def self.batch_writes(kitchen)
  Current.batching_kitchen = kitchen
  yield
ensure
  Current.batching_kitchen = nil
  plan = MealPlan.for_kitchen(kitchen)
  plan.with_optimistic_retry { plan.reconcile! }
  kitchen.broadcast_update
end
```

`Kitchen.batching?` returns `Current.batching_kitchen.present?`.

### 2. Service Finalization Guards

Each service wraps its reconcile + broadcast in a batching guard:

```ruby
unless Kitchen.batching?
  reconcile_meal_plan
  kitchen.broadcast_update
end
```

Affected services:
- **RecipeWriteService** — `create`, `update`, `destroy`. Extract a
  `finalize` helper wrapping both behind the guard.
- **CatalogWriteService** — `upsert`, `destroy`. `bulk_import` already
  skips both; no change.
- **MealPlanWriteService** — `apply_action`, `select_all`, `clear`,
  `reconcile`. Additionally, `select_all` and `clear` gain reconciliation
  (bug fix) behind the same guard.

### 3. `QuickBitesWriteService`

New service paralleling existing write services. Owns kitchen write +
parse validation + reconcile + broadcast:

```ruby
class QuickBitesWriteService
  Result = Data.define(:warnings)

  def self.update(kitchen:, content:)
    new(kitchen:).update(content:)
  end
end
```

`MenuController#update_quick_bites` becomes a thin adapter delegating to
the service. `ImportService#import_quick_bites` also switches to the
service.

### 4. `ImportService` Changes

Wraps all work in `Kitchen.batch_writes`:

```ruby
def import
  zip_file = files.find { ... }
  Kitchen.batch_writes(kitchen) do
    zip_file ? import_zip(zip_file) : files.each { ... }
  end
  build_result
end
```

The trailing `kitchen.broadcast_update` is removed — `batch_writes`
handles it. Net result for a 30-recipe ZIP: 1 reconcile + 1 broadcast
instead of 31 + 30.

## Testing

- **`Kitchen.batch_writes`** — reconcile + broadcast fire once on block
  exit; `batching?` true inside, false outside; ensure cleanup on raise.
- **Service tests** — existing tests unchanged (standalone still
  finalizes). Add tests verifying batching suppresses finalization.
- **`QuickBitesWriteService`** — persists content, returns warnings,
  reconciles, broadcasts. Plus batching guard.
- **`MealPlanWriteService`** — `select_all` and `clear` now reconcile.
- **`ImportService` integration** — multi-recipe ZIP produces exactly
  one broadcast + one reconcile.
- **`MenuController`** — `update_quick_bites` delegates to service.
