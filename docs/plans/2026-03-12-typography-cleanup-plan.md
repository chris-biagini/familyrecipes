# Typography Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace Bodoni 72 with Source Sans 3 for body text, consolidate all font-family declarations into CSS custom properties.

**Architecture:** Self-host Source Sans 3 WOFF2 files in `public/fonts/`, add `@font-face` rules to `style.css`, define three `--font-*` custom properties, replace all 33 scattered `font-family` declarations with variable references.

**Tech Stack:** CSS `@font-face`, CSS custom properties, Propshaft (static files in `public/`)

---

### Task 1: Download and install Source Sans 3 font files

**Files:**
- Create: `public/fonts/source-sans-3/SourceSans3-Regular.woff2`
- Create: `public/fonts/source-sans-3/SourceSans3-Italic.woff2`
- Create: `public/fonts/source-sans-3/SourceSans3-SemiBold.woff2`
- Create: `public/fonts/source-sans-3/SourceSans3-Bold.woff2`
- Create: `public/fonts/source-sans-3/OFL.txt`

**Step 1: Create directory and download fonts**

```bash
mkdir -p public/fonts/source-sans-3

# Download from Google Fonts' github repo (canonical WOFF2 source)
curl -L -o public/fonts/source-sans-3/SourceSans3-Regular.woff2 \
  "https://github.com/google/fonts/raw/main/ofl/sourcesans3/SourceSans3%5Bwght%5D.woff2"
```

If the variable font isn't available as individual weights, download individual
static WOFF2 files from the Google Fonts CSS API:

```bash
# Alternative: extract URLs from Google Fonts CSS
curl -sH "User-Agent: Mozilla/5.0" \
  "https://fonts.googleapis.com/css2?family=Source+Sans+3:ital,wght@0,400;0,600;0,700;1,400&display=swap" \
  | grep -oP 'url\(\K[^)]+' \
  | while read url; do echo "$url"; done
```

Download each URL to the corresponding file. The exact URLs will come from the
CSS response — save each to its weight-named file.

**Step 2: Add OFL license**

Download the license from the source repo:

```bash
curl -L -o public/fonts/source-sans-3/OFL.txt \
  "https://raw.githubusercontent.com/adobe-fonts/source-sans/main/LICENSE.md"
```

**Step 3: Verify files exist**

```bash
ls -la public/fonts/source-sans-3/
```

Expected: 4 WOFF2 files + OFL.txt

**Step 4: Commit**

```bash
git add public/fonts/source-sans-3/
git commit -m "asset: add Source Sans 3 WOFF2 files (SIL OFL)"
```

---

### Task 2: Add @font-face declarations and CSS custom properties

**Files:**
- Modify: `app/assets/stylesheets/style.css:7-60` (`:root` block)

**Step 1: Add @font-face rules at the very top of style.css (before `:root`)**

Insert before line 7 (before the `:root` block):

```css
@font-face {
  font-family: "Source Sans 3";
  src: url("/fonts/source-sans-3/SourceSans3-Regular.woff2") format("woff2");
  font-weight: 400;
  font-style: normal;
  font-display: swap;
}

@font-face {
  font-family: "Source Sans 3";
  src: url("/fonts/source-sans-3/SourceSans3-Italic.woff2") format("woff2");
  font-weight: 400;
  font-style: italic;
  font-display: swap;
}

@font-face {
  font-family: "Source Sans 3";
  src: url("/fonts/source-sans-3/SourceSans3-SemiBold.woff2") format("woff2");
  font-weight: 600;
  font-style: normal;
  font-display: swap;
}

@font-face {
  font-family: "Source Sans 3";
  src: url("/fonts/source-sans-3/SourceSans3-Bold.woff2") format("woff2");
  font-weight: 700;
  font-style: normal;
  font-display: swap;
}
```

**Step 2: Add font custom properties to `:root`**

Add these three variables inside the `:root` block (after line 7, before
`--border-color`):

