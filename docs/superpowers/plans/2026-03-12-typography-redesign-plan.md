# Typography Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Retheme the site's typography and visual style from gingham-check with Futura/Source Sans to a quieter, warm, typographically rich design using Instrument Serif + Outfit.

**Architecture:** CSS-only retheme across three stylesheets (`style.css`, `menu.css`, `groceries.css`) plus two infrastructure changes (CSP + layout). No HTML template changes, no JavaScript changes. The V4 reference mockup at `public/typography/redesign/v4-quiet-lux.html` is the visual target.

**Tech Stack:** CSS custom properties, Google Fonts (Instrument Serif, Outfit), Rails CSP configuration.

**Design spec:** `docs/plans/2026-03-12-typography-redesign-spec.md`

**Design decisions (resolved):**
- Desktop recipe list columns: **2** (not 3)
- Nav background: **solid** (no frosted glass)
- Nav animated underline: **drop it**

---

## Conventions

- **No tests** — this is a CSS-only retheme. Verification is `rake lint` + visual inspection.
- **Breakpoints** — use `720px` everywhere (not 600px from the V4 mockup).
- **`--font-display` rule** — only for large display text: page titles (`h1`), step headers (`h2` in recipes), site name in nav, recipe descriptions. Everything else (section headers, labels, nav links, buttons, form elements, editor chrome) uses `--font-body`.
- **Variable strategy** — define new canonical tokens (`--ground`, `--text`, `--text-soft`, `--text-light`, `--red`, `--red-light`, `--rule`, `--rule-faint`), then redefine old variables as aliases pointing at the new tokens. This way all existing CSS rules pick up new values without find-and-replace. In the cleanup task, sweep through and replace old names with new ones, then delete the aliases.

---

### Task 0: CSP and font loading

The CSP is strictly `:self` for all directives. Google Fonts requires `fonts.googleapis.com` in `style_src` and `fonts.gstatic.com` in `font_src`.

**Files:**
- Modify: `config/initializers/content_security_policy.rb`
- Modify: `app/views/layouts/application.html.erb`

**Step 1: Update CSP**

In `config/initializers/content_security_policy.rb`, add the Google Fonts domains:

```ruby
policy.style_src   :self, 'https://fonts.googleapis.com'
policy.font_src    :self, 'https://fonts.gstatic.com'
```

**Step 2: Add font `<link>` tags to layout**

In `app/views/layouts/application.html.erb`, add after the `<meta>` tags and before `<title>`:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=Outfit:wght@300;400;500;600&display=swap" rel="stylesheet">
```

**Step 3: Update theme-color meta tags**

Change `rgb(205, 71, 84)` → `#b33a3a` (light) and `rgb(30, 24, 22)` → `#1e1b18` (dark).

**Step 4: Restart Puma** (CSP initializer change requires restart)

```bash
pkill -f puma; rm -f tmp/pids/server.pid
bin/dev &
```

**Step 5: Run `rake lint` and commit**

---

### Task 1: Root variables and base typography

Replace font stacks, define new color tokens, alias old variables, remove gingham/weave variables.

**Files:**
- Modify: `app/assets/stylesheets/style.css` (`:root` block, lines 23–80)

**Step 1: Replace font variables**

```css
--font-display: "Instrument Serif", Georgia, serif;
--font-body: "Outfit", system-ui, sans-serif;
/* --font-mono stays unchanged */
```

**Step 2: Add new canonical color tokens** (after font variables)

```css
/* Canonical color tokens */
--ground: #faf8f5;
--text: #2d2a26;
--text-soft: #706960;
--text-light: #a09788;
--red: #b33a3a;
--red-light: rgba(179, 58, 58, 0.08);
--rule: #e4dfd8;
--rule-faint: #eee9e3;
```

**Step 3: Redefine old variables as aliases**

```css
--border-color: var(--text);
--text-color: var(--text);
--content-background-color: var(--ground);
--frosted-glass-bg: var(--ground);

--checked-color: var(--red);
--muted-text: var(--text-soft);
--muted-text-light: var(--text-light);
--border-light: var(--rule-faint);
--border-muted: var(--rule);
--separator-color: var(--rule);
--surface-alt: #f5f2ee;
--danger-color: #c00;
--accent-color: var(--red);
--on-hand-color: var(--red);
--missing-color: var(--red);
--hover-bg: var(--red-light);

--input-bg: white;
--accent-hover: #993030;
--overscroll-color: var(--ground);
```

