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
- No new HTML elements or view changes — work within existing markup

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
`::before` on `.ingredients li`. For instructions and headings, prepend a
checkbox via `::before` with appropriate spacing.

Checkbox style: `1px solid black`, `0.7rem` square, `border-radius: 1px`,
inline with text via `vertical-align` or flexbox alignment.

#### 1d. Nutrition label float

Float `.nutrition-label` to the right so recipe content flows beside it:

```
.nutrition-label {
  float: right;
  width: 14rem;
  margin: 0 0 1rem 1.5rem;
}
```

Reduce from the screen `max-width: 16rem` to `14rem` to leave more room for
text flow. Clear the float after the article.

The `.nutrition-footnote` below the label should also float right or be
positioned to stay with the label. Use a wrapping container or make the
footnote follow the label's float.

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
- `font-size: 11pt` (slightly smaller than current 12pt) for density
- Tighter line-height on instructions: `1.5` instead of `1.75`
- Reduce section margins/padding for compactness
- `header h1` at a smaller print size (e.g., `2rem` instead of `3.8rem`)

#### 1g. Embedded recipes

- Strip `box-shadow` (already done) and `border` to a simple `1px solid #ccc`
- Maintain `break-inside: avoid`
- `.embedded-recipe-link` (arrow to full recipe) — hide in print

#### 1h. Recipe footer

Keep the recipe footer visible but strip decorative styling (the `::after`
pseudo-element rule line above it). Tighten margins.

#### 1i. Crossed-off state

In print, ignore crossed-off state — show all items without strikethrough or
fade. Users print fresh copies to work with.

### 2. Menu Page — menu.css

The menu print styles are already good. Minor improvements:

- Hide help links and contextual help icons
- Verify `break-inside: avoid` on `.category` blocks prevents orphaned headers
- The two-column grid layout is already in place

No structural changes needed.

### 3. Groceries Page — groceries.css

The grocery print styles are the most polished. Minor improvements:

- Verify aisle headers don't orphan from their item lists
  (`break-after: avoid` on `.aisle-header` if not already present)
- Hide help links and contextual help icons

No structural changes needed.

### 4. Global print.css

Consolidate global hide rules and add missing ones:

**Currently hidden:** `nav`, `.notify-bar`, `.editor-dialog`, `#export-actions`

**Add to hidden list:**
- `.app-version` (footer version text)
- `.search-overlay` (search dialog)
- `#settings-dialog` (settings dialog)
- Any help icons/links that aren't caught by hiding `nav`

**Dark mode in print:** Force nutrition label to white bg / black borders
regardless of `prefers-color-scheme`. The label's dark mode styles use CSS
custom properties — override with explicit `#000` / `#fff` in the print block.

**Scalable quantity highlight:** Already handled — `.scalable.scaled` gets
`background-color: transparent`. Keep this.

### 5. Summary of Files Changed

| File | Scope |
|------|-------|
| `app/assets/stylesheets/print.css` | Major — all recipe print rules, global hides |
| `app/assets/stylesheets/menu.css` | Minor — add missing hides |
| `app/assets/stylesheets/groceries.css` | Minor — verify orphan prevention |

No view files, JavaScript, or controller changes.

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
