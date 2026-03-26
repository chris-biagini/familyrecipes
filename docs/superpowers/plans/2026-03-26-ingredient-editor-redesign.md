# Ingredient Editor Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the ingredient editor's density, portions, and recipe units sections into a unified "Nutrition & Conversions" layout with recipe-oriented terminology.

**Architecture:** UI/language refactor only — no data model, migration, or service-layer changes. Grocery Aisle and Aliases move to always-visible top, everything nutrition-related collapses into a single meta-section. A new view helper handles resolution method label translation. Client-side JS adds derived volume conversions and a compact/expanded nutrition toggle.

**Tech Stack:** Rails 8 ERB views, Stimulus controllers, Propshaft CSS, Minitest

**Spec:** `docs/superpowers/specs/2026-03-26-ingredient-editor-redesign-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `app/helpers/ingredients_helper.rb` | Modify | Add `format_resolution_method` and `format_unit_name` helpers |
| `test/helpers/ingredients_helper_test.rb` | Modify | Add tests for resolution label formatting (file already exists with `format_nutrient_value` test) |
| `app/helpers/icon_helper.rb` | Modify | Add `check` and `alert` SVG icons |
| `test/helpers/icon_helper_test.rb` | Modify | Add assertions for new icons |
| `app/views/ingredients/_editor_form.html.erb` | Modify | Full layout restructure |
| `app/views/ingredients/_portion_row.html.erb` | No change | Already translates `~unitless` to `each` |
| `app/assets/stylesheets/nutrition.css` | Modify | New section styles, remove old collapse styles for aisle/aliases |
| `app/javascript/controllers/nutrition_editor_controller.js` | Modify | Compact nutrition toggle, derived volumes, section key updates, USDA dim fix |
| `config/html_safe_allowlist.yml` | Modify | Update line numbers after template edits |
| `test/controllers/ingredients_controller_test.rb` | Modify | Update assertions for new section headings |
| `test/controllers/nutrition_entries_controller_test.rb` | Modify | Update assertions if any reference old section names |

---

### Task 1: Add Resolution Label Helper

**Files:**
- Modify: `app/helpers/ingredients_helper.rb`
- Modify: `test/helpers/ingredients_helper_test.rb` (already exists with `include ApplicationHelper`,
  `setup_test_kitchen`, and a `format_nutrient_value` test — append new tests to the existing class)

- [ ] **Step 1: Write failing tests for `format_resolution_method`**

Read the existing `test/helpers/ingredients_helper_test.rb` first. It already
has `include ApplicationHelper` and a `setup` block — both are required
because `format_resolution_method` calls `format_nutrient_value` which
delegates to `format_numeric` from `ApplicationHelper`. Append these tests
to the existing class (do NOT replace the file):

```ruby
  test "formats 'via density' as 'volume conversion'" do
    assert_equal 'volume conversion', format_resolution_method('via density', nil)
  end

  test "formats 'weight' as 'standard weight'" do
    assert_equal 'standard weight', format_resolution_method('weight', nil)
  end

  test "formats 'no density' as 'no volume conversion'" do
    assert_equal 'no volume conversion', format_resolution_method('no density', nil)
  end

  test "formats 'no portion' with actionable prompt" do
    assert_equal 'no matching unit — add one above?', format_resolution_method('no portion', nil)
  end

  test "formats 'no ~unitless portion' with each language" do
    result = format_resolution_method('no ~unitless portion', nil)

    assert_equal "no 'each' weight — add one above?", result
  end

  test "formats 'via ~unitless' with gram weight from entry" do
    entry = OpenStruct.new(portions: { '~unitless' => 50.0 })

    assert_equal 'unit weight (50 g)', format_resolution_method('via ~unitless', entry)
  end

  test "formats 'via stick' with gram weight from entry" do
    entry = OpenStruct.new(portions: { 'stick' => 113.0 })

    assert_equal 'unit weight (113 g)', format_resolution_method('via stick', entry)
  end

  test "formats 'via clove' without entry gracefully" do
    assert_equal 'unit weight', format_resolution_method('via clove', nil)
  end

  test "passes through 'no nutrition data' unchanged" do
    assert_equal 'no nutrition data', format_resolution_method('no nutrition data', nil)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/helpers/ingredients_helper_test.rb`
Expected: FAIL — `format_resolution_method` is not defined

- [ ] **Step 3: Implement `format_resolution_method` in `IngredientsHelper`**

Read `app/helpers/ingredients_helper.rb` and add the method. The helper
should pattern-match on the method string:

```ruby
def format_resolution_method(method, entry)
  case method
  when 'via density'          then 'volume conversion'
  when 'weight'               then 'standard weight'
  when 'no density'           then 'no volume conversion'
  when 'no portion'           then 'no matching unit — add one above?'
  when 'no ~unitless portion' then "no 'each' weight — add one above?"
  when /\Avia (.+)\z/
    name = Regexp.last_match(1)
    grams = entry&.portions&.dig(name)
    grams ? "unit weight (#{format_nutrient_value(grams)} g)" : 'unit weight'
  else
    method
  end
