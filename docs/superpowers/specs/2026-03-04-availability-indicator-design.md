# Availability Indicator Redesign (GH #163)

## Problem

The Turbo migration removed the ingredient popover from availability dots on the menu page. The remaining dots have additional problems: ugly in bulk, hard to distinguish with color vision deficiency, inconsistent between recipes and quick bites.

## Design

Replace colored dots with text-based "need N" badges that expand inline to show missing ingredients. Uses native `<details>/<summary>` — zero JS for the core interaction.

### Layout

```
[x] Focaccia                  need 2  →
    Flour, Active dry yeast
[x] Bagels                         ✓  →
[ ] Chicken Pot Pie           need 7  →
[x] Pasta Salad                     ✓  →
```

### Components

**"need N" badge** — replaces the colored dot. A `<summary>` element inside `<details>`, right-aligned via flexbox. Styled as small muted text (`0.8rem`, `var(--muted-text)`). The native disclosure triangle is suppressed — the text itself is the click target. Uses `cursor: pointer` and subtle underline-on-hover to indicate interactivity.

**Expanded ingredient list** — the `<details>` content. Appears below the recipe row as a comma-separated list of missing ingredient names. Smaller muted text, indented to align with the label. Pushed into a new flex row via `display: contents` on the `<details>` or a wrapper approach.

**"✓" for ready recipes** — a plain `<span>`, not expandable (nothing to show). Uses `var(--checked-color)` for a subtle green tint, but the checkmark character is the primary signal (CVD-safe).

**No indicator** — when availability data isn't available (e.g., no grocery list active), no badge renders. Same as current behavior.

### HTML Structure

```erb
<li>
  <input type="checkbox" ...>
  <label ...>Focaccia</label>
  <% if info[:missing].zero? %>
    <span class="availability-ready" aria-label="All ingredients on hand">✓</span>
  <% else %>
    <details class="availability-detail">
      <summary aria-label="Missing <%= info[:missing] %>: <%= info[:missing_names].join(', ') %>">
        need&nbsp;<%= info[:missing] %>
      </summary>
      <span class="availability-missing"><%= info[:missing_names].join(', ') %></span>
    </details>
  <% end %>
  <%= link_to "→", recipe_path(recipe.slug), ... %>
</li>
```

### CSS Approach

The `<li>` is already `display: flex`. The `<details>` element participates in the flex row via its `<summary>`, with the expanded content breaking onto a new line below.

```
.availability-detail          — flex-shrink: 0, margin-left: auto to right-align
.availability-detail summary  — list-style: none (hide triangle), small muted text
.availability-detail[open] .availability-missing
                              — full-width row below, indented, smaller text
.availability-ready           — flex-shrink: 0, subtle green, margin-left: auto
```

The flex-row-to-block transition for expanded content uses `flex-wrap: wrap` on the `<li>` with the missing-names span set to `flex-basis: 100%`.

### Quick Bites

Treated identically to recipes. The old inconsistency (quick bites always showing as "almost available") is resolved naturally — "need 1" reads the same whether it's a quick bite or a 20-ingredient recipe. Users interpret the number relative to what they're looking at.

### Morph Preservation

Turbo's idiomorph preserves `<details>` open/closed state across morphs (it tracks boolean attributes reflecting user interaction). If testing reveals otherwise, a small Stimulus behavior can snapshot open `<details>` IDs before morph and restore them after — same pattern used for aisle collapse on the grocery page.

### Accessibility

- `aria-label` on `<summary>` provides full context for screen readers (same content as old dots)
- `<details>/<summary>` is natively accessible — keyboard-operable, announces expanded/collapsed state
- Text-based indicator eliminates color-only encoding (CVD-safe)
- ✓ character is a text glyph, not color-dependent

### Print

Availability badges hidden in print (same as current dots).

## What Gets Deleted

- `.availability-dot` CSS (lines 100-121 of menu.css)
- Dot `<span>` markup in `_recipe_selector.html.erb`
- `data-missing` attribute system (0/1/2/3+ bucketing)
- The entire color-coded approach

## What Changes

- `_recipe_selector.html.erb` — dot markup → details/summary markup
- `menu.css` — dot styles → badge/expansion styles
- `recipe_availability_calculator.rb` — header comment update (no longer "dots")
- `menu_controller.js` — header comment update

## What Stays

- `RecipeAvailabilityCalculator` — same data, same interface
- `availability` hash shape — `{ missing:, missing_names:, ingredients: }`
- Server-side rendering — no client-side availability logic
- ARIA labels — same content, moved to `<summary>`
