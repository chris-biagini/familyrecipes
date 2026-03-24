# Recipe Change Propagation Design

**Date:** 2026-02-28
**GitHub Issue:** #114

## Problem

Edits to recipes (creates, updates, deletes, renames, ingredient changes) do not propagate to other open pages in real time. Users must manually refresh to see changes reflected on the homepage, menu, groceries, ingredients, and individual recipe pages.

## Decision

Use Turbo Stream broadcasts for HTML-rendered pages and ActionCable state re-fetch for the JSON-driven groceries page. Auto-update page content in place with a brief toast confirming what changed. Only kitchen members get real-time updates — public visitors see static pages until they refresh.

## Stream Architecture

One kitchen-scoped Turbo Stream serves all list pages:

```erb
<% if current_user && current_kitchen.member?(current_user) %>
  <%= turbo_stream_from current_kitchen, "recipes" %>
<% end %>
```

Individual recipe pages additionally subscribe to a recipe-specific stream (same auth gate):

```erb
<%= turbo_stream_from @recipe, "content" %>
```

Auth is two layers: views only render the `turbo_stream_from` tag for members, and Turbo's signed stream tokens prevent unauthorized subscriptions. No custom channel auth needed.

The groceries page does not use Turbo Streams — it builds its shopping list client-side from JSON. It uses the existing `MealPlanChannel` ActionCable subscription, changed from "show notification" to "auto-fetch state."

## Broadcast Triggers

On recipe create, update, or delete, the controller calls a `RecipeBroadcaster` service that sends:

| Target | Action | Content |
|---|---|---|
| `#recipe-listings` | `replace` | Homepage category/recipe grid partial |
| `#recipe-selector` | `replace` | Menu page checkbox list partial |
| `#ingredients-table` | `replace` | Ingredients page table partial |
| `#notifications` | `append` | Toast element (self-removing) |

Plus:
- `MealPlanChannel.broadcast_content_changed` — groceries page auto-fetches state
- Recipe-specific stream: `replace` targeting `#recipe-content` on individual recipe pages

The broadcaster runs after all synchronous cascades (nutrition, cross-references) complete, so rendered partials contain fresh data.

## Per-Page Behavior

**Homepage:** Recipe listings wrapped in `<div id="recipe-listings">`, content extracted into `homepage/_recipe_listings.html.erb`. Broadcast replaces the entire listing.

**Menu page:** Already has `#recipe-selector` as a Turbo Stream target for quick bites. Recipe changes broadcast to the same target. `menu_controller` already restores checkbox state across Turbo Stream replacements via `turbo:before-stream-render`.

**Groceries page:** `grocery_sync_controller` changes from showing a "Reload" notification on `content_changed` to calling `fetchState()` directly, then showing a toast. Checked-off items and custom items are preserved (they live in `MealPlan.state`).

**Ingredients page:** Table wrapped in `<div id="ingredients-table">`, content extracted into partial. Broadcast replaces it. Open editor dialogs are unaffected (separate DOM).

**Individual recipe page:** Subscribes to `[recipe, "content"]`. Recipe body wrapped in `<div id="recipe-content">`. On update, broadcast replaces with fresh HTML. Scaling/cross-off state lives in localStorage and is restored by `recipe_state_controller`. On delete, broadcast replaces with a "deleted" message and link home.

## Toast Notifications

Every page layout includes `<div id="notifications"></div>`. Broadcasts append a self-removing element:

```html
<div data-controller="toast" data-toast-message-value="Bagels was updated"></div>
```

A `toast_controller` Stimulus controller calls the existing `notify()` utility on connect and removes itself:

```javascript
connect() {
  notify(this.messageValue)
  this.element.remove()
}
```

Messages: "X was added" / "X was updated" / "X was deleted" / "Shopping list updated" (groceries).

The user who made the change sees the toast on other open tabs, which is useful confirmation. On the page where they made the edit, the controller response handles the UX (redirect, flash, etc.), so no "skip self" logic is needed.

## Edge Cases

**Deleted recipe while viewing it:** Broadcast a `replace` to the recipe-specific stream with a "This recipe has been deleted" message and link home before destroying the record.

**Recipe rename with slug change:** Broadcast the "deleted/renamed" message to the old recipe's stream before the old record is destroyed. Message includes "Bagels was renamed to Everything Bagels" with a link to the new slug. Homepage/menu/ingredients broadcasts use kitchen-scoped data and naturally show the new title.

**Cross-reference cascade:** `CrossReferenceUpdater.rename_references` re-imports referencing recipes. Each re-import triggers its own broadcasts, so pages viewing affected recipes also update. All synchronous.

**Nutrition cascade:** `CascadeNutritionJob` runs before the broadcaster, so partials include fresh nutrition data.

**No-op updates and rapid edits:** Idempotent — identical HTML replacements are harmless. Multiple toasts from rapid edits are accurate.