end
```

Also add a display helper for nil units:

```ruby
def format_unit_name(unit)
  unit || 'each'
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/helpers/ingredients_helper_test.rb`
Expected: All 9 tests PASS

- [ ] **Step 5: Add test for `format_unit_name`**

Append to the test file:

```ruby
test "format_unit_name returns 'each' for nil" do
  assert_equal 'each', format_unit_name(nil)
end

test "format_unit_name passes through named units" do
  assert_equal 'cup', format_unit_name('cup')
end
```

- [ ] **Step 6: Run full helper tests**

Run: `ruby -Itest test/helpers/ingredients_helper_test.rb`
Expected: All 11 tests PASS

- [ ] **Step 7: Commit**

```bash
git add app/helpers/ingredients_helper.rb test/helpers/ingredients_helper_test.rb
git commit -m "Add resolution label formatting helpers for ingredient editor"
```

---

### Task 2: Add Check and Alert Icons

**Files:**
- Modify: `app/helpers/icon_helper.rb`
- Modify: `test/helpers/icon_helper_test.rb`

- [ ] **Step 1: Read existing icon_helper_test.rb to understand test patterns**

Read `test/helpers/icon_helper_test.rb` to see how existing icon tests work.

- [ ] **Step 2: Add failing tests for new icons**

Add test cases for `:check` and `:alert` icons following the existing pattern
in the test file.

- [ ] **Step 3: Add `:check` and `:alert` SVG icons to ICONS hash**

Read `app/helpers/icon_helper.rb`, then add two new icons to the `ICONS`
hash. Design simple, clean monochrome paths:

- **check**: a simple checkmark stroke path (similar to a check mark)
- **alert**: a warning triangle with exclamation mark

These are single-stroke SVGs using the existing `DEFAULTS` (stroke-based,
no fill). Keep paths minimal.

- [ ] **Step 4: Run icon helper tests**

Run: `ruby -Itest test/helpers/icon_helper_test.rb`
Expected: All tests PASS including the two new icons

- [ ] **Step 5: Commit**

```bash
git add app/helpers/icon_helper.rb test/helpers/icon_helper_test.rb
git commit -m "Add check and alert icons for ingredient editor resolution status"
```

---

### Task 3: Restructure Editor Form Template

This is the largest task — reordering sections and applying terminology
changes to the ERB partial.

**Files:**
- Modify: `app/views/ingredients/_editor_form.html.erb`

**Reference:**
- Spec: `docs/superpowers/specs/2026-03-26-ingredient-editor-redesign-design.md`
- Current template: 246 lines, 7 collapsible `<details>` sections

- [ ] **Step 1: Read the current template and the spec**

Read both files in full. Note the current section order:
1. USDA Import (lines 6-30)
2. Nutrition Facts (lines 32-72)
3. Density (lines 74-115)
4. Portions (lines 117-138)
5. Grocery Aisle (lines 140-170)
6. Aliases (lines 172-201)
7. Recipe Units (lines 203-223)
8. Used-in sources (lines 225-237)
9. Reset button (lines 239-243)

- [ ] **Step 2: Restructure to new layout**

Rewrite the template with this order:

1. **Grocery Aisle** — plain `<div>` with styled label, not `<details>`.
   Keep the same select, new-aisle input, and omit checkbox. Use a
   `<div class="editor-top-field">` wrapper with
   `<div class="editor-field-label">Grocery Aisle</div>`.

2. **Aliases** — plain `<div>` with styled label. Keep chip list and add
   input. Same wrapper pattern.

3. **Divider** — `<hr class="editor-divider">`

4. **Nutrition & Conversions** — single `<details class="collapse-header">`
   with `data-section-key="nutrition-conversions"`. Summary line includes:
   - Compact nutrition text (server-rendered): calories/basis or empty state
   - Resolution status icon: `<%= icon(:check, size: 14) %>` if all
     `needed_units` are resolvable, `<%= icon(:alert, size: 14) %>` otherwise

   Inside the `<details>`:

   a. **USDA Import** — same search bar/results, wrapped in a conditional
      on `has_usda_key`. No `<details>` wrapper — just a `<div>` with the
      `editor-inner-title` class heading.

   b. **Nutrition Facts** — two alternate views controlled by Stimulus:
      - Compact summary: `<div data-nutrition-editor-target="nutrientSummary">`
        showing cal/fat/carbs/protein/basis inline, plus an "Edit all
        nutrients" link with `data-action="click->nutrition-editor#expandNutrients"`.
      - Full form: `<div data-nutrition-editor-target="nutrientDetail" hidden>`
        containing the existing FDA-label nutrient inputs, plus a "Done" link
        with `data-action="click->nutrition-editor#collapseNutrients"`.

   c. **Volume Conversions** — heading "Volume Conversions", help text from
      spec, same density inputs (volume amount, unit select, grams). Add a
      `<div data-nutrition-editor-target="derivedVolumes">` below the input
      row for client-rendered derived conversions. Add `data-action`
      attributes to the density inputs:
      - Volume input: `data-action="input->nutrition-editor#updateDerivedVolumes"`
      - Unit select: `data-action="change->nutrition-editor#updateDerivedVolumes"`
      - Grams input: `data-action="input->nutrition-editor#updateDerivedVolumes"`

   d. **Unit Weights** — heading "Unit Weights", help text from spec, same
      portion list and add button.

   e. **Recipe Check** — heading "Recipe Check" (conditional on
      `needed_units.any?`), help text from spec. Each row uses
      `format_resolution_method` and `format_unit_name` helpers. Unresolvable
      rows get a `class="recipe-unit-unresolved"` for highlighting.

5. **Used-in sources** — unchanged, after the meta-section.
6. **Reset button** — unchanged.

- [ ] **Step 3: Verify the template renders without errors**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb`
This exercises the ingredients index which renders editor frames.
Fix any ERB syntax errors or missing variables.

