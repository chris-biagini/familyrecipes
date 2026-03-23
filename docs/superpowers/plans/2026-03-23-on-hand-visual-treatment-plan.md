# On-Hand Visual Treatment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace strikethrough on grocery on-hand items with an opacity-based freshness gradient (3 bins tied to interval progress).

**Architecture:** New helper method computes freshness bin from interval progress. Three CSS classes apply opacity. Scoped CSS override removes strikethrough for on-hand items only, preserving to-buy check-off feedback.

**Tech Stack:** Rails helpers, ERB partials, CSS, Minitest

**Spec:** `docs/superpowers/specs/2026-03-23-on-hand-visual-treatment-design.md`

---

### Task 1: Add `on_hand_freshness_class` helper with tests

**Files:**
- Modify: `app/helpers/groceries_helper.rb`
- Modify: `test/helpers/groceries_helper_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/helpers/groceries_helper_test.rb`:

```ruby
test 'on_hand_freshness_class returns on-hand-fresh for early progress' do
  # interval 10, SAFETY_MARGIN 0.9 → effective 9 days (.to_i)
  # 2 days elapsed → progress 0.22 → fresh
  entry = { 'confirmed_at' => '2026-03-21', 'interval' => 10 }

  assert_equal 'on-hand-fresh', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
end

test 'on_hand_freshness_class returns on-hand-mid for middle progress' do
  # interval 10, effective 9 → 4 days elapsed → progress 0.44 → mid
  entry = { 'confirmed_at' => '2026-03-19', 'interval' => 10 }

  assert_equal 'on-hand-mid', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
end

test 'on_hand_freshness_class returns on-hand-aging for late progress' do
  # interval 10, effective 9 → 7 days elapsed → progress 0.78 → aging
  entry = { 'confirmed_at' => '2026-03-16', 'interval' => 10 }

  assert_equal 'on-hand-aging', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
end

test 'on_hand_freshness_class returns on-hand-fresh for nil interval' do
  entry = { 'confirmed_at' => '2026-03-01', 'interval' => nil }

  assert_equal 'on-hand-fresh', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
end

test 'on_hand_freshness_class boundary at 0.33 returns mid' do
  # interval 9, effective (9*0.9).to_i = 8 → need progress == 0.33..
  # Actually: 3 days / 8 = 0.375 → mid. Use exact: need elapsed/effective == 1/3.
  # effective=9 (.to_i of 10*0.9=9.0), elapsed=3 → 3/9=0.333... → mid (not < 0.33)
  entry = { 'confirmed_at' => '2026-03-20', 'interval' => 10 }

  assert_equal 'on-hand-mid', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
end

test 'on_hand_freshness_class boundary at 0.66 returns aging' do
  # effective=9, elapsed=6 → 6/9=0.666... → aging (not < 0.66)
  entry = { 'confirmed_at' => '2026-03-17', 'interval' => 10 }

  assert_equal 'on-hand-aging', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
end

test 'on_hand_freshness_class clamps progress above 1.0 to aging' do
  # effective=9, elapsed=15 → progress 1.67 → aging
  entry = { 'confirmed_at' => '2026-03-08', 'interval' => 10 }

  assert_equal 'on-hand-aging', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/helpers/groceries_helper_test.rb`
Expected: 7 errors — `on_hand_freshness_class` not defined

- [ ] **Step 3: Implement `on_hand_freshness_class`**

Add to `app/helpers/groceries_helper.rb` (public method, before the `private` keyword):

```ruby
def on_hand_freshness_class(entry, now: Date.current)
  return 'on-hand-fresh' if entry['interval'].nil?

  effective = (entry['interval'] * MealPlan::SAFETY_MARGIN).to_i
  return 'on-hand-aging' if effective <= 0

  days_elapsed = (now - Date.parse(entry['confirmed_at'])).to_i
  progress = days_elapsed.to_f / effective

  return 'on-hand-aging' unless progress < 0.66
  return 'on-hand-mid' unless progress < 0.33

  'on-hand-fresh'
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/helpers/groceries_helper_test.rb`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add app/helpers/groceries_helper.rb test/helpers/groceries_helper_test.rb
git commit -m "Add on_hand_freshness_class helper with tests"
```

---

### Task 2: CSS changes — scoped on-hand override + freshness classes

**Files:**
- Modify: `app/assets/stylesheets/groceries.css`

- [ ] **Step 1: Add scoped override for on-hand checked items**

After the existing `.check-off input[type="checkbox"]:checked + .item-text`
rule (around line 269), add:

```css
.on-hand-items .check-off input[type="checkbox"]:checked + .item-text {
  text-decoration: none;
  opacity: unset;
}
```

This overrides the base rule for on-hand items only. To-buy items keep their
strikethrough + opacity flash during the exit animation.

- [ ] **Step 2: Add freshness opacity classes**

After the `.confirmed-today` rule (around line 294), add:

```css
.on-hand-fresh  { opacity: 0.75; }
.on-hand-mid    { opacity: 0.625; }
.on-hand-aging  { opacity: 0.50; }
```

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/groceries.css
git commit -m "Add on-hand freshness opacity classes, remove strikethrough for on-hand items"
```

