# Recipe Scaling Overhaul Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the `prompt()`/`alert()` scaling UI with an inline collapsible panel, fix the two scaling bugs (duplicate handlers, static cross-ref badges).

**Architecture:** New `scale_panel_controller` Stimulus controller owns the panel UI. Existing `recipe_state_controller` refactored: embedded instances skip scaling entirely, top-level listens for dispatched events from the panel. All client-side — no server round-trips for scaling.

**Tech Stack:** Stimulus controllers, CSS `grid-template-rows` animation, localStorage persistence, ERB partials.

**Design doc:** `docs/plans/2026-03-13-recipe-scaling-overhaul-design.md`

---

### Task 1: Add `data-base-multiplier` to embedded recipe articles

The embedded recipe partial needs a `data-base-multiplier` attribute so the
client-side scaler can update the `× N` badge dynamically.

**Files:**
- Modify: `app/views/recipes/_embedded_recipe.html.erb:9-12`
- Modify: `test/controllers/recipes_controller_test.rb`

**Step 1: Write the failing test**

In `test/controllers/recipes_controller_test.rb`, add after the existing
`embedded recipe with multiplier shows scaled quantities` test (around line 505):

```ruby
test 'embedded recipe article includes data-base-multiplier' do
  get recipe_path('double-pizza')

  assert_select 'article.embedded-recipe[data-base-multiplier="2.0"]'
end
```

This test uses the same `double-pizza` recipe created by the existing test's
`setup` block (check — if the recipe is created inline in the other test
rather than setup, create `Pizza Dough` and `Double Pizza` via
`MarkdownImporter.import` inside this test too).

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n test_embedded_recipe_article_includes_data-base-multiplier`
Expected: FAIL — no `data-base-multiplier` attribute exists yet.

**Step 3: Add the attribute to the partial**

In `app/views/recipes/_embedded_recipe.html.erb`, add
`data-base-multiplier="<%= cross_reference.multiplier %>"` to the `<article>`
tag. The article tag currently spans lines 9-12:

```erb
<article class="embedded-recipe"
         data-base-multiplier="<%= cross_reference.multiplier %>"
         data-controller="recipe-state"
         data-recipe-state-recipe-id-value="xref-<%= cross_reference.target_slug %>"
         data-recipe-state-version-hash-value="<%= Digest::SHA256.hexdigest(target.markdown_source) %>">