- [ ] **Step 4: Update html_safe_allowlist.yml**

Read `config/html_safe_allowlist.yml` and run `rake lint:html_safe` to
check if any `.html_safe` call line numbers shifted. Update the allowlist
file:line entries as needed.

- [ ] **Step 5: Run lint**

Run: `bundle exec rubocop app/views/ingredients/_editor_form.html.erb app/helpers/ingredients_helper.rb`
Fix any offenses.

- [ ] **Step 6: Commit**

```bash
git add app/views/ingredients/_editor_form.html.erb config/html_safe_allowlist.yml
git commit -m "Restructure ingredient editor: unified Nutrition & Conversions layout"
```

---

**Note:** After Task 3, the template references Stimulus targets
(`nutrientSummary`, `nutrientDetail`, `derivedVolumes`) not yet declared in
the controller. This causes harmless console warnings in dev until Task 5
adds them. Tests will still pass.

### Task 4: Update CSS for New Layout

**Files:**
- Modify: `app/assets/stylesheets/nutrition.css`

- [ ] **Step 1: Read current nutrition.css**

Read `app/assets/stylesheets/nutrition.css` to see existing classes.

- [ ] **Step 2: Add new CSS classes and update existing ones**

Add/modify these classes:

```css
/* Always-visible top fields (Grocery Aisle, Aliases) */
.editor-top-field { margin-bottom: 0.75rem; }
.editor-field-label {
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-soft);
  margin-bottom: 0.3rem;
}

/* Divider between top fields and nutrition section */
.editor-divider {
  border: none;
  border-top: 1px solid var(--rule-faint);
  margin: 1rem 0;
}

/* Inner section titles (non-collapsible headings within meta-section) */
.editor-inner-title {
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-soft);
  margin: 1rem 0 0.35rem;
  border-bottom: 1px solid var(--rule-faint);
  padding-bottom: 0.25rem;
}
.editor-inner-title:first-child { margin-top: 0.25rem; }

/* Compact nutrition summary */
.nf-summary {
  display: flex;
  flex-wrap: wrap;
  gap: 0.3rem 1rem;
  font-size: 0.85rem;
  color: var(--text-soft);
  padding: 0.25rem 0;
}
.nf-summary strong { color: var(--text); font-weight: 600; }
.nf-expand-link {
  font-size: 0.8rem;
  color: var(--text-light);
  cursor: pointer;
  text-decoration: underline;
  margin-top: 0.25rem;
  display: inline-block;
}
.nf-expand-link:hover { color: var(--red); }

/* Derived volume conversions */
.derived-volumes {
  display: flex;
  flex-wrap: wrap;
  gap: 0.2rem 0.75rem;
  margin: 0.15rem 0 0.4rem 0.5rem;
  font-size: 0.8rem;
  color: var(--text-light);
}

/* Recipe Check: unresolved row */
.recipe-unit-unresolved {
  background: color-mix(in srgb, var(--red) 8%, transparent);
  padding: 0.3rem 0.4rem;
  border-radius: 4px;
}

/* Collapsed summary status icons */
.nutrition-summary-icon { vertical-align: middle; margin-left: 0.25rem; }
```