**Step 4: Remove all `--gingham-*` and `--weave-*` variable definitions**

Delete lines defining: `--gingham-base`, `--gingham-stripe-color`, `--gingham-stripe-width`, `--gingham-tile-size`, `--weave-color`, `--weave-stripe-width`.

**Step 5: Run `rake lint` and commit**

---

### Task 2: Body, HTML, and main restructure

Remove gingham background, add red line, remove card from `main`, fix body padding.

**Files:**
- Modify: `app/assets/stylesheets/style.css` (`html`, `body`, `main` rules)

**Step 1: Replace `html` background**

Remove the entire `background-color`, `background-attachment`, `background-size`, `background-image` block (lines ~161–199). Replace with:

```css
background-color: var(--ground);
```

Keep `color-scheme: light dark`, `font-size: 18px`, and `touch-action: manipulation`.

**Step 2: Update `body`**

Remove side-padding. Add line-height. Remove `--breathing-room` from padding:

```css
body {
  padding: env(safe-area-inset-top, 0px) 0 0;
  font-family: var(--font-body);
  color: var(--text-color);
  line-height: 1.65;
}
```

**Step 3: Add `body::before` red line**

```css
body::before {
  content: "";
  display: block;
  height: 2px;
  background: var(--red);
}
```

**Step 4: Remove card from `main`**

Replace the `main` block (lines ~574–584) with:

```css
main {
  max-width: 35rem;
  margin: 0 auto;
  padding: 3rem 1.5rem 5rem;
}
```

Remove: `border`, `background-color`, `border-radius`, `box-shadow`. The `margin: var(--breathing-room) auto` becomes `margin: 0 auto`.

**Step 5: Remove `--breathing-room` variable definition**

Delete `--breathing-room: 3rem;` from `:root`. Also delete the two mobile overrides:
- `@media (max-width: 720px) and (pointer: coarse)` → remove `--breathing-room: 0.75rem;`
- `@media (max-width: 720px)` → remove `--breathing-room: 1.5rem;`

**Step 6: Update mobile `main` padding**

In the `@media (max-width: 720px)` block, change `main { padding: 1.5rem; }` to:

```css
main { padding: 1.5rem 1rem 3rem; }
```

**Step 7: Run `rake lint` and commit**

---

### Task 3: Nav retheme

Solid background, new fonts, remove animated underline, remove negative margin.

**Files:**
- Modify: `app/assets/stylesheets/style.css` (nav rules, lines ~245–549)

**Step 1: Remove negative margin from `nav`**

Change `margin: 0 calc(-1 * var(--breathing-room));` → `margin: 0;`

**Step 2: Update nav border**

Change `border-bottom: 1px solid var(--gingham-stripe-color);` → `border-bottom: 1px solid var(--rule);`

**Step 3: Replace frosted glass with solid background**

Remove the entire `nav::before` pseudo-element (lines ~261–272). Add to the `nav` rule:

```css
background-color: var(--ground);
```

**Step 4: Restyle nav links**

Change the `nav a` rule from display font to body font:

```css
nav a {
  font-family: var(--font-body);
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  text-decoration: none;
  font-weight: 500;
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  padding: 0.5rem 0.9rem;
  line-height: 1.5;
  color: var(--text-light);
  transition: color 0.2s ease;
  position: relative;
}
```

**Step 5: Style the site name (Recipes link) with display font**

Add a new rule for the home link:

```css
nav a.recipes {
  font-family: var(--font-display);
  font-size: 1.1rem;
  font-weight: 400;
  text-transform: none;
  letter-spacing: normal;
  color: var(--text-color);
  margin-right: auto;
}
```

**Step 6: Remove animated underline**

Delete the `nav a::after` rule (lines ~298–308) and the `nav a:hover::after, nav a:focus::after` rule (lines ~310–313). Add a simple hover:

```css
nav a:hover {
  color: var(--red);
}
```

**Step 7: Update `.nav-auth-btn`**

Change `font-family: var(--font-display)` → `font-family: var(--font-body)` and match the new nav link styling (0.72rem, weight 500, etc.).

**Step 8: Update drawer border**

In `.nav-hamburger .nav-drawer` (line ~534), change `border-bottom: 1px solid var(--gingham-stripe-color)` → `border-bottom: 1px solid var(--rule)`. Add `background-color: var(--ground);` to the drawer.

**Step 9: Run `rake lint` and commit**

---

### Task 4: Recipe content

Headers, step grid, ingredients, footer dingbat removal.

