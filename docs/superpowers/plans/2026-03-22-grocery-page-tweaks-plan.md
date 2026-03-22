# Grocery Page Tweaks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve groceries page UX — collapsible Inventory Check with tooltips, per-section aisle collapsibles, reduced layout shift.

**Architecture:** Template restructuring + CSS updates + localStorage schema migration. No backend changes. Three files touched: the shopping list partial, the groceries stylesheet, and the grocery UI Stimulus controller.

**Tech Stack:** Rails ERB templates, CSS (collapse animation via `grid-template-rows`), Stimulus JS, localStorage.

**Spec:** `docs/superpowers/specs/2026-03-22-grocery-page-tweaks-design.md`

---

## File Map

| File | Role |
|---|---|
| `app/views/groceries/_shopping_list.html.erb` | Shopping list partial — inventory check + aisle rendering |
| `app/assets/stylesheets/groceries.css` | Grocery-specific styles including print |
| `app/javascript/controllers/grocery_ui_controller.js` | Collapse persistence, checkbox handling, morph state restoration |

---

### Task 1: Restructure the shopping list partial

**Files:**
- Modify: `app/views/groceries/_shopping_list.html.erb` (complete rewrite)

- [ ] **Step 1: Rewrite the partial**

Replace the entire content of `_shopping_list.html.erb` with the new structure.
Key changes from current code:

1. **Inventory Check** moves above the shopping list header, wrapped in
   `<details class="collapse-header inventory-check-section">` with a
   `collapse-body`/`collapse-inner` pair. Summary: "Inventory Check (N)".
   Defaults to `open`. Each `<li>` gets a `title` tooltip built from
   `item[:sources]` (same pattern as to-buy items on current lines 74-76).

2. **Shopping list header** (`<div class="shopping-list-header">`) renders
   after the inventory check section.

3. **Aisle loop** — no more `aisle-complete` branch. Every aisle renders:
   - `<h3 class="aisle-header">` with aisle name + checkmark span (visible
     only when `to_buy` is empty)
   - If `to_buy` is non-empty: a `<div class="aisle-section">` wrapping
     `<details class="collapse-header to-buy-section" open>` with summary
     "N to buy", then `<div class="collapse-body"><div class="collapse-inner"><ul class="to-buy-items">`.
   - If `on_hand` is non-empty: a `<div class="aisle-section">` wrapping
     `<details class="collapse-header on-hand-section" open>` with summary
     "N on hand", then `<div class="collapse-body on-hand-body"><div class="collapse-inner"><ul class="on-hand-items">`.
   - Each section hidden when its item list is empty.