```css
  --font-display: "Futura", "Trebuchet MS", sans-serif;
  --font-body: "Source Sans 3", "Source Sans Pro", sans-serif;
  --font-mono: ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, monospace;
```

**Step 3: Verify CSS is valid**

```bash
bin/dev &  # start server
curl -s http://localhost:3030 | grep -c "font"  # page loads
```

**Step 4: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "style: add Source Sans 3 @font-face and font CSS variables"
```

---

### Task 3: Replace body font and all Futura declarations in style.css

**Files:**
- Modify: `app/assets/stylesheets/style.css`

Replace every `font-family` declaration in `style.css` with the appropriate
CSS variable. Work through the file top to bottom.

**Replacements (line → old → new):**

| Line | Selector | Old Value | New Value |
|------|----------|-----------|-----------|
| 206 | `body` | `"Bodoni 72", Georgia, serif` | `var(--font-body)` |
| 262 | `nav a` | `"Futura", sans-serif` | `var(--font-display)` |
| 334 | `.nav-auth-btn` | `"Futura", sans-serif` | `var(--font-display)` |
| 366 | `.btn` | `"Futura", sans-serif` | `var(--font-body)` |
| 571 | `header h1` (commented quigley) | delete the comment line entirely | — |
| 572 | `header h1` | `"Futura", sans-serif` | `var(--font-display)` |
| 658 | `section h2` | `"Futura", sans-serif` | `var(--font-display)` |
| 728 | `.ingredients-table thead th` | `'Futura', 'Trebuchet MS', Arial, sans-serif` | `var(--font-display)` |
| 788 | `.settings-page h1` | `"Futura", sans-serif` | `var(--font-display)` |
| 797 | `.settings-section h2` | `"Futura", sans-serif` | `var(--font-display)` |
| 814 | `.settings-field label` | `"Futura", sans-serif` | `var(--font-display)` |
| 844 | `.settings-api-key-row .settings-input` | `ui-monospace, ...monospace` | `var(--font-mono)` |
| 926 | `.nutrition-label` | `'Helvetica Neue', Helvetica, Arial, sans-serif` | KEEP (FDA compliance) |
| 1199 | `.search-overlay` | `"Helvetica Neue", Helvetica, system-ui, ...` | `var(--font-body)` |
| 1241 | `.search-input` | `inherit` | KEEP (inherits from search-overlay) |
| 1329 | `.editor-header h2` | `"Futura", sans-serif` | `var(--font-display)` |
| 1350 | `.editor-errors` | `"Futura", sans-serif` | `var(--font-display)` |
| 1376 | `.editor-textarea` | `ui-monospace, ...monospace` | `var(--font-mono)` |
| 1426 | `.hl-overlay` | `ui-monospace, ...monospace` | `var(--font-mono)` |
| 1579 | `.aisle-name` | `"Futura", sans-serif` | `var(--font-display)` |
| 1728 | `.notify-bar` | `"Futura", sans-serif` | `var(--font-display)` |
| 1784 | `.login-field label` | `"Futura", sans-serif` | `var(--font-display)` |
| 1795 | `.login-field input` | `inherit` | `var(--font-body)` |
| 2049 | `.nf-editor` | `'Helvetica Neue', Helvetica, Arial, sans-serif` | `var(--font-body)` |
| 2112 | `.nf-input` | `inherit` | KEEP (inherits from nf-editor) |
| 2580 | `.embedded-recipe section h3` | `"Futura", sans-serif` | `var(--font-display)` |

**Notes:**
- `.btn` gets `--font-body` (buttons are user-interactive, not display)
- `.login-field input` gets explicit `--font-body` instead of inherit (was inheriting Bodoni from body)
- `.nf-editor` (nutrition form editor) gets `--font-body` (form/input context)
- `.search-overlay` gets `--font-body` (was oddly Helvetica Neue)
- `.nutrition-label` stays Helvetica Neue (FDA standard)
- `inherit` on `.search-input` and `.nf-input` is fine — they inherit from their now-correct parents

**Step 1: Make all replacements**

Work through the table above. Use find-and-replace where possible, but verify
each one — some are KEEP, some change to different variables.

**Step 2: Run lint**

```bash
bundle exec rubocop
```

(CSS isn't linted by RuboCop, but make sure no Ruby was accidentally touched.)

**Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "style: replace Bodoni/Futura declarations with font variables in style.css"
```

