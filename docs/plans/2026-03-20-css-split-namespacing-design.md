# CSS Split & Class Namespacing — Design

GitHub: #262 (CSS portion; JS portion completed in PR #266)

## Problem

`style.css` is a 3,351-line monolith. Finding and modifying styles requires
scrolling through unrelated sections. Additionally, ~16 editor-related CSS
classes in the nutrition editor lack the `editor-` prefix used by every other
editor class, creating naming inconsistency.

## Decisions

- **Moderate split (~6 files).** Enough to organize by domain without
  overengineering. A 15-file split solves a scale problem this app doesn't
  have — HTTP/2 parallelizes requests, but 15 `stylesheet_link_tag` calls
  clutter the layout, and more files mean more cascade-ordering surface area.
- **Responsive rules stay with their components.** Each file owns its own
  `@media` queries. No separate `responsive.css` — keeps related rules
  together and avoids cross-file ordering dependencies.
- **Dark-mode overrides distributed.** The consolidated `prefers-color-scheme:
  dark` block (lines 1557-1584) is split so each file owns its dark-mode
  rules alongside the light-mode base.
- **Page-specific extraction for ingredients.** Follows the existing pattern
  of `menu.css` and `groceries.css` — loaded via `content_for(:head)` only
  on the ingredients page.

## New file structure

All files in `app/assets/stylesheets/`. No subdirectories.

### `base.css` (~1,100 lines)

Foundation styles used across the entire site.

- `:root` color tokens (light + dark mode)
- Body, gingham background, turbo progress bar, `sr-only`
- Main content card (centered card, paper texture, shadows)
- Typography: headers, TOC nav, sections, homepage sections, export actions
- Recipe content layout (ingredients/instructions grid, footer)
- Buttons (`.btn*`), inputs (`.input-base*`), custom checkbox
- Collapse mechanism (`.collapse-header`, `.collapse-body`, `.collapse-inner`)
- Scale bar and controls
- Tag pills and smart tag variants (cross-cutting — used in search and
  recipe display)
- Screen interactivity (crossed-off, cursor states)
- Mobile base overrides (720px breakpoint)
- App version, `prefers-reduced-motion`

### `navigation.css` (~500 lines)

Everything related to the nav bar and search overlay.

- Nav bar, links, compact mode, hamburger button/icon, drawer
- Search overlay dialog, search panel, input, results
- Nav search button
- Keyframe: `fade-in`
- Dark-mode: nav backdrop

### `editor.css` (~700 lines)

All editor dialog and form styling.

- Editor dialog, keyframe `bloop`
- Editor header/body/footer/errors/warnings
- Textarea, category row, side panel, mobile meta toggle
- Tag input (pills editor, autocomplete)
- CodeMirror mount
- Token highlights (`hl-*` classes)
- Aisle order editor
- Editor form, editor sections (collapsible)
- Mode toggle, header actions
- Graphical editor (step cards, ingredient rows, section headers, buttons)
- Mobile editor overrides (720px — fullscreen dialogs, bigger tap targets)
- Dark-mode: `.editor-section`

### `nutrition.css` (~400 lines)

FDA nutrition label display and nutrition editor form.

- FDA label (`.nutrition-label*`), nutrition footnote
- Nutrition facts editor (`.nf-*` classes)
- USDA search panel
- Density, portion, alias classes (renamed with `editor-` prefix)
- `.editor-btn-icon`, aisle form select
- iOS zoom prevention
- Dark-mode: nutrition label, thick rule, USDA results, density candidates

### `recipe.css` (~120 lines)

Embedded cross-referenced recipe cards.

- `.embedded-recipe*`, `.broken-reference`
- `.recipe-link`
- Mobile embedded card override

### `print.css` (~60 lines)

Print-only styles.

- `@media print` block

### `ingredients.css` (~130 lines, page-specific)

Ingredients page table and toolbar. Loaded via `content_for(:head)` only on
the ingredients index page.

