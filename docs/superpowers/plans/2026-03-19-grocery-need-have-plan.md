# Grocery List: Need / On Hand Layout — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the grocery page so unchecked ("to buy") items are prominent and checked ("on hand") items collapse below a per-aisle divider, reducing noise and making the shopping list scannable.

**Architecture:** Pure view/CSS/JS change — no data model changes. The `_shopping_list.html.erb` partial is rewritten to render need/have zones per aisle. `<details>` elements are replaced with accessible `<section>`/`<button>` patterns. The JS controller gets on-hand collapse management, check animations, and updated morph preservation.

**Tech Stack:** Rails ERB views, CSS transitions/animations, Stimulus JS controller

**Spec:** `docs/superpowers/specs/2026-03-19-grocery-list-need-have-design.md`

---

### Task 1: Update GroceriesHelper — summary text and remove aisle_count_tag

The summary bar changes from "X of Y items needed" to "N items to buy". The
`aisle_count_tag` helper is no longer used (aisle headers are no longer
`<summary>` elements with count badges).

**Files:**
- Modify: `app/helpers/groceries_helper.rb`
- Modify: `test/helpers/groceries_helper_test.rb`

- [ ] **Step 1: Update helper tests for new summary format**

Replace all `shopping_list_count_text` tests. The new format:
- Empty list → `''`
- All unchecked → `"N items to buy"` (singular: `"1 item to buy"`)
- Some checked → `"N items to buy"` (only unchecked count, no "of Y")
- All checked → `"✓ All done!"`

```ruby
test 'shopping_list_count_text with no items returns empty string' do
  assert_equal '', shopping_list_count_text({}, Set.new)
end

test 'shopping_list_count_text with no checked items shows total to buy' do
  shopping_list = { 'Dairy' => [{ name: 'Milk' }, { name: 'Eggs' }] }

  assert_equal '2 items to buy', shopping_list_count_text(shopping_list, Set.new)
end

test 'shopping_list_count_text with some checked shows unchecked count' do
  shopping_list = { 'Dairy' => [{ name: 'Milk' }, { name: 'Eggs' }] }

  assert_equal '1 item to buy', shopping_list_count_text(shopping_list, Set.new(%w[Milk]))
end

test 'shopping_list_count_text with all checked shows done' do
  shopping_list = { 'Dairy' => [{ name: 'Milk' }] }

  assert_equal "\u2713 All done!", shopping_list_count_text(shopping_list, Set.new(%w[Milk]))
end

test 'shopping_list_count_text with single item uses singular' do
  shopping_list = { 'Dairy' => [{ name: 'Milk' }] }

  assert_equal '1 item to buy', shopping_list_count_text(shopping_list, Set.new)
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/helpers/groceries_helper_test.rb`
Expected: FAIL — format mismatch ("2 items" vs "2 items to buy", "1 of 2 items needed" vs "1 item to buy")

- [ ] **Step 3: Implement new `shopping_list_count_text`**

```ruby
def shopping_list_count_text(shopping_list, checked_off)
  total = shopping_list.each_value.sum(&:size)
  return '' if total.zero?

  remaining = total - shopping_list.each_value.sum { |items| items.count { |i| checked_off.include?(i[:name]) } }

  return "\u2713 All done!" if remaining.zero?

  "#{remaining} #{'item'.pluralize(remaining)} to buy"
end
```

- [ ] **Step 4: Remove `aisle_count_tag` helper and its tests**

Delete the `aisle_count_tag` method from `groceries_helper.rb`. Delete all
four `aisle_count_tag` tests from `groceries_helper_test.rb`.

- [ ] **Step 5: Run tests to verify pass**

