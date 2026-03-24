# On Hand "Need It" Button + Optimistic Zone Transitions

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace checkboxes on non-today on-hand items with "Need It" buttons and add optimistic client-side zone transitions so items appear in their destination instantly.

**Architecture:** Two changes layered on top of the existing three-zone grocery model. First, the ERB partial splits on-hand rendering by `confirmed_today?` — today items keep checkboxes, non-today items get a "Need It" button that fires the existing `need_it` server action. Second, `grocery_ui_controller.js` gains a `buildOptimisticItem` helper that constructs a minimal destination `<li>` and inserts it immediately after exit, so the Turbo morph becomes a no-op refinement instead of the sole source of the new item.

**Tech Stack:** Rails ERB, Stimulus JS, CSS, Minitest

**Spec:** `docs/superpowers/specs/2026-03-24-on-hand-need-it-button-design.md`

---

## Key files reference

These files are the ones you'll read and modify. Read the architectural header comments in each before editing.

| File | Role |
|---|---|
| `app/views/groceries/_shopping_list.html.erb` | Three-zone rendering partial |
| `app/assets/stylesheets/groceries.css` | Grocery page styles |
| `app/helpers/groceries_helper.rb` | Zone classification, `confirmed_today?`, freshness classes |
| `app/javascript/controllers/grocery_ui_controller.js` | All grocery interactions, animations, collapse |
| `test/controllers/groceries_controller_test.rb` | Integration tests for grocery page rendering + actions |
| `test/helpers/groceries_helper_test.rb` | Unit tests for helper methods |

---

### Task 1: Update on-hand rendering — "Need It" button for non-today items

**Files:**
- Modify: `app/views/groceries/_shopping_list.html.erb:100-127`
- Modify: `app/assets/stylesheets/groceries.css:129-138,279-281`
- Modify: `test/controllers/groceries_controller_test.rb`

The on-hand `<ul>` currently renders every item identically with a pre-checked checkbox. Split the rendering: `confirmed_today?` items keep their checkbox, non-today items get a "Need It" button + item text (no checkbox, no "Have It" button).

- [ ] **Step 1: Write failing test — today item renders checkbox, non-today renders button**

In `test/controllers/groceries_controller_test.rb`, update the existing `'show renders confirmed-today class on items confirmed today'` test (line ~324) to assert on the new markup structure instead of the `.confirmed-today` class. Then add a new test for the non-today case.

Update the existing test at line ~324 to assert a checkbox exists inside the today on-hand `<li>`:

```ruby
test 'show renders on-hand today item with checkbox' do
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

  MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'Recipe', selectable_id: 'focaccia')
  MealPlanWriteService.apply_action(kitchen: @kitchen, action_type: 'check', item: 'Flour', checked: true)

  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_select '.on-hand-items li[data-item="Flour"] input[type="checkbox"][checked]'
end
```

Add a new test for non-today items rendering a "Need It" button:

```ruby
test 'show renders on-hand non-today item with need-it button' do
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

  MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'Recipe', selectable_id: 'focaccia')
  OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour',
                      confirmed_at: Date.current - 1, interval: 7, ease: 1.5)

  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_select '.on-hand-items li[data-item="Flour"]' do
    assert_select 'button[data-grocery-action="need-it"]'
    assert_select 'input[type="checkbox"]', count: 0
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb -n /on_hand.*checkbox|on_hand.*need/`

Expected: The new test fails (non-today item still has a checkbox, no button). The updated today test may pass if the checkbox selector matches the existing markup.

- [ ] **Step 3: Update the on-hand rendering in the partial**

In `app/views/groceries/_shopping_list.html.erb`, replace lines 109-122 (the `on-hand-items` `<ul>` contents) with a conditional:

```erb
<ul class="on-hand-items">
  <% on_hand.each do |item| %>
    <% sources_tip = item[:sources].present? ? "Needed for: #{h item[:sources].join(', ')}" : nil %>
    <% restock_tip = restock_tooltip(item[:name], on_hand_data, on_hand_names) %>
    <% full_tip = [sources_tip, restock_tip].compact.join("\n") %>
    <% oh_entry = on_hand_data[item[:name].downcase] %>
    <% today = confirmed_today?(item[:name], on_hand_data) %>
    <% li_class = today ? nil : on_hand_freshness_class(oh_entry, now: Date.current) %>
    <li<%= " class=\"#{li_class}\"" if li_class %> data-item="<%= item[:name] %>"<%= " title=\"#{h full_tip}\"".html_safe if full_tip.present? %>>
      <% if today %>
        <label class="check-off">
          <input class="custom-checkbox" type="checkbox" data-item="<%= item[:name] %>" checked>
          <span class="item-text"><%= item[:name] %><% amount_str = format_amounts(item[:amounts], uncounted: item[:uncounted]) %><% if amount_str.present? %> <span class="item-amount"><%= amount_str %></span><% end %></span>
        </label>
      <% else %>
        <button class="btn btn-sm btn-need-it" data-grocery-action="need-it"
                data-item="<%= item[:name] %>">Need It</button>
        <span class="item-text"><%= item[:name] %><% amount_str = format_amounts(item[:amounts], uncounted: item[:uncounted]) %><% if amount_str.present? %> <span class="item-amount"><%= amount_str %></span><% end %></span>
      <% end %>
    </li>
  <% end %>
</ul>
```

