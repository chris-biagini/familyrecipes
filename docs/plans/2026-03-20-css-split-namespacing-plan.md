# CSS Split & Class Namespacing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the 3,351-line `style.css` monolith into 7 focused CSS files and rename 16 un-namespaced editor classes.

**Architecture:** Extract contiguous and non-contiguous line ranges from `style.css` into domain-specific files. The consolidated dark-mode block (lines 1557-1584) is distributed to each file. Class renaming touches CSS, ERB, JS, and tests.

**Tech Stack:** CSS, Propshaft (Rails 8 asset pipeline), ERB templates, Stimulus JS

**Spec:** `docs/plans/2026-03-20-css-split-namespacing-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| **Create**: `app/assets/stylesheets/base.css` | Variables, body, typography, buttons, inputs, collapse, tags, notifications, shared keyframes |
| **Create**: `app/assets/stylesheets/navigation.css` | Nav bar, hamburger, drawer, search overlay |
| **Create**: `app/assets/stylesheets/editor.css` | Editor dialog, all editor internals, settings dialog, graphical editor |
| **Create**: `app/assets/stylesheets/nutrition.css` | FDA label, nf-editor, USDA search, density/portion/alias classes |
| **Create**: `app/assets/stylesheets/recipe.css` | Embedded recipe cards |
| **Create**: `app/assets/stylesheets/print.css` | Print styles |
| **Create**: `app/assets/stylesheets/ingredients.css` | Ingredients table, toolbar (page-specific) |
| **Modify**: `app/views/layouts/application.html.erb:17` | Replace single stylesheet_link_tag with 6 |
| **Modify**: `app/views/ingredients/index.html.erb` | Add page-specific ingredients.css |
| **Modify**: `app/views/ingredients/_editor_form.html.erb` | Rename CSS classes |
| **Modify**: `app/views/ingredients/_portion_row.html.erb` | Rename CSS classes |
| **Modify**: `app/javascript/controllers/nutrition_editor_controller.js` | Rename CSS classes |
| **Modify**: `test/controllers/ingredients_controller_test.rb` | Rename CSS selectors |
| **Delete**: `app/assets/stylesheets/style.css` | Replaced by the 7 new files |

---

### Task 1: Create `base.css`

Extract foundation styles from `style.css`. This is the largest output file (~1,150 lines).

**Files:**
- Create: `app/assets/stylesheets/base.css`
- Read: `app/assets/stylesheets/style.css`

- [ ] **Step 1: Create `base.css`**

Read `style.css` and extract these line ranges (in order) into `base.css`:

| Lines | Content |
|-------|---------|
| 1-226 | `:root` tokens, dark mode, html, body, gingham, turbo bar, sr-only |
| 350-538 | Custom checkbox, all `.btn*` classes |
| 540-639 | `.input-base*`, `.collapse-*` |
| 769-895 | `main` card, header, `h1`, recipe-meta, recipe-tags |
| 896-1081 | Scale bar and controls |
| 1082-1199 | `header::after`, `.toc_nav`, `section`, homepage, `#export-actions` |
| 1257-1262 | `.loading-placeholder` |
| 1329-1409 | Recipe content grid, `.instructions`, `.ingredients`, `footer` |
| 1574-1583 | Dark-mode: `.smart-icon--crossout::after` — wrap in `@media (prefers-color-scheme: dark) { }` |
| 1586-1667 | Screen interactivity + mobile base overrides (720px) |
| 1685-1687 | `html:has(dialog[open]) { overflow: hidden; }` |
| 1725-1746 | Shared keyframes: `fade-in`, `bloop`, `check-box-pop`, `check-mark-pop` |
| 1774-1831 | Tag pills, smart tag variants, smart icons |
| 2356-2418 | Notification toast |
| 3333-3351 | `.app-version`, `prefers-reduced-motion` |

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/base.css
git commit -m "Extract base.css from style.css monolith"
```

---

### Task 2: Create `navigation.css`

**Files:**
- Create: `app/assets/stylesheets/navigation.css`
- Read: `app/assets/stylesheets/style.css`

- [ ] **Step 1: Create `navigation.css`**

Extract these line ranges into `navigation.css`:

| Lines | Content |
|-------|---------|
| 228-349 | `nav`, nav links, `.nav-compact`, `.nav-settings-link` |
| 641-767 | `nav a:hover/focus`, `.nav-icon`, hamburger, `.nav-links`, `.nav-drawer` |
| 1573 | Dark-mode: `nav::before` — wrap in `@media (prefers-color-scheme: dark) { }` |
| 1700-1724 | `.search-overlay`, open state, backdrop |
| 1748-1773 | `.search-panel`, `.search-input-wrapper`, `.search-pill-area`, `.search-icon` |
| 1832-1931 | `.search-input*`, `.search-result*`, `.search-no-results`, `.nav-search-btn` |

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/navigation.css
git commit -m "Extract navigation.css from style.css monolith"
```