- Ingredients toolbar, filter pills
- Ingredients table, sortable headers, ingredient rows
- Column classes (`.col-name`, `.col-aisle`, `.col-recipes`)
- Loading placeholder, error message
- Settings dialog
- Mobile: hide aisle/recipes columns

## Layout changes

`application.html.erb` gains 5 additional `stylesheet_link_tag` calls (6
total, replacing the single `style` tag):

```erb
<%= stylesheet_link_tag 'base', "data-turbo-track": "reload" %>
<%= stylesheet_link_tag 'navigation', "data-turbo-track": "reload" %>
<%= stylesheet_link_tag 'editor', "data-turbo-track": "reload" %>
<%= stylesheet_link_tag 'nutrition', "data-turbo-track": "reload" %>
<%= stylesheet_link_tag 'recipe', "data-turbo-track": "reload" %>
<%= stylesheet_link_tag 'print', "data-turbo-track": "reload" %>
```

`base.css` must load first (owns `:root` tokens). Remaining files are
order-independent since they target distinct selectors.

Ingredients index view adds:
```erb
<% content_for(:head) do %>
  <%= stylesheet_link_tag 'ingredients', "data-turbo-track": "reload" %>
<% end %>
```

## Class renaming

All un-namespaced classes are in the nutrition editor context. Rename with
`editor-` prefix for consistency:

| Current | New |
|---------|-----|
| `.form-row` | `.editor-form-row` |
| `.field-unit` | `.editor-field-unit` |
| `.portion-eq` | `.editor-portion-eq` |
| `.density-row` | `.editor-density-row` |
| `.portion-row` | `.editor-portion-row` |
| `.portion-unit` | `.editor-portion-unit` |
| `.add-portion` | `.editor-add-portion` |
| `.density-candidates` | `.editor-density-candidates` |
| `.density-candidate-row` | `.editor-density-candidate-row` |
| `.alias-chip-list` | `.editor-alias-list` |
| `.alias-chip` | `.editor-alias-chip` |
| `.alias-chip-remove` | `.editor-alias-remove` |
| `.alias-add-row` | `.editor-alias-add-row` |
| `.alias-input` | `.editor-alias-input` |
| `.add-alias` | `.editor-add-alias` |
| `.btn-icon` | `.editor-btn-icon` |

### Files touched by renaming

1. `nutrition.css` — CSS rules (the definitions)
2. `app/views/ingredients/_editor_form.html.erb` — HTML class attributes
3. `app/views/ingredients/_portion_row.html.erb` — HTML class attributes
4. `app/javascript/controllers/nutrition_editor_controller.js` — JS class
   name strings in DOM manipulation
5. `test/controllers/ingredients_controller_test.rb` — test assertions using
   CSS selectors

## Testing

- `rake test` — all Ruby tests pass
- `npm test` — JS classifier tests pass
- `rake lint` — RuboCop passes
- `rake lint:html_safe` — allowlist line numbers may need updating if ERB
  edits shift lines
- Manual verification: visual spot-check that pages render identically

## Files touched

1. **Delete**: `app/assets/stylesheets/style.css`
2. **New**: `base.css`, `navigation.css`, `editor.css`, `nutrition.css`,
   `recipe.css`, `print.css`, `ingredients.css`
3. **Edit**: `app/views/layouts/application.html.erb` (stylesheet tags)
4. **Edit**: `app/views/ingredients/index.html.erb` (page-specific CSS)
5. **Edit**: `app/views/ingredients/_editor_form.html.erb` (class renames)
6. **Edit**: `app/views/ingredients/_portion_row.html.erb` (class renames)
7. **Edit**: `app/javascript/controllers/nutrition_editor_controller.js`
   (class renames)
8. **Edit**: `test/controllers/ingredients_controller_test.rb` (class renames)
9. **Edit**: `config/html_safe_allowlist.yml` (if line numbers shift)

No Ruby model, controller, or routing changes.
