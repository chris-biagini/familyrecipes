# Revert Grocery Pluralization Design

Fixes GitHub issue #62 (bad pluralization on groceries page).

## Problem

The grocery list displays "Kombus", "Jasmine rices", "Salad greenses", "Cinnamons", "Smoked paprikas", and similar malformed plurals. These bugs are self-inflicted.

Before the unified pluralization work (commit 92ee1c8), grocery-info.yaml stored items in their **natural display form**: "Carrots", "Salad greens", "Kombu". The template showed the YAML value directly. Everything displayed correctly.

The Inflector work migrated YAML keys to singular canonical form ("Carrots" → "Carrot") and introduced `name_for_grocery()` to re-pluralize for display. This round-trip is the source of every grocery bug — the code attempts to recover what the YAML already had, and fails for mass nouns, inherently-plural items, and compound names.

## Decision: revert the YAML migration, keep the Inflector wins

Instead of making `name_for_grocery()` smarter (expanded uncountable set, head-noun matching, already-plural heuristics), remove the round-trip entirely. Let the YAML carry the display form. Delete `name_for_grocery()`.

### What was genuinely valuable in the Inflector work

- **Consolidated three scattered pluralization implementations** into one module (Ingredient, NutritionEntryHelpers, build_alias_map all had overlapping regex). Keep.
- **`unit_display(unit, count)`**: "4 cloves" → "1 clove" when scaling. Real user-facing fix. Keep.
- **Yield line inflection**: "Makes 12 cookies" → "Makes 1 cookie" via data attributes. Keep.
- **`build_alias_map` with Inflector**: generates aliases so recipes can use "Carrot" or "Carrots" and both match. Keep (with reversed alias direction).

### What introduced the bugs

- **YAML migration to singular keys**: forced `name_for_grocery()` into existence.
- **`name_for_grocery()`**: tries to auto-pluralize from singular keys, fails for mass nouns ("Kombus"), compounds ("Jasmine rices"), and already-plural items ("Salad greenses").

## Changes

### 1. Revert grocery-info.yaml to natural display forms

Countable items return to their plural grocery-list form:
- "Apple" → "Apples", "Carrot" → "Carrots", "Egg" → "Eggs"
- "Tomato (fresh)" → "Tomatoes (fresh)", "Bean (any dry)" → "Beans (any dry)"

Mass nouns and inherently-plural items are already in their natural form and don't change:
- "Kombu", "Rice", "Flour (all-purpose)" stay as-is
- "Salad greens", "Sesame seeds" stay as-is

### 2. Revert nutrition-data.yaml keys to match

Both files share one canonical form (the natural display form). Only ~6-8 countable keys change: "Carrot" → "Carrots", "Egg" → "Eggs", "Onion" → "Onions", "Red bell pepper" → "Red bell peppers", "Lemon" → "Lemons", "Lime" → "Limes".

Mass noun keys are already correct: "Rice", "Flour (all-purpose)", "Cinnamon".

This eliminates the need for a singularization bridge between the two files.

### 3. Grocery template uses YAML value directly

Drop `display_name: Inflector.name_for_grocery(item[:name])` from SiteGenerator. The template renders `ingredient[:name]` directly, which is already in display form.

### 4. build_alias_map generates singular aliases

Reverse the alias direction. Currently generates plural aliases from singular canonical:
```ruby
# Current: canonical "Carrot", alias "carrots" → "Carrot"
plural = Inflector.name_for_grocery(canonical)
alias_map[plural.downcase] = canonical
```

New: generate singular aliases from display canonical:
```ruby
# New: canonical "Carrots", alias "carrot" → "Carrots"
singular = Inflector.singular(canonical)
alias_map[singular.downcase] = canonical
```

This ensures recipes can write "Carrot, 3" or "Carrots, 3" and both resolve to the canonical "Carrots".

### 5. Remove name_for_grocery() and name_for_count()

These methods exist solely to support the singular-canonical → display round-trip. With the YAML carrying display forms, they have no callers. Remove from Inflector and tests.

### 6. Fix "go" unit (unrelated but small)

Add `go → go` as an irregular so the Japanese gō unit doesn't become "goes". One-line change.

## What stays unchanged

- Inflector module structure and core API (`singular`, `plural`, `uncountable?`, `unit_display`, `normalize_unit`)
- nutrition-data.yaml structure (only key renames, no schema changes)
- All JavaScript (recipe-state-manager.js, groceries.js)
- Recipe template (data attributes for unit inflection stay)
- Yield line inflection (ScalableNumberPreprocessor, VulgarFractions)
- UNCOUNTABLE set (no expansion needed — we're not auto-pluralizing anymore)

## File changes

### Data
- `resources/grocery-info.yaml` — revert countable keys to display form
- `resources/nutrition-data.yaml` — revert ~8 countable keys to match

### Ruby
- `lib/familyrecipes/inflector.rb` — remove `name_for_grocery`, `name_for_count`, related private helpers; add `go` irregular
- `lib/familyrecipes.rb` — reverse alias direction in `build_alias_map`
- `lib/familyrecipes/site_generator.rb` — drop `name_for_grocery` call in grocery page generation; remove `collect_unit_plurals` if it used `name_for_grocery`

### Templates
- `templates/web/groceries-template.html.erb` — use `name` directly instead of `display_name` (if they differ)

### Tests
- `test/inflector_test.rb` — remove `name_for_grocery` and `name_for_count` tests
- Other test files — update any assertions that expect singular canonical keys

## Future considerations

This design defers ingredient classification (countable/uncountable/inherently-plural) to Phase 2 (#64) and Phase 3 (#63). When the unified ingredient-data.yaml is built, each ingredient can carry a `countability` field. The Inflector can consult it for contexts where programmatic inflection is needed (e.g., scaling "2 Carrots" to "1 Carrot"). For now, the YAML carries the display form and no inflection intelligence is required for grocery display.