```erb
<%# locals: (shopping_list:, on_hand_names:, on_hand_data:, custom_items:) %>
<% if shopping_list.present? %>
  <% zone_for = ->(name) { item_zone(name:, on_hand_names:, on_hand_data:, custom_items:) } %>
  <% all_items = shopping_list.values.flatten %>
  <% inventory_items = all_items.select { |i| zone_for.(i[:name]) == :inventory_check } %>
  <% inventory_items.sort_by! { |i| [-i[:sources].size, i[:name]] } %>

  <% if inventory_items.any? %>
    <details class="collapse-header inventory-check-section" open data-section="inventory-check">
      <summary>
        <span class="section-header">Inventory Check (<%= inventory_items.size %>)</span>
      </summary>
    </details>
    <div class="collapse-body">
      <div class="collapse-inner">
        <p class="inventory-check-hint">Check your kitchen &mdash; do you have these?</p>
        <ul class="inventory-check-items">
          <% inventory_items.each do |item| %>
            <% sources_tip = item[:sources].present? ? "Needed for: #{h item[:sources].join(', ')}" : nil %>
            <li data-item="<%= item[:name] %>"<%= " title=\"#{h sources_tip}\"".html_safe if sources_tip %>>
              <button class="btn btn-sm btn-need-it" data-grocery-action="need-it"
                      data-item="<%= item[:name] %>">Need It</button>
              <span class="item-text"><%= item[:name] %>
                <% if item[:amounts].any? %>
                  <span class="item-amount"><%= format_amounts(item[:amounts], uncounted: item[:uncounted]) %></span>
                <% end %>
              </span>
              <button class="btn btn-sm btn-have-it" data-grocery-action="have-it"
                      data-item="<%= item[:name] %>">Have It</button>
            </li>
          <% end %>
        </ul>
      </div>
    </div>
  <% end %>
<% end %>

<div class="shopping-list-header">
  <h2>Shopping List</h2>
  <span id="item-count"><%= shopping_list_count_text(shopping_list, on_hand_names, on_hand_data:, custom_items:) %></span>
</div>

<% if shopping_list.empty? %>
  <p id="grocery-preview-empty">No items yet.</p>
<% else %>
  <% zone_for ||= ->(name) { item_zone(name:, on_hand_names:, on_hand_data:, custom_items:) } %>

  <% shopping_list.each do |aisle, items| %>
    <% to_buy = items.select { |i| zone_for.(i[:name]) == :to_buy } %>
    <% on_hand = items.select { |i| zone_for.(i[:name]) == :on_hand } %>
    <% next if to_buy.empty? && on_hand.empty? %>

    <section class="aisle-group" data-aisle="<%= aisle %>">
      <h3 class="aisle-header">
        <%= aisle %>
        <% if to_buy.empty? %>
          <span class="aisle-check">&#10003;</span>
        <% end %>
      </h3>

      <% if to_buy.any? %>
        <div class="aisle-section">
          <details class="collapse-header to-buy-section" open data-section="to-buy">
            <summary>
              <span class="section-count"><%= to_buy.size %> to buy</span>
            </summary>
          </details>
          <div class="collapse-body">
            <div class="collapse-inner">
              <ul class="to-buy-items">
                <% to_buy.each do |item| %>
                  <% sources_tip = item[:sources].present? ? "Needed for: #{h item[:sources].join(', ')}" : nil %>
                  <% restock_tip = restock_tooltip(item[:name], on_hand_data, on_hand_names) %>
                  <% full_tip = [sources_tip, restock_tip].compact.join("\n") %>
                  <li data-item="<%= item[:name] %>"<%= " title=\"#{h full_tip}\"".html_safe if full_tip.present? %>>
                    <label class="check-off">
                      <input class="custom-checkbox" type="checkbox" data-item="<%= item[:name] %>">
                      <span class="item-text"><%= item[:name] %><% amount_str = format_amounts(item[:amounts], uncounted: item[:uncounted]) %><% if amount_str.present? %> <span class="item-amount"><%= amount_str %></span><% end %></span>
                    </label>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
        </div>
      <% end %>

      <% if on_hand.any? %>
        <div class="aisle-section">
          <details class="collapse-header on-hand-section" open data-section="on-hand">
            <summary>
              <span class="section-count"><%= on_hand.size %> on hand</span>
            </summary>
          </details>
          <div class="collapse-body on-hand-body">
            <div class="collapse-inner">
              <ul class="on-hand-items">
                <% on_hand.each do |item| %>
                  <% sources_tip = item[:sources].present? ? "Needed for: #{h item[:sources].join(', ')}" : nil %>
                  <% restock_tip = restock_tooltip(item[:name], on_hand_data, on_hand_names) %>
                  <% full_tip = [sources_tip, restock_tip].compact.join("\n") %>
                  <li data-item="<%= item[:name] %>"<%= " title=\"#{h full_tip}\"".html_safe if full_tip.present? %>>
                    <label class="check-off">
                      <input class="custom-checkbox" type="checkbox" data-item="<%= item[:name] %>" checked>
                      <span class="item-text"><%= item[:name] %><% amount_str = format_amounts(item[:amounts], uncounted: item[:uncounted]) %><% if amount_str.present? %> <span class="item-amount"><%= amount_str %></span><% end %></span>
                    </label>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
        </div>
      <% end %>
    </section>
  <% end %>
<% end %>
```

- [ ] **Step 2: Verify the page renders**

Run: `bin/dev` (if not running), load the groceries page in the browser.
Expected: Inventory Check at top (collapsible), then Shopping List header,
then aisles with separate "to buy" / "on hand" collapsibles. No "all on hand"
text. Checkmark after aisle name when all items are on hand.

