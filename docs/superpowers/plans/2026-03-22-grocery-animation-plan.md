# Grocery Item Check-Off Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Animate grocery items between To Buy and On Hand zones on check-off, with bold styling for items confirmed today.

**Architecture:** Two-phase client-side animation (exit collapse + bloop entry) coordinated with Turbo morphs. Server adds a `confirmed-today` CSS class based on `confirmed_at` date comparison. No new endpoints.

**Tech Stack:** CSS animations/transitions, Stimulus controller, ERB helpers

**Spec:** `docs/superpowers/specs/2026-03-22-grocery-animation-design.md`

---

### Task 1: `confirmed_today?` Helper + Tests

**Files:**
- Modify: `app/helpers/groceries_helper.rb:64-66` (add new method before `private`)
- Modify: `test/helpers/groceries_helper_test.rb`

- [ ] **Step 1: Write tests for `confirmed_today?`**

Add to `test/helpers/groceries_helper_test.rb`:

```ruby
test 'confirmed_today? returns true when confirmed_at matches today' do
  on_hand_data = { 'Milk' => { 'confirmed_at' => Date.current.iso8601 } }

  assert confirmed_today?('Milk', on_hand_data)
end

test 'confirmed_today? returns false for past confirmed_at' do
  on_hand_data = { 'Milk' => { 'confirmed_at' => '2026-01-01' } }

  assert_not confirmed_today?('Milk', on_hand_data)
end

test 'confirmed_today? returns false for missing entry' do
  assert_not confirmed_today?('Eggs', {})
end

test 'confirmed_today? returns false for orphan sentinel' do
  on_hand_data = { 'Milk' => { 'confirmed_at' => MealPlan::ORPHAN_SENTINEL } }

  assert_not confirmed_today?('Milk', on_hand_data)
end

test 'confirmed_today? matches case-insensitively' do
  on_hand_data = { 'milk' => { 'confirmed_at' => Date.current.iso8601 } }

  assert confirmed_today?('Milk', on_hand_data)
end

test 'confirmed_today? returns false when confirmed_at is nil' do
  on_hand_data = { 'Milk' => { 'interval' => nil } }

  assert_not confirmed_today?('Milk', on_hand_data)
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/helpers/groceries_helper_test.rb`
Expected: 6 failures (undefined method `confirmed_today?`)

- [ ] **Step 3: Implement `confirmed_today?`**

Add to `app/helpers/groceries_helper.rb`, before the `private` keyword (line 66):

```ruby
def confirmed_today?(name, on_hand_data)
  entry = on_hand_data.find { |k, _| k.casecmp?(name) }&.last
  return false unless entry

  confirmed = entry['confirmed_at']
  return false if confirmed.nil? || confirmed == MealPlan::ORPHAN_SENTINEL

  confirmed == Date.current.iso8601
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/helpers/groceries_helper_test.rb`
Expected: All pass

- [ ] **Step 5: Run lint**

Run: `bundle exec rubocop app/helpers/groceries_helper.rb test/helpers/groceries_helper_test.rb`
Expected: no offenses

- [ ] **Step 6: Commit**

```bash
git add app/helpers/groceries_helper.rb test/helpers/groceries_helper_test.rb
git commit -m "Add confirmed_today? helper for grocery bold styling"
```

---

### Task 2: Server-Side `confirmed-today` Class in Template

**Files:**
- Modify: `app/views/groceries/_shopping_list.html.erb:100-109`

- [ ] **Step 1: Add `confirmed-today` class to On Hand `<li>` elements**

In `_shopping_list.html.erb`, replace the On Hand `<li>` tag (line 104):

```erb
<li<%= ' class="confirmed-today"' if confirmed_today?(item[:name], on_hand_data) %> data-item="<%= item[:name] %>"<%= " title=\"#{h full_tip}\"".html_safe if full_tip.present? %>>
```

- [ ] **Step 2: Add controller test for `confirmed-today` class**

Add to `test/controllers/groceries_controller_test.rb`, after the existing
"show renders on-hand divider in mixed aisle" test:

```ruby
test 'show renders confirmed-today class on items confirmed today' do
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

  assert_select '.on-hand-items li.confirmed-today[data-item="Flour"]'
end

test 'show omits confirmed-today class on items confirmed yesterday' do
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
  plan.on_hand['Flour']['confirmed_at'] = (Date.current - 1).iso8601
  plan.save!

  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_select '.on-hand-items li[data-item="Flour"]'
  assert_select '.on-hand-items li.confirmed-today[data-item="Flour"]', count: 0
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb -n /confirmed_today/`
Expected: 2 failures (no `confirmed-today` class on the `<li>` yet)

- [ ] **Step 4: Verify all tests pass after template change from Step 1**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/views/groceries/_shopping_list.html.erb test/controllers/groceries_controller_test.rb
git commit -m "Add confirmed-today class to On Hand items confirmed today"
```

---

### Task 3: CSS for Exit, Entry, and Bold Styling

**Files:**
- Modify: `app/assets/stylesheets/groceries.css:228-255` (after existing check-off rules)

- [ ] **Step 1: Add animation and bold CSS rules**

Add after the `.item-text { line-height: 1.4; }` block (line 255) in `groceries.css`:

```css
/* Check-off zone animations — JS sets display:grid + grid-template-rows:1fr
   as starting state; this class transitions to 0fr for a smooth collapse */
.check-off-exit {
  grid-template-rows: 0fr;
  opacity: 0;
  transition: grid-template-rows 250ms ease, opacity 250ms ease;
}

