# Graphical Editor Shared Utilities — Design

**GH #251** — Extract shared utilities from graphical editor controllers.

## Problem

`recipe_graphical_controller.js` (497 lines) and
`quickbites_graphical_controller.js` (339 lines) duplicate ~60% of their
patterns: DOM builder helpers are verbatim copies, and accordion
collapse/expand/toggle logic is structurally identical.

## Approach

Extract two plain utility modules into `app/javascript/utilities/`. No Stimulus
coupling — these are pure DOM functions. Both controllers import and call them
instead of maintaining local copies.

## Module 1: `utilities/dom_builders.js`

Four exported functions, extracted verbatim from the controllers:

```js
export function buildButton(text, onClick, className)
export function buildInput(placeholder, value, onChange, className)
export function buildFieldGroup(labelText, type, value, onChange)
export function buildTextareaGroup(labelText, value, onChange)
```

- Signatures and behavior are unchanged from the current local methods.
- `buildTextareaGroup` is only used by the recipe controller today but belongs
  here — same pattern as `buildFieldGroup`.

## Module 2: `utilities/accordion.js`

Three exported functions plus a toggle button builder. All take a container
element as the first argument:

```js
export function toggleAccordionItem(container, index)
export function expandAccordionItem(container, index)
export function collapseAllAccordionItems(container)
export function buildToggleButton(onToggle)
```

- Toggle/collapse query for `.graphical-step-body` and
  `.graphical-step-toggle-icon` — same selectors both controllers already use.
- `expandAccordionItem` calls `collapseAllAccordionItems` then
  `toggleAccordionItem` internally — same composition as the current
  `expandStep`/`expandCategory` methods.
- `buildToggleButton` takes a callback rather than an index, so the controller
  wires it: `buildToggleButton(() => toggleAccordionItem(this.container, index))`.
- Recipe controller's `findExpandedIndex()` stays local — only one consumer.

## Controller changes

**Removed from each controller:** `buildButton`, `buildInput`,
`buildFieldGroup`, `buildTextareaGroup` (recipe only), `buildToggleButton`,
`toggleStep`/`toggleCategory`, `expandStep`/`expandCategory`,
`collapseAllSteps`/`collapseAllCategories`.

**Stays local** — domain-specific builders that call the shared helpers:

- **Recipe:** `buildStepCard`, `buildStepHeader`, `buildStepBody`,
  `buildStepActions`, `buildIngredientRow`, `buildIngredientsSection`,
  `buildCrossRefCard`, `findExpandedIndex`, all serialization, front matter,
  category/tag management.
- **Quick bites:** `buildCategoryCard`, `buildCategoryHeader`,
  `buildCategoryBody`, `buildCategoryActions`, `buildItemRow`,
  `buildItemsSection`, all serialization, `ingredientsDisplayText`.

## Constraints

- **No behavioral changes.** Same DOM output, same class names, same event
  wiring. Pure extraction — no new features, no renamed CSS classes.
- **No esbuild config changes.** New utility modules are plain ES imports,
  picked up automatically by the existing esbuild watcher.
- **Header comments** on both new modules per project convention.

## Testing

Existing integration tests cover both editors end-to-end. Since the rendered
DOM is identical, all tests should pass unchanged. No new unit tests needed —
the functions are trivial DOM factories with no branching logic worth testing
in isolation.
