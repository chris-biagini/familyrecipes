# Print Stylesheet Overhaul

**Issue:** GH #285
**Date:** 2026-03-26

## Problem

Print stylesheets have not kept pace with app development. The recipe page
prints a blank half-page before the title, interactive elements are visible,
ingredient bullets are plain dots, there is no pagination control, and the
nutrition label wastes vertical space. The menu and grocery pages are better
but have minor gaps.

## Goals

- Every printable page should look intentional — no blank space, no interactive
  artifacts, sensible pagination
- Recipes should print as usable kitchen sheets: checkbox bullets for
  ingredients, instruction paragraphs, and section headings (matching the web
  cross-off behavior) — suitable for laminating and using with dry erase markers
- Maximize content density to fit recipes on as few pages as possible (ideally
  front-and-back on a single sheet for typical recipes)
- Nutrition facts should float alongside recipe content rather than sitting as
  a centered block below

## Non-Goals

- No JavaScript print logic — pure CSS `@media print`
- No changes to the web/screen layout
- Minimal view changes — only where CSS alone cannot achieve the goal

## Design

### 1. Recipe Page — print.css

This is the primary focus. The recipe show page currently has significant
print issues.

#### 1a. Eliminate blank space

The blank half-page is caused by several compounding styles:

- `main` has `padding: 3rem 3rem 5rem` and `margin: var(--gingham-gap) auto`
- `header` has `margin-bottom: 1.5rem` and a `header::after` pseudo-element
  adding `margin: 1.5rem auto 0`
- `h1` has default browser top margin

Fix: in `@media print`, zero out `main` padding/margin, `header` bottom
margin, `header::after` display, `h1` margin-top. The existing `print.css`
partially does this but misses `main` margin and `header` specifics.

#### 1b. Hide interactive elements

Elements to hide in print:

- `.scale-bar` (scale toggle + controls)
- `.recipe-actions` (Edit button, middot, scale link) — redundant since
  scale-bar contains it, but explicit for safety
- `.recipe-tags` (clickable filter pills, not informational in print)
- `.search-overlay` (dialog)
- `#settings-dialog` (dialog)
- `.app-version` (footer version badge)
- `[data-open-editor]` buttons in nutrition footnotes
- Nutrition footnote editor buttons should be hidden but the footnote text
  itself should remain

#### 1c. Checkbox bullets

Replace ingredient list markers with empty checkbox squares, matching the
grocery page pattern. Also add checkboxes before:

- Instruction paragraphs (`.instructions p`)
- Section headings (`article.recipe section h2`, `h3`)

Implementation: Use `::before` pseudo-elements to render unfilled checkbox
squares. For ingredients, the list already has `list-style: none`, so add a
`::before` on `.ingredients li`. For instructions, prepend a checkbox via
`::before` on `.instructions p` using `float: left` to preserve block text
flow (avoids disrupting the existing grid layout). For section headings,
use `::before` on `article.recipe section h2, article.recipe section h3`
(fully qualified selectors to avoid matching headings outside the recipe).

Checkbox style:

```css
/* Shared checkbox pattern — float: left for block-level elements */
content: "";
display: inline-block;
width: 0.7rem;
height: 0.7rem;
border: 1px solid black;
border-radius: 1px;
margin-right: 0.4rem;
vertical-align: middle;
flex-shrink: 0;
```

For `.instructions p`, use `float: left; margin: 0.25em 0.4rem 0 0` to keep
text wrapping naturally around the checkbox.

#### 1d. Nutrition label float

The nutrition label (`<aside class="nutrition-label">`) is currently the last
child of `<article>` in the DOM, rendered after all steps and the footer.
CSS `float: right` only affects content that flows *after* the floated element,
so floating it in its current position would just push it right with nothing
beside it.

**View change required:** Wrap the nutrition label and its footnotes in a
`<div class="nutrition-print-wrap">` and move it to render *before* the
recipe steps in `_recipe_content.html.erb`. This is invisible on screen
(the wrapper has no screen styles) but allows the float to work in print.
The existing centered layout on screen is preserved by not adding any screen
styles to the wrapper.

Print styles for the wrapper:

```css
.nutrition-print-wrap {
  float: right;
  width: 14rem;
  margin: 0 0 1rem 1.5rem;
}
```

The `.nutrition-footnote` paragraphs move inside the wrapper so they stay
with the label.

Reduce label from the screen `max-width: 16rem` to `width: 100%` within the
floated wrapper. Clear the float after the article via `article.recipe::after
{ content: ""; display: block; clear: both; }`.

Ensure dark-mode overrides don't apply in print — force white bg, black text
and borders on the label.

#### 1e. Pagination

