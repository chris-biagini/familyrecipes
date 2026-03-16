# QuickBites `## Section` Header Syntax

**GitHub issue:** #249
**Date:** 2026-03-16

## Summary

Switch QuickBites section headers from colon-terminated (`Snacks:`) to Markdown
heading syntax (`## Snacks`). Clean break — no backwards compatibility with the
old format.

## Current Format

```
Snacks:
- Apples and Honey: Apples, Honey
- Crackers and Cheese: Ritz crackers, Cheddar

Breakfast:
- Cereal and Milk: Rolled oats, Milk
```

## New Format

```
## Snacks
- Apples and Honey: Apples, Honey
- Crackers and Cheese: Ritz crackers, Cheddar

## Breakfast
- Cereal and Milk: Rolled oats, Milk
```

## Changes

### Parser (`lib/familyrecipes.rb`)

Category header regex changes from `/^([^-].+):\s*$/` to `/^##\s+(.+)$/`.
Capture group extracts the text after `## ` (trimmed). No other parser logic
changes — item lines, blank line handling, and warning generation stay the same.

### Serializer (`lib/familyrecipes/quick_bites_serializer.rb`)

`serialize_category` emits `"## #{category[:name]}"` instead of
`"#{category[:name]}:"`.

### CodeMirror classifier (`app/javascript/codemirror/quickbites_classifier.js`)

`CATEGORY_RE` changes from `/^[^-].+:\s*$/` to `/^##\s+.+$/`.

### Seed data (`db/seeds/recipes/Quick Bites.md`)

Rewrite all section headers: `Snacks:` → `## Snacks`, etc.

### Header comment (`lib/familyrecipes/quick_bite.rb`)

Update the architectural header comment that references the old `"Category:\n"`
format to show `"## Category\n"` instead.

### Data migration

Sequential migration using raw SQL to regex-replace existing
`Kitchen#quick_bites_content`. Converts `^([^-\n].+):\s*$` lines to `## \1`.
No application model references per migration conventions. The regex is safe
because the parser already validates content on write — any stored content
conforms to the expected structure.

## What Doesn't Change

- Item format (`- Name: ing1, ing2`)
- `QuickBite` domain model (code, not comment)
- IR hash structure (`{ categories: [{ name:, items: [...] }] }`)
- `QuickBitesWriteService`
- Controller endpoints
- Graphical editor (works with IR, never sees plaintext syntax)

## Edge Cases

**Old-format exports.** ZIP exports created before the migration contain
old-format content. Importing them post-migration will produce parser warnings
and items without proper categories. Acceptable at this stage of development.

## Test Updates

All files containing literal `Snacks:` or similar colon-header strings need
updating. Known files (grep for old-format headers to catch any missed):

- `test/familyrecipes_test.rb`
- `test/quick_bite_test.rb`
- `test/quick_bites_serializer_test.rb`
- `test/javascript/quickbites_classifier_test.mjs`
- `test/controllers/menu_controller_test.rb`
- `test/services/quick_bites_write_service_test.rb`
- `test/services/shopping_list_builder_test.rb`
- `test/services/recipe_availability_calculator_test.rb`
- `test/services/ingredient_row_builder_test.rb`
- `test/models/kitchen_test.rb`
- `test/models/meal_plan_test.rb`
- `test/integration/end_to_end_test.rb`
- `test/controllers/auth_test.rb`