---

### Task 3: Wire up partial to apply freshness classes

**Files:**
- Modify: `app/views/groceries/_shopping_list.html.erb`

- [ ] **Step 1: Update on-hand `<li>` to include freshness class**

In `_shopping_list.html.erb`, the on-hand item loop starts around line 106.
Currently line 110 reads:

```erb
<li<%= ' class="confirmed-today"'.html_safe if confirmed_today?(item[:name], on_hand_data) %> data-item="<%= item[:name] %>"<%= " title=\"#{h full_tip}\"".html_safe if full_tip.present? %>>
```

Replace with:

```erb
<% oh_entry = on_hand_data.find { |k, _| k.casecmp?(item[:name]) }&.last %>
<% li_class = confirmed_today?(item[:name], on_hand_data) ? 'confirmed-today' : on_hand_freshness_class(oh_entry, now: Date.current) %>
<li class="<%= li_class %>" data-item="<%= item[:name] %>"<%= " title=\"#{h full_tip}\"".html_safe if full_tip.present? %>>
```

Note: `oh_entry` will always exist for on-hand items (they're in `on_hand_names`
because they have a valid entry). The class is always present now — either
`confirmed-today` or one of the freshness classes.

- [ ] **Step 2: Verify in browser**

Run: `bin/dev` (if not already running)

Navigate to the groceries page. On-hand items should:
- Show no strikethrough
- Have full opacity + bold if confirmed today
- Have graduated opacity (0.75/0.625/0.50) based on age
- To-buy items should still show strikethrough flash on check-off

- [ ] **Step 3: Update html_safe allowlist**

The old line 110 had `.html_safe` for the `class="confirmed-today"` literal,
which is now replaced by `<%= li_class %>` (no `.html_safe` needed). The title
attribute `.html_safe` shifts to a new line number due to the 2-line insertion.
Update `config/html_safe_allowlist.yml`:

- Remove the entry for `_shopping_list.html.erb:110`
- Update the title `.html_safe` entry to the new line number (approximately
  line 112 — verify with `grep -n html_safe` on the modified file)

- [ ] **Step 4: Commit**

```bash
git add app/views/groceries/_shopping_list.html.erb config/html_safe_allowlist.yml
git commit -m "Apply freshness classes to on-hand items in shopping list partial"
```

---

### Task 4: Update help doc

**Files:**
- Modify: `docs/help/groceries.md`

- [ ] **Step 1: Update the On Hand bullet**

Lines 32-34 currently say on-hand items are "collapsed by default since you
don't need to act on them." Update to mention the opacity treatment:

```markdown
- **On Hand** — items you have, shown with reduced opacity that fades as the
  item ages. Items you just bought appear bolder so you can confirm your cart
  at a glance. If you run out of something, uncheck it — it moves to To Buy.
```

- [ ] **Step 2: Update the While Shopping section**

Lines 48-53 describe strikethrough for checked-off items. The strikethrough
still applies to to-buy items, so the description is mostly correct. Just
clarify the on-hand side:

```markdown
## While Shopping

Check off items as they go in the cart. Checked items get a brief
strikethrough before sliding into the On Hand section, where they appear bold
to confirm what you've just grabbed. If you checked something by mistake,
just uncheck it — same-day corrections are treated as an undo.

Older on-hand items gradually fade, giving you a sense of pantry freshness at
a glance without adding clutter.
```

- [ ] **Step 3: Commit**

```bash
git add docs/help/groceries.md
git commit -m "Update help doc to reflect on-hand opacity treatment"
```

---

### Task 5: Run full test suite and lint

- [ ] **Step 1: Run full test suite**

Run: `rake test`
Expected: all tests pass

- [ ] **Step 2: Run linter**

Run: `bundle exec rubocop`
Expected: no offenses

- [ ] **Step 3: Run html_safe audit**

Run: `rake lint:html_safe`
Expected: pass (the `.html_safe` on the title attribute is already allowlisted;
the new class attribute uses `<%= %>` not `.html_safe`)

- [ ] **Step 4: Fix any issues found, commit if needed**