Run: `ruby -Itest test/helpers/groceries_helper_test.rb`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add app/helpers/groceries_helper.rb test/helpers/groceries_helper_test.rb
git commit -m "Update grocery summary text format, remove aisle_count_tag"
```

---

### Task 2: Rewrite _shopping_list.html.erb partial

Replace the flat `<details>`-based aisle list with need/have zones. Each aisle
renders unchecked items first, then an on-hand divider + collapsible checked
section. Fully-checked aisles render as a single collapsed summary line.

**Files:**
- Modify: `app/views/groceries/_shopping_list.html.erb`
- Modify: `test/controllers/groceries_controller_test.rb`

**Key HTML structure:**

Mixed aisle:
```html
<section class="aisle-group" data-aisle="Produce">
  <h3 class="aisle-header">Produce</h3>
  <ul class="to-buy-items">
    <li data-item="Onions">...</li>
  </ul>
  <button class="on-hand-divider" type="button"
          aria-expanded="false" aria-controls="on-hand-0">
    <span class="on-hand-count">5 on hand</span>
    <span class="on-hand-arrow">▸</span>
  </button>
  <div id="on-hand-0" class="on-hand-items" hidden>
    <ul>
      <li data-item="Garlic">...</li>
    </ul>
  </div>
</section>
```

All-checked aisle:
```html
<section class="aisle-group aisle-complete" data-aisle="Pantry">
  <button class="aisle-complete-header" type="button"
          aria-expanded="false" aria-controls="on-hand-3">
    <span class="aisle-complete-check">✓</span>
    <span class="aisle-name">Pantry</span>
    <span class="aisle-complete-detail">12 items, all on hand</span>
  </button>
  <div id="on-hand-3" class="on-hand-items" hidden>
    <ul>...</ul>
  </div>
</section>
```

- [ ] **Step 1: Rewrite the partial**

Replace the entire contents of `_shopping_list.html.erb`:

```erb
<%# locals: (shopping_list:, checked_off:) %>
<div class="shopping-list-header">
  <h2>Shopping List</h2>
  <span id="item-count"><%= shopping_list_count_text(shopping_list, checked_off) %></span>
</div>

<% if shopping_list.empty? %>
  <p id="grocery-preview-empty">No items yet.</p>
<% else %>
  <% shopping_list.each_with_index do |(aisle, items), idx| %>
    <% unchecked, checked = items.partition { |i| checked_off.exclude?(i[:name]) } %>
    <% if unchecked.empty? %>
      <section class="aisle-group aisle-complete" data-aisle="<%= aisle %>">
        <button class="aisle-complete-header" type="button"
                aria-expanded="false" aria-controls="on-hand-<%= idx %>">
          <span class="aisle-complete-check">&#10003;</span>
          <span class="aisle-name"><%= aisle %></span>
          <span class="aisle-complete-detail"><%= checked.size %> <%= 'item'.pluralize(checked.size) %>, all on hand</span>
        </button>
        <div id="on-hand-<%= idx %>" class="on-hand-items" hidden>
          <ul>
            <% checked.each do |item| %>
              <li data-item="<%= item[:name] %>"<%= " title=\"Needed for: #{h item[:sources].join(', ')}\"".html_safe if item[:sources].present? %>>
                <label class="check-off">
                  <input type="checkbox" data-item="<%= item[:name] %>" checked>
                  <span class="item-text"><%= item[:name] %><% amount_str = format_amounts(item[:amounts]) %><% if amount_str.present? %> <span class="item-amount"><%= amount_str %></span><% end %></span>
                </label>
              </li>
            <% end %>
          </ul>
        </div>
      </section>
    <% else %>
      <section class="aisle-group" data-aisle="<%= aisle %>">
        <h3 class="aisle-header"><%= aisle %></h3>
        <ul class="to-buy-items">
          <% unchecked.each do |item| %>
            <li data-item="<%= item[:name] %>"<%= " title=\"Needed for: #{h item[:sources].join(', ')}\"".html_safe if item[:sources].present? %>>
              <label class="check-off">
                <input type="checkbox" data-item="<%= item[:name] %>">
                <span class="item-text"><%= item[:name] %><% amount_str = format_amounts(item[:amounts]) %><% if amount_str.present? %> <span class="item-amount"><%= amount_str %></span><% end %></span>
              </label>
            </li>
          <% end %>
        </ul>
        <% if checked.any? %>
          <button class="on-hand-divider" type="button"
                  aria-expanded="false" aria-controls="on-hand-<%= idx %>">
            <span class="on-hand-count"><%= checked.size %> on hand</span>
            <span class="on-hand-arrow">&#9656;</span>
          </button>
          <div id="on-hand-<%= idx %>" class="on-hand-items" hidden>
            <ul>
              <% checked.each do |item| %>
                <li data-item="<%= item[:name] %>"<%= " title=\"Needed for: #{h item[:sources].join(', ')}\"".html_safe if item[:sources].present? %>>
                  <label class="check-off">
                    <input type="checkbox" data-item="<%= item[:name] %>" checked>
                    <span class="item-text"><%= item[:name] %><% amount_str = format_amounts(item[:amounts]) %><% if amount_str.present? %> <span class="item-amount"><%= amount_str %></span><% end %></span>
                  </label>
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>
      </section>
    <% end %>
  <% end %>