---

### Task 4: Replace font declarations in menu.css and groceries.css

**Files:**
- Modify: `app/assets/stylesheets/menu.css`
- Modify: `app/assets/stylesheets/groceries.css`

**menu.css replacements:**

| Line | Selector | Old | New |
|------|----------|-----|-----|
| 57 | `#recipe-selector .category h2` | `"Futura", sans-serif` | `var(--font-display)` |
| 145 | `.availability-detail summary` | `"Futura", sans-serif` | `var(--font-display)` |
| 227 | `.availability-ingredients-inner` | `"Futura", sans-serif` | `var(--font-display)` |
| 275 | `#recipe-selector .quick-bites > h2` | `"Futura", sans-serif` | `var(--font-display)` |
| 298 | `#recipe-selector .quick-bites .subsection h3` | `"Futura", sans-serif` | `var(--font-display)` |

**groceries.css replacements:**

| Line | Selector | Old | New |
|------|----------|-----|-----|
| 52 | `#custom-input` | `inherit` | `var(--font-body)` |
| 133 | `.shopping-list-header h2` | `"Futura", sans-serif` | `var(--font-display)` |
| 167 | `#shopping-list details.aisle > summary` | `"Futura", sans-serif` | `var(--font-display)` |

**Notes:**
- `#custom-input` gets explicit `--font-body` (user input field, was inheriting Bodoni)

**Step 1: Make all replacements**

**Step 2: Commit**

```bash
git add app/assets/stylesheets/menu.css app/assets/stylesheets/groceries.css
git commit -m "style: replace font declarations with variables in menu.css and groceries.css"
```

---

### Task 5: Visual verification

**Files:** None modified — verification only.

**Step 1: Start server and visually verify**

```bash
bin/dev
```

Open in browser and check these pages:

1. **Recipe page** — body text should be Source Sans 3 (clean sans-serif),
   title should be Futura, category headers Futura
2. **Menu page** — category headers Futura, recipe titles Futura, descriptions
   Source Sans 3
3. **Groceries page** — aisle headers Futura, item text Source Sans 3, custom
   input Source Sans 3
4. **Settings page** — labels Futura, inputs Source Sans 3
5. **Ingredient editor** — table headers Futura, form inputs Source Sans 3,
   nutrition label still Helvetica Neue
6. **Search overlay** — input text Source Sans 3 (not Helvetica Neue)
7. **Dark mode** — all of the above
8. **Navigation** — still Futura, uppercase, letter-spaced

**Step 2: Check font loading**

Open browser DevTools → Network tab → filter by Font. Should see 2-4 WOFF2
requests (only weights actually used on the page).

**Step 3: Check for Bodoni remnants**

```bash
grep -rn "Bodoni" app/assets/stylesheets/
```

Expected: zero results.

```bash
grep -rn 'font-family' app/assets/stylesheets/ | grep -v 'var(--font' | grep -v 'Helvetica' | grep -v 'inherit'
```

Expected: zero results (only nutrition label Helvetica and inherited inputs remain as raw values).

**Step 4: Run full test suite**

```bash
rake test
```

Expected: all tests pass (font changes are CSS-only, no test impact).

**Step 5: Commit design doc and plan**

```bash
git add docs/plans/2026-03-12-typography-cleanup-design.md docs/plans/2026-03-12-typography-cleanup-plan.md
git commit -m "docs: typography cleanup design and implementation plan"
```
