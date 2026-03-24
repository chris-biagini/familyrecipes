# Server-Render Initial State (gh-158)

## Problem

The Menu and Groceries pages use a `hidden-until-js` CSS pattern that hides content until Stimulus controllers connect. This causes a two-stage render: the page shell (header/nav) appears first, then content pops in 200-500ms later with a visible layout shift. Groceries is worst because the shopping list is built entirely by JS after an async fetch.

## Approach

Server-render both pages with their full initial state so content is visible on first paint. JS enhances and takes over DOM ownership after connecting — the rebuild is visually invisible because the server-rendered HTML matches what JS produces.

## Menu Page

The `_recipe_selector` partial already renders all checkboxes server-side. Currently they arrive unchecked and hidden; JS fetches state, checks the right boxes, and reveals the container.

**Change:** Load MealPlan state in the controller, pass selected slugs to the partial, and pre-check checkboxes in ERB. Remove `hidden-until-js` so content is visible immediately. JS `syncCheckboxes` still runs to correct any stale state — it just finds correct checkboxes instead of blank ones.

### Controller

`MenuController#show` loads `MealPlan.for_kitchen(current_kitchen)` and extracts `selected_recipes` and `selected_quick_bites` arrays. Passes them to the `_recipe_selector` partial.

### Partial

`_recipe_selector.html.erb` accepts `selected_recipes:` and `selected_quick_bites:` locals. Each checkbox gets `checked` if its slug appears in the matching set. Use `Set` for O(1) lookup.

### JS

`menu_controller.js` `syncCheckboxes` drops the `classList.remove("hidden-until-js")` line. Everything else stays the same — it already reconciles checkbox state.

## Groceries Page

The shopping list container arrives empty; JS builds the full DOM after fetching `/groceries/state`. This is the primary source of layout shift.

**Change:** Run `ShoppingListBuilder` in the controller's `show` action (same computation the `state` endpoint already does) and render the shopping list HTML server-side. The ERB template produces the same `<details>/<summary>/<ul>/<li>` structure that `grocery_ui_controller.renderShoppingList` builds in JS.

### Controller

`GroceriesController#show` loads the MealPlan, builds the shopping list, and extracts checked-off and custom-items arrays. Passes all four to the view.

### View / Partials

- `show.html.erb` removes `hidden-until-js` class and the `<noscript>` block.
- New `_shopping_list.html.erb` partial renders the aisle sections with `<details open>`, item checkboxes (pre-checked from `checked_off`), amounts, and item counts.
- `_custom_items.html.erb` receives the custom items array and pre-renders the `<li>` elements.

### JS

`grocery_ui_controller.js` drops the `classList.remove("hidden-until-js")` line from `connect()`. `renderShoppingList` and `renderCustomItems` still do full DOM rebuilds on state updates — but since the server HTML matches, the first rebuild is invisible. No hydration logic needed.

## Cleanup

Remove from both pages:
- `<noscript>` blocks (JS is always available in this PWA)
- `.hidden-until-js` CSS rule from `menu.css` and `groceries.css`
- `classList.remove("hidden-until-js")` from `menu_controller.js` and `grocery_ui_controller.js`

## Testing

- Controller tests: verify `show` assigns the expected instance variables
- Integration tests: verify checkboxes arrive pre-checked, shopping list HTML is present
- Existing JS behavior tests continue to pass (JS still rebuilds DOM on state updates)
