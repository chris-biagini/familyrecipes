# Print Stylesheet Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Overhaul print stylesheets so recipes, menus, and grocery lists print as clean, dense, usable kitchen sheets with checkboxes and sensible pagination.

**Architecture:** Pure CSS `@media print` changes in `print.css`, with one minor view change to move the nutrition label before recipe steps so it can float right. Menu and grocery print styles get minor polish.

**Tech Stack:** CSS (print media queries), ERB (one view partial change)

**Spec:** `docs/superpowers/specs/2026-03-26-print-stylesheet-overhaul-design.md`

---

### Task 1: Move nutrition label before recipe steps in the view

The nutrition label must appear before recipe steps in the DOM so CSS
`float: right` can work in print. Wrap it in a `.nutrition-print-wrap` div
that has no screen styles (invisible change on screen).

**Files:**
- Modify: `app/views/recipes/_recipe_content.html.erb`

- [ ] **Step 1: Move the nutrition block before the steps loop**

In `_recipe_content.html.erb`, the nutrition conditional is currently at lines
77-79 (after the steps loop and footer). Move it to just after `</header>`
(after line 64) and wrap it in a div:

```erb
    <%- if current_kitchen.show_nutrition && nutrition && nutrition['totals']&.values&.any? { |v| v.to_f > 0 } -%>
      <div class="nutrition-print-wrap">
        <%= render 'recipes/nutrition_table', nutrition: nutrition %>
      </div>
    <%- end -%>
```

Remove the old nutrition block from lines 77-79.

- [ ] **Step 2: Run tests to verify no breakage**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: All tests pass — this is a markup reorder, not a logic change.

- [ ] **Step 3: Verify in browser that the screen layout is unchanged**

Run: `bin/dev` (if not already running), visit a recipe with nutrition data.
The nutrition label should still appear at the bottom of the recipe on screen
(CSS `margin: 2.5rem auto 0` on `.nutrition-label` positions it). The
`.nutrition-print-wrap` div has no screen styles so it's transparent.

- [ ] **Step 4: Commit**

```bash
git add app/views/recipes/_recipe_content.html.erb
git commit -m "Move nutrition label before steps for print float support (#285)"
```

---

### Task 2: Global print cleanup in print.css

Expand the global `@media print` block to hide all interactive/chrome elements
and fix the blank space issue.

**Files:**
- Modify: `app/assets/stylesheets/print.css`

- [ ] **Step 1: Rewrite print.css with all global and recipe print rules**

Replace the entire contents of `print.css` with:

```css
/********************/
/* Styles for print */
/********************/

/* Recipe pages use 1in/1.5in margins (set here, loaded globally).
   Menu and grocery pages override to 0.5in/0.6in via page-specific
   stylesheets loaded after this one via content_for(:head). */
@media print {
  @page {
    margin: 1in 1.5in;
  }

  html {
    font-size: 12pt;
    margin: 0;
    padding: 0;
    background: white;
  }

  body {
    margin: 0;
    padding: 0;
    background: white;
    color: black;
  }

  /* --- Global hides: interactive chrome --- */
  nav,
  .notify-bar,
  .editor-dialog,
  .search-overlay,
  .app-version,
  #export-actions,
  [data-open-editor] {
    display: none !important;
  }

  /* --- Main content card: strip decoration --- */
  main {
    margin: 0;
    padding: 0;
    border: none;
    background: white;
    box-shadow: none;
    max-width: none;
    min-height: 0;
  }

  main::before {
    display: none;
  }

  /* --- Links: plain black text --- */
  a {
    color: black;
    text-decoration: none;
  }

  /* --- Recipe-specific print styles --- */

  article.recipe {
    font-size: 11pt;
  }

  /* Kill blank space: header margins and decorative rule */
  article.recipe header {
    margin-bottom: 0.5rem;
  }

  article.recipe header::after {
    display: none;
  }

  article.recipe header h1 {
    font-size: 2rem;
    margin: 0 0 0.25rem;
  }

  article.recipe header p {
    font-size: 1rem;
    margin-top: 0;
  }

  /* Hide interactive elements */
  .scale-bar,
  .recipe-actions,
  .recipe-tags {
    display: none !important;
  }

  /* --- Compact spacing --- */
  article.recipe section {
    margin-top: 1.5rem;
  }

  article.recipe section h2 {
    margin-bottom: 0.5rem;
  }

  article.recipe .instructions p {
    line-height: 1.5;
  }

  article.recipe footer {
    margin-top: 2rem;
    padding-top: 1rem;
  }

  article.recipe footer::after {
    display: none;
  }

  /* --- Checkbox bullets on ingredients --- */
  .ingredients li::before {
    content: "";
    display: inline-block;
    width: 0.7rem;
    height: 0.7rem;
    border: 1px solid black;
    border-radius: 1px;
    margin-right: 0.4rem;
    vertical-align: middle;
    position: relative;
    top: -0.05em;
  }

  /* --- Checkbox bullets on instruction paragraphs --- */
  .instructions p::before {
    content: "";
    float: left;
    width: 0.7rem;
    height: 0.7rem;
    border: 1px solid black;
    border-radius: 1px;
    margin: 0.25em 0.4rem 0 0;
  }

  /* --- Checkbox bullets on section headings --- */
  article.recipe section h2::before,
  article.recipe section h3::before {
    content: "";
    display: inline-block;
    width: 0.7rem;
    height: 0.7rem;
    border: 1px solid black;
    border-radius: 1px;
    margin-right: 0.4rem;
    vertical-align: middle;
    position: relative;
    top: -0.05em;
  }

  /* --- Nutrition label: float right alongside recipe content --- */
  .nutrition-print-wrap {
    float: right;
    width: 14rem;
    margin: 0 0 1rem 1.5rem;
    break-inside: avoid;
  }

  .nutrition-print-wrap .nutrition-label {
    width: 100%;
    margin: 0;
    background: white;
    color: black;
    border-color: black;
  }

  .nutrition-print-wrap .nutrition-label .serving-size,
  .nutrition-print-wrap .nutrition-label .calories-row,
  .nutrition-print-wrap .nutrition-label .dv-header,
  .nutrition-print-wrap .nutrition-label .nutrient-row,
  .nutrition-print-wrap .nutrition-label .nutrient-row:last-child {
    border-color: black;
  }

  .nutrition-print-wrap .nutrition-footnote {
    max-width: none;
    color: black;
  }

  article.recipe::after {
    content: "";
    display: block;
    clear: both;
  }

  /* --- Pagination --- */
  article.recipe section {
    break-inside: avoid;
  }

  article.recipe section:first-of-type {
    break-before: avoid;
  }

  article.recipe section h2,
  article.recipe section h3 {
    break-after: avoid;
  }

  .embedded-recipe {
    break-inside: avoid;
    box-shadow: none;
    border: 1px solid #ccc;
  }

  /* Embedded recipe headings are informational, not actionable steps */
  .embedded-recipe h3::before {
    content: none;
  }

  /* Hide "go to recipe" links on embedded recipes */
  .embedded-recipe-link {
    display: none;
  }

  /* Scaled quantity highlight: transparent in print */
  .scalable.scaled {
    background-color: transparent;
  }
}
```