- `break-inside: avoid` on `article.recipe section` — keep ingredient groups
  and their instructions together when possible
- `break-after: avoid` on section headings — don't orphan a heading at the
  bottom of a page
- `break-before: avoid` on the first section after the header
- `break-inside: avoid` on `.embedded-recipe` cards
- `break-inside: avoid` on `.nutrition-label`
- Allow breaks between sections — this is where multi-page recipes should
  naturally split

#### 1f. Content width and typography

- The existing `@page { margin: 1in 1.5in }` provides good side margins for
  readability. Keep this for recipes.
- `article.recipe { font-size: 11pt }` — scoped to recipe only so menu and
  grocery pages keep their own sizing. Internal units use `em` where needed.
- Tighter line-height on instructions: `1.5` instead of `1.75`
- Section `margin-top`: `1.5rem` (down from `2.5rem`)
- Section heading `margin-bottom`: `0.5rem`
- `header h1` at `2rem` (down from `3.8rem`)
- `header p` (description) at `1rem` (down from `1.3rem`)

#### 1g. Embedded recipes

- Strip `box-shadow` (already done) and `border` to a simple `1px solid #ccc`
- Maintain `break-inside: avoid`
- `.embedded-recipe-link` (arrow to full recipe) — hide in print

#### 1h. Recipe footer

Keep the recipe footer visible but strip decorative styling (the `::after`
pseudo-element rule line above it). Tighten margins.

#### 1i. Crossed-off state

The crossed-off styles in `base.css` are already scoped to `@media screen`,
so they never apply in print. No additional work needed — just noting this
for completeness.

### 2. Menu Page — menu.css

The menu print styles are already good. Minor improvements:

- Help links live inside `nav` (already hidden globally) — no additional hides
  needed
- Verify `break-inside: avoid` on `.category` blocks prevents orphaned headers
- The two-column grid layout is already in place

No structural changes needed.

### 3. Groceries Page — groceries.css

The grocery print styles are the most polished. Minor improvements:

- Verify aisle headers don't orphan from their item lists
  (`break-after: avoid` on `.aisle-header` if not already present)
- Help links live inside `nav` (already hidden globally) — no additional hides
  needed

No structural changes needed.

### 4. Global print.css

Consolidate global hide rules and add missing ones:

**Currently hidden:** `nav`, `.notify-bar`, `.editor-dialog`, `#export-actions`

**Add to hidden list:**
- `.app-version` (footer version text)
- `.search-overlay` (search dialog)
- `#settings-dialog` (settings dialog — verify it isn't already caught by
  `.editor-dialog` class; if so, skip)

Help links and contextual help icons are children of `nav` or `.editor-dialog`,
both already hidden — no additional selectors needed.

**Dark mode in print:** Force nutrition label to white bg / black borders
regardless of `prefers-color-scheme`. The label's dark mode styles use CSS
custom properties — override with explicit `#000` / `#fff` in the print block.

**Scalable quantity highlight:** Already handled — `.scalable.scaled` gets
`background-color: transparent`. Keep this.

### 5. Summary of Files Changed

| File | Scope |
|------|-------|
| `app/assets/stylesheets/print.css` | Major — all recipe print rules, global hides |
| `app/assets/stylesheets/menu.css` | Minor — verify category orphan prevention |
| `app/assets/stylesheets/groceries.css` | Minor — verify aisle orphan prevention |
| `app/views/recipes/_recipe_content.html.erb` | Minor — move nutrition block before steps, wrap in `.nutrition-print-wrap` |

No JavaScript or controller changes.

**Note on `@page` margins:** The recipe, menu, and grocery pages each declare
`@page` margins. Because `@page` is global, the winning declaration depends on
CSS load order. Currently this works correctly: `print.css` (loaded globally)
sets `1in 1.5in`, then `menu.css` / `groceries.css` (loaded via
`content_for(:head)`) override to `0.5in 0.6in` on their pages. This is
fragile but functional — document it with a comment in each file.

## Testing

- Print preview each page type in Chrome/Firefox and verify:
  - Recipe: no blank space, checkboxes on ingredients/instructions/headings,
    nutrition floated right, pagination breaks between sections, no interactive
    elements visible
  - Menu: selected items in 2-column grid, no interactive elements
  - Groceries: 4-column grid, checkbox squares, no interactive elements
- Test a long recipe (many steps, embedded references, nutrition) — verify
  it paginates cleanly across 2+ pages
- Test a short recipe — verify it fits on one page compactly
- Test recipe with no nutrition data — verify no empty float space
- Test recipe with embedded cross-references — verify cards don't split
- Verify dark mode doesn't affect print output
