# Menu / Groceries Split Design

**Date:** 2026-02-27
**Issue:** #110

## Problem

The Groceries page serves two functions: (1) building a "menu" of meals and quick bites for the week, and (2) a shopping list of groceries needed to make them. This creates friction — users must scroll past the menu interface to interact with the shopping list, both at home when taking inventory and in-store.

## Solution

Split into two separate pages: a **Menu** page for meal planning and a **Groceries** page for the shopping list. Rename the backing model from `GroceryList` to `MealPlan` to reflect its dual role.

## Model & Channel Rename

`GroceryList` → `MealPlan`. Same table, same jsonb state blob (`selected_recipes`, `selected_quick_bites`, `custom_items`, `checked_off`), same optimistic locking. Migration renames the table.

`GroceryListChannel` → `MealPlanChannel`. Same behavior: broadcasts version numbers on state changes. Both pages subscribe. The Turbo Stream channel for content changes (quick bites edits) scopes to the Menu page only (where the recipe selector lives).

`ShoppingListBuilder` keeps its name — it still builds shopping lists. Its constructor changes from accepting a `GroceryList` to a `MealPlan`.

## Routes

New `menu` resource alongside the slimmed `groceries` resource, both inside the optional kitchen scope:

```ruby
# Menu page (new)
get    'menu',              to: 'menu#show'
patch  'menu/select',       to: 'menu#select'
patch  'menu/quick_bites',  to: 'menu#update_quick_bites'
delete 'menu/clear',        to: 'menu#clear'

# Groceries page (slimmed)
get    'groceries',                    to: 'groceries#show'
get    'groceries/state',              to: 'groceries#state'
patch  'groceries/check',              to: 'groceries#check'
patch  'groceries/custom_items',       to: 'groceries#update_custom_items'
patch  'groceries/aisle_order',        to: 'groceries#update_aisle_order'
get    'groceries/aisle_order_content', to: 'groceries#aisle_order_content'
```

`select`, `update_quick_bites`, and `clear` move from `GroceriesController` to `MenuController`. The `clear` action on the Menu page resets only selections (`selected_recipes` + `selected_quick_bites`), not `custom_items` or `checked_off`.

## Controllers

**MenuController** (new):
- `show` — loads recipe categories, quick bites; renders the menu page
- `select` — toggles recipe/quick bite selection (moved from GroceriesController)
- `update_quick_bites` — edits quick bites content (moved from GroceriesController)
- `clear` — resets selections only

**GroceriesController** (slimmed):
- `show` — renders the shopping list page (no recipe selector)
- `state` — returns JSON state with shopping list
- `check` — toggles item check-off
- `update_custom_items` — add/remove custom items
- `update_aisle_order` / `aisle_order_content` — aisle order editing

Both controllers use `require_membership` on all actions.

## Views

### Menu page (`menu/show.html.erb`)

- **Header:** "Menu"
- **Subtitle:** "What's on the menu? Pick recipes and quick bites that you want to have available."
- Recipe selector (moved from groceries — the `_recipe_selector` partial)
- "Edit Quick Bites" and "Edit Aisle Order" editor dialogs (members only)
- Clear button
- Subscribes to `MealPlanChannel` for real-time sync of selections

### Groceries page (`groceries/show.html.erb`, simplified)

- **Header:** "Groceries"
- **Subtitle:** "Your shopping list, built from the menu."
- Shopping list (aisle-organized items, rendered by JS from state)
- Custom items input + list at the **bottom** of the shopping list, in their own section below all aisles (not a separate "Additional Items" section above the list)
- Subscribes to `MealPlanChannel` for live updates when menu selections change

## Stimulus Controllers

Split the monolithic grocery controllers into page-specific concerns:

**`menu_controller.js`** (new) — Menu page:
- Checkbox toggling for recipe/quick bite selection
- Sends `select` actions to `MenuController`
- Subscribes to `MealPlanChannel` for cross-device sync of selections
- Syncs checkbox state from server state
- localStorage caching of selection state

**`grocery_sync_controller.js`** (slimmed) — Groceries page:
- Subscribes to `MealPlanChannel`
- Fetches state from `/groceries/state`
- Re-fetches and re-renders when version changes (from menu or grocery actions)
- localStorage caching, offline pending action queue (check/custom_items only)

**`grocery_ui_controller.js`** (slimmed) — Groceries page rendering:
- `renderShoppingList` — aisle-organized items (unchanged)
- Custom items rendered inline at the bottom of the shopping list
- `syncCheckedOff`, `renderItemCount` — unchanged
- Recipe selector checkbox logic removed (moved to `menu_controller`)

## Real-Time Sync

Both pages subscribe to `MealPlanChannel`. On any state write:

1. Server updates `MealPlan`, increments `lock_version`
2. `MealPlanChannel.broadcast_version(kitchen, version)` fires
3. Menu page re-fetches selections → syncs checkboxes
4. Groceries page re-fetches full state → re-renders shopping list

If someone is on the Menu page adding recipes while someone else is in the store on the Groceries page, the shopping list updates live.

Turbo Streams for content changes (quick bites structure) broadcast to the Menu page only.

### Two sync mechanisms, different jobs

**ActionCable (MealPlanChannel)** handles frequent, lightweight state sync. Broadcasts version numbers (`{ version: 42 }`); clients compare to local version and fetch fresh state only when stale. Efficient for high-frequency changes like checkbox toggles.

**Turbo Streams** handle infrequent content structure changes. When someone edits Quick Bites, the server renders fresh HTML and broadcasts a `replace` fragment. No JS rendering logic needed — the browser gets ready-to-display markup.

## Print Stylesheets

**Menu page print:** Selected recipes in a clean multi-column layout (adapted from current page 1 print styles). Hides checkboxes, shows only selected items.

**Groceries page print:** Shopping list in multi-column layout (adapted from current page 2 print styles). Aisles forced open, empty squares for pen-and-paper checking. Hides custom items input and checked-off items.

## Navbar

Order: `[Ingredients] [Menu] [Groceries]`

Both Menu and Groceries links appear only when a kitchen is selected and user is logged in (same visibility rules as current Groceries link).

## PWA / Service Worker

Update `API_PATTERN` in `public/service-worker.js` to include `/menu/select`, `/menu/quick_bites`, and `/menu/clear` in the skip list. Consider adding a `/menu` shortcut to `manifest.json` alongside the existing `/groceries` shortcut.

## Custom Items Placement

Custom items move from a separate "Additional Items" section above the shopping list to an inline section at the bottom of the shopping list, below all aisles. This eliminates the awkward "Additional to what?" problem that would arise when the menu is no longer on the same page.

The input field and item list live in their own untitled section at the bottom, visually distinct from aisle-organized ingredients.
