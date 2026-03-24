# DRY Graphical Editors — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract shared logic from recipe and quickbites graphical controllers into a utility module.

**Architecture:** New `graphical_editor_utils.js` utility with three groups: accordion helpers, collection management, and card DOM builders. Both controllers import and call these functions, keeping only their unique logic.

**Tech Stack:** JavaScript (Stimulus controllers), no new dependencies.

**Spec:** `docs/plans/2026-03-20-dry-graphical-editors-design.md`

---

### Task 1: Create `graphical_editor_utils.js`

**Files:**
- Create: `app/javascript/utilities/graphical_editor_utils.js`

Write the shared utility module with three groups:

**Accordion helpers:**
- `collapseAll(container)` — close all open `<details class="collapse-header">`
- `expandItem(container, index)` — collapse all, open one
- `toggleItem(container, index)` — toggle one detail

**Collection management:**
- `removeFromList(list, index, rebuildFn)` — splice + rebuild
- `moveInList(list, index, direction, container, rebuildFn)` — bounds check, splice, insert, rebuild, optionally expand target
- `rebuildContainer(container, items, buildFn)` — replaceChildren + forEach

**Card DOM builders** (import `buildButton` from `dom_builders`):
- `buildCardShell(detailsEl, bodyEl)` — `div.graphical-step-card` wrapper
- `buildCardDetails(titleEl, summaryEl, actionsEl)` — `details.collapse-header` + `summary.graphical-step-header`
- `buildCardTitle(text, fallback)` — `span.graphical-step-title`
- `buildCountSummary(count, singular, plural)` — `span.graphical-ingredient-summary`
- `buildCardActions(index, onMove, onRemove)` — `div.graphical-step-actions` with up/down/delete buttons
- `buildCollapseBody(contentFn)` — `div.collapse-body` > `div.collapse-inner.graphical-step-body`, calls contentFn(inner)
- `buildRowsSection(label, items, onAdd, buildRowFn, containerAttrs)` — section header with add button + rows container
- `updateTitleDisplay(container, index, text, fallback)` — update title span in card at index

- [ ] Write all functions
- [ ] Commit

### Task 2: Refactor `recipe_graphical_controller.js`

**Files:**
- Modify: `app/javascript/controllers/recipe_graphical_controller.js`

Import shared utilities and replace duplicated methods:

- Replace `collapseAll`, `expandItem`, `toggleItem` with imports
- Replace `removeStep` body: guard then `removeFromList(this.steps, index, ...)`
- Replace `moveStep` body: `moveInList(this.steps, index, direction, this.stepsContainerTarget, ...)`
- Replace `rebuildSteps` body: `rebuildContainer(this.stepsContainerTarget, this.steps, ...)`
- Replace `buildStepCard`: use `buildCardShell`
- Replace `buildStepDetails`: use `buildCardDetails`, `buildCardTitle`, `buildCountSummary`, `buildCardActions`
- Replace `buildStepCollapseBody`: use `buildCollapseBody`
- Replace `buildIngredientsSection`: use `buildRowsSection`
- Replace `updateStepTitleDisplay`: use `updateTitleDisplay`
- Replace ingredient management: use `removeFromList`, `moveInList`, `rebuildContainer`
- Delete `buildStepTitle`, `buildIngredientSummary`, `buildStepActions`

Keep: `readStepFromCard`, `readIngredientsFromCard`, `loadStructure`, `toStructure`, `isModified`, `addStep`, front matter, category, tags, cross-reference methods, `buildIngredientRow`, serialization, `emptyStep`, `findExpandedIndex`, `appendStepCard`.

- [ ] Refactor all methods
- [ ] Commit

### Task 3: Refactor `quickbites_graphical_controller.js`

**Files:**
- Modify: `app/javascript/controllers/quickbites_graphical_controller.js`

Same pattern as Task 2:

- Replace `collapseAll`, `expandItem` with imports
- Replace `removeCategory`, `moveCategory`, `rebuildCategories`: use shared collection functions
- Replace `removeItem`, `moveItem`, `rebuildItemRows`: use shared collection functions
- Replace card builders: use `buildCardShell`, `buildCardDetails`, `buildCardTitle`, `buildCountSummary`, `buildCardActions`, `buildCollapseBody`, `buildRowsSection`, `updateTitleDisplay`
- Delete `buildCategoryTitle`, `buildItemSummary`, `buildCategoryActions`, `updateCategoryTitleDisplay`

Keep: `readCategoryFromCard`, `readItemsFromCard`, `loadStructure`, `toStructure`, `isModified`, `addCategory`, `appendCategoryCard`, `buildItemRow`, `ingredientsDisplayText`, all serialization.

- [ ] Refactor all methods
- [ ] Commit

### Task 4: Test and verify

- [ ] Run `npm run build` — JS bundles without errors
- [ ] Run `npm test` — JS classifier tests pass
- [ ] Run `rake test` — all Ruby tests pass
- [ ] Run `rake lint` — RuboCop passes
- [ ] Commit any fixes