**Files:**
- Modify: `app/assets/stylesheets/style.css` (header, section, ingredients, footer rules)

**Step 1: Update `header h1`**

```css
header h1 {
  font-family: var(--font-display);
  font-size: 3.8rem;
  font-weight: 400;
  line-height: 1.05;
  letter-spacing: -0.01em;
  margin: 0 0 0.5rem 0;
}
```

At the 720px breakpoint, add: `header h1 { font-size: 2.6rem; }`

**Step 2: Style recipe description with display italic**

`header p` — add `font-family: var(--font-display)` to the existing rule. Keep italic. Update `color: var(--text-soft)`.

**Step 3: Style recipe meta line**

`header .recipe-meta` — update to small uppercase body font:

```css
header .recipe-meta {
  font-style: normal;
  font-family: var(--font-body);
  font-size: 0.72rem;
  font-weight: 500;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  margin-top: 1rem;
  color: var(--text-light);
}
```

**Step 4: Add 40px red divider after recipe header**

```css
header::after {
  content: "";
  display: block;
  width: 40px;
  height: 1px;
  background: var(--red);
  margin: 1.5rem auto 0;
}
```

Suppress on non-recipe pages where header shouldn't have it:
```css
.homepage header::after,
.index header::after,
.settings-page header::after,
.login header::after,
.ingredients-page header::after {
  display: none;
}
```

**Step 5: Update step headers (category `section h2`)**

The `section h2` selector (line ~677) is shared between recipe step headers and homepage/index category headers. Recipe step headers (`h2` inside a `.recipe` section) should use display font. Category headers elsewhere should use body font. Current CSS has:

```css
section h2 { font-family: var(--font-display); font-size: 1.25rem; ... }
.homepage section h2, .index section h2 { font-size: 1.1rem; ... }
```

Change `section h2` to the recipe step header style:

```css
section h2 {
  font-family: var(--font-display);
  font-size: 1.4rem;
  font-weight: 400;
  line-height: 1.35;
  text-transform: none;
  letter-spacing: normal;
  margin-top: 3.5rem;
  margin-bottom: 1.25rem;
  border-bottom: none;
  padding-bottom: 0;
}

section:first-of-type h2 {
  margin-top: 0;
}
```

Override for homepage/index category headers (body font, small uppercase):

```css
.homepage section h2,
.index section h2 {
  font-family: var(--font-body);
  font-size: 0.68rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.2em;
  color: var(--text-light);
  margin: 3rem 0 0.9rem;
  padding-bottom: 0.7rem;
  border-bottom: 1px solid var(--rule-faint);
}

.homepage section:first-of-type h2,
.index section:first-of-type h2 {
  margin-top: 0;
}
```

**Step 6: Update ingredient/instruction grid**

`section > div:has(.ingredients):has(.instructions)` — change `gap: 2rem` → `gap: 0 2.5rem`.

Add instruction border:

```css
.instructions {
  border-left: 1px solid var(--rule-faint);
  padding-left: 2rem;
}
```

Update the mobile override for `.instructions` at 720px:

```css
@media (max-width: 720px) {
  .instructions {
    border-left: none;
    padding-left: 0;
    padding-top: 0.5rem;
    border-top: 1px solid var(--rule-faint);
  }
}
```

**Step 7: Style ingredient list items**

```css
.ingredients li {
  break-inside: avoid;
  padding: 0;
  font-size: 0.84rem;
  line-height: 2;
}
```

The `.ingredient-name` (bold) stays weight 400 (inherits), and `.quantity` gets:

```css
.quantity {
  color: var(--text-light);
  font-weight: 300;
}
```

**Step 8: Remove `footer:before` dingbat**

Change `footer:before { content: "❇︎"; }` to `footer::before { display: none; }`.

Note: `.nutrition-label footer::before { content: none; }` and `.app-version::before { content: none; }` can stay as-is (redundant but harmless).

**Step 9: Style recipe footer as source note**

```css
footer {
  font-family: var(--font-display);
  font-style: italic;
  text-align: center;
  font-size: 1rem;
  margin-top: 3.5rem;
  padding-top: 2rem;
  color: var(--text-light);
  position: relative;
}

footer::after {
  content: "";
  display: block;
  width: 40px;
  height: 1px;
  background: var(--rule);
  position: absolute;
  top: 0;
  left: 50%;
  transform: translateX(-50%);
}
```

Suppress on `.app-version` footer:

```css
.app-version::after {
  display: none;
}
```

**Step 10: Run `rake lint` and commit**

---