- [ ] **Step 4: Update CSS — delete `.confirmed-today` rule, style button-mode on-hand items**

In `app/assets/stylesheets/groceries.css`:

Delete the `.confirmed-today` rule (lines 279-281):
```css
/* DELETE THIS BLOCK */
.confirmed-today .item-text {
  font-weight: 600;
}
```

Add layout for button-mode on-hand items (after the existing `.on-hand-body .on-hand-items li` rule at line ~138). The button-mode `<li>` needs the same flex layout as IC items so the button and text align:

```css
.on-hand-items li:has(.btn-need-it) {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.on-hand-items li:has(.btn-need-it) .item-text {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb -n /on_hand.*checkbox|on_hand.*need/`

Expected: Both pass.

- [ ] **Step 6: Delete stale tests that reference `.confirmed-today`**

The new tests from Step 1 replace the old ones. Delete these two tests entirely:
- `'show renders confirmed-today class on items confirmed today'` (line ~324) — replaced by `'show renders on-hand today item with checkbox'`
- `'show omits confirmed-today class on items confirmed yesterday'` (line ~351) — replaced by `'show renders on-hand non-today item with need-it button'`

Search for any remaining `confirmed-today` references in tests: `grep -r 'confirmed-today' test/`. There should be none after these deletions.

- [ ] **Step 7: Run full test suite and lint**

Run: `bundle exec rubocop app/views/groceries/_shopping_list.html.erb app/assets/stylesheets/groceries.css app/helpers/groceries_helper.rb && ruby -Itest test/controllers/groceries_controller_test.rb && ruby -Itest test/helpers/groceries_helper_test.rb`

Expected: All pass, no lint offenses.

- [ ] **Step 8: Update `html_safe_allowlist.yml` if line numbers shifted**

Check if the `_shopping_list.html.erb` entries in `config/html_safe_allowlist.yml` need line number updates. The `.html_safe` calls for tooltips may have shifted.

Run: `bundle exec rake lint:html_safe`

If it reports violations, update the allowlist file with the new line numbers.

- [ ] **Step 9: Commit**

```bash
git add app/views/groceries/_shopping_list.html.erb app/assets/stylesheets/groceries.css test/controllers/groceries_controller_test.rb config/html_safe_allowlist.yml
git commit -m "Replace non-today on-hand checkboxes with Need It button (#291)

Today items keep checkboxes (uncheck = undo purchase). Non-today items
get a Need It button that fires need_it! (SM-2 blending) instead of
the simpler uncheck!. Removes .confirmed-today bold styling."
```

---

### Task 2: Optimistic zone transitions — `buildOptimisticItem`

**Files:**
- Modify: `app/javascript/controllers/grocery_ui_controller.js`

Add a helper that constructs a minimal destination `<li>` and inserts it into the correct aisle's `<ul>`. Wire it into all zone-move code paths.

- [ ] **Step 1: Add `buildOptimisticItem(name, zone)` method**

Read the current `grocery_ui_controller.js` fully before editing. Add this method in the "Zone transition animations" section (after `applyPendingMoves`, before the closing `}`):

```javascript
buildOptimisticItem(name, zone) {
  const li = document.createElement("li")
  li.dataset.item = name

  if (zone === "on-hand") {
    const label = document.createElement("label")
    label.className = "check-off"
    const cb = document.createElement("input")
    cb.className = "custom-checkbox"
    cb.type = "checkbox"
    cb.dataset.item = name
    cb.checked = true
    const span = document.createElement("span")
    span.className = "item-text"
    span.textContent = name
    label.append(cb, span)
    li.append(label)
  } else {
    const span = document.createElement("span")
    span.className = "item-text"
    span.textContent = name
    const label = document.createElement("label")
    label.className = "check-off"
    const cb = document.createElement("input")
    cb.className = "custom-checkbox"
    cb.type = "checkbox"
    cb.dataset.item = name
    label.append(cb, span)
    li.append(label)
  }

  return li
}
```

- [ ] **Step 2: Add `insertOptimisticItem(name, zone, aisleGroup)` method**

This finds the target `<ul>` within the given aisle group and appends the optimistic `<li>`. If the target `<ul>` doesn't exist, returns without inserting (morph handles it).

```javascript
insertOptimisticItem(name, zone, aisleGroup) {
  if (!aisleGroup) return

  const selector = zone === "on-hand" ? ".on-hand-items" : ".to-buy-items"
  const ul = aisleGroup.querySelector(selector)
  if (!ul) return

  const li = this.buildOptimisticItem(name, zone)
  ul.appendChild(li)

  li.classList.add("check-off-enter")
  li.addEventListener("animationend", () => {
    li.classList.remove("check-off-enter")
  }, { once: true })
}
```

- [ ] **Step 3: Wire optimistic insert into checkbox handler**

