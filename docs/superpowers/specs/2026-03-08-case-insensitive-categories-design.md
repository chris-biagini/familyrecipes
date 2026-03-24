# Case-Insensitive Category Lookups (#194)

## Problem

`CategoriesController` uses `find_by!(name:)` and `where(name:)` for rename, delete, and position operations. These are case-sensitive. If the DB has "Bread" and the frontend sends "bread", the lookup fails.

## Design

Switch all category lookups in the controller from name-based to slug-based. Slugify the incoming name with `FamilyRecipes.slugify` and query by `slug`. This matches the pattern already used by `RecipeWriteService#find_or_create_category` and `CategoriesController#find_or_create_miscellaneous`.

### Changes

**`CategoriesController`** — three methods:
- `cascade_category_renames`: `find_by!(slug: FamilyRecipes.slugify(old_name))`
- `cascade_category_deletes`: `find_by(slug: FamilyRecipes.slugify(name))`
- `update_category_positions`: `where(slug: FamilyRecipes.slugify(name))`

**`Category` model** — add `case_sensitive: false` to the name uniqueness validation to prevent "Bread" and "bread" from coexisting.

**Tests** — verify:
- Rename with case mismatch works
- Delete with case mismatch works
- Position update with case mismatch works
- Case-only rename ("Bread" -> "bread") works correctly
- Model rejects case-duplicate names

### No frontend changes needed

`FamilyRecipes.slugify` normalizes case, so slug-based lookup is inherently case-insensitive. The frontend continues to send names; the controller slugifies them for lookup.