<% end %>
```

- [ ] **Step 2: Update controller tests for new HTML structure**

Tests that assert `details.aisle` selectors need updating. The key changes:

Replace `assert_select 'details.aisle[data-aisle="Baking"]'` with
`assert_select 'section.aisle-group[data-aisle="Baking"]'`.

In `test 'show renders aisle sections when recipes selected'`:
```ruby
assert_select 'section.aisle-group[data-aisle="Baking"]'
assert_select 'li[data-item="Flour"]'
assert_select 'input[type="checkbox"][data-item="Flour"]'
```

In `test 'show pre-checks checked-off items'`:
```ruby
assert_select 'input[type="checkbox"][data-item="Flour"][checked]'
```
(This assertion is unchanged — the `checked` attribute works the same way.)

Also add a test for the all-checked aisle state:
```ruby
test 'show renders all-checked aisle as collapsed summary' do
  @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia


    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
    p.basis_grams = 30
    p.aisle = 'Baking'
  end

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  plan.apply_action('check', item: 'Flour', checked: true)

  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_select 'section.aisle-complete[data-aisle="Baking"]' do
    assert_select '.aisle-complete-header'
    assert_select '.on-hand-items[hidden]'
  end
end
```

Add a test for mixed aisle with on-hand divider:
```ruby
test 'show renders on-hand divider in mixed aisle' do
  @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia


    ## Mix (combine)

    - Flour, 3 cups
    - Yeast, 1 tsp

    Mix well.
  MD

  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
    p.basis_grams = 30
    p.aisle = 'Baking'
  end
  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Yeast') do |p|
    p.basis_grams = 4
    p.aisle = 'Baking'
  end

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  plan.apply_action('check', item: 'Flour', checked: true)

  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_select 'section.aisle-group[data-aisle="Baking"]' do
    assert_select '.to-buy-items li[data-item="Yeast"]'
    assert_select '.on-hand-divider'
    assert_select '.on-hand-items li[data-item="Flour"]'
  end