- [ ] **Step 3: Commit**

```bash
git add app/views/groceries/_shopping_list.html.erb
git commit -m "Restructure shopping list: collapsible inventory check, per-section aisle collapsibles"
```

---

### Task 2: Update groceries CSS

**Files:**
- Modify: `app/assets/stylesheets/groceries.css`

- [ ] **Step 1: Update styles**

Changes to make:

1. **Remove `aisle-complete` styles** — delete the `aisle-complete-header`,
   `aisle-complete-check`, `.aisle-complete .aisle-name`, and
   `aisle-complete-detail` rule blocks (current lines 154-180).

2. **Update `.inventory-check-section`** — it's now a `<details>` collapse
   header, not a `<section>`. Remove `padding` from the section (the
   collapse-inner handles it). The `summary` needs the section header styling.

```css
.inventory-check-section {
  margin-bottom: 0.75rem;
  background: var(--surface-alt);
  border: 1px solid var(--aisle-row-border);
  border-radius: 6px;
}

.inventory-check-section summary {
  padding: 0.6rem 0.75rem;
}

.inventory-check-section + .collapse-body {
  padding: 0 0.75rem 0.5rem;
}

.inventory-check-section .section-header {
  font-family: var(--font-body);
  font-size: 0.8rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: var(--text);
}
```

3. **Update `.on-hand-section`** — no longer needs `border: none` override.
   Remove the `.on-hand-divider` rules (current lines 131-141) since that
   class no longer exists. The on-hand section now uses the standard collapse
   pattern with the `section-count` summary text.

4. **Add shared section summary styles:**

```css
.to-buy-section summary,
.on-hand-section summary {
  padding: 0.4rem 0.75rem;
  font-family: var(--font-body);
  font-size: 0.75rem;
  color: var(--text-light);
}

.to-buy-section summary:hover,
.on-hand-section summary:hover {
  color: var(--text-soft);
}
```

5. **Add aisle checkmark style** (after aisle name, not before):

```css
.aisle-check {
  color: var(--text-light);
  font-size: 0.75rem;
  margin-left: 0.35rem;
}
```

6. **Update print styles:**

Replace the `.on-hand-section, .on-hand-body, .aisle-complete` hide rule
(current lines 337-341) with:

```css
.on-hand-section,
.on-hand-body {
  display: none !important;
}

/* Force to-buy details open in print */
details.to-buy-section {
  display: block !important;
}

details.to-buy-section > summary {
  display: none !important;
}
```

Also hide the inventory check section in print (it's actionable, not
printable): add `.inventory-check-section` and its sibling `.collapse-body`
to the print hide rules. Use:

```css
details.inventory-check-section,
details.inventory-check-section + .collapse-body {
  display: none !important;
}
```

- [ ] **Step 2: Verify styles**