In `bindShoppingListEvents`, after the exit animation and before `sendAction`, determine the destination zone and schedule the optimistic insert after the exit animation completes (250ms).

Replace the current handler body (inside the `if (li)` block and after) with:

```javascript
const li = cb.closest("li")
if (li) {
  this.pendingMoves.add(name)
  const aisleGroup = li.closest(".aisle-group")
  const destZone = cb.checked ? "on-hand" : "to-buy"

  this.animateExit(li)
  setTimeout(() => this.insertOptimisticItem(name, destZone, aisleGroup), 260)
}

this.updateItemCount()
sendAction(this.element.dataset.checkUrl, { item: name, checked: cb.checked })
```

- [ ] **Step 4: Wire optimistic insert into IC / on-hand "Need It" and "Have It" buttons**

In `bindInventoryCheckButtons`, after the existing `li.remove()` call, add the optimistic insert. The button's `<li>` is inside an `.aisle-group` (for on-hand buttons) or `.inventory-check-items` (for IC buttons). IC items don't have an aisle group in the DOM, so we need to find the right aisle.

For IC buttons, the item's aisle isn't directly available in the DOM (IC items live inside `.inventory-check-wrapper`, not inside an `.aisle-group`). Skip optimistic insert for IC buttons — they already feel fast because of instant `li.remove()`. Only add optimistic inserts for on-hand "Need It" buttons, which DO have an `.aisle-group` ancestor.

In the existing `bindInventoryCheckButtons` handler, find this block (lines ~119-124):

```javascript
this.pendingMoves.add(name)
const li = btn.closest("li")
if (li) li.remove()

this.hideEmptyInventoryCheck()
this.updateItemCount()
```

Replace it with:

```javascript
this.pendingMoves.add(name)
const li = btn.closest("li")
const aisleGroup = li?.closest(".aisle-group")
if (li) li.remove()

if (aisleGroup) {
  const destZone = action === "have-it" ? "on-hand" : "to-buy"
  this.insertOptimisticItem(name, destZone, aisleGroup)
}

this.hideEmptyInventoryCheck()
this.updateItemCount()
```

Note: `aisleGroup` must be captured *before* `li.remove()` — once the `<li>` is removed from the DOM, `.closest()` returns null.

- [ ] **Step 5: Prevent duplicate bloop on morph for optimistically inserted items**

The current `applyPendingMoves` bloops items after morph. But if we already optimistically inserted and blooped, we don't want a second animation. The simplest fix: clear items from `pendingMoves` when they're optimistically inserted.

In `insertOptimisticItem`, after successfully appending the `<li>`, add:

```javascript
this.pendingMoves.delete(name)
```

- [ ] **Step 6: Run full test suite**

Run: `rake test`

Expected: All pass. JS changes are not unit-tested (no JS test framework for Stimulus controllers in this project) — behavior is verified via manual testing and the Turbo integration tests.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js
git commit -m "Add optimistic zone transitions for grocery items (#291)

Items now appear in their destination zone immediately after exit
animation, without waiting for the server morph round-trip.
buildOptimisticItem constructs a minimal <li>; the morph patches
in amounts, tooltips, and freshness classes as a near-no-op."
```

---

### Task 3: Update header comment and final cleanup

**Files:**
- Modify: `app/javascript/controllers/grocery_ui_controller.js:5-22`
- Modify: `app/views/groceries/_shopping_list.html.erb` (header comment if present)

- [ ] **Step 1: Update the architectural header comment in `grocery_ui_controller.js`**

The header comment (lines 5-22) describes the two-phase animation and `pendingMoves`. Update it to reflect the new optimistic insert behavior and the "Need It" button in on-hand zone.

Replace lines 5-22 with:

```javascript
/**
 * Groceries page interaction — optimistic zone transitions, inventory check
 * and on-hand "Need It" buttons, checkbox toggle, custom item input, and
 * collapse persistence. All authoritative rendering is server-side via Turbo
 * page-refresh morphs; this controller handles interactions and provides
 * optimistic UI so transitions feel instant.
 *
 * Three zones: Inventory Check (unknown items), To Buy (confirmed needed),
 * On Hand (confirmed in stock). On Hand splits further: today items have
 * checkboxes (undo purchase), non-today items have "Need It" buttons (SM-2
 * blending). IC buttons and on-hand "Need It" use instant li.remove();
 * checkboxes use collapse+fade exit animation.
 *
 * Optimistic zone moves: after exit, buildOptimisticItem constructs a minimal
 * <li> in the destination zone with bloop animation. The subsequent Turbo
 * morph patches in amounts, tooltips, and freshness classes as a near-no-op.
 * When the destination <ul> doesn't exist, the optimistic insert is skipped
 * and the morph handles it.
 *
 * - turbo_fetch (sendAction): fire-and-forget mutations with retry and error toast
 * - ListenerManager: tracks event listeners for clean teardown on disconnect
 */
```

- [ ] **Step 2: Run full suite + lint**

Run: `rake`

Expected: All tests pass, no lint offenses.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js
git commit -m "Update grocery controller header comment for #291 changes"
```
