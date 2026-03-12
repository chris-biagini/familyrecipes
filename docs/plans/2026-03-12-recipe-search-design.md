# Recipe Search — Spotlight-Style Overlay

**Date:** 2026-03-12

## Context

The app needs a fast way to find recipes. The homepage groups recipes by
category, but as the collection grows, scanning visually doesn't scale. Browser
Ctrl+F works but only on the current page and can't search ingredients.

## Design

### Data Strategy

Client-side search over an embedded JSON blob. Server renders a
`<script type="application/json">` tag in the application layout containing all
recipes for the current kitchen:

```json
[
  {
    "title": "Pancakes",
    "slug": "pancakes",
    "description": "Fluffy buttermilk pancakes",
    "category": "Baking",
    "ingredients": ["flour", "buttermilk", "eggs", "butter", "sugar"]
  }
]
```

Ingredient names are deduplicated from the recipe's ingredient associations.
The helper is kitchen-scoped (`current_kitchen.recipes`). At typical scale
(10-100 recipes) this is well under 10KB — smaller than the stylesheet.

No server-side search endpoint. No libraries.

### Trigger

- **`/` key** globally, via Stimulus controller on `<body>`. Suppressed when
  focus is inside any input/textarea/contenteditable or when a `<dialog>` is
  already open.
- **Magnifying glass icon** in the nav bar.

### Overlay

A `<dialog>` element using `showModal()` for native focus trapping and
accessibility.

- **Backdrop** (`::backdrop`): dimmed only (semi-transparent dark, no blur) —
  consistent with existing editor dialogs.
- **Panel**: frosted glass effect — translucent background with
  `backdrop-filter: blur()` so the page bleeds through softly. Centered
  horizontally, ~30% from viewport top via fixed positioning.
- **Width**: ~500px, rounded corners, subtle shadow.

### Search Input

Large, prominent input at the top of the panel. Magnifying glass icon as visual
affordance. Autofocused on open. Placeholder: "Search recipes..."

### Results

Rendered below the input as the user types. Each result shows recipe title with
a small muted category label to the right.

- **Matching**: case-insensitive substring across title, description, category,
  and ingredient names. Any match includes the recipe.
- **Ranking**: title matches first, then description, then category, then
  ingredients. Alphabetical within each tier.
- **Minimum query**: 2 characters before results appear.
- **Max visible**: ~6-7 results, scrollable overflow.
- **Empty query**: nothing shown (just the input).
- **No matches**: brief "No matches" message.

### Keyboard Navigation

- **Arrow up/down**: move selection highlight through results.
- **Enter**: navigate to the selected result (or first if none highlighted).
- **Escape**: close overlay.
- **`/` while open**: focuses input (does not toggle closed).

### Dismiss

- Escape key.
- Clicking the backdrop (outside the panel).
- Selecting a result (navigates away).
- Does not participate in browser history.

### Visual Direction

Frosted glass panel echoing macOS Spotlight. Clean surface (light mode: white
tint, dark mode: dark tint), generous input padding, hover/selected highlight
on results, smooth fade-in on open.

### Architecture

- **`SearchDataHelper`** — Ruby helper, builds JSON array from kitchen recipes.
- **`search_overlay_controller.js`** — Stimulus controller: open/close, search,
  keyboard nav, result rendering.
- **`shared/_search_overlay.html.erb`** — `<dialog>` markup, rendered in
  application layout.
- **CSS** — added to `style.css`.

### Excluded

- Server-side search endpoint.
- Fuzzy/Levenshtein matching (substring sufficient for now).
- Search history or analytics.
- Deep linking to search queries.
- Result previews or matched-field context.
- Empty-state suggestions (recent, meal plan, etc.).