.check-off-enter {
  animation: bloop 250ms cubic-bezier(0.16, 0.75, 0.40, 1);
}

.confirmed-today .item-text {
  font-weight: 600;
}
```

- [ ] **Step 2: Verify lint passes**

Run: `bundle exec rubocop` (RuboCop doesn't lint CSS, but verify no unrelated breakage)

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/groceries.css
git commit -m "Add CSS for check-off exit/enter animations and confirmed-today bold"
```

---

### Task 4: JavaScript — Exit Animation + Pending Moves Tracking

**Files:**
- Modify: `app/javascript/controllers/grocery_ui_controller.js`

This task adds the `pendingMoves` Set, the exit animation on checkbox toggle,
and the `pendingMoves` tracking for inventory check buttons.

- [ ] **Step 1: Add `pendingMoves` to `connect()`**

In `connect()`, after `this.listeners = new ListenerManager()` (line 26), add:

```javascript
this.pendingMoves = new Set()
```

- [ ] **Step 2: Add exit animation to checkbox handler**

In `bindShoppingListEvents()`, after `if (!name) return` (line 51), add the
exit animation before the existing `updateItemCount()` call. Uses a two-frame
approach: first set explicit starting values so the transition has endpoints,
then apply the exit class in the next animation frame:

```javascript
const li = cb.closest("li")
if (li) {
  this.pendingMoves.add(name)
  this.animateExit(li)
}
```

- [ ] **Step 3: Add `animateExit()` method**

Add after `updateItemCount()` (after line 81):

```javascript
animateExit(li) {
  li.style.display = "grid"
  li.style.gridTemplateRows = "1fr"
  li.style.overflow = "hidden"
  li.firstElementChild.style.minHeight = "0"
  li.offsetHeight // force reflow so browser computes 1fr before transition
  li.classList.add("check-off-exit")
}
```

The `<li>` elements don't have `display: grid` or `grid-template-rows` by
default. Setting them explicitly gives the CSS transition defined start and
end values (`1fr` → `0fr`). The forced reflow (`offsetHeight`) ensures the
browser computes the starting layout before the transition class is applied —
without it, the browser may batch both style changes into one recalculation
and snap instead of animating.

- [ ] **Step 4: Add `pendingMoves` tracking to inventory check handler**

In `bindInventoryCheckButtons()`, before `if (li) li.remove()` (line 99), add:

```javascript
this.pendingMoves.add(name)
```

- [ ] **Step 5: Rebuild JS and verify**

Run: `npm run build`
Expected: Build succeeds with no errors

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js
git commit -m "Track pending moves and animate exit on checkbox toggle"
```

---

### Task 5: JavaScript — Bloop Entry Animation Post-Morph

**Files:**
- Modify: `app/javascript/controllers/grocery_ui_controller.js`

- [ ] **Step 1: Add `applyPendingMoves()` method**

Add a new method after `applyInCartState()` (after line 301):

```javascript
// --- Zone transition animations ---

applyPendingMoves() {
  if (this.pendingMoves.size === 0) return

  this.pendingMoves.forEach(name => {
    const li = this.element.querySelector(
      `li[data-item="${CSS.escape(name)}"]`
    )
    if (!li || li.classList.contains("in-cart")) return

    li.classList.add("check-off-enter")
    li.addEventListener("animationend", () => {
      li.classList.remove("check-off-enter")
    }, { once: true })
  })

  this.pendingMoves.clear()
}
```

- [ ] **Step 2: Call `applyPendingMoves()` in `preserveOnHandStateOnRefresh`**

In `preserveOnHandStateOnRefresh()`, after `this.applyInCartState()` (line 228),
add:

```javascript
this.applyPendingMoves()
```

- [ ] **Step 3: Rebuild JS**

Run: `npm run build`
Expected: Build succeeds

- [ ] **Step 4: Update header comment**

Update the controller's header comment (lines 5-22) to mention zone transition
animations. After "CSS transitions provide immediate visual feedback." add:

```
 * Two-phase zone animation: exit (grid collapse + fade on the old <li>)
 * and entry (bloop on the new <li> after morph). pendingMoves tracks items
 * mid-transition so the post-morph hook knows which items to animate in.
```

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js
git commit -m "Add bloop entry animation for items arriving in new zone after morph"
```

---

### Task 6: Manual Smoke Test

**Files:** None (testing only)

- [ ] **Step 1: Start dev server**

Run: `bin/dev`

- [ ] **Step 2: Test To Buy → On Hand**

1. Open the grocery page in a browser
2. Select a recipe on the menu page so items appear in To Buy
3. Check off an item — verify it collapses out of To Buy with a fade
4. After the morph, verify it bloops into On Hand
5. Verify the item text is bold (confirmed today)

- [ ] **Step 3: Test On Hand → To Buy**

1. Uncheck the same item in On Hand
2. Verify it collapses out of On Hand
3. After morph, verify it bloops into To Buy
4. Verify it is no longer bold

- [ ] **Step 4: Test Inventory Check → On Hand**

1. Find an item in Inventory Check
2. Click "Have It"
3. Verify the item is removed instantly (existing behavior)
4. After morph, verify it bloops into On Hand with bold styling

- [ ] **Step 5: Test rapid toggling**

1. Check off 3 items in quick succession
2. Verify each collapses independently and bloops into On Hand after morph

- [ ] **Step 6: Run full test suite**

Run: `rake test`
Expected: All tests pass