Also update `.recipe-unit-method` to `.recipe-unit-explain` if the class
name is referenced in the template (check the template for consistency).

- [ ] **Step 3: Verify styles render correctly**

Start the dev server (`bin/dev`), open the ingredient editor in a browser,
and visually verify the layout. Check:
- Grocery Aisle and Aliases are always visible at top
- Nutrition & Conversions collapses/expands
- Inner section titles render properly
- Recipe Check unresolved rows are highlighted

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/nutrition.css
git commit -m "Update ingredient editor CSS for new section layout"
```

---

### Task 5: Update Stimulus Controller — Section Keys and Compact Nutrition

**Files:**
- Modify: `app/javascript/controllers/nutrition_editor_controller.js`

- [ ] **Step 1: Read the current controller**

Read `app/javascript/controllers/nutrition_editor_controller.js` in full.
Note the targets array (line 18-27), `restoreSectionStates` (lines 562-573),
and `onFrameLoad` (lines 555-560).

- [ ] **Step 2: Add new Stimulus targets**

Add to the static targets array:
- `nutrientSummary` — compact nutrition view
- `nutrientDetail` — full nutrient form
- `derivedVolumes` — container for derived volume conversions

- [ ] **Step 3: Implement `expandNutrients` and `collapseNutrients` actions**

```javascript
expandNutrients() {
  this.nutrientSummaryTarget.hidden = true
  this.nutrientDetailTarget.hidden = false
}

collapseNutrients() {
  this.updateNutrientSummary()
  this.nutrientDetailTarget.hidden = true
  this.nutrientSummaryTarget.hidden = false
}
```

- [ ] **Step 4: Implement `updateNutrientSummary`**

This reads current values from the nutrient input fields and updates the
compact summary text. Called by `collapseNutrients` and `populateFromUsda`.
Build DOM elements using `createElement`/`textContent` (never set content
via string interpolation into markup — strict CSP):

```javascript
updateNutrientSummary() {
  if (!this.hasNutrientSummaryTarget) return

  const basis = this.basisGramsTarget.value || '\u2014'
  const cal = this.findNutrientValue('calories') || '\u2014'
  const fat = this.findNutrientValue('fat') || '\u2014'
  const carbs = this.findNutrientValue('carbs') || '\u2014'
  const protein = this.findNutrientValue('protein') || '\u2014'

  const summary = this.nutrientSummaryTarget.querySelector('.nf-summary')
  summary.replaceChildren()

  const items = [
    { label: '', value: cal, unit: 'cal' },
    { label: '', value: fat, unit: 'g fat' },
    { label: '', value: carbs, unit: 'g carbs' },
    { label: '', value: protein, unit: 'g protein' },
    { label: 'per ', value: basis, unit: 'g' }
  ]
  items.forEach(({ label, value, unit }) => {
    const span = document.createElement('span')
    if (label) span.appendChild(document.createTextNode(label))
    const strong = document.createElement('strong')
    strong.textContent = value
    span.appendChild(strong)
    span.appendChild(document.createTextNode(` ${unit}`))
    summary.appendChild(span)
  })
}

