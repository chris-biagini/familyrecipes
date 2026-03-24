# Write Service Extraction: Aisles & Categories

## Problem

Two controllers — `GroceriesController` and `CategoriesController` — do transactional orchestration (cascade renames, cascade deletes, broadcast) inline, violating the convention established by `RecipeWriteService` and `CatalogWriteService`. Worse, aisle mutations are split across two code paths: `GroceriesController` handles reorder/rename/delete, while `CatalogWriteService` independently appends new aisles via `sync_aisle_to_kitchen`. Two writers, no single owner.

## Design

### AisleWriteService

Single owner of all aisle mutations on `Kitchen#aisle_order` and the cascading effects on `IngredientCatalog` rows.

**Public API:**

- `AisleWriteService.update_order(kitchen:, aisle_order:, renames:, deletes:)` — validates via `OrderedListEditor` logic, cascades renames/deletes to catalog rows, normalizes and saves `kitchen.aisle_order`, returns a Result. Called by `GroceriesController#update_aisle_order`.
- `AisleWriteService.sync_new_aisle(kitchen:, aisle:)` — appends an aisle to `kitchen.aisle_order` if not already present. Called by `CatalogWriteService` after saving a catalog entry with a new aisle.

**Result type:** `Data.define(:success, :errors)` — controller checks `result.success` and renders accordingly.

**What moves out of `GroceriesController`:**
- `cascade_aisle_renames` (lines 67-73)
- `cascade_aisle_deletes` (lines 76-83)
- The transaction block in `update_aisle_order` (lines 51-55)
- Validation call moves into service (currently in controller action)

**What moves out of `CatalogWriteService`:**
- `sync_aisle_to_kitchen` (lines 70-76)
- `sync_all_aisles` (lines 105-119)

`CatalogWriteService` will call `AisleWriteService.sync_new_aisle` for single-entry writes, and a new `AisleWriteService.sync_new_aisles` (plural) for bulk import.

**What stays in `Kitchen`:**
- `parsed_aisle_order` and `all_aisles` — these are read-path helpers, not mutations
- `normalize_aisle_order!` — called by the service during writes

### CategoryWriteService

Single owner of category ordering, renaming, and deletion cascades.

**Public API:**

- `CategoryWriteService.update_order(kitchen:, names:, renames:, deletes:)` — validates, cascades renames (slug-based lookup + update), cascades deletes (reassign recipes to Miscellaneous, destroy), updates positions. Returns a Result.

**Result type:** `Data.define(:success, :errors)` — same shape as AisleWriteService.

**What moves out of `CategoriesController`:**
- `cascade_category_renames` (lines 42-49)
- `cascade_category_deletes` (lines 52-65)
- `find_or_create_miscellaneous` (lines 67-73)
- `update_category_positions` (lines 75-78)
- The transaction block in `update_order` (lines 30-34)
- Validation call moves into service

### What does NOT change

- `OrderedListEditor` concern stays — it provides the validation helper. Services call it (include the module or extract the validation to a plain method).
- `MealPlanActions` concern stays — unrelated to this refactor.
- `broadcast_update` stays in controllers — services return results, controllers decide when to broadcast. This keeps services side-effect-free for testing and avoids the question of whether a service should broadcast on validation failure.
- No shared cascade abstraction — aisle cascades (case-insensitive `update_all`) and category cascades (slug-based find + update + destroy) are semantically different enough that a generic framework would be speculative.

### Controller shape after extraction

```ruby
# GroceriesController#update_aisle_order
def update_aisle_order
  result = AisleWriteService.update_order(
    kitchen: current_kitchen,
    aisle_order: params[:aisle_order].to_s,
    renames: params[:renames],
    deletes: params[:deletes]
  )
  return render(json: { errors: result.errors }, status: :unprocessable_content) unless result.success

  current_kitchen.broadcast_update
  render json: { status: 'ok' }
end

# CategoriesController#update_order
def update_order
  result = CategoryWriteService.update_order(
    kitchen: current_kitchen,
    names: Array(params[:category_order]),
    renames: params[:renames],
    deletes: params[:deletes]
  )
  return render(json: { errors: result.errors }, status: :unprocessable_content) unless result.success

  current_kitchen.broadcast_update
  render json: { status: 'ok' }
end
```

### Testing

- Service unit tests for each public method — no controller overhead, focused assertions on DB state
- Existing controller integration tests stay and verify the full request cycle
- `CatalogWriteService` tests verify that aisle sync delegates to `AisleWriteService`

## Scope boundaries

- No changes to models, concerns, or other services beyond the moves described
- No shared cascade abstraction
- No changes to broadcast timing or MealPlan pruning
- No changes to the read path (Kitchen#parsed_aisle_order, Kitchen#all_aisles, etc.)