end
```

- [ ] **Step 3: Run tests to verify pass**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: All pass

- [ ] **Step 4: Run lint**

Run: `bundle exec rubocop app/views/groceries/_shopping_list.html.erb app/helpers/groceries_helper.rb`
Expected: No offenses. Update `config/html_safe_allowlist.yml` — the new
partial has `.html_safe` on 3 lines (was 1 in the old partial). Run
`rake lint:html_safe` to identify the new line numbers and update all 3
entries in the allowlist.

- [ ] **Step 5: Commit**

```bash
git add app/views/groceries/_shopping_list.html.erb test/controllers/groceries_controller_test.rb config/html_safe_allowlist.yml
git commit -m "Rewrite shopping list partial with need/have zones per aisle"
```

---

### Task 3: CSS — replace aisle styles with need/have layout

Remove the `<details>`/`<summary>` aisle styles and replace with the new
structure: `.aisle-header` (h3), `.to-buy-items`, `.on-hand-divider`,
`.on-hand-items`, `.aisle-complete`.

**Files:**
- Modify: `app/assets/stylesheets/groceries.css`

- [ ] **Step 1: Remove old aisle collapse styles**

Delete the following CSS blocks (approximately lines 153–258 in the current
file):
- `#shopping-list details.aisle > summary` and its pseudo-elements
- `#shopping-list details.aisle > summary::-webkit-details-marker`
- `#shopping-list details.aisle > summary::before`
- `#shopping-list details.aisle[open] > summary::before`
- `#shopping-list .aisle-items` (the grid-template-rows animation)
- `#shopping-list details.aisle[open] + .aisle-items`
- `#shopping-list .aisle-items > ul` (min-height/overflow)
- `#shopping-list details.aisle[open] + .aisle-items > ul`
- `.aisle-count` and `.aisle-done` (no longer used)

Keep: `.aisle-group` container styles (background, border, border-radius,
margin-bottom, overflow). Keep: `#shopping-list .aisle-items ul` and
`#shopping-list .aisle-items li` padding rules (rename selectors).

- [ ] **Step 2: Add new aisle structure styles**

```css
/* Aisle header (always visible, non-interactive) */
.aisle-header {
  padding: 0.6rem 0.75rem;
  margin: 0;
  font-family: var(--font-body);
  font-size: 0.8rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: var(--text);
}

/* To-buy items list */
.to-buy-items {
  list-style: none;
  margin: 0;
  padding: 0 0.75rem 0.5rem;
}

.to-buy-items li {
  padding: 0.3rem 0;
}

/* On-hand divider button */
.on-hand-divider {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
  padding: 0.4rem 0.75rem;
  border: none;
  border-top: 1px solid var(--rule-faint);
  background: none;
  cursor: pointer;
  font-family: var(--font-body);
  font-size: 0.75rem;
  color: var(--text-light);
  text-align: left;
}

.on-hand-divider:hover {
  color: var(--text-soft);
}

.on-hand-arrow {
  font-size: 0.6rem;
  transition: transform 0.15s ease;
}

.on-hand-divider[aria-expanded="true"] .on-hand-arrow {
  transform: rotate(90deg);
}

/* On-hand items container */
.on-hand-items {
  padding: 0 0.75rem 0.5rem;
}

.on-hand-items[hidden] {
  display: none;
}

.on-hand-items ul {
  list-style: none;
  margin: 0;
  padding: 0;
}

.on-hand-items li {
  padding: 0.3rem 0;
}

/* Fully-checked aisle */
.aisle-complete .aisle-complete-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
  padding: 0.6rem 0.75rem;
  border: none;
  background: none;
  cursor: pointer;
  font-family: var(--font-body);
  font-size: 0.8rem;
  text-align: left;
  color: var(--text-light);
}

.aisle-complete .aisle-complete-header:hover {
  color: var(--text-soft);
}

.aisle-complete-check {
  color: var(--text-light);
  font-size: 0.75rem;
}

.aisle-complete .aisle-name {
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.1em;
}

.aisle-complete-detail {
  margin-left: auto;
  font-size: 0.75rem;
}
```

- [ ] **Step 3: Add check animation for on-hand transition**

```css
/* Item slide animation when checking off */
@keyframes check-slide-down {
  from { opacity: 1; max-height: 2.5rem; }
  to   { opacity: 0; max-height: 0; padding: 0; }
}

.item-checking {
  animation: check-slide-down 0.3s ease forwards;
  overflow: hidden;
}

/* Item appearing in on-hand section */
@keyframes check-slide-in {
  from { opacity: 0; max-height: 0; }
  to   { opacity: 1; max-height: 2.5rem; }
}

.item-appearing {
  animation: check-slide-in 0.2s ease forwards;
}
```

- [ ] **Step 4: Update print styles**

Replace the old print rules that reference `details.aisle` selectors:

```css
@media print {
  /* Hide on-hand sections, dividers, and fully-checked aisles */
  .on-hand-divider,
  .on-hand-items,
  .aisle-complete {
    display: none !important;
  }

  /* Aisle header as simple bold header in print */
  .aisle-header {
    padding: 0.2rem 0;
  }

  /* Force all items visible (no hidden states) */
  #shopping-list .to-buy-items {
    padding: 0 0 0.25rem 0.25rem;
  }

  /* Summary as simple bold header */
  /* (remove old details.aisle > summary rules) */

  /* Hide the triangle arrow indicator — no longer needed (was for details) */
}
```

Also remove these stale print rules that reference deleted selectors:
- `#shopping-list .aisle-items { grid-template-rows: 1fr !important; }`
- `#shopping-list details.aisle > summary { ... }`
- `#shopping-list details.aisle > summary::before { display: none; }`

Update tightened spacing selectors — replace `.aisle-items ul` / `.aisle-items
li` with `.to-buy-items` / `.to-buy-items li`.

Keep the existing print rules for: page margins, hiding UI elements
(`#custom-items-section`, `.shopping-list-header`, etc.), 4-column grid,
checkbox styles, `.aisle-group` break-inside/background overrides, `.check-off`
font/gap. Update the checked-item-hide selector to work with the new structure:

```css
/* Exclude checked-off items from print (safety net — on-hand section
   is already hidden, but this catches any edge cases) */
#shopping-list li:has(.check-off input:checked) {
  display: none;
}

/* Hide aisle groups that have no to-buy items in print */
#shopping-list .aisle-group:not(:has(.to-buy-items li)) {
  display: none;
}
```

- [ ] **Step 5: Commit**

```bash
git add app/assets/stylesheets/groceries.css
git commit -m "Replace aisle collapse CSS with need/have zone styles"
```

---

### Task 4: JS — on-hand collapse, localStorage, and morph preservation

Replace aisle `<details>` collapse management with on-hand section
expand/collapse. New localStorage key. All-checked aisle expand/collapse.
Morph preservation for on-hand state.

**Files:**
- Modify: `app/javascript/controllers/grocery_ui_controller.js`

- [ ] **Step 1: Replace aisle collapse with on-hand collapse**

Remove these methods entirely:
- `saveAisleCollapse()`
- `restoreAisleCollapse()`
- `loadCollapsedAisles()`
- `updateAisleCount()` (no longer used — aisle count badges are gone)

The `toggle` event listener in `bindShoppingListEvents` (for `details.aisle`)
is also removed.

Replace with on-hand section management. In `connect()`:

```javascript
connect() {
  this.onHandKey = `grocery-on-hand-${this.element.dataset.kitchenSlug}`
  this.listeners = new ListenerManager()
  this.pendingTimers = []

  this.cleanupOldStorage()
  this.bindShoppingListEvents()
  this.bindCustomItemInput()
  this.bindOnHandToggle()
  this.restoreOnHandState()

  this.listeners.add(document, "turbo:before-render", (e) => this.preserveOnHandStateOnRefresh(e))
}

disconnect() {
  this.pendingTimers.forEach(id => clearTimeout(id))
  this.pendingTimers = []
  this.listeners.teardown()
}
```

New methods:

