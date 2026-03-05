# QuickBites Editor Simplification

## Problem

The QuickBites editor exposes raw Markdown with a `# Quick Bites` header, description line, and `## Category` syntax. The header and description are boilerplate users should never edit. The `##` category syntax is heavier than necessary for what is essentially a categorized grocery list.

## Design

### New Format

Strip the `# Quick Bites` header and description. Replace `## Category` with `Category:`.

Before:
```
# Quick Bites

Pantry staples and "fast food" that comes together with minimal fuss.

## Snacks
  - Goldfish
  - Fried eggs: Eggs, Olive oil, Bread
```

After:
```
Snacks:
- Goldfish
- Fried eggs: Eggs, Olive oil, Bread
```

**Line types:**
- **Category:** bare text ending with colon at start of line (no `- ` prefix). E.g., `Snacks:`, `Kids' Lunches:`
- **Item:** line starting with `- ` (optional leading whitespace). Simple: `- Goldfish`. Composed: `- Fried eggs: Eggs, Olive oil, Bread`
- **Blank lines:** ignored
- **Anything else:** unrecognized — triggers a warning

### Parser Changes

Update `FamilyRecipes.parse_quick_bites_content` to:
- Match `SomeText:` as category lines (instead of `## SomeText`)
- Distinguish categories from items by the `- ` prefix
- Track unrecognized lines (non-blank, not a category, not an item)
- Return both parsed QuickBites and warnings

The return type changes from a plain array to a struct or two-element return:
```ruby
Result = Data.define(:quick_bites, :warnings)
```

Warnings are simple strings like `"Line 7 not recognized"`.

### Save Endpoint

`MenuController#update_quick_bites` calls the parser on submitted content. If warnings exist, they're included in the JSON response. The content is still saved (warnings are non-blocking).

Response with warnings:
```json
{ "status": "ok", "warnings": ["Line 7 not recognized", "Line 12 not recognized"] }
```

### Editor Behavior on Warnings

The editor dialog currently auto-closes on successful save (`editor_on_success: 'close'`). When warnings are present:

- Dialog stays open
- Warnings display in the existing `.editor-errors` area (styled as warnings, not errors)
- If more than 3 warnings, summarize: "5 lines were not recognized (lines 3, 7, 9, 12, 14)"
- Save succeeded — user can fix and re-save, or close manually

This requires the editor controller to inspect the response body and distinguish "clean save" from "save with warnings."

### Seed Data

Update `db/seeds/recipes/Quick Bites.md` to the new format. Drop the `#` header and description.

### Migration

No database migration needed. The stored content is a text column. Update the seed file and any test fixtures to use the new format. Existing kitchen data (if any) is overwritten by re-seeding or manual editing.

## Scope

- Parser: new format, warnings
- Editor controller JS: handle warnings in save response, stay open when warnings present
- Menu controller: pass warnings through
- Seed file: new format
- Tests: parser, controller, warning behavior
