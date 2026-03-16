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

`serialize` emits `"## #{category[:name]}"` instead of `"#{category[:name]}:"`.

### CodeMirror classifier (`app/javascript/codemirror/quickbites_classifier.js`)

`CATEGORY_RE` changes from `/^[^-].+:\s*$/` to `/^##\s+.+$/`.

### Seed data (`db/seeds/recipes/Quick Bites.md`)

Rewrite all section headers: `Snacks:` → `## Snacks`, etc.

### Data migration

Sequential migration using raw SQL to regex-replace existing
`Kitchen#quick_bites_content`. Converts `^([^-\n].+):\s*$` lines to `## \1`.
No application model references per migration conventions.

## What Doesn't Change

- Item format (`- Name: ing1, ing2`)
- `QuickBite` domain model
- IR hash structure (`{ categories: [{ name:, items: [...] }] }`)
- `QuickBitesWriteService`
- Controller endpoints
- Graphical editor (works with IR, never sees plaintext syntax)

## Test Updates

- Parser tests (`test/quick_bite_test.rb`): update literal content strings
- Serializer tests (`test/quick_bites_serializer_test.rb`): update expected output
- Classifier tests (`test/javascript/quickbites_classifier_test.mjs`): update
  category line examples
- Integration tests using literal QuickBites content strings