```javascript
cleanupOldStorage() {
  try {
    localStorage.removeItem(`grocery-aisles-${this.element.dataset.kitchenSlug}`)
  } catch { /* ignore */ }
}

bindOnHandToggle() {
  this.listeners.add(this.element, "click", (e) => {
    const btn = e.target.closest(".on-hand-divider, .aisle-complete-header")
    if (!btn) return

    const targetId = btn.getAttribute("aria-controls")
    const target = document.getElementById(targetId)
    if (!target) return

    const expanding = target.hidden
    target.hidden = !expanding
    btn.setAttribute("aria-expanded", String(expanding))

    this.saveOnHandState()
  })
}

saveOnHandState() {
  const expanded = {}
  this.element.querySelectorAll("[aria-controls^='on-hand-']").forEach(btn => {
    const aisle = btn.closest(".aisle-group")?.dataset.aisle
    if (aisle) expanded[aisle] = btn.getAttribute("aria-expanded") === "true"
  })

  try {
    localStorage.setItem(this.onHandKey, JSON.stringify(expanded))
  } catch { /* localStorage full */ }
}

restoreOnHandState() {
  const state = this.loadOnHandState()
  this.element.querySelectorAll("[aria-controls^='on-hand-']").forEach(btn => {
    const aisle = btn.closest(".aisle-group")?.dataset.aisle
    if (!aisle || !state[aisle]) return

    const targetId = btn.getAttribute("aria-controls")
    const target = document.getElementById(targetId)
    if (!target) return

    target.hidden = false
    btn.setAttribute("aria-expanded", "true")
  })
}

loadOnHandState() {
  try {
    const raw = localStorage.getItem(this.onHandKey)
    return raw ? JSON.parse(raw) : {}
  } catch {
    return {}
  }
}

preserveOnHandStateOnRefresh(event) {
  if (!event.detail.render) return
  this.saveOnHandState()
  const originalRender = event.detail.render
  event.detail.render = async (...args) => {
    await originalRender(...args)
    this.restoreOnHandState()
  }
}
```

- [ ] **Step 2: Update `bindShoppingListEvents` — remove toggle listener**

Remove the `toggle` event listener that was for `details.aisle`:

```javascript
// DELETE this block:
this.listeners.add(this.element, "toggle", (e) => {
  if (e.target.matches("#shopping-list details.aisle")) this.saveAisleCollapse()
}, true)
```

- [ ] **Step 3: Run tests and verify manually**

