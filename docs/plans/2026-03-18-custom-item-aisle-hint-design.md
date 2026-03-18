# Custom Item Aisle Hint Design

**Date:** 2026-03-18
**Issue:** GH #242

## Problem

Custom grocery items always route to "Miscellaneous" unless the item name
happens to match an `IngredientCatalog` entry. Non-food items (shaving cream,
trash bags) and niche ingredients will never match. Users need a way to
explicitly route custom items to a specific aisle.

## Solution

Add an `@ Aisle` hint syntax to custom item strings:

```
"Shaving cream @ Personal care"  → name: "Shaving cream", aisle: "Personal care"
"Foo @ Bar @ Baz"                → name: "Foo @ Bar",     aisle: "Baz"
"Just milk"                      → name: "Just milk",     aisle: (catalog lookup)
"foo@bar"                        → name: "foo@bar",       aisle: (catalog lookup)
```

Parse on last ` @ ` (space-at-space) via `String#rpartition`. No-space `@` is
not treated as a separator.

## Storage

No change. Custom items remain plain strings in `MealPlan#state['custom_items']`.
The full string including hint is stored as-is. Backwards compatible — existing
items without `@` continue to work identically.

## Parsing

A private `parse_custom_item(text)` method on `ShoppingListBuilder` returns
`[name, aisle_hint_or_nil]`. The same logic is exposed as a
`GroceriesHelper#parse_custom_item` view helper for the partial.

## ShoppingListBuilder Changes

### `add_custom_items`

1. Parse each custom item → `[name, aisle_hint]`
2. Use `name` (not raw string) for `canonical_name` lookup and dedup
3. If `aisle_hint` present: case-insensitive match against existing aisle keys
   in the organized hash and `Kitchen#parsed_aisle_order`; use matched casing
   if found, otherwise use hint as-is
4. If no hint: fall back to `aisle_for(name)` as today

### `visible_names`

Update to parse custom items before calling `canonical_name` — use the
extracted name, not the raw string including hint.

### Aisle matching helper

`resolve_aisle_hint(hint, organized)` — case-insensitive match against:
1. Keys already in the `organized` hash (aisles with items)
2. `@kitchen.parsed_aisle_order` (all configured aisles)
3. If no match, use hint as-is (creates a new aisle section)

## View Changes

### `_custom_items.html.erb`

Parse each item via `parse_custom_item`. Display:
- Item name as primary text (same `<span>` as today)
- If aisle hint present: append a second `<span>` with class
  `custom-item-aisle` showing the aisle name

The remove button's `data-item` attribute keeps the full raw string so
removal still works via exact string match.

### `groceries.css`

Add `.custom-item-aisle` style: smaller font size, lighter color (use a new
CSS variable `--custom-item-aisle` for light/dark theme support), with a
separator character or left margin to visually distinguish from the item name.

## Dedup Behavior

Unchanged. If a custom item's parsed name matches a recipe ingredient already
on the list, the custom item is filtered out of the shopping list (but remains
in `custom_items` state so it reappears if the recipe is deselected).

## Validation

No change. The existing 100-character max on the full string (including hint)
applies. No validation on aisle name content.

## Files Changed

| File | Change |
|------|--------|
| `app/services/shopping_list_builder.rb` | `parse_custom_item`, update `add_custom_items` and `visible_names` |
| `app/helpers/groceries_helper.rb` | `parse_custom_item` helper |
| `app/views/groceries/_custom_items.html.erb` | Display parsed name + aisle hint |
| `app/assets/stylesheets/groceries.css` | `.custom-item-aisle` style |
| `app/assets/stylesheets/style.css` | `--custom-item-aisle` CSS variable (light + dark) |
| `test/services/shopping_list_builder_test.rb` | Tests for hint parsing, aisle routing, dedup, case matching |
| `test/helpers/groceries_helper_test.rb` | Tests for `parse_custom_item` helper |

## Out of Scope

- Aisle name autocomplete (v2)
- Structured storage for custom items (v2)
- Custom item quantities