Reload the groceries page. Check:
- Inventory check has collapse animation (triangle rotates, content slides)
- Aisle sections have independent collapse animations
- Checkmark appears after aisle name (not before) when all items on hand
- Print preview hides on-hand sections and inventory check

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/groceries.css
git commit -m "Update grocery styles for per-section collapsibles"
```

---

### Task 3: Update Stimulus controller — localStorage schema + persistence

**Files:**
- Modify: `app/javascript/controllers/grocery_ui_controller.js`

- [ ] **Step 1: Update `saveOnHandState()` to new schema**

The new schema stores per-aisle objects with `to_buy` and `on_hand` keys,
plus a top-level `_inventory_check` key. Replace the current method:

```javascript
saveCollapseState() {
  const state = {}

  const invCheck = this.element.querySelector("details.inventory-check-section")
  if (invCheck) state._inventory_check = invCheck.open

  this.element.querySelectorAll(".aisle-group").forEach(group => {
    const aisle = group.dataset.aisle
    if (!aisle) return

    const toBuy = group.querySelector("details.to-buy-section")
    const onHand = group.querySelector("details.on-hand-section")

    state[aisle] = {
      to_buy: toBuy ? toBuy.open : true,
      on_hand: onHand ? onHand.open : true
    }
  })

  try {
    localStorage.setItem(this.onHandKey, JSON.stringify(state))
  } catch { /* localStorage full */ }
}
```

- [ ] **Step 2: Update `restoreOnHandState()` with migration + close support**

Must handle old boolean format and close sections where stored value is false:

```javascript
restoreCollapseState() {
  const state = this.loadCollapseState()

  const invCheck = this.element.querySelector("details.inventory-check-section")
  if (invCheck && state._inventory_check === false) invCheck.open = false

  this.element.querySelectorAll(".aisle-group").forEach(group => {
    const aisle = group.dataset.aisle
    if (!aisle || !state[aisle]) return

    let entry = state[aisle]
    if (typeof entry === "boolean") {
      entry = { to_buy: true, on_hand: entry }
    }

    const toBuy = group.querySelector("details.to-buy-section")
    const onHand = group.querySelector("details.on-hand-section")

    if (toBuy && entry.to_buy === false) toBuy.open = false
    if (onHand && entry.on_hand === false) onHand.open = false
  })
}
```

- [ ] **Step 3: Update `loadOnHandState()` → `loadCollapseState()`**

Rename for clarity (same implementation, just renamed):

```javascript
loadCollapseState() {
  try {
    const raw = localStorage.getItem(this.onHandKey)
    return raw ? JSON.parse(raw) : {}
  } catch {
    return {}
  }
}
```

- [ ] **Step 4: Update `bindOnHandToggle()` to listen for all collapse toggles**

The toggle listener must now catch both `to-buy-section` and `on-hand-section`
details, plus the inventory check:

```javascript
bindCollapseToggle() {
  this.listeners.add(this.element, "toggle", (e) => {
    if (!e.target.matches("details.to-buy-section, details.on-hand-section, details.inventory-check-section")) return
    this.saveCollapseState()
  }, true)
}
```

- [ ] **Step 5: Update `preserveOnHandStateOnRefresh()` and `connect()`**

Rename method references and update `hideEmptyInventoryCheck` to work with the
new `<details>` structure:

In `connect()`:
- `this.bindOnHandToggle()` → `this.bindCollapseToggle()`
- `this.restoreOnHandState()` → `this.restoreCollapseState()`

In `preserveOnHandStateOnRefresh()`:
- `this.saveOnHandState()` → `this.saveCollapseState()`
- `this.restoreOnHandState()` → `this.restoreCollapseState()`

Update `hideEmptyInventoryCheck()`:
```javascript
hideEmptyInventoryCheck() {
  const details = this.element.querySelector("details.inventory-check-section")
  if (!details) return

  const remaining = details.closest("#shopping-list")
    ?.querySelectorAll(".inventory-check-items li")
  if (!remaining || remaining.length === 0) {
    details.remove()
    details.nextElementSibling?.remove()  // collapse-body
  }
}
```

- [ ] **Step 6: Verify behavior**

Test in browser:
1. Collapse the inventory check section → reload → should stay collapsed
2. Collapse "to buy" in one aisle → reload → should stay collapsed
3. Collapse "on hand" in one aisle → reload → should stay collapsed
4. Clear localStorage → reload → all sections should be open (defaults)

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js
git commit -m "Update grocery collapse persistence for per-section state"
```

---

### Task 4: Run tests and fix any breakage

**Files:**
- Possibly modify: any of the three files above

- [ ] **Step 1: Run full test suite**

```bash
rake test
```

Expected: All tests pass. If any grocery controller tests fail due to changed
HTML structure (e.g., assertions on CSS classes or DOM structure), update them
to match the new markup.

- [ ] **Step 2: Run lint**

```bash
bundle exec rubocop
```

Expected: No new offenses. The ERB changes don't go through RuboCop, but
check that any helper changes (if made) pass.

- [ ] **Step 3: Run JS build**

```bash
npm run build
```

Expected: Clean build, no errors.

- [ ] **Step 4: Check html_safe_allowlist**

The `title` attribute rendering in the inventory check section uses the same
`.html_safe` pattern as existing to-buy items. Verify:

```bash
rake lint:html_safe
```

If the new `.html_safe` calls on different line numbers need allowlisting,
update `config/html_safe_allowlist.yml`.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "Fix test/lint issues from grocery page restructure"
```