Run: `rake test`
Expected: All pass (JS changes don't affect Ruby tests)

Start the dev server (`bin/dev`), open the groceries page, and verify:
- On-hand sections toggle on click
- Collapse state persists across page loads
- Fully-checked aisles expand/collapse on click
- Old `grocery-aisles-*` localStorage key is cleaned up

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js
git commit -m "Replace aisle collapse with on-hand section toggle"
```

---

### Task 5: JS — optimistic check animations and summary bar

Add the check/uncheck animation: strikethrough → 400ms pause → slide item to
on-hand section. Uncheck reverses: slide item back to to-buy zone. Summary bar
updates optimistically. Morph snap-to-completion for mid-animation items.

**Files:**
- Modify: `app/javascript/controllers/grocery_ui_controller.js`

- [ ] **Step 1: Add check animation in `bindShoppingListEvents`**

Replace the current `change` handler with one that animates:

```javascript
bindShoppingListEvents() {
  this.listeners.add(this.element, "change", (e) => {
    const cb = e.target
    if (!cb.matches('#shopping-list .check-off input[type="checkbox"]')) return

    const name = cb.dataset.item
    if (!name) return

    const li = cb.closest("li[data-item]")
    const aisle = cb.closest(".aisle-group")

    if (cb.checked) {
      this.animateCheck(li, aisle)
    } else {
      this.animateUncheck(li, aisle)
    }

    this.updateItemCount()
    sendAction(this.element.dataset.checkUrl, { item: name, checked: cb.checked })
  })
}
```

- [ ] **Step 2: Implement `animateCheck` — strikethrough, pause, slide to on-hand**

```javascript
animateCheck(li, aisle) {
  if (!li || !aisle) return

  // Phase 1: strikethrough + fade (immediate via CSS :checked selector)
  // Phase 2: pause, then slide out of to-buy
  const timerId = setTimeout(() => {
    this.pendingTimers = this.pendingTimers.filter(id => id !== timerId)
    li.classList.add("item-checking")
    li.addEventListener("animationend", () => {
      this.moveToOnHand(li, aisle)
    }, { once: true })
  }, 400)
  this.pendingTimers.push(timerId)
}

moveToOnHand(li, aisle) {
  let onHandList = aisle.querySelector(".on-hand-items ul")
  let divider = aisle.querySelector(".on-hand-divider")

  // Create on-hand section if this is the first checked item in an
  // all-unchecked aisle (server didn't render the section).
  // Build entirely with createElement/textContent (strict CSP).
  if (!onHandList) {
    const toBuyList = aisle.querySelector(".to-buy-items")
    const idx = Array.from(document.querySelectorAll(".aisle-group")).indexOf(aisle)

    divider = document.createElement("button")
    divider.className = "on-hand-divider"
    divider.type = "button"
    divider.setAttribute("aria-expanded", "false")
    divider.setAttribute("aria-controls", `on-hand-${idx}`)

    const countSpan = document.createElement("span")
    countSpan.className = "on-hand-count"
    countSpan.textContent = "0 on hand"
    divider.appendChild(countSpan)

    const arrowSpan = document.createElement("span")
    arrowSpan.className = "on-hand-arrow"
    arrowSpan.textContent = "\u25B8"
    divider.appendChild(arrowSpan)

    const onHandDiv = document.createElement("div")
    onHandDiv.id = `on-hand-${idx}`
    onHandDiv.className = "on-hand-items"
    onHandDiv.hidden = true

    const ul = document.createElement("ul")
    onHandDiv.appendChild(ul)

    if (toBuyList) {
      toBuyList.after(divider, onHandDiv)
    } else {
      aisle.appendChild(divider)
      aisle.appendChild(onHandDiv)
    }
    onHandList = ul
  }

  // Move item to on-hand section
  li.classList.remove("item-checking")
  li.classList.add("item-appearing")
  onHandList.appendChild(li)
  li.addEventListener("animationend", () => {
    li.classList.remove("item-appearing")
  }, { once: true })

  // Update on-hand count
  this.updateOnHandCount(divider, aisle)

  // Check if aisle is now fully checked
  const toBuyList = aisle.querySelector(".to-buy-items")
  if (toBuyList && toBuyList.children.length === 0) {
    this.collapseCompleteAisle(aisle)
  }
}

updateOnHandCount(divider, aisle) {
  if (!divider) return
  const count = aisle.querySelectorAll(".on-hand-items li[data-item]").length
  const countSpan = divider.querySelector(".on-hand-count")
  if (countSpan) countSpan.textContent = `${count} on hand`
}
```

- [ ] **Step 3: Implement `animateUncheck` — slide back to to-buy**

```javascript
animateUncheck(li, aisle) {
  if (!li || !aisle) return

  let toBuyList = aisle.querySelector(".to-buy-items")

  // If aisle was all-checked (no .to-buy-items), create the list and header
  // to transition from all-checked to mixed state.
  if (!toBuyList) {
    const header = aisle.querySelector(".aisle-complete-header")
    const aisleName = aisle.dataset.aisle

    const h3 = document.createElement("h3")
    h3.className = "aisle-header"
    h3.textContent = aisleName

    toBuyList = document.createElement("ul")
    toBuyList.className = "to-buy-items"

    // Insert header + list before the on-hand divider or at start of aisle
    const divider = aisle.querySelector(".on-hand-divider")
    if (divider) {
      aisle.insertBefore(toBuyList, divider)
      aisle.insertBefore(h3, toBuyList)
    } else if (header) {
      header.after(h3, toBuyList)
    }
    aisle.classList.remove("aisle-complete")
  }

  li.classList.add("item-appearing")
  toBuyList.appendChild(li)
  li.addEventListener("animationend", () => {
    li.classList.remove("item-appearing")
  }, { once: true })

  // Update on-hand count
  const divider = aisle.querySelector(".on-hand-divider")
  this.updateOnHandCount(divider, aisle)

  // Remove divider if no more on-hand items
  const onHandList = aisle.querySelector(".on-hand-items ul")
  if (onHandList && onHandList.children.length === 0) {
    const onHandSection = aisle.querySelector(".on-hand-items")
    if (divider) divider.remove()
    if (onHandSection) onHandSection.remove()
  }
}
```

- [ ] **Step 4: Implement `collapseCompleteAisle`**

When the last unchecked item in an aisle is checked, transition the aisle to
the all-checked state. This is optimistic — the server morph will render the
correct structure. For the optimistic UI, just visually indicate completion:

```javascript
collapseCompleteAisle(aisle) {
  // The Turbo morph will soon rebuild with proper aisle-complete markup.
  // For optimistic feedback, add a visual class.
  aisle.classList.add("aisle-complete")
}
```

- [ ] **Step 5: Update `updateItemCount` for new format**

```javascript
updateItemCount() {
  const countEl = document.getElementById("item-count")
  if (!countEl) return

  const allItems = document.querySelectorAll("#shopping-list li[data-item]")
  const total = allItems.length
  const unchecked = Array.from(allItems).filter(li => {
    const cb = li.querySelector('input[type="checkbox"]')
    return cb && !cb.checked
  }).length

  if (total === 0) {
    countEl.textContent = ""
  } else if (unchecked === 0) {
    countEl.textContent = "\u2713 All done!"
  } else {
    countEl.textContent = `${unchecked} ${unchecked === 1 ? "item" : "items"} to buy`
  }
}
```

- [ ] **Step 6: Add morph snap-to-completion**

Items that are mid-animation when a Turbo morph arrives should snap to their
end state. Add to the morph preservation hook:

```javascript
preserveOnHandStateOnRefresh(event) {
  if (!event.detail.render) return

  // Snap any in-progress animations to completion
  this.element.querySelectorAll(".item-checking, .item-appearing").forEach(el => {
    el.classList.remove("item-checking", "item-appearing")
    el.style.animation = "none"
  })

  this.saveOnHandState()
  const originalRender = event.detail.render
  event.detail.render = async (...args) => {
    await originalRender(...args)
    this.restoreOnHandState()
  }
}
```

- [ ] **Step 7: Verify manually**

Start `bin/dev`. On the groceries page:
- Check an item → strikethrough, pause, slides below divider
- Summary bar decrements
- Uncheck from on-hand → slides back up
- Summary bar increments
- Check last item in aisle → aisle collapses
- Turbo morph (from another device) doesn't break mid-animation

- [ ] **Step 8: Run full test suite**

Run: `rake test`
Expected: All pass

- [ ] **Step 9: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js
git commit -m "Add optimistic check animations and summary bar updates"
```

---

### Task 6: Update html_safe_allowlist, run lint, final integration

Ensure the `html_safe_allowlist.yml` is correct (line numbers may have shifted
in the partial rewrite), run RuboCop, and verify the full test suite.

**Files:**
- Modify: `config/html_safe_allowlist.yml` (if needed)

- [ ] **Step 1: Run the html_safe audit**

Run: `rake lint:html_safe`
Expected: If the `_shopping_list.html.erb` `.html_safe` call changed line
numbers, update the allowlist file.

- [ ] **Step 2: Run full lint**

Run: `bundle exec rubocop`
Expected: 0 offenses

- [ ] **Step 3: Run full test suite**

Run: `rake test`
Expected: All pass

- [ ] **Step 4: Manual testing checklist**

With `bin/dev` running:
1. Select 2–3 recipes on the menu page
2. Go to groceries — verify need/have layout renders correctly
3. Check an item — verify animation and summary bar update
4. Check all items in an aisle — verify auto-collapse
5. Expand a collapsed all-checked aisle — verify items visible
6. Uncheck from on-hand — verify item returns to to-buy zone
7. Refresh page — verify on-hand collapse state persists
8. Print the page — verify only to-buy items print
9. Open on a second device — verify ActionCable morph works

- [ ] **Step 5: Final commit (if any fixups needed)**

```bash
git add -A
git commit -m "Grocery need/have layout: final polish

Resolves #256"
```