### Task 5: Homepage/TOC

Category headers, recipe lists (2 columns), toc nav.

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Update `.toc_nav`**

Remove borders. Style as centered inline list with middot separators:

```css
.toc_nav {
  text-align: center;
  margin-bottom: 3rem;
  padding: 0;
  border: none;
}

.toc_nav ul li a {
  font-style: normal;
  font-size: 0.84rem;
  color: var(--text-light);
  text-decoration: none;
  transition: color 0.2s;
}

.toc_nav ul li a:hover {
  color: var(--red);
}
```

**Step 2: Update recipe list column count**

Change `section > ul { column-count: 3; }` → `column-count: 2;`

Add column-gap and update link styles:

```css
section > ul {
  column-count: 2;
  column-gap: 2.5rem;
  list-style: none;
  padding-left: 0;
}
```

Mobile (720px) stays at `column-count: 2` — no change needed.

**Step 3: Run `rake lint` and commit**

---

### Task 6: Menu page

**Files:**
- Modify: `app/assets/stylesheets/menu.css`

**Step 1: Change all `--font-display` → `--font-body`**

Five instances in menu.css, all are section headers/labels — ALL change to `--font-body`:
- Line 57: `#recipe-selector .category h2`
- Line 145: `.availability-detail summary`
- Line 227: `.availability-ingredients-inner`
- Line 275: `#recipe-selector .quick-bites > h2`
- Line 298: `#recipe-selector .quick-bites .subsection h3`

**Step 2: Update Quick Bites separator**

Line 271: `border-top: 2px solid var(--separator-color)` — already aliased via `:root`, but update to `1px solid var(--rule)` for the thinner aesthetic.

**Step 3: Update menu actions separator**

Line 344: `border-top: 2px solid var(--separator-color)` → `1px solid var(--rule)`.

**Step 4: Run `rake lint` and commit**

---

### Task 7: Groceries page

**Files:**
- Modify: `app/assets/stylesheets/groceries.css`

**Step 1: Change `--font-display` → `--font-body`**

Two instances — both are aisle headers:
- Line 133: `.shopping-list-header h2`
- Line 167: `#shopping-list details.aisle > summary`

**Step 2: Update custom items separator**

Line 42: `border-top: 2px solid var(--separator-color)` → `1px solid var(--rule)`.

**Step 3: Run `rake lint` and commit**

---

### Task 8: Ingredients page

**Files:**
- Modify: `app/assets/stylesheets/style.css` (ingredients table section)

**Step 1: Update `.ingredients-table thead th` font**

Line 747: Change `font-family: var(--font-display)` → `font-family: var(--font-body)`.

**Step 2: Run `rake lint` and commit**

---

### Task 9: Editor dialogs

**Files:**
- Modify: `app/assets/stylesheets/style.css` (editor section)

**Step 1: Change `--font-display` → `--font-body` in all editor chrome**

Four instances:
- Line 1348: `.editor-header h2`
- Line 1369: `.editor-errors`
- Line 1861: `.editor-section-title`
- Line 1894: `.editor-collapse-header > summary`

**Step 2: Run `rake lint` and commit**

---

### Task 10: Search overlay

**Files:**
- Modify: `app/assets/stylesheets/style.css` (search overlay section)

**Step 1: Update selected result highlight**

Line 1293: `.search-result.selected` — the `background: var(--accent-color)` is already aliased to `var(--red)` via `:root`. No change needed.

**Step 2: Verify search panel colors**

`.search-panel` background uses `--content-background-color` (now aliased to `--ground`). The `border-top` on `.search-results` uses `--separator-color` (now aliased to `--rule`). Both should look correct. No changes needed.

**Step 3: Commit** (if any changes were needed, otherwise skip)

---

### Task 11: Settings, login, notifications

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Change `--font-display` → `--font-body` in settings and login**

Five instances:
- Line 807: `.settings-page h1` — **KEEP** `--font-display` (page title)
- Line 816: `.settings-section h2` — CHANGE to `--font-body`
- Line 833: `.settings-field label` — CHANGE to `--font-body`
- Line 1803: `.login-field label` — CHANGE to `--font-body`

**Step 2: Update notification toast**

- Line 1745: Change `border-top: 1px solid var(--gingham-stripe-color)` → `border-top: 1px solid var(--rule)`
- Line 1747: Change `font-family: var(--font-display)` → `font-family: var(--font-body)`

**Step 3: Run `rake lint` and commit**

---

### Task 12: Embedded recipe cards