---

### Task 3: Create `editor.css`

**Files:**
- Create: `app/assets/stylesheets/editor.css`
- Read: `app/assets/stylesheets/style.css`

- [ ] **Step 1: Create `editor.css`**

Extract these line ranges into `editor.css`:

| Lines | Content |
|-------|---------|
| 1264-1267 | `.editor-error-message` |
| 1269-1320 | Settings dialog (`#settings-editor`, `.settings-*`) |
| 1568 | Dark-mode: `.editor-section` — wrap in `@media (prefers-color-scheme: dark) { }` |
| 1669-1698 | `.editor-dialog`, open state, backdrop |
| 1933-2157 | Editor header/body/footer/errors, textarea, category row, side panel, mobile meta, tag input |
| 2159-2229 | CodeMirror mount (`.cm-mount`), token highlights (`hl-*`) |
| 2231-2355 | `.editor-footer*`, aisle order editor |
| 2420-2422 | `.editor-form` |
| 2428-2502 | `.editor-section*`, collapsible sections, `.editor-help`, `.editor-recipes*`, `.editor-reset-btn` |
| 2843-2957 | Mobile editor overrides (720px — fullscreen dialogs, stacked layouts, bigger tap targets, including nutrition-related mobile rules) |
| 3069-3273 | Graphical editor, `.editor-mode-toggle`, `.editor-header-actions`, mobile graphical overrides |

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/editor.css
git commit -m "Extract editor.css from style.css monolith"
```

---

### Task 4: Create `nutrition.css`

**Files:**
- Create: `app/assets/stylesheets/nutrition.css`
- Read: `app/assets/stylesheets/style.css`

- [ ] **Step 1: Create `nutrition.css`**

Extract these line ranges into `nutrition.css`:

| Lines | Content |
|-------|---------|
| 1410-1553 | FDA nutrition label (`.nutrition-label*`, `.nutrition-footnote`) |
| 1557-1567, 1569-1572 | Dark-mode nutrition rules (skip line 1568 `.editor-section` — that goes in editor.css): `.nutrition-label` (border, bg, color), `.serving-size`, `.calories-row`, `.dv-header`, `.nutrient-row`, `.nutrient-row:last-child`, `.nf-thick-rule`, `.usda-results`, `.usda-result-item`, `.density-candidates` — wrap in `@media (prefers-color-scheme: dark) { }` |
| 2424-2426 | `#nutrition-editor` width |
| 2504-2602 | `.recipe-unit-row*`, USDA search (`.usda-*`) |
| 2604-2676 | `.nf-editor`, `.nf-serving-row`, `.nf-thick-rule`, `.nf-row*`, `.nf-name`, `.nf-unit`, spin button hide |
| 2678-2841 | `.density-candidates*`, `.form-row*`, `.field-unit`, `.portion-*`, `.btn-icon`, `.add-portion`, `.alias-*`, `.add-alias`, `.aisle-form-*`, iOS zoom prevention |

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/nutrition.css
git commit -m "Extract nutrition.css from style.css monolith"
```

---

### Task 5: Create `recipe.css` and `print.css`

**Files:**
- Create: `app/assets/stylesheets/recipe.css`
- Create: `app/assets/stylesheets/print.css`
- Read: `app/assets/stylesheets/style.css`

- [ ] **Step 1: Create `recipe.css`**

Extract lines 2959-3067 into `recipe.css`:
- `.embedded-recipe*`, `.recipe-link`, `.embedded-recipe-link`, `.embedded-description`, `.embedded-footer`, `.embedded-multiplier`, `.embedded-prep-note`, `.broken-reference`, mobile override

- [ ] **Step 2: Create `print.css`**

Extract lines 3275-3331 into `print.css`:
- `@media print` block

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/recipe.css app/assets/stylesheets/print.css
git commit -m "Extract recipe.css and print.css from style.css monolith"
```

---

### Task 6: Create `ingredients.css` and wire up page-specific loading

**Files:**
- Create: `app/assets/stylesheets/ingredients.css`
- Modify: `app/views/ingredients/index.html.erb`
- Read: `app/assets/stylesheets/style.css`

- [ ] **Step 1: Create `ingredients.css`**

Extract these line ranges into `ingredients.css`:

| Lines | Content |
|-------|---------|
| 1200-1255 | Ingredients toolbar, table, sortable headers, ingredient rows, column classes |
| 1322-1328 | Mobile: hide aisle/recipes columns |

- [ ] **Step 2: Add page-specific CSS loading**

In `app/views/ingredients/index.html.erb`, add at the top (before line 1):

```erb
<% content_for(:head) do %>
  <%= stylesheet_link_tag 'ingredients', "data-turbo-track": "reload" %>
<% end %>
```

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/ingredients.css app/views/ingredients/index.html.erb
git commit -m "Extract ingredients.css as page-specific stylesheet"
```

---

### Task 7: Update layout, delete `style.css`, verify

**Files:**
- Modify: `app/views/layouts/application.html.erb:17`
- Delete: `app/assets/stylesheets/style.css`

- [ ] **Step 1: Update layout stylesheet tags**

In `app/views/layouts/application.html.erb`, replace line 17:

```erb
  <%= stylesheet_link_tag 'style', "data-turbo-track": "reload" %>
```

with:

```erb
  <%= stylesheet_link_tag 'base', "data-turbo-track": "reload" %>
  <%= stylesheet_link_tag 'navigation', "data-turbo-track": "reload" %>
  <%= stylesheet_link_tag 'editor', "data-turbo-track": "reload" %>
  <%= stylesheet_link_tag 'nutrition', "data-turbo-track": "reload" %>
  <%= stylesheet_link_tag 'recipe', "data-turbo-track": "reload" %>
  <%= stylesheet_link_tag 'print', "data-turbo-track": "reload" %>
```

- [ ] **Step 2: Delete `style.css`**

```bash
rm app/assets/stylesheets/style.css
```

- [ ] **Step 3: Run tests**

```bash
rake test
```

Expected: all tests pass. If failures mention missing stylesheets, check that all line ranges were extracted correctly and no CSS was lost.

```bash
npm test
```

Expected: all JS tests pass (unchanged).

- [ ] **Step 4: Run lint**

```bash
rake lint
```

Expected: 0 offenses.

- [ ] **Step 5: Verify no CSS was lost**

Quick sanity check — total lines in new files should roughly equal the original:

```bash
wc -l app/assets/stylesheets/base.css app/assets/stylesheets/navigation.css app/assets/stylesheets/editor.css app/assets/stylesheets/nutrition.css app/assets/stylesheets/recipe.css app/assets/stylesheets/print.css app/assets/stylesheets/ingredients.css
```

Expected: total ~3,350 lines (±50 for blank line differences).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Replace style.css monolith with 7 focused CSS files

Resolves the CSS split portion of #262. style.css (3,351 lines) is
replaced by: base.css, navigation.css, editor.css, nutrition.css,
recipe.css, print.css, and ingredients.css (page-specific)."
```

---

### Task 8: Rename un-namespaced CSS classes

**Files:**
- Modify: `app/assets/stylesheets/nutrition.css` — CSS rules
- Modify: `app/assets/stylesheets/editor.css` — mobile override rules
- Modify: `app/views/ingredients/_editor_form.html.erb` — HTML classes
- Modify: `app/views/ingredients/_portion_row.html.erb` — HTML classes
- Modify: `app/javascript/controllers/nutrition_editor_controller.js` — JS class strings
- Modify: `test/controllers/ingredients_controller_test.rb` — CSS selectors

- [ ] **Step 1: Rename classes in `nutrition.css`**

Apply these find-and-replace operations in `nutrition.css` (use `replace_all`):

| Find | Replace |
|------|---------|
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
| `.alias-chip-remove` | `.editor-alias-remove` |
| `.alias-chip` | `.editor-alias-chip` |
| `.alias-add-row` | `.editor-alias-add-row` |
| `.alias-input` | `.editor-alias-input` |
| `.add-alias` | `.editor-add-alias` |
| `.btn-icon` | `.editor-btn-icon` |

**Order matters:** Rename `.alias-chip-remove` before `.alias-chip` to avoid partial matches. Similarly, `.density-candidate-row` before `.density-candidates`.

- [ ] **Step 2: Rename classes in `editor.css`**

The mobile editor overrides block in `editor.css` (originally lines 2843-2957) references some of these classes. Apply the same renames:

- `.form-row` → `.editor-form-row`
- `.portion-row` → `.editor-portion-row`
- `.alias-add-row` → `.editor-alias-add-row`

- [ ] **Step 3: Rename classes in `_editor_form.html.erb`**

Apply renames in `app/views/ingredients/_editor_form.html.erb`:

| Line | Current | New |
|------|---------|-----|
| 84 | `class="form-row density-row"` | `class="editor-form-row editor-density-row"` |
| 99 | `class="portion-eq"` | `class="editor-portion-eq"` |
| 106 | `class="field-unit"` | `class="editor-field-unit"` |
| 109 | `class="density-candidates"` | `class="editor-density-candidates"` |
| 134 | `class="btn add-portion"` | `class="btn editor-add-portion"` |
| 146 | `class="form-row aisle-row"` | `class="editor-form-row aisle-row"` |
| 162 | `class="form-row"` | `class="editor-form-row"` |
| 182 | `class="alias-chip-list"` | `class="editor-alias-list"` |
| 184 | `class="alias-chip"` | `class="editor-alias-chip"` |
| 186 | `class="alias-chip-remove"` | `class="editor-alias-remove"` |
| 191 | `class="alias-add-row"` | `class="editor-alias-add-row"` |
| 192 | `class="alias-input"` | `class="editor-alias-input"` |
| 196 | `class="btn add-alias"` | `class="btn editor-add-alias"` |

Note: `.alias-chip-text` at line 185 does NOT get renamed — it has no CSS rule and is only used as a DOM selector.

- [ ] **Step 4: Rename classes in `_portion_row.html.erb`**

Apply renames in `app/views/ingredients/_portion_row.html.erb`:

| Line | Current | New |
|------|---------|-----|
| 2 | `class="portion-row"` | `class="editor-portion-row"` |
| 8 | `class="portion-eq"` | `class="editor-portion-eq"` |
| 14 | `class="portion-unit"` | `class="editor-portion-unit"` |
| 15 | `class="btn-icon"` | `class="editor-btn-icon"` |

- [ ] **Step 5: Rename classes in `nutrition_editor_controller.js`**

Apply renames in `app/javascript/controllers/nutrition_editor_controller.js`:

| Line | Current | New |
|------|---------|-----|
| 127 | `"portion-row"` | `"editor-portion-row"` |
| 138 | `"portion-eq"` | `"editor-portion-eq"` |
| 151 | `"portion-unit"` | `"editor-portion-unit"` |
| 156 | `"btn-icon"` | `"editor-btn-icon"` |
| 172 | `".portion-row"` | `".editor-portion-row"` |
| 185 | `"alias-chip"` | `"editor-alias-chip"` |
| 194 | `"alias-chip-remove"` | `"editor-alias-remove"` |
| 207 | `".alias-chip"` | `".editor-alias-chip"` |
| 443 | `".portion-row"` | `".editor-portion-row"` |
| 464 | `"density-candidate-row"` | `"editor-density-candidate-row"` |

- [ ] **Step 6: Rename selectors in tests**

Apply renames in `test/controllers/ingredients_controller_test.rb`:

| Line | Current | New |
|------|---------|-----|
| 465 | `'details.density-candidates[hidden]'` | `'details.editor-density-candidates[hidden]'` |

Note: Lines 390-391 use `.alias-chip-text` which is NOT renamed.

- [ ] **Step 7: Run tests**

```bash
rake test
```

Expected: all tests pass.

```bash
npm test
```

Expected: all JS tests pass.

- [ ] **Step 8: Run lint**

```bash
rake lint
rake lint:html_safe
```

Expected: 0 offenses. The `html_safe_allowlist.yml` should not need updating since the renamed files (`_editor_form.html.erb`, `_portion_row.html.erb`) are not in the allowlist.

- [ ] **Step 9: Commit**

```bash
git add app/assets/stylesheets/nutrition.css app/assets/stylesheets/editor.css \
       app/views/ingredients/_editor_form.html.erb \
       app/views/ingredients/_portion_row.html.erb \
       app/javascript/controllers/nutrition_editor_controller.js \
       test/controllers/ingredients_controller_test.rb
git commit -m "Namespace editor CSS classes with editor- prefix

Rename 16 un-namespaced classes (form-row, portion-*, alias-*,
density-*, btn-icon) to use the editor- prefix for consistency
with the rest of the editor class naming convention.

Resolves #262"
```

---

### Task 9: Create PR

- [ ] **Step 1: Push and create PR**

```bash
git push -u origin feature/css-split-namespacing
gh pr create --title "CSS split and class namespacing (#262)" --body "$(cat <<'EOF'
## Summary

- Split the 3,351-line `style.css` monolith into 7 focused CSS files
- Renamed 16 un-namespaced editor CSS classes with `editor-` prefix
- Extracted `ingredients.css` as a page-specific stylesheet

## Test plan

- [ ] `rake test` passes
- [ ] `npm test` passes
- [ ] `rake lint` passes
- [ ] Visual spot-check: recipe page, ingredients page, menu page, settings dialog, nutrition editor

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