- [ ] **Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass — CSS-only change.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/print.css
git commit -m "Overhaul recipe print styles: fix blank page, add checkboxes, float nutrition (#285)"
```

---

### Task 3: Menu print style polish

Verify and tighten the menu page print styles.

**Files:**
- Modify: `app/assets/stylesheets/menu.css`

- [ ] **Step 1: Add @page comment and verify break-inside**

At the top of the `@media print` block in `menu.css` (around line 399), add
a comment explaining the `@page` override:

```css
@media print {
  /* Override global 1in/1.5in margins from print.css — menu is denser */
  @page {
    margin: 0.5in 0.6in;
  }
```

Verify that `.category` has `break-inside: avoid` (it does, at line 442).
No other changes needed — the menu print styles are already solid.

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/menu.css
git commit -m "Add @page margin comment to menu print styles (#285)"
```

---

### Task 4: Grocery print style polish

Verify and tighten the grocery page print styles.

**Files:**
- Modify: `app/assets/stylesheets/groceries.css`

- [ ] **Step 1: Add @page comment and aisle header orphan prevention**

At the top of the `@media print` block in `groceries.css` (around line 299),
add a comment explaining the `@page` override:

```css
@media print {
  /* Override global 1in/1.5in margins from print.css — groceries is denser */
  @page {
    margin: 0.5in 0.6in;
  }
```

Add `break-after: avoid` to `.aisle-header` to prevent orphaned headers:

```css
  .aisle-header {
    padding: 0.2rem 0;
    break-after: avoid;
  }
```

This replaces the existing `.aisle-header` rule (currently at line 356-358)
by adding `break-after: avoid` to the existing `padding` rule.

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/groceries.css
git commit -m "Add @page comment and aisle header orphan prevention to grocery print styles (#285)"
```

---

### Task 5: Run lint and full test suite

**Files:** None (verification only)

- [ ] **Step 1: Run RuboCop**

Run: `bundle exec rubocop`
Expected: 0 offenses. The only non-CSS file changed was the ERB partial.

- [ ] **Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass.

- [ ] **Step 3: Run html_safe lint**

Run: `rake lint:html_safe`
Expected: Pass — no new `.html_safe` or `raw()` calls added.

- [ ] **Step 4: Verify print preview in browser**

Start the dev server (`bin/dev`) and check print preview (Ctrl+P) for:

1. **Recipe page** — no blank space before title, checkboxes on ingredients /
   instructions / headings, nutrition label floated right, pagination breaks
   between sections, no interactive elements visible
2. **Menu page** — selected items in 2-column grid, no interactive elements
3. **Grocery page** — 4-column grid, checkbox squares, no interactive elements

- [ ] **Step 5: Final commit if any fixes needed**

Only if lint or preview revealed issues that needed fixing.
