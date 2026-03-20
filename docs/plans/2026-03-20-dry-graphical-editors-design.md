# DRY Graphical Editors — Design

GitHub: #262 (JS portion only; CSS split deferred to separate PR)

## Problem

`recipe_graphical_controller.js` (471 lines) and
`quickbites_graphical_controller.js` (308 lines) share ~14 nearly identical
methods: accordion helpers, collection management (add/remove/move/rebuild),
and card DOM builders. The differences are property names (`steps` vs
`categories`, `ingredients` vs `items`) and recipe-specific features (front
matter, cross-references, tags).

## Decisions

- **Utility module, not base class.** A plain JS module of exported functions,
  matching the existing pattern (`dom_builders.js`, `editor_utils.js`). Avoids
  Stimulus inheritance complexity.
- **One level of abstraction.** Extract only truly identical patterns at each
  level. No generic recursive nesting abstraction — two concrete use cases
  don't justify it.
- **Serialization stays in each controller.** Recipe serializes steps with
  nested ingredients; QB has name-as-ingredient fallback and comma-separated
  parsing. Different enough to keep separate.
- **`ordered_list_editor_utils` consolidation deferred.** Tracked in #265.

## New file: `graphical_editor_utils.js`

Location: `app/javascript/utilities/graphical_editor_utils.js` (~100 lines)

Three groups of pure functions:

### Accordion helpers (~15 lines)

- `collapseAll(container)` — close all `<details>` elements
- `expandItem(container, index)` — open one, close others
- `toggleItem(container, index)` — toggle one detail element

### Collection management (~25 lines)

Pure array + DOM operations. Controller passes its array and rebuild callback.

- `removeItem(list, index, rebuildFn)` — splice + rebuild
- `moveItem(list, index, direction, rebuildFn, expandFn)` — bounds check,
  swap, rebuild, expand target
- `rebuildItems(container, list, buildFn)` — clear container, call buildFn for
  each item
- `addItem(list, emptyFactory, rebuildFn, expandFn)` — push new item, rebuild,
  expand last

### Card DOM builders (~60 lines)

Pure element creation. Callers provide content via config objects/callbacks.

- `buildCard(index, { detailsFn, bodyFn })` — wrapper div + details + collapse
  body
- `buildDetails(index, { titleFn, summaryFn, actionsFn, onToggle })` —
  `<details>` with summary containing title, summary text, and action buttons
- `buildTitle(text, fallback, className)` — span with title or fallback text
- `buildSummary(count, singular, plural)` — "3 ingredients" / "1 item" text
- `buildActions(index, { onMove, onRemove })` — up/down/delete buttons using
  `buildButton` from `dom_builders.js`
- `buildCollapseBody(innerContent)` — collapse-body + collapse-inner wrapper
- `buildRowsSection(label, rows, { onAdd, buildRowFn })` — section header with
  add button + rows container

## What stays in each controller

### Recipe controller (~250 lines, down from 471)

- `connect()`, `initFromRenderedDOM()`, `readStepFromCard()`,
  `readIngredientsFromCard()`
- `loadStructure()`, `toStructure()`, `isModified()`
- Front matter (serves, makes, category dropdown, tags)
- Cross-reference card rendering
- `buildStepCollapseBody()` — recipe-specific fields (name input, ingredients
  section, instructions textarea)
- `buildIngredientRow()` — recipe-specific fields (name, quantity, prep_note)
- All serialization (`serializeSteps`, `serializeIngredients`, `emptyStep`)

### QB controller (~120 lines, down from 308)

- `connect()`, `initFromRenderedDOM()`, `readCategoryFromCard()`,
  `readItemsFromCard()`
- `loadStructure()`, `toStructure()`, `isModified()`
- `buildCategoryCollapseBody()` — QB-specific fields (name input, items
  section)
- `buildItemRow()` — QB-specific fields (name, ingredients text)
- All serialization (`serializeCategories`, `serializeItems`, `serializeItem`,
  `parseIngredientsList`, `ingredientsDisplayText`)

## Estimated reduction

| File | Before | After | Change |
|------|--------|-------|--------|
| recipe_graphical_controller.js | 471 | ~250 | -47% |
| quickbites_graphical_controller.js | 308 | ~120 | -61% |
| graphical_editor_utils.js | 0 | ~100 | new |
| **Net** | **779** | **~470** | **-40%** |

## Testing

- No new JS test file — utility is pure DOM manipulation, tested indirectly
  through existing graphical editor behavior.
- `rake test` (Ruby) and `npm test` (JS classifiers) must pass.
- Manual verification: both recipe and QB graphical editors work identically —
  add/remove/move items, accordion expand/collapse, mode switching.

## Files touched

1. **New**: `app/javascript/utilities/graphical_editor_utils.js`
2. **Edit**: `app/javascript/controllers/recipe_graphical_controller.js`
3. **Edit**: `app/javascript/controllers/quickbites_graphical_controller.js`
4. **Edit**: `app/javascript/utilities/dom_builders.js` (only if `buildButton`
   needs a minor signature tweak — unlikely)

No ERB, CSS, or Ruby changes. No new Stimulus controller registration needed.
