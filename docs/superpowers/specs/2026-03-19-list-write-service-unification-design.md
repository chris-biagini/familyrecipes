# List Write Service Unification

## Problem

`AisleWriteService`, `CategoryWriteService`, and `TagWriteService` all manage
named lists with rename/delete changeset processing, but use inconsistent
patterns: different class vs instance method styles, different entry point
names, inconsistent validation, and duplicated skeleton logic. The frontend
already treats these as instances of one pattern
(`ordered_list_editor_controller`), but the backend tells three different
stories.

## Approach

Extract a `ListWriteService` base class using the template method pattern.
Each existing service becomes a thin subclass that overrides hooks for its
cascade behavior. `OrderedListValidation` concern is absorbed into the base
class and deleted.

## Base Class: `ListWriteService`

Lives at `app/services/list_write_service.rb`.

Owns:
- `Result = Data.define(:success, :errors)` — shared by all subclasses
- The skeleton: validate -> transaction(renames, deletes, ordering) -> finalize
- Shared validation helpers (`validate_order`, `validate_renames`) absorbed
  from `OrderedListValidation`
- Universal entry point: `self.update(kitchen:, renames: {}, deletes: [], **params)`
- Input normalization: coerces `renames` to a Hash and `deletes` to an Array
  before passing to hooks, so subclasses never need defensive type guards

Subclass hooks (all default to no-op):
- `validate_changeset(renames:, deletes:, **)` — return errors array
- `apply_renames(renames)` — within transaction
- `apply_deletes(deletes)` — within transaction
- `apply_ordering(**)` — within transaction; no-op for unordered lists (tags)

Subclass-specific keyword arguments (e.g. `aisle_order:` for aisles, `names:`
for categories) flow through `**params` in the base class and are destructured
in each subclass's hook signatures.

```ruby
class ListWriteService
  Result = Data.define(:success, :errors)

  def self.update(kitchen:, renames: {}, deletes: [], **params)
    new(kitchen:).update(renames:, deletes:, **params)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def update(renames: {}, deletes: [], **params)
    renames = normalize_renames(renames)
    deletes = Array(deletes)

    errors = validate_changeset(renames:, deletes:, **params)
    return Result.new(success: false, errors:) if errors.any?

    ActiveRecord::Base.transaction do
      apply_renames(renames)
      apply_deletes(deletes)
      apply_ordering(**params)
    end

    Kitchen.finalize_writes(kitchen)
    Result.new(success: true, errors: [])
  end

  private

  attr_reader :kitchen

  def validate_changeset(renames:, deletes:, **) = []
  def apply_renames(renames) = nil
  def apply_deletes(deletes) = nil
  def apply_ordering(**) = nil

  def normalize_renames(renames)
    case renames
    when Hash then renames
    when ActionController::Parameters then renames.to_unsafe_h
    else {}
    end
  end

  def validate_order(items, max_items:, max_name_length:, exact_dupes: true)
    # Moved from OrderedListValidation — unchanged logic
  end

  def validate_renames_length(renames, max_length)
    # Moved from OrderedListValidation — renamed to avoid confusion with
    # TagWriteService's validate_changeset which checks uniqueness, not length
  end
end
```

## Subclasses

### AisleWriteService

Cascades to `IngredientCatalog` rows. Aisles stored as newline-delimited
string on `Kitchen#aisle_order`. Keeps `sync_new_aisles` as a standalone class
method (called by `CatalogWriteService`, unrelated to the changeset flow).

- `validate_changeset(renames:, aisle_order:, **)`: sets
  `kitchen.aisle_order = aisle_order.to_s`, then validates the parsed result
  via `validate_order` + `validate_renames_length` using `Kitchen::MAX_AISLES`
  / `Kitchen::MAX_AISLE_NAME_LENGTH`. Passes `exact_dupes: false` because
  exact duplicates are silently normalized away — only mixed-case variants are
  flagged.
- `apply_renames`: `update_all` on IngredientCatalog (case-insensitive SQL)
- `apply_deletes`: `update_all(aisle: nil)` on IngredientCatalog
- `apply_ordering(aisle_order:, **)`: `kitchen.normalize_aisle_order!` +
  `kitchen.save!`

**Execution order change:** In the current code, `normalize_aisle_order!` runs
before the transaction; in the new design it runs inside `apply_ordering`,
which is inside the transaction. This is safe because normalization only
deduplicates the in-memory `aisle_order` string — it does not affect
IngredientCatalog rows, which are cascaded by aisle name via case-insensitive
SQL. Moving normalization inside the transaction is actually slightly better:
it rolls back with everything else if a later step fails.

### CategoryWriteService

Cascades to `Category` AR records. Deletes reassign orphaned recipes to
Miscellaneous.

- `validate_changeset(renames:, names:, **)`: calls `validate_order` +
  `validate_renames_length` with `MAX_ITEMS = 50` / `MAX_NAME_LENGTH = 50`
- `apply_renames`: `find_by!(slug:)` + `update!(name:, slug:)`
- `apply_deletes`: reassign recipes to Miscellaneous, then `destroy!`
- `apply_ordering(names:, **)`: update `position` column by index

### TagWriteService

No ordering. Custom uniqueness validation (checks for duplicate tag names, not
length — `StructureValidation#validated_tag_renames` in the controller already
enforces length at the boundary).

**Structural change:** TagWriteService currently uses all class methods with
`private_class_method`. This refactoring converts it to instance methods via
the base class constructor, matching its siblings. All `kitchen` arguments
become `@kitchen` references.

- `validate_changeset(renames:, **)`: checks for duplicate tag names (does not
  use shared `validate_order` or `validate_renames_length`)
- `apply_renames`: `find_by!(name:)` + `update!(name: downcase)`
- `apply_deletes`: `where(name:).destroy_all`
- `apply_ordering`: inherits no-op

## Controller Changes

Mechanical renames at call sites:

| Controller | Before | After |
|---|---|---|
| `GroceriesController#update_aisle_order` | `AisleWriteService.update_order(...)` | `AisleWriteService.update(...)` |
| `CategoriesController#update_order` | `CategoryWriteService.update_order(...)` | `CategoryWriteService.update(...)` |
| `TagsController#update_tags` | `TagWriteService.update(...)` | No change |

`CatalogWriteService` calls `AisleWriteService.sync_new_aisles(...)` — no
change needed.

Controller response formats (`{ status: 'ok' }` vs `{ success: true }`) are
left as-is — normalizing them is a separate concern from this refactoring.

## Deletions

- `app/services/concerns/ordered_list_validation.rb` — absorbed into base class
- Its test coverage merges into base class tests

## Testing

- **Base class:** skeleton tests using a minimal test subclass to verify:
  - Hooks are called within a transaction
  - Validation errors short-circuit (no transaction, no finalize)
  - `finalize_writes` is called after the transaction on success
  - Transaction rolls back if a hook raises
- **Subclass tests:** existing tests with mechanical `update_order(` ->
  `update(` rename for aisles and categories; tag tests already call `.update`
- Existing assertions should pass after the rename — cascade behavior is
  unchanged

## Documentation

- Add architectural header comment to `ListWriteService` (role, collaborators,
  constraints per project convention)
- Update subclass header comments to reference the base class
- Update CLAUDE.md Architecture section to note the base class and template
  method pattern