```

Also: always render the `.embedded-multiplier` span (even when multiplier is
1.0) so the client-side scaler can show/hide it. Change lines 16-18 from
the conditional render to:

```erb
<span class="embedded-multiplier"<%= ' hidden' if cross_reference.multiplier == 1.0 %>>&times; <%= format_numeric(cross_reference.multiplier) %></span>
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n test_embedded_recipe_article_includes_data-base-multiplier`
Expected: PASS

**Step 5: Run full test suite**

Run: `rake test`
Expected: All pass. The existing `embedded recipe with multiplier shows scaled
quantities` test should still pass since the HTML structure is unchanged.

**Step 6: Commit**

```bash
git add app/views/recipes/_embedded_recipe.html.erb test/controllers/recipes_controller_test.rb
git commit -m "feat: add data-base-multiplier to embedded recipe articles"
```

---

### Task 2: Add `embedded` value to `recipe_state_controller` and skip scaling for embedded instances

This is the core bug fix — embedded cross-reference controllers must stop
independently scaling ingredients.

**Files:**
- Modify: `app/javascript/controllers/recipe_state_controller.js`
- Modify: `app/views/recipes/_embedded_recipe.html.erb:10`

**Step 1: Add the `embedded` Stimulus value**

In `recipe_state_controller.js`, add `embedded` to the static values:

```javascript
static values = { recipeId: String, versionHash: String, embedded: Boolean }
```

**Step 2: Guard scaling behind `!this.embeddedValue`**

In `connect()`, wrap the scaling-related calls so embedded instances only
set up cross-off:

```javascript
connect() {
  this.recipeId = this.hasRecipeIdValue ? this.recipeIdValue : document.body.dataset.recipeId
  this.versionHash = this.hasVersionHashValue ? this.versionHashValue : document.body.dataset.versionHash

  this.crossableItemNodes = Array.from(
    this.element.querySelectorAll('.ingredients li, .instructions p')
  ).filter(node => node.closest('[data-controller*="recipe-state"]') === this.element)
  this.sectionTogglerNodes = Array.from(
    this.element.querySelectorAll('section :is(h2, h3)')
  ).filter(node => node.closest('[data-controller*="recipe-state"]') === this.element)

  this.listeners = new ListenerManager()
  this.setupEventListeners()
  this.loadRecipeState()
}
```

Note: `setupScaleButton()` and `updateScaleButtonLabel()` removed from
`connect()`. They will be replaced in Task 4 by the scale panel event
listener.

**Step 3: Make `saveRecipeState` and `loadRecipeState` skip scale factor for embedded**

In `saveRecipeState()`, only include `scaleFactor` when not embedded:

```javascript
saveRecipeState() {
  const state = {
    lastInteractionTime: Date.now(),
    versionHash: this.versionHash,
    crossableItemState: {}
  }

  if (!this.embeddedValue) state.scaleFactor = this.scaleFactor || 1

  this.crossableItemNodes.forEach((node, idx) => {
    state.crossableItemState[idx] = node.classList.contains('crossed-off')
  })

  localStorage.setItem(`saved-state-for-${this.recipeId}`, JSON.stringify(state))
}
```

In `loadRecipeState()`, change the scale restoration block to skip for
embedded and store the factor as a number:

```javascript
if (scaleFactor && !this.embeddedValue) {
  this.scaleFactor = scaleFactor
  this.applyScale(scaleFactor)
}
```

**Step 4: Change `applyScale` to accept a number (not raw string)**

Replace the first line of `applyScale`:

```javascript
applyScale(factor) {
  // factor is now always a number — no parseFactor() call needed
```

Remove `const factor = this.parseFactor(rawInput)` from the top of the
method. The factor is passed as a number by both the scale panel event
handler (Task 4) and `loadRecipeState`.

**Step 5: Delete `setupScaleButton`, `updateScaleButtonLabel`, and `lastScaleInput`**

Remove these three methods/properties entirely. They are replaced by the
scale panel controller in Task 4.

**Step 6: Set the embedded flag in the view**

In `app/views/recipes/_embedded_recipe.html.erb`, add the embedded value to
the article tag:

```erb
data-recipe-state-embedded-value="true"
```

**Step 7: Run full test suite**

Run: `rake test`
Expected: All pass. The `renders scale button` test
(recipes_controller_test.rb:80) will need to be removed or updated in Task 5
when we remove the nav button.

**Step 8: Commit**

```bash
git add app/javascript/controllers/recipe_state_controller.js app/views/recipes/_embedded_recipe.html.erb
git commit -m "fix: skip scaling in embedded recipe-state controllers

Only the top-level recipe-state controller scales ingredients.
Embedded instances handle cross-off state only. This fixes the
bug where multiple controllers bound to the same scale button
and overwrote each other's scaling on reconnect."
```

---

### Task 3: Add cross-reference multiplier badge updating to `applyScale`

When the user scales, the `× 2` badge on embedded recipes should update
to reflect the effective multiplier.

**Files:**
- Modify: `app/javascript/controllers/recipe_state_controller.js`

**Step 1: Add multiplier badge updating to `applyScale`**

At the end of the `applyScale(factor)` method, after the yield block, add:

```javascript
this.element.querySelectorAll('article.embedded-recipe[data-base-multiplier]').forEach(article => {
  const base = parseFloat(article.dataset.baseMultiplier)
  const effective = base * factor
  const badge = article.querySelector('.embedded-multiplier')
  if (!badge) return

  if (Math.abs(effective - 1) < 0.001) {
    badge.hidden = true
  } else {
    badge.hidden = false
    const pretty = Number.isInteger(effective)
      ? effective
      : Math.round(effective * 100) / 100
    badge.textContent = `\u00D7 ${pretty}`
  }
})
```

**Step 2: Manual verification**

This is client-side JS — no Ruby test can verify it directly. Verify
manually after Task 5 when the full UI is wired up: scale
`/recipes/pasta-with-tomato-sauce` to 3× and confirm the `× 2` badge
updates to `× 6`.

**Step 3: Commit**

```bash
git add app/javascript/controllers/recipe_state_controller.js
git commit -m "fix: update cross-reference multiplier badges on scale change"
```

---

### Task 4: Create `scale_panel_controller` Stimulus controller

The new controller that owns the inline scaling UI.

**Files:**
- Create: `app/javascript/controllers/scale_panel_controller.js`

**Step 1: Create the controller**

```javascript
import { Controller } from "@hotwired/stimulus"

/**
 * Inline collapsible recipe scaling panel. Renders as a "Scale" link in the
 * recipe-meta line; clicking it expands a strip with preset scale buttons
 * (½×, 1×, 2×, 3×) and a free-form text input. Input supports integers,
 * decimals, and fractions (e.g. "3/2", "372/400"). Presets and input stay
 * in sync — clicking a preset updates the input and vice versa.
 *
 * Dispatches "scale-panel:change" on factor change, consumed by
 * recipe_state_controller for actual ingredient scaling. Listens for
 * "recipe-state:restored" to sync UI when localStorage state is loaded.
 *
 * - recipe_state_controller: consumes change events, dispatches restored
 */
const PRESETS = [
  { label: '\u00BD\u00D7', value: 0.5, input: '1/2' },
  { label: '1\u00D7', value: 1, input: '1' },
  { label: '2\u00D7', value: 2, input: '2' },
  { label: '3\u00D7', value: 3, input: '3' }
]

export default class extends Controller {
  static targets = ['toggle', 'panel', 'inner', 'input', 'preset', 'reset']

  connect() {
    this.open = false
    this.factor = 1

    this.element.addEventListener('recipe-state:restored', (e) => {
      this.syncToFactor(e.detail.factor)
    })
  }

  toggle() {
    this.open = !this.open
    this.panelTarget.style.gridTemplateRows = this.open ? '1fr' : '0fr'
    this.innerTarget.setAttribute('aria-hidden', !this.open)
  }

  selectPreset(e) {
    const idx = this.presetTargets.indexOf(e.currentTarget)
    if (idx === -1) return

    this.updateFactor(PRESETS[idx].value, PRESETS[idx].input)
  }

  onInput() {
    const raw = this.inputTarget.value.trim()
    const factor = this.parseFactor(raw)

    if (!(factor > 0 && isFinite(factor))) {
      this.inputTarget.classList.add('invalid')
      return
    }

    this.inputTarget.classList.remove('invalid')
    this.updateFactor(factor, raw)
  }

  reset() {
    this.updateFactor(1, '1')
  }

  updateFactor(factor, inputText) {
    this.factor = factor
    this.inputTarget.value = inputText
    this.inputTarget.classList.remove('invalid')
    this.highlightPreset(factor)
    this.updateToggleLabel(factor)
    this.updateResetVisibility(factor)

    this.dispatch('change', { detail: { factor }, bubbles: true })
  }

  syncToFactor(factor) {
    this.factor = factor
    const preset = PRESETS.find(p => Math.abs(p.value - factor) < 0.001)
    this.inputTarget.value = preset ? preset.input : String(Math.round(factor * 100) / 100)
    this.inputTarget.classList.remove('invalid')
    this.highlightPreset(factor)
    this.updateToggleLabel(factor)
    this.updateResetVisibility(factor)
  }

  highlightPreset(factor) {
    this.presetTargets.forEach((btn, idx) => {
      btn.classList.toggle('active', Math.abs(PRESETS[idx].value - factor) < 0.001)
    })
  }

  updateToggleLabel(factor) {
    if (!this.hasToggleTarget) return
    if (Math.abs(factor - 1) < 0.001) {
      this.toggleTarget.textContent = 'Scale'
    } else {
      const pretty = Number.isInteger(factor)
        ? factor
        : Math.round(factor * 100) / 100
      this.toggleTarget.textContent = `Scale (\u00D7${pretty})`
    }
  }

  updateResetVisibility(factor) {
    if (!this.hasResetTarget) return
    this.resetTarget.hidden = Math.abs(factor - 1) < 0.001
  }

  parseFactor(str) {
    str = str.trim()
    const frac = str.match(/^(\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)$/)
    if (frac) return parseFloat(frac[1]) / parseFloat(frac[2])
    const num = parseFloat(str)
    return isNaN(num) ? NaN : num
  }
}
```

Note: importmap auto-registers controllers in
`app/javascript/controllers/` via `pin_all_from` — no manual pin needed.

**Step 2: Commit**

```bash
git add app/javascript/controllers/scale_panel_controller.js
git commit -m "feat: add scale_panel_controller Stimulus controller"
```

---

### Task 5: Wire up the scale panel in recipe views and connect to recipe_state_controller

Add the HTML for the scale panel, hook up event listener in
recipe_state_controller, remove the nav Scale button, update tests.

**Files:**
- Modify: `app/views/recipes/_recipe_content.html.erb`
- Modify: `app/views/recipes/show.html.erb:7-14`
- Modify: `app/javascript/controllers/recipe_state_controller.js`
- Modify: `test/controllers/recipes_controller_test.rb`

**Step 1: Update the `renders scale button` test**

In `test/controllers/recipes_controller_test.rb`, replace the existing test
(line 80-84):

```ruby
test 'renders scale toggle in recipe meta' do
  get recipe_path('focaccia', kitchen_slug: kitchen_slug)

  assert_select '.recipe-meta .scale-toggle'
end

test 'renders scale panel with presets' do
  get recipe_path('focaccia', kitchen_slug: kitchen_slug)

  assert_select '.scale-panel'
  assert_select '.scale-preset', count: 4
  assert_select '.scale-input'
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /scale/`
Expected: FAIL — new selectors don't exist yet.

**Step 3: Remove the Scale button from the nav bar**

In `app/views/recipes/show.html.erb`, change the `extra_nav` content_for
(lines 7-14) to only include the Edit button:

```erb
<% content_for(:extra_nav) do %>
    <div>
      <% if current_member? %>
      <button type="button" id="edit-button" class="btn">Edit</button>
      <% end %>
    </div>
<% end %>
```

**Step 4: Add the scale toggle to recipe-meta and the panel HTML**

In `app/views/recipes/_recipe_content.html.erb`, wrap the scale panel in a
`data-controller="scale-panel"` div. Add the toggle link to the recipe-meta
line, and the collapsible panel between header and steps.

Replace the full content of the partial:

```erb
<%# locals: (recipe:, nutrition:) %>
<div id="recipe-content">
  <article class="recipe" data-controller="wake-lock recipe-state scale-panel">
    <header>
      <h1><%= recipe.title %></h1>
      <%- if recipe.description.present? -%>
      <p><%= recipe.description %></p>
      <%- end -%>
      <p class="recipe-meta">
        <%= link_to recipe.category.name, home_path(anchor: recipe.category.slug) %><%- if recipe.makes_quantity -%>
        <%- if nutrition&.dig('makes_unit_singular') -%>
        &middot; Makes <%= format_yield_with_unit(format_makes(recipe), nutrition['makes_unit_singular'], nutrition['makes_unit_plural']) %><%- else -%>
        &middot; Makes <%= format_yield_line(format_makes(recipe)) %><%- end -%><%- end -%><%- if recipe.serves -%>
        &middot; Serves <%= format_yield_line(recipe.serves.to_s) %><%- end -%>
        &middot; <a href="#" class="scale-toggle" data-scale-panel-target="toggle" data-action="click->scale-panel#toggle:prevent">Scale</a>
      </p>
    </header>

    <div class="scale-panel" data-scale-panel-target="panel">
      <div class="scale-panel-inner" data-scale-panel-target="inner" aria-hidden="true">
        <div class="scale-panel-row">
          <div class="scale-presets">
            <button type="button" class="scale-preset" data-scale-panel-target="preset" data-action="scale-panel#selectPreset">&frac12;&times;</button>
            <button type="button" class="scale-preset active" data-scale-panel-target="preset" data-action="scale-panel#selectPreset">1&times;</button>
            <button type="button" class="scale-preset" data-scale-panel-target="preset" data-action="scale-panel#selectPreset">2&times;</button>
            <button type="button" class="scale-preset" data-scale-panel-target="preset" data-action="scale-panel#selectPreset">3&times;</button>
          </div>
          <span class="scale-divider"></span>
          <div class="scale-input-group">
            <input type="text" class="scale-input" data-scale-panel-target="input" data-action="input->scale-panel#onInput" value="1" placeholder="e.g. 3/2" inputmode="text" autocomplete="off">
            <span class="scale-suffix">&times;</span>
          </div>
          <button type="button" class="scale-reset" data-scale-panel-target="reset" data-action="scale-panel#reset" hidden>Reset</button>
        </div>
      </div>
    </div>

    <% recipe.steps.each do |step| %>
      <%= render 'recipes/step', step: step, embedded: false, heading_level: 2, scale_factor: 1.0 %>
    <% end %>

    <%- if recipe.footer.present? -%>
    <footer>
      <%= render_markdown(recipe.footer) %>
    </footer>
    <%- end -%>

    <%- if nutrition && nutrition['totals']&.values&.any? { |v| v.to_f > 0 } -%>
      <%= render 'recipes/nutrition_table', nutrition: nutrition %>
    <%- end -%>
  </article>
</div>
```

Key decisions:
- `scale-panel` controller added to the same `<article>` as `recipe-state`
  (not a separate wrapper). This means dispatched events from scale-panel are
  directly available to recipe-state on the same element.
- `data-action="click->scale-panel#toggle:prevent"` uses `:prevent` modifier
  to stop the `<a href="#">` from scrolling.

**Step 5: Add the event listener in recipe_state_controller**

In `recipe_state_controller.js`, in `connect()`, add the scale-panel event
listener (for non-embedded instances only):

```javascript
if (!this.embeddedValue) {
  this.element.addEventListener('scale-panel:change', (e) => {
    this.scaleFactor = e.detail.factor
    this.applyScale(e.detail.factor)
    this.saveRecipeState()
  })
}
```

Also, in `loadRecipeState()`, after applying the saved scale, dispatch a
restoration event so the panel controller can sync:

```javascript
if (scaleFactor && !this.embeddedValue) {
  this.scaleFactor = scaleFactor
  this.applyScale(scaleFactor)
  this.dispatch('restored', { detail: { factor: scaleFactor }, bubbles: false })
}
```

Note: `this.dispatch()` is Stimulus's built-in dispatch — it automatically
prefixes with the controller identifier, emitting `recipe-state:restored`.
`bubbles: false` since scale-panel is on the same element.

**Step 6: Run tests**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /scale/`
Expected: PASS

Run: `rake test`
Expected: All pass.

**Step 7: Commit**

```bash
git add app/views/recipes/_recipe_content.html.erb app/views/recipes/show.html.erb \
  app/javascript/controllers/recipe_state_controller.js test/controllers/recipes_controller_test.rb
git commit -m "feat: wire scale panel into recipe views, remove nav Scale button"
```

---

### Task 6: Add CSS for the scale panel

Style the collapsed toggle, animated expand/collapse, and the panel contents.

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Add scale panel styles**

Insert after the `header .recipe-meta a:hover` block (around line 488) and
before `.scalable.scaled`:

```css
/* Scale toggle in recipe-meta */
.scale-toggle {
  color: inherit;
  text-decoration: none;
  cursor: pointer;
}

.scale-toggle:hover {
  text-decoration: underline;
}

/* Scale panel — animated expand/collapse */
.scale-panel {
  display: grid;
  grid-template-rows: 0fr;
  transition: grid-template-rows 0.2s ease;
}

.scale-panel.open {
  grid-template-rows: 1fr;
}

.scale-panel-inner {
  overflow: hidden;
}

.scale-panel-row {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding: 0.5rem 0 1.5rem;
}

.scale-presets {
  display: flex;
  gap: 0.25rem;
}

.scale-preset {
  font-family: var(--font-body);
  font-size: 0.8rem;
  padding: 0.25rem 0.55rem;
  border: 1px solid var(--rule);
  border-radius: 3px;
  background: var(--ground);
  color: var(--text);
  cursor: pointer;
  transition: background-color 0.12s ease, border-color 0.12s ease, color 0.12s ease;
  line-height: 1;
}

.scale-preset:hover {
  border-color: var(--red);
  color: var(--red);
}

.scale-preset.active {
  background: var(--red);
  border-color: var(--red);
  color: white;
}

.scale-divider {
  width: 1px;
  height: 1.25rem;
  background: var(--rule);
}

.scale-input-group {
  display: flex;
  align-items: center;
  gap: 0.3rem;
}

.scale-input {
  font-family: var(--font-body);
  font-size: 0.85rem;
  width: 4.5rem;
  padding: 0.25rem 0.4rem;
  border: 1px solid var(--rule-faint);
  border-radius: 3px;
  background: var(--input-bg);
  color: var(--text);
  text-align: center;
}

.scale-input:focus {
  outline: 2px solid var(--red);
  outline-offset: -1px;
  border-color: var(--red);
}

.scale-input.invalid {
  outline: 2px solid var(--danger-color);
  outline-offset: -1px;
  border-color: var(--danger-color);
}

.scale-suffix {
  color: var(--text-light);
  font-size: 0.8rem;
}

.scale-reset {
  font-family: var(--font-body);
  font-size: 0.75rem;
  padding: 0.2rem 0.5rem;
  border: none;
  border-radius: 3px;
  background: none;
  color: var(--text-light);
  cursor: pointer;
  transition: color 0.12s ease;
}

.scale-reset:hover {
  color: var(--red);
}
```

Note: the animation uses a class toggle (`.open` on `.scale-panel`) rather
than inline `style.gridTemplateRows` — update the controller's `toggle()`
method accordingly:

```javascript
toggle() {
  this.open = !this.open
  this.panelTarget.classList.toggle('open', this.open)
}
```

Remove the `aria-hidden` manipulation from `toggle()` — use CSS
`overflow: hidden` on `.scale-panel-inner` which handles visibility during
the transition.

**Step 2: Manual verification**

Start dev server (`bin/dev`), navigate to
`http://localhost:3030/recipes/pasta-with-tomato-sauce`:
- "Scale" link visible in recipe-meta line
- Click "Scale" → panel animates open
- Preset buttons, input field, divider visible
- Click preset → highlights, input updates
- Type in input → live validation
- Click "Scale" again → panel collapses
- Mobile (resize to 390px) → layout stays on one line

**Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css app/javascript/controllers/scale_panel_controller.js
git commit -m "feat: add scale panel CSS with animated expand/collapse"
```

---

### Task 7: Update `html_safe_allowlist.yml` and run lints

The embedded_recipe partial change (always rendering the multiplier span)
and any shifted line numbers need the allowlist updated.

**Files:**
- Modify: `config/html_safe_allowlist.yml` (if line numbers shifted)

**Step 1: Run lint**

Run: `bundle exec rubocop`
Expected: 0 offenses (no Ruby changes in this task, but verify).

**Step 2: Run html_safe audit**

Run: `rake lint:html_safe`

If any failures due to shifted line numbers in `_embedded_recipe.html.erb`
or `_recipe_content.html.erb`, update the line numbers in
`config/html_safe_allowlist.yml`.

**Step 3: Run full test suite**

Run: `rake test`
Expected: All pass.

**Step 4: Commit (if allowlist changed)**

```bash
git add config/html_safe_allowlist.yml
git commit -m "chore: update html_safe allowlist for shifted line numbers"
```

---

### Task 8: End-to-end manual verification and cleanup

Verify all scaling scenarios work correctly.

**Files:**
- Possibly: `app/javascript/controllers/recipe_state_controller.js` (any fixes)
- Possibly: `app/javascript/controllers/scale_panel_controller.js` (any fixes)

**Step 1: Verify basic scaling**

Navigate to `http://localhost:3030/recipes/focaccia`:
- Click "Scale" in recipe-meta → panel opens
- Click 2× → all quantities double, "Serves" line updates
- Click ½× → quantities halve
- Type `3/2` → quantities scale to 1.5×
- Type `372/400` → fractional scaling works
- Type `abc` → red border on input, no scaling change
- Click Reset → returns to 1×
- Panel toggle label shows "Scale (×2)" when at 2×

**Step 2: Verify cross-reference scaling**

Navigate to `http://localhost:3030/recipes/pasta-with-tomato-sauce`:
- Default: `× 2` badge visible on Simple Tomato Sauce
- Scale to 3× → badge updates to `× 6`
- Scale to ½× → badge updates to `× 1` → hidden
- Scale to 1× → badge shows `× 2` again
- All embedded ingredient quantities scale correctly

**Step 3: Verify state persistence**

- Scale to 2×, navigate away, come back → "Scale (×2)" in meta, click
  open → panel shows 2× highlighted
- Cross-off items, scale, navigate away, return → both states restored
- Edit recipe (change markdown) → stale scale state discarded (version
  hash mismatch)

**Step 4: Verify Turbo morph**

Open same recipe in two tabs (both logged in). Edit recipe in tab 1.
Tab 2 should morph and restore any saved scale factor.

**Step 5: Cleanup**

- Delete `parseFactor` from `recipe_state_controller.js` if it's no longer
  called (it was moved to `scale_panel_controller.js`)
- Remove any unused imports
- Verify `lastScaleInput` property is fully removed

**Step 6: Run all checks**

Run: `rake` (runs lint + test)
Expected: 0 offenses, all tests pass.

**Step 7: Final commit**

```bash
git add -A
git commit -m "chore: cleanup after scaling overhaul"
```