findNutrientValue(key) {
  const field = this.nutrientFieldTargets.find(
    f => f.dataset.nutrientKey === key
  )
  return field?.value || null
}
```

- [ ] **Step 5: Update `restoreSectionStates`**

The method at lines 562-573 uses `data-section-key` on `<details>` elements.
The old keys (`density`, `portions`, `recipe-units`, `grocery-aisle`,
`aliases`) no longer exist. Add cleanup of stale sessionStorage keys in
`onFrameLoad`:

```javascript
const staleKeys = ['density', 'portions', 'recipe-units', 'grocery-aisle', 'aliases']
staleKeys.forEach(key => sessionStorage.removeItem(`editor:section:${key}`))
```

The `restoreSectionStates` method itself needs no structural changes — it
already iterates all `[data-section-key]` elements and will find only
`nutrition-conversions` and `usda-import` (if present).

- [ ] **Step 6: Update `populateFromUsda` to refresh the compact summary**

After the existing nutrient population logic (around line 417), add:

```javascript
this.updateNutrientSummary()
```

- [ ] **Step 7: Run JS build and verify no errors**

Run: `npm run build`
Expected: Clean build, no errors

- [ ] **Step 8: Commit**

```bash
git add app/javascript/controllers/nutrition_editor_controller.js
git commit -m "Add compact nutrition toggle and update section key persistence"
```

---

### Task 6: Update Stimulus Controller — Derived Volume Conversions

**Files:**
- Modify: `app/javascript/controllers/nutrition_editor_controller.js`

- [ ] **Step 1: Add VOLUME_TO_ML constant**

At the top of the controller file (outside the class), add the conversion
table mirroring `UnitResolver::VOLUME_TO_ML`:

```javascript
const VOLUME_TO_ML = {
  tsp: 4.929, tbsp: 14.787, 'fl oz': 29.5735,
  cup: 236.588, pt: 473.176, qt: 946.353,
  gal: 3785.41, ml: 1, l: 1000
}
```

- [ ] **Step 2: Implement `updateDerivedVolumes`**

Build derived volume spans using `createElement`/`textContent` (strict CSP):

```javascript
updateDerivedVolumes() {
  if (!this.hasDerivedVolumesTarget) return

  const container = this.derivedVolumesTarget
  container.replaceChildren()

  const grams = parseFloat(this.densityGramsTarget.value)
  const volume = parseFloat(this.densityVolumeTarget.value)
  const unit = this.densityUnitTarget.value

  if (!grams || !volume || !unit || !VOLUME_TO_ML[unit]) return

  const gramsPerMl = grams / (volume * VOLUME_TO_ML[unit])

  Object.entries(VOLUME_TO_ML).forEach(([derivedUnit, ml]) => {
    if (derivedUnit === unit) return

    const derivedGrams = gramsPerMl * ml
    if (derivedGrams < 0.1 || derivedGrams > 50000) return

    const span = document.createElement('span')
    span.textContent = `1 ${derivedUnit} \u2248 ${this.formatValue(derivedGrams)} g`
    container.appendChild(span)
  })
}
```

- [ ] **Step 3: Call `updateDerivedVolumes` on frame load and after USDA import**

In `onFrameLoad` (after restoring section states):
```javascript
this.updateDerivedVolumes()
```

In `populateFromUsda` (after setting density values):
```javascript
this.updateDerivedVolumes()
```

In the density candidate radio handler (after updating density values):
```javascript
this.updateDerivedVolumes()
```

The `data-action` attributes on density inputs were already added in Task 3
step 2.

- [ ] **Step 4: Run JS build and verify**

Run: `npm run build`
Expected: Clean build

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/nutrition_editor_controller.js
git commit -m "Add derived volume conversions to ingredient editor"
```

