# Menu Page Visual Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Restyle the menu page's availability indicators, hover states, and checkbox colors to match a warm 1960s cookbook aesthetic.

**Architecture:** Pure CSS + template changes. No new controllers, models, or JS. Replace Unicode glyphs with inline SVGs, update color variables, restructure the expanded ingredient detail markup from a comma dump into labeled Have/Missing lines.

**Tech Stack:** ERB templates, CSS custom properties, inline SVG

---

### Task 1: Update color variables in style.css

**Files:**
- Modify: `app/assets/stylesheets/style.css:25` (`--checked-color` variable)

**Step 1: Change the checked-color variable**

Replace `--checked-color: #2a5a3a` with `--checked-color: rgb(155, 10, 25)` (the existing `--accent-color`). This changes checkbox fill color site-wide from green to accent red.

Add two new variables for availability:
```css
--on-hand-color: #b8860b;
--missing-color: #996;
--hover-bg: #f5efe8;
```

**Step 2: Run tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -v`
Expected: All pass (color changes don't affect test assertions)

**Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "style: warm color palette for availability indicators"
```

---

### Task 2: Update hover states in menu.css

**Files:**
- Modify: `app/assets/stylesheets/menu.css:74-79` (recipe hover)
- Modify: `app/assets/stylesheets/menu.css:253-258` (quick bite hover)

**Step 1: Update recipe row hover**

Replace the current hover rule for `.category li:hover`:
```css
#recipe-selector .category li:hover {
  background-color: var(--hover-bg);
  margin: 0 -0.5rem;
  padding-left: calc(0.5rem - 2px);
  padding-right: 0.5rem;
  border-left: 2px solid var(--accent-color);
}
```

Apply the same pattern to `.quick-bites .subsection li:hover`.

**Step 2: Verify visually in browser**

Navigate to `http://localhost:3030/menu`, hover over recipe rows. Should see warm cream background + red left border.

**Step 3: Commit**

```bash
git add app/assets/stylesheets/menu.css
git commit -m "style: stronger hover state with warm background and accent border"
```

---

### Task 3: Replace Unicode glyphs with SVGs in template

**Files:**
- Modify: `app/views/menu/_recipe_selector.html.erb:14,17,47,50` (glyph locations)

**Step 1: Define the SVG snippets**

Filled circle (on-hand):
```html
<svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><circle cx="5" cy="5" r="4.5" fill="currentColor"/></svg>
```

Open circle (missing):
```html
<svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><circle cx="5" cy="5" r="3.5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg>
```

**Step 2: Replace in recipe section**

Line 14: Replace `<%= info[:missing].zero? ? "\u2713" : "\u2717" %>` with the appropriate SVG based on `info[:missing].zero?`.

Line 17: Replace `&#10003;` (all-on-hand summary) with the filled circle SVG.

**Step 3: Replace in quick bites section**

Lines 47 and 50: Same replacements as above.

**Step 4: Update tests**

In `test/controllers/menu_controller_test.rb`:
- Line 101: Change `text: "\u2717"` to `assert_select 'span.availability-single.not-on-hand svg'`
- Line 113: Change `text: "\u2713"` to `assert_select 'span.availability-single.on-hand svg'`
- Line 127: Change `text: /\u2713/` to `assert_select 'details.availability-detail.all-on-hand summary svg'`

**Step 5: Run tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -v`
Expected: All pass

**Step 6: Commit**

```bash
git add app/views/menu/_recipe_selector.html.erb test/controllers/menu_controller_test.rb
git commit -m "feat: replace Unicode glyphs with geometric SVG indicators"
```

---

### Task 4: Restyle availability badges and detail in menu.css

**Files:**
- Modify: `app/assets/stylesheets/menu.css:102-195` (availability section)

**Step 1: Update availability-single colors**

```css
.availability-single.on-hand {
  color: var(--on-hand-color);
}

.availability-single.not-on-hand {
  color: var(--missing-color);
}
```

**Step 2: Update availability-detail badge styling**

Add `font-family: "Futura", sans-serif` to `.availability-detail summary`. Update colors:
- Default summary text/border: use `--missing-color`
- `.all-on-hand summary`: use `--on-hand-color`
- Triangle `::before` border colors: update to match

**Step 3: Restyle expanded ingredient detail**

```css
.availability-ingredients {
  display: none;
  font-family: "Futura", sans-serif;
  font-size: 0.8rem;
  font-style: normal;
  color: var(--missing-color);
  padding: 0.4rem 0;
  flex-basis: 100%;
  padding-left: 1.6rem;
}

.availability-have {
  color: var(--on-hand-color);
}

.availability-need {
  color: var(--missing-color);
}
```

**Step 4: Add label styling for Have/Missing**

In the template, the labels "Have:" and "Missing:" need a `<strong>` wrapper. Add CSS:

```css
.availability-have strong,
.availability-need strong {
  font-family: "Futura", sans-serif;
  font-size: 0.65rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  margin-right: 0.3rem;
}
```

**Step 5: Update template for labeled lines**

In `_recipe_selector.html.erb`, change the Have/Missing lines from:
```erb
<div class="availability-have">Have: <%= have.join(', ') %></div>
<div class="availability-need">Missing: <%= info[:missing_names].join(', ') %></div>
```
to:
```erb
<div class="availability-have"><strong>Have</strong> <%= have.join(', ') %></div>
<div class="availability-need"><strong>Missing</strong> <%= info[:missing_names].join(', ') %></div>
```

Apply same change in quick bites section.

**Step 6: Run tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -v`
Expected: All pass (test assertions check class names and ingredient text, not label format)

**Step 7: Verify visually**

Check expanded detail: Futura font, harvest gold "HAVE" label, warm muted "MISSING" label, clean spacing.

**Step 8: Commit**

```bash
git add app/assets/stylesheets/menu.css app/views/menu/_recipe_selector.html.erb
git commit -m "style: warm 1960s cookbook aesthetic for availability detail"
```

---

### Task 5: Run full test suite and lint

**Step 1: Run lint**

Run: `bundle exec rubocop`
Expected: 0 offenses

**Step 2: Run full tests**

Run: `rake test`
Expected: All pass

**Step 3: Run html_safe lint**

Run: `rake lint:html_safe`
Expected: Pass (no new .html_safe calls)

**Step 4: Visual check**

Take screenshots of:
- Menu page at desktop width
- Menu page with expanded availability detail
- Menu page hover state
- A recipe with "all on hand" state if possible

**Step 5: Final commit if any fixes needed**

```bash
git add -A
git commit -m "polish: menu visual refresh final adjustments"
```