**Files:**
- Modify: `app/assets/stylesheets/style.css` (embedded recipe section, lines ~2529–2620)

**Step 1: Update `.embedded-recipe` styles**

Keep the "paper on paper" effect but soften. The variables are already aliased so `--border-color`, `--content-background-color`, `--shadow-sm` pick up new values automatically. Minimal CSS changes needed.

**Step 2: Change `.embedded-recipe section h3` font**

Line 2599: `font-family: var(--font-display)` → `font-family: var(--font-body)`.

**Step 3: Run `rake lint` and commit**

---

### Task 13: Dark mode

Full pass through the `@media (prefers-color-scheme: dark)` block in `:root`.

**Files:**
- Modify: `app/assets/stylesheets/style.css` (dark mode block, lines ~82–134)

**Step 1: Add dark-mode canonical tokens**

```css
--ground: #1e1b18;
--text: #dcd7d0;
--text-soft: #a09788;
--text-light: #706960;
--red: #c85050;
--red-light: rgba(200, 80, 80, 0.12);
--rule: #3a3530;
--rule-faint: #2e2a26;
```

**Step 2: Update dark-mode aliases**

```css
--border-color: var(--rule);
--text-color: var(--text);
--frosted-glass-bg: var(--ground);
--content-background-color: var(--ground);

--checked-color: var(--red);
--muted-text: var(--text-soft);
--muted-text-light: var(--text-light);
--border-light: var(--rule-faint);
--border-muted: var(--rule);
--separator-color: var(--rule);
--surface-alt: #252220;
--danger-color: #d05050;
--accent-color: var(--red);
--on-hand-color: var(--red);
--missing-color: var(--red);
--hover-bg: rgba(255, 255, 255, 0.04);

--input-bg: #1a1816;
--accent-hover: #a03838;
--overscroll-color: var(--ground);
```

**Step 3: Remove dark-mode gingham/weave variables**

Delete `--gingham-base`, `--gingham-stripe-color`, `--weave-color` from the dark block.

**Step 4: Verify FDA nutrition label**

The nutrition label uses hard-coded `#000`/`#fff` colors and Helvetica. The existing dark-mode override (if any) should be preserved. Check that no new tokens break it.

**Step 5: Run `rake lint` and commit**

---

### Task 14: Print styles

**Files:**
- Modify: `app/assets/stylesheets/style.css` (`@media print` block)

**Step 1: Verify print styles**

Print already strips backgrounds, shadows, borders and sets `background: white; color: black;`. Font-family changes should be harmless since print uses system rendering. Check that the gingham background removal doesn't create issues (it shouldn't — print already overrides to `background: none`).

**Step 2: Commit** (if any changes needed)

---

### Task 15: Cleanup

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Remove Source Sans 3 `@font-face` declarations**

Delete the two `@font-face` blocks at the top of `style.css` (lines 7–21).

**Step 2: Remove `--breathing-room` variable**

If any remaining references to `--breathing-room` exist, remove them. Should be clean after Task 2.

**Step 3: Remove dead gingham-related comments**

Delete the gingham-inspired-by comments (lines ~242–243).

**Step 4: Sweep old variable names → new token names**

Do a find-and-replace pass across all three CSS files:
- `var(--text-color)` → `var(--text)`
- `var(--muted-text)` → `var(--text-soft)` (but NOT `--muted-text-light`)
- `var(--muted-text-light)` → `var(--text-light)`
- `var(--border-light)` → `var(--rule-faint)`
- `var(--border-muted)` → `var(--rule)`
- `var(--separator-color)` → `var(--rule)`
- `var(--accent-color)` → `var(--red)`
- `var(--content-background-color)` → `var(--ground)`
- `var(--border-color)` → `var(--text)` (for high-contrast borders) or `var(--rule)` (for dividers) — case by case

Then remove the alias definitions from `:root` and the dark-mode block.

**Step 5: Remove unused `.aisle-name` font reference**

Line 1598: `.aisle-name` uses `--font-display` — change to `--font-body`.

**Step 6: Run `rake lint`**

**Step 7: Run `rake test` to verify nothing is broken**

**Step 8: Commit**

---

## Final verification

After all tasks complete:

1. `rake lint` — 0 offenses
2. `rake test` — all passing
3. Visual check of: homepage, recipe page, menu page, groceries page, settings page, ingredients page, search overlay, editor dialogs
4. Dark mode check on all pages
5. Mobile layout check at 720px breakpoint
6. Print layout check (Cmd+P preview)
