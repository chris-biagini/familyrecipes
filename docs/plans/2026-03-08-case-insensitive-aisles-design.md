# Case-Insensitive Aisle Handling (#195)

## Problem

Aisles are free-text strings compared case-sensitively everywhere. Renaming "Produce" leaves behind "produce" entries; deleting does the same; duplicates like "Produce" and "produce" can coexist in the aisle order.

## Design

Normalize comparisons via downcased form, preserve user's display casing.

### Changes

1. **`GroceriesController#cascade_aisle_renames`** — `where("LOWER(aisle) = LOWER(?)", old_name)`
2. **`GroceriesController#cascade_aisle_deletes`** — iterate deletes with `where("LOWER(aisle) = LOWER(?)", name)`
3. **`OrderedListEditor#validate_ordered_list`** — detect case-insensitive duplicates, return error
4. **`Kitchen#normalize_aisle_order!`** — `.uniq { |a| a.downcase }` to collapse case variants (keeps first occurrence's casing)
5. **`CatalogWriteService#sync_aisle_to_kitchen`** — `.any? { |a| a.casecmp?(aisle) }` instead of `.include?`
6. **`Kitchen#all_aisles`** — case-insensitive set subtraction when merging catalog aisles with saved order

### Tests

- Aisle rename updates all case variants
- Aisle delete clears all case variants
- Aisle order rejects case-insensitive duplicates
- normalize_aisle_order! collapses case variants
- sync_aisle_to_kitchen skips case-duplicate aisles
- all_aisles deduplicates by downcased form
