# Catalog/Seed Separation Design

## Problem

The Docker entrypoint runs `db:seed` on every container start. Seeds load both
sample content (kitchen, user, recipes) and the ingredient catalog (reference
data the app depends on). This coupling caused a production crash-loop when a
new nutrient validation rejected legitimate USDA sodium values during seeding.

The root issues:

1. **Reference data and sample data share a loading path.** The ingredient
   catalog is infrastructure; sample recipes are dev content. They have
   different lifecycles and different deployment needs.
2. **`save!` runs validations on every boot**, even when records are unchanged.
   A new validation that conflicts with existing data breaks the entire
   startup sequence.
3. **No CI coverage for catalog data validity.** The validation/data mismatch
   was only caught in production.

## Design

### `catalog:sync` rake task

A new `lib/tasks/catalog.rake` defines a `catalog:sync` task that:

- Reads `db/seeds/resources/ingredient-catalog.yaml`
- For each entry, calls `find_or_initialize_by(kitchen_id: nil, ingredient_name: name)`
- Assigns attributes from the YAML entry
- Calls `save!` only when the record is new or has changed
  (`new_record? || changed?`), skipping unchanged records entirely
- Prints a summary: created count, updated count, unchanged count

The dirty-check prevents re-validation of unchanged records, which is what
caused the crash-loop. It also makes the task faster on routine deploys where
most entries haven't changed.

### Docker entrypoint

`bin/docker-entrypoint` runs three distinct steps:

```
db:prepare      — schema migrations
catalog:sync    — reference data sync
db:seed         — sample content (kitchen, user, recipes)
```

All three run in production for now (dogfooding phase). The catalog sync is
independent of seeds, so when sample content is no longer needed in production,
removing `db:seed` from the entrypoint has no effect on the catalog.

### Seeds cleanup

`db/seeds.rb` changes:

- Remove the ingredient catalog loading block entirely (moved to `catalog:sync`)
- Rename sample kitchen from "Biagini Family" to "Our Kitchen" (slug:
  `our-kitchen`)
- Rename sample user from "Chris" / `chris@example.com` to "Home Cook" /
  `user@example.com`
- Recipe imports, Quick Bites, and cross-reference resolution remain unchanged

### CI validation

A new test file (`test/lib/catalog_sync_test.rb`) loads the YAML, builds
`IngredientCatalog` objects for each entry, and asserts they all pass model
validations. This is a dry-run of `catalog:sync` that catches validation/data
mismatches in CI before they reach production.

The existing CI workflow runs `bundle exec rake` (lint + all tests), so no
workflow changes are needed.

## Future direction

These changes are not part of this work but inform the design:

- **Seeds gated by environment.** When the dogfooding phase ends, the
  entrypoint drops `db:seed`. Seeds become dev-only (`rake db:setup` locally).
  New users create kitchens through the normal auth flow.
- **Sample content becomes obviously sample.** Generic tutorial-style recipes
  replace personal recipes in `db/seeds/`. Real recipes live in production as
  user data.
- **`catalog:sync` is permanent.** It's the long-term mechanism for shipping
  reference data with the app. It runs on every deploy regardless of
  environment.