---

### Task 7: Fix USDA Import Dimming

**Files:**
- Modify: `app/javascript/controllers/nutrition_editor_controller.js`

- [ ] **Step 1: Read the current import dimming logic**

Read the `importUsdaResult` method (lines 386-405) and `buildResultItem`
(lines 329-358). Look for how the "loading" or "imported" class is applied
to USDA result items.

- [ ] **Step 2: Change to single-result dimming**

The current logic applies a class to each clicked result and never removes
it. Change to: before applying the dim class to the new result, remove it
from any previously-dimmed result. Track via a controller property:

```javascript
// In importUsdaResult, before adding loading class:
if (this.lastImportedItem) {
  this.lastImportedItem.classList.remove('usda-result-imported')
}
// After successful import:
item.classList.add('usda-result-imported')
this.lastImportedItem = item
```

Check the exact class names used — it may be `loading` or a similar class.
Adjust the approach to match the actual implementation.

- [ ] **Step 3: Clear tracking on new search**

In `fetchUsdaPage` or `usdaSearch`, reset:
```javascript
this.lastImportedItem = null
```

- [ ] **Step 4: Run JS build**

Run: `npm run build`
Expected: Clean build

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/nutrition_editor_controller.js
git commit -m "Only dim the most recently imported USDA search result"
```

---

### Task 8: Update Tests

**Files:**
- Modify: `test/controllers/ingredients_controller_test.rb`
- Modify: `test/controllers/nutrition_entries_controller_test.rb`

- [ ] **Step 1: Run existing test suite**

Run: `rake test`
Identify which tests fail due to the template changes (changed section
headings, removed `<details>` wrappers, etc.).

- [ ] **Step 2: Fix failing ingredient controller tests**

Read the failing tests. Update any assertions that reference old section
names ("Density", "Portions", "Recipe Units") or old HTML structure
(`<details>` for aisle/aliases).

- [ ] **Step 3: Fix failing nutrition entries controller tests**

Same approach — update assertions for changed labels or structure.

- [ ] **Step 4: Add test for collapsed summary icon selection**

Add a controller test (in `test/controllers/ingredients_controller_test.rb`)
that verifies the collapsed "Nutrition & Conversions" summary renders the
check icon when all recipe units are resolvable, and the alert icon when
some are not. This exercises the conditional logic in the template's
`<summary>` line.

- [ ] **Step 5: Run full test suite and lint**

Run: `rake`
Expected: All tests pass, 0 RuboCop offenses

- [ ] **Step 6: Commit**

```bash
git add test/
git commit -m "Update ingredient editor tests for new section layout and terminology"
```

---

### Task 9: Manual Verification

- [ ] **Step 1: Start dev server and test the full flow**

Run: `bin/dev`

Open the ingredient editor for an ingredient with complete data (e.g.
butter — has density, portions, nutrition). Verify:
- Grocery Aisle and Aliases visible at top, not collapsible
- "Nutrition & Conversions" collapses with summary + status icon
- USDA search works inside the section
- Compact nutrition summary shows, "Edit all nutrients" expands the form
- Volume Conversions shows density input + derived volumes below
- Unit Weights shows portion rows
- Recipe Check shows human-readable labels
- Unresolved units are highlighted

- [ ] **Step 2: Test with an ingredient that has unresolved units**

Pick or create an ingredient where some recipe units don't resolve. Verify
the warning icon appears in the collapsed summary and the Recipe Check
section shows actionable prompts.

- [ ] **Step 3: Test USDA import flow**

Search USDA, click a result. Verify:
- Nutrients populate and compact summary updates
- Density populates and derived volumes appear
- Portions populate
- Only the last-clicked result is dimmed
- Click a different result — first one un-dims

- [ ] **Step 4: Test section state persistence**

Collapse/expand "Nutrition & Conversions". Navigate away and back. Verify
the collapse state is restored from sessionStorage.

- [ ] **Step 5: Final commit if any fixes needed**

```bash
git add -A
git commit -m "Fix issues found during manual verification"
```
