# Grocery Backoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the binary `checked_off` array with an `on_hand` hash carrying exponential backoff intervals, so the grocery list learns which ingredients the user reliably has at home.

**Architecture:** MealPlan's `checked_off` string array becomes an `on_hand` hash keyed by canonical ingredient name, with `confirmed_at` (ISO date string) and `interval` (integer days or null for custom items). `MealPlanWriteService` canonicalizes item names via `IngredientResolver` before passing to `MealPlan`. `effective_on_hand(now:)` is the single read API — all display and availability code calls it. Reconciliation runs four cleanup passes on every write. The "in cart" shopping-trip boundary is purely client-side via `sessionStorage`.

**Tech Stack:** Ruby on Rails 8, SQLite (JSONB state column), Stimulus, Turbo Drive morphs

**Spec:** `docs/superpowers/specs/2026-03-21-grocery-backoff-design.md`

---

## File Map

| File | Role | Action |
|------|------|--------|
| `app/models/meal_plan.rb` | State model: `on_hand` hash, `effective_on_hand`, `apply_check`, `prune_on_hand` | Modify |
| `app/services/meal_plan_write_service.rb` | Canonicalization boundary, custom item detection | Modify |
| `app/controllers/groceries_controller.rb` | Pass `effective_on_hand` keys to views | Modify |
| `app/controllers/menu_controller.rb` | Pass `effective_on_hand` keys to calculator | Modify |
| `app/helpers/groceries_helper.rb` | `shopping_list_count_text` uses on_hand set | Modify |
| `app/views/groceries/show.html.erb` | Rename partial local from `checked_off:` to `on_hand_names:` | Modify |
| `app/views/groceries/_shopping_list.html.erb` | Use `on_hand_names` set for partitioning | Modify |
| `app/javascript/controllers/grocery_ui_controller.js` | Add `sessionStorage`-backed "in cart" set | Modify |
| `db/migrate/012_convert_checked_off_to_on_hand.rb` | Data migration: array → hash | Create |
| `test/models/meal_plan_test.rb` | Rewrite for `on_hand` semantics + backoff math | Modify |
| `test/services/meal_plan_write_service_test.rb` | Add canonicalization + custom detection tests | Modify |
| `test/controllers/groceries_controller_test.rb` | Update `checked_off` → `on_hand` references | Modify |
| `test/controllers/menu_controller_test.rb` | Update availability data source | Modify |
| `test/services/recipe_availability_calculator_test.rb` | Update `checked_off` → `on_hand` references | Modify |
| `test/services/catalog_write_service_test.rb` | Update `checked_off` → `on_hand` references | Modify |
| `test/services/ingredient_resolver_regression_test.rb` | Update `checked_off` → `on_hand` references | Modify |

---

### Task 1: MealPlan model — `on_hand` hash, `STATE_DEFAULTS`, accessors

Replace `checked_off` array infrastructure with `on_hand` hash. This is the
foundation everything else builds on.

**Files:**
- Modify: `app/models/meal_plan.rb:17-18` (STATE_KEYS, CASE_INSENSITIVE_KEYS)
- Modify: `app/models/meal_plan.rb:37-39` (checked_off accessor → on_hand)
- Modify: `app/models/meal_plan.rb:111-113` (ensure_state_keys)
- Test: `test/models/meal_plan_test.rb`

- [ ] **Step 1: Write failing tests for `on_hand` accessor and `STATE_DEFAULTS`**

Add to `test/models/meal_plan_test.rb` (replace `test 'defaults to version 0 and empty state'`):

```ruby
test 'on_hand defaults to empty hash' do
  list = MealPlan.create!(kitchen: @kitchen)

  assert_equal({}, list.on_hand)
end

test 'ensure_state_keys initializes on_hand as hash not array' do
  list = MealPlan.create!(kitchen: @kitchen)
  list.apply_action('custom_items', item: 'test', action: 'add')
  list.reload

  assert_instance_of Hash, list.state['on_hand']
  assert_instance_of Array, list.state['custom_items']
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb -n '/on_hand defaults|ensure_state_keys initializes/'`

Expected: FAIL — `on_hand` method returns `[]`, not `{}`

- [ ] **Step 3: Implement STATE_DEFAULTS, on_hand accessor, ensure_state_keys**

In `app/models/meal_plan.rb`, replace constants and methods:

```ruby
# Replace STATE_KEYS and CASE_INSENSITIVE_KEYS (lines 17-18)
STATE_DEFAULTS = {
  'selected_recipes' => [],
  'selected_quick_bites' => [],
  'custom_items' => [],
  'on_hand' => {}
}.freeze
CASE_INSENSITIVE_KEYS = %w[custom_items].freeze

# Also add these constants after the existing ones:
STARTING_INTERVAL = 7
MAX_INTERVAL = 56
```

Replace the `checked_off` accessor (line 37-39):

```ruby
def on_hand
  state.fetch('on_hand', {})
end
```

Replace `ensure_state_keys` (lines 111-113):

```ruby
def ensure_state_keys
  STATE_DEFAULTS.each { |key, default| state[key] ||= default.dup }
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/meal_plan_test.rb -n '/on_hand defaults|ensure_state_keys initializes/'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "refactor: replace checked_off array with on_hand hash in MealPlan

Introduce STATE_DEFAULTS hash for mixed-type defaults (arrays vs hash).
Add on_hand accessor returning hash. ensure_state_keys uses .dup to
avoid mutating frozen defaults."
```

---

### Task 2: MealPlan model — `effective_on_hand` and expiration logic

Add the single source of truth for "what's actually on hand right now?"
with time-injectable expiration filtering.

**Files:**
- Modify: `app/models/meal_plan.rb`
- Test: `test/models/meal_plan_test.rb`

- [ ] **Step 1: Write failing tests for `effective_on_hand`**

```ruby
test 'effective_on_hand returns non-expired entries' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 14 },
    'Salt' => { 'confirmed_at' => '2026-03-01', 'interval' => 56 }
  }
  plan.save!

  result = plan.effective_on_hand(now: Date.new(2026, 3, 20))

  assert result.key?('Salt'), 'Salt (56-day interval, confirmed 19 days ago) should still be on hand'
  assert_not result.key?('Flour'), 'Flour (14-day interval, confirmed 19 days ago) should be expired'
end

test 'effective_on_hand excludes expired entries' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Milk' => { 'confirmed_at' => '2026-03-01', 'interval' => 7 }
  }
  plan.save!

  result = plan.effective_on_hand(now: Date.new(2026, 3, 9))

  assert_not result.key?('Milk'), 'Milk confirmed 8 days ago with 7-day interval should be expired'
end

test 'effective_on_hand preserves custom items with null interval' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Birthday candles' => { 'confirmed_at' => '2026-01-01', 'interval' => nil }
  }
  plan.save!

  result = plan.effective_on_hand(now: Date.new(2026, 12, 31))

  assert result.key?('Birthday candles'), 'Custom items (null interval) never expire'
end

test 'effective_on_hand boundary: item expires on exact day' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 7 }
  }
  plan.save!

  day_before = plan.effective_on_hand(now: Date.new(2026, 3, 7))
  exact_day = plan.effective_on_hand(now: Date.new(2026, 3, 8))
  day_after = plan.effective_on_hand(now: Date.new(2026, 3, 9))

  assert day_before.key?('Flour'), 'Day 7 (confirmed_at + 6): still on hand'
  assert exact_day.key?('Flour'), 'Day 8 (confirmed_at + 7): boundary, still on hand'
  assert_not day_after.key?('Flour'), 'Day 9 (confirmed_at + 8): expired'
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb -n '/effective_on_hand/'`

Expected: FAIL — `effective_on_hand` not defined

- [ ] **Step 3: Implement `effective_on_hand`**

Add to `app/models/meal_plan.rb` (public method, after `on_hand`):

```ruby
def effective_on_hand(now: Date.current)
  on_hand.select { |_, entry| entry_on_hand?(entry, now) }
end

# In the private section:
def entry_on_hand?(entry, now)
  return true if entry['interval'].nil?

  Date.parse(entry['confirmed_at']) + entry['interval'].days >= now
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/meal_plan_test.rb -n '/effective_on_hand/'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "feat: add MealPlan#effective_on_hand with time-injectable expiration

Returns on_hand entries that haven't expired. Items with null interval
(custom items) never expire. Accepts now: parameter for deterministic
testing without waiting for real time to pass."
```

---

### Task 3: MealPlan model — rewrite `apply_check` for `on_hand` hash

Replace the array-based `toggle_array('checked_off', ...)` with hash
operations that track `confirmed_at`, `interval`, and enforce same-day
idempotency.

**Files:**
- Modify: `app/models/meal_plan.rb:121-123` (apply_check)
- Test: `test/models/meal_plan_test.rb`

- [ ] **Step 1: Write failing tests for new apply_check behavior**

Replace the existing `test 'apply_action checks off item'` and related tests:

```ruby
# --- on_hand check/uncheck ---

test 'checking off a new item creates on_hand entry with interval 7' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('check', item: 'Flour', checked: true)

  entry = plan.on_hand['Flour']

  assert_equal Date.current.iso8601, entry['confirmed_at']
  assert_equal 7, entry['interval']
end

test 'checking off a custom item creates on_hand entry with null interval' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('check', item: 'Birthday candles', checked: true, custom: true)

  entry = plan.on_hand['Birthday candles']

  assert_equal Date.current.iso8601, entry['confirmed_at']
  assert_nil entry['interval']
end

test 'checking off an existing item on a different day doubles the interval' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 7 }
  }
  plan.save!

  plan.apply_action('check', item: 'Flour', checked: true, now: Date.new(2026, 3, 10))

  entry = plan.on_hand['Flour']

  assert_equal '2026-03-10', entry['confirmed_at']
  assert_equal 14, entry['interval']
end

test 'interval caps at 56 days' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Salt' => { 'confirmed_at' => '2026-01-01', 'interval' => 56 }
  }
  plan.save!

  plan.apply_action('check', item: 'Salt', checked: true, now: Date.new(2026, 3, 10))

  assert_equal 56, plan.on_hand['Salt']['interval']
end

test 'checking off same item on same day is idempotent' do
  plan = MealPlan.for_kitchen(@kitchen)
  today = Date.new(2026, 3, 15)
  plan.apply_action('check', item: 'Flour', checked: true, now: today)
  version_after_first = plan.lock_version

  plan.apply_action('check', item: 'Flour', checked: true, now: today)

  assert_equal 7, plan.on_hand['Flour']['interval'], 'interval should not double on same-day re-check'
  assert_equal version_after_first, plan.lock_version, 'no save on idempotent check'
end

test 'expired item re-confirmed doubles interval from previous value' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Milk' => { 'confirmed_at' => '2026-03-01', 'interval' => 7 }
  }
  plan.save!

  plan.apply_action('check', item: 'Milk', checked: true, now: Date.new(2026, 3, 20))

  assert_equal 14, plan.on_hand['Milk']['interval']
  assert_equal '2026-03-20', plan.on_hand['Milk']['confirmed_at']
end

test 'unchecking an item deletes it from on_hand' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('check', item: 'Milk', checked: true)
  plan.apply_action('check', item: 'Milk', checked: false)

  assert_not plan.on_hand.key?('Milk')
end

test 'unchecking then re-checking starts fresh at interval 7' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 28 }
  }
  plan.save!

  plan.apply_action('check', item: 'Flour', checked: false)
  plan.apply_action('check', item: 'Flour', checked: true)

  assert_equal 7, plan.on_hand['Flour']['interval']
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb -n '/checking off|unchecking|interval caps|expired item/'`

Expected: FAIL — `apply_check` still uses `toggle_array('checked_off', ...)`

- [ ] **Step 3: Rewrite `apply_check`**

In `app/models/meal_plan.rb`, replace `apply_check`:

```ruby
def apply_check(item:, checked:, custom: false, now: Date.current, **)
  if checked
    add_to_on_hand(item, custom:, now:)
  else
    remove_from_on_hand(item)
  end
end
```

Add private helpers:

```ruby
def add_to_on_hand(item, custom:, now:)
  hash = state['on_hand']
  existing = hash[item]
  today = now.iso8601

  if existing && existing['confirmed_at'] == today
    # Same-day idempotency: no interval change
    return
  end

  hash[item] = if existing
                 { 'confirmed_at' => today, 'interval' => next_interval(existing, custom) }
               else
                 { 'confirmed_at' => today, 'interval' => custom ? nil : STARTING_INTERVAL }
               end
  save!
end

def remove_from_on_hand(item)
  return unless state['on_hand'].delete(item)

  save!
end

def next_interval(existing, custom)
  return nil if custom

  [existing['interval'].to_i * 2, MAX_INTERVAL].min
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/meal_plan_test.rb -n '/checking off|unchecking|interval caps|expired item/'`

Expected: PASS

- [ ] **Step 5: Remove old checked_off tests and verify no regressions**

Delete these test methods from `meal_plan_test.rb`:
- `test 'apply_action checks off item'`
- `test 'apply_action unchecks item'`
- `test 'checking off item is case-insensitive'`
- `test 'unchecking item is case-insensitive'`

Run: `ruby -Itest test/models/meal_plan_test.rb`

Expected: Some existing reconciliation tests will fail (they reference `state['checked_off']`). That's expected — Task 4 fixes reconciliation.

- [ ] **Step 6: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "feat: rewrite apply_check for on_hand hash with backoff intervals

New item: interval 7. Re-confirmation on a different day: interval
doubles (capped at 56). Same-day re-confirmation: idempotent (no
interval change). Uncheck: deletes entry (fresh start on re-check).
Custom items get interval null (never expires)."
```

---

### Task 4: MealPlan model — rewrite `reconcile!` and `prune_on_hand`

Replace `prune_checked_off` with `prune_on_hand` running four cleanup
passes: prune orphans, prune expired, fix orphaned null intervals,
re-canonicalize keys.

**Files:**
- Modify: `app/models/meal_plan.rb:81-95` (reconcile!, prune_checked_off)
- Test: `test/models/meal_plan_test.rb`

- [ ] **Step 1: Write failing tests for the four reconciliation passes**

Replace existing reconciliation tests:

```ruby
# --- reconcile! ---

def reconcile_plan!(plan, now: Date.current)
  visible = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan).visible_names
  plan.reconcile!(visible_names: visible, now:)
end

test 'reconcile! prunes orphaned on_hand entries not in visible names' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Phantom' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 7 }
  }
  plan.save!

  reconcile_plan!(plan)
  plan.reload

  assert_empty plan.on_hand
end

test 'reconcile! preserves on_hand entries in visible names' do
  @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 14 },
    'Phantom' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 7 }
  }
  plan.save!

  reconcile_plan!(plan)
  plan.reload

  assert plan.on_hand.key?('Flour')
  assert_not plan.on_hand.key?('Phantom')
end

test 'reconcile! preserves custom items in on_hand' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'birthday candles', action: 'add')
  plan.state['on_hand'] = {
    'birthday candles' => { 'confirmed_at' => Date.current.iso8601, 'interval' => nil }
  }
  plan.save!

  reconcile_plan!(plan)
  plan.reload

  assert plan.on_hand.key?('birthday candles')
end

test 'reconcile! preserves custom items case-insensitively' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'Birthday Candles', action: 'add')
  plan.state['on_hand'] = {
    'birthday candles' => { 'confirmed_at' => Date.current.iso8601, 'interval' => nil }
  }
  plan.save!

  reconcile_plan!(plan)
  plan.reload

  assert plan.on_hand.key?('birthday candles')
end

test 'reconcile! prunes expired entries' do
  plan = MealPlan.for_kitchen(@kitchen)
  @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import("# Bread\n\n## Mix (combine)\n\n- Flour, 2 cups\n\nMix.\n", kitchen: @kitchen, category: @category)
  plan.apply_action('select', type: 'recipe', slug: 'bread', selected: true)

  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => '2026-01-01', 'interval' => 7 }
  }
  plan.save!

  reconcile_plan!(plan, now: Date.new(2026, 3, 21))
  plan.reload

  assert_not plan.on_hand.key?('Flour'), 'Expired entry should be pruned'
end

test 'reconcile! fixes orphaned null intervals' do
  plan = MealPlan.for_kitchen(@kitchen)
  @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import("# Bread\n\n## Mix (combine)\n\n- Flour, 2 cups\n\nMix.\n", kitchen: @kitchen, category: @category)
  plan.apply_action('select', type: 'recipe', slug: 'bread', selected: true)

  # Flour was checked as custom, then custom item removed, but recipe still uses it
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => Date.current.iso8601, 'interval' => nil }
  }
  plan.save!

  reconcile_plan!(plan)
  plan.reload

  assert_equal 7, plan.on_hand['Flour']['interval'],
               'Null interval should be converted to starting interval when item is not in custom_items'
end

test 'reconcile! is idempotent when nothing to prune' do
  plan = MealPlan.for_kitchen(@kitchen)
  version_before = plan.lock_version

  reconcile_plan!(plan)

  assert_equal version_before, plan.reload.lock_version
end

test 'removing custom item and reconciling cleans up on_hand entry' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'Birthday Candles', action: 'add')
  plan.state['on_hand'] = {
    'Birthday Candles' => { 'confirmed_at' => Date.current.iso8601, 'interval' => nil }
  }
  plan.save!

  plan.apply_action('custom_items', item: 'Birthday Candles', action: 'remove')
  reconcile_plan!(plan)
  plan.reload

  assert_empty plan.state['custom_items']
  assert_empty plan.on_hand
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb -n '/reconcile!/'`

Expected: FAIL — `prune_checked_off` still references `state['checked_off']`

- [ ] **Step 3: Rewrite `reconcile!` and `prune_on_hand`**

In `app/models/meal_plan.rb`, update `reconcile!` to accept `now:`:

```ruby
def reconcile!(visible_names:, now: Date.current)
  ensure_state_keys
  changed = prune_on_hand(visible_names:, now:)
  changed |= prune_stale_selections
  save! if changed
end
```

Update `reconcile_kitchen!` to pass `now:`:

```ruby
def self.reconcile_kitchen!(kitchen, now: Date.current)
  plan = for_kitchen(kitchen)
  plan.with_optimistic_retry do
    visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan).visible_names
    plan.reconcile!(visible_names: visible, now:)
  end
end
```

Replace `prune_checked_off` with `prune_on_hand`:

```ruby
def prune_on_hand(visible_names:, now:) # rubocop:disable Metrics/AbcSize, Naming/PredicateMethod
  hash = state['on_hand']
  before_size = hash.size
  custom = state['custom_items']

  # Pass 1: prune orphans
  hash.select! { |key, _| visible_names.include?(key) || custom.any? { |c| c.casecmp?(key) } }

  # Pass 2: prune expired
  hash.reject! { |_, entry| entry['interval'] && Date.parse(entry['confirmed_at']) + entry['interval'].days < now }

  # Pass 3: fix orphaned null intervals
  null_fixed = false
  hash.each do |key, entry|
    next unless entry['interval'].nil?
    next if custom.any? { |c| c.casecmp?(key) }

    entry['interval'] = STARTING_INTERVAL
    null_fixed = true
  end

  hash.size != before_size || null_fixed
end
```

Note: The fourth pass (re-canonicalize keys) requires an `IngredientResolver`,
which is available via `ShoppingListBuilder`. This pass is added in Task 4b
below to keep this commit focused.

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/meal_plan_test.rb -n '/reconcile!/'`

Expected: PASS

- [ ] **Step 5: Delete old reconciliation tests that reference `checked_off`**

Remove from `meal_plan_test.rb`:
- `test 'reconcile! removes checked-off items not on shopping list'`
- `test 'reconcile! preserves checked-off items on shopping list'`
- `test 'reconcile! preserves custom items even when not in visible names'` (replaced above)
- `test 'reconcile! preserves custom items case-insensitively'` (replaced above)
- `test 'removing custom item and reconciling cleans up checked-off entry'`
- `test 'removing custom item and reconciling cleans up case-mismatched checked-off entry'`

Run: `ruby -Itest test/models/meal_plan_test.rb`

Expected: PASS (remaining tests that don't touch checked_off should still pass)

- [ ] **Step 6: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "feat: rewrite reconciliation for on_hand hash

prune_on_hand runs three passes: prune orphans (not in visible names
or custom items), prune expired entries, fix orphaned null intervals
(formerly-custom items that lost their custom_items membership).
reconcile! accepts now: parameter for deterministic testing."
```

---

### Task 4b: MealPlan reconciliation — re-canonicalize keys (pass 4)

Add the fourth reconciliation pass: resolve each `on_hand` key through
the current `IngredientResolver` and rename drift.

**Files:**
- Modify: `app/models/meal_plan.rb` (prune_on_hand, reconcile_kitchen!)
- Test: `test/models/meal_plan_test.rb`

- [ ] **Step 1: Write failing test for key re-canonicalization**

```ruby
test 'reconcile! re-canonicalizes on_hand keys when catalog changes' do
  create_catalog_entry('Flour', aisle: 'Baking')
  @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import("# Bread\n\n## Mix (combine)\n\n- Flour, 2 cups\n\nMix.\n", kitchen: @kitchen, category: @category)

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'bread', selected: true)
  # Simulate a key stored with non-canonical casing
  plan.state['on_hand'] = {
    'flour' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 28 }
  }
  plan.save!

  reconcile_plan!(plan)
  plan.reload

  assert plan.on_hand.key?('Flour'), 'Key should be re-canonicalized to catalog name'
  assert_not plan.on_hand.key?('flour'), 'Old key should be removed'
  assert_equal 28, plan.on_hand['Flour']['interval'], 'Interval should be preserved'
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/meal_plan_test.rb -n '/re-canonicalizes/'`

Expected: FAIL — `flour` gets pruned (not in `visible_names` which has `Flour`)

- [ ] **Step 3: Add resolver to reconciliation and implement pass 4**

Update `reconcile_kitchen!` to pass the resolver:

```ruby
def self.reconcile_kitchen!(kitchen, now: Date.current)
  plan = for_kitchen(kitchen)
  plan.with_optimistic_retry do
    resolver = IngredientCatalog.resolver_for(kitchen)
    visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan, resolver:).visible_names
    plan.reconcile!(visible_names: visible, resolver:, now:)
  end
end
```

Update `reconcile!` to accept and forward resolver:

```ruby
def reconcile!(visible_names:, resolver: nil, now: Date.current)
  ensure_state_keys
  changed = prune_on_hand(visible_names:, resolver:, now:)
  changed |= prune_stale_selections
  save! if changed
end
```

Add pass 4 to `prune_on_hand` (after pass 3, before the changed-detection return).
Insert re-canonicalization BEFORE the orphan prune so keys are normalized first:

```ruby
def prune_on_hand(visible_names:, resolver: nil, now:) # rubocop:disable Metrics/AbcSize, Naming/PredicateMethod
  hash = state['on_hand']
  custom = state['custom_items']

  # Pass 4 (runs first): re-canonicalize keys
  recanon_changed = recanon_on_hand_keys(hash, resolver) if resolver

  before_size = hash.size

  # Pass 1: prune orphans
  hash.select! { |key, _| visible_names.include?(key) || custom.any? { |c| c.casecmp?(key) } }

  # Pass 2: prune expired
  hash.reject! { |_, entry| entry['interval'] && Date.parse(entry['confirmed_at']) + entry['interval'].days < now }

  # Pass 3: fix orphaned null intervals
  null_fixed = false
  hash.each do |key, entry|
    next unless entry['interval'].nil?
    next if custom.any? { |c| c.casecmp?(key) }

    entry['interval'] = STARTING_INTERVAL
    null_fixed = true
  end

  hash.size != before_size || null_fixed || recanon_changed
end

def recanon_on_hand_keys(hash, resolver)
  renames = {}
  hash.each_key do |key|
    canonical = resolver.resolve(key)
    renames[key] = canonical if canonical != key
  end
  return false if renames.empty?

  renames.each do |old_key, new_key|
    old_entry = hash.delete(old_key)
    if hash.key?(new_key)
      # Two keys collapsed: keep the longer interval
      existing = hash[new_key]
      hash[new_key] = old_entry if (old_entry['interval'].to_i) > (existing['interval'].to_i)
    else
      hash[new_key] = old_entry
    end
  end
  true
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/models/meal_plan_test.rb -n '/re-canonicalizes/'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "feat: add key re-canonicalization pass to reconciliation

Resolves each on_hand key through the current IngredientResolver. If
canonical name differs (e.g., catalog edit), renames the key. If two
keys collapse to the same canonical name, keeps the longer interval."
```

---

### Task 5: MealPlanWriteService — canonicalization boundary

The service resolves item names to canonical form via `IngredientResolver`
and determines custom vs. recipe status before passing to `MealPlan`.

**Files:**
- Modify: `app/services/meal_plan_write_service.rb`
- Test: `test/services/meal_plan_write_service_test.rb`

- [ ] **Step 1: Write failing tests for canonicalization and custom detection**

Add to `test/services/meal_plan_write_service_test.rb`:

```ruby
test 'check action canonicalizes item name via IngredientResolver' do
  create_catalog_entry('Flour', aisle: 'Baking')

  MealPlanWriteService.apply_action(
    kitchen: @kitchen, action_type: 'check',
    item: 'flour', checked: true
  )

  plan = MealPlan.for_kitchen(@kitchen)

  assert plan.on_hand.key?('Flour'), 'on_hand key should use canonical catalog name'
  assert_not plan.on_hand.key?('flour'), 'non-canonical name should not be stored'
end

test 'check action sets null interval for custom items' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'Birthday candles', action: 'add')

  MealPlanWriteService.apply_action(
    kitchen: @kitchen, action_type: 'check',
    item: 'Birthday candles', checked: true
  )

  plan.reload
  entry = plan.on_hand['Birthday candles']

  assert_nil entry['interval'], 'Custom items should get null interval'
end

test 'check action sets recipe interval for non-custom items' do
  MealPlanWriteService.apply_action(
    kitchen: @kitchen, action_type: 'check',
    item: 'Flour', checked: true
  )

  plan = MealPlan.for_kitchen(@kitchen)

  assert_equal 7, plan.on_hand['Flour']['interval']
end

test 'check action detects custom items case-insensitively' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'Paper Towels', action: 'add')

  MealPlanWriteService.apply_action(
    kitchen: @kitchen, action_type: 'check',
    item: 'paper towels', checked: true
  )

  plan.reload
  # The on_hand key is the canonical name (resolved via IngredientResolver),
  # which for uncataloged items is the first form seen
  entry = plan.on_hand.values.find { |e| e['interval'].nil? }

  assert_not_nil entry, 'Custom item should have null interval'
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/meal_plan_write_service_test.rb -n '/canonicalizes|custom items|recipe interval/'`

Expected: FAIL — service doesn't canonicalize or pass `custom:` yet

- [ ] **Step 3: Update MealPlanWriteService to canonicalize and detect custom items**

In `app/services/meal_plan_write_service.rb`, update `apply_action`:

```ruby
def apply_action(action_type:, **params)
  errors = validate_action(action_type, **params)
  return Result.new(success: false, errors:) if errors.any?

  mutate_plan do |plan|
    enriched = enrich_check_params(plan, action_type, **params)
    plan.apply_action(action_type, **enriched)
  end
  Kitchen.finalize_writes(kitchen)
  Result.new(success: true, errors: [])
end
```

Add private helper:

```ruby
def enrich_check_params(plan, action_type, **params)
  return params unless action_type == 'check'

  resolver = IngredientCatalog.resolver_for(kitchen)
  canonical = resolver.resolve(params[:item].to_s)
  custom = plan.custom_items.any? { |c| c.casecmp?(params[:item].to_s) }
  params.merge(item: canonical, custom:)
end
```

Also update the header comment to mention the canonicalization role.

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/meal_plan_write_service_test.rb -n '/canonicalizes|custom items|recipe interval/'`

Expected: PASS

- [ ] **Step 5: Run full write service test suite**

Run: `ruby -Itest test/services/meal_plan_write_service_test.rb`

Expected: Some existing tests that reference `state['checked_off']` will need updating. Fix them:
- Tests checking `plan.state['checked_off']` → check `plan.on_hand`
- Tests asserting array membership → assert hash key existence

- [ ] **Step 6: Commit**

```bash
git add app/services/meal_plan_write_service.rb test/services/meal_plan_write_service_test.rb
git commit -m "feat: canonicalize item names and detect custom items in MealPlanWriteService

MealPlanWriteService is the canonicalization boundary: resolves item
names via IngredientResolver before passing to MealPlan. Detects
custom items by testing membership in plan.custom_items
(case-insensitive) and passes custom: true so MealPlan assigns null
interval."
```

---

### Task 6: Controllers, helper, and views — wire up `effective_on_hand`

Update the read path: `GroceriesController` and `MenuController` pass
`effective_on_hand.keys.to_set` instead of `checked_off.to_set`.

**Files:**
- Modify: `app/controllers/groceries_controller.rb:17-22`
- Modify: `app/controllers/menu_controller.rb:23-25`
- Modify: `app/helpers/groceries_helper.rb:19`
- Modify: `app/views/groceries/show.html.erb:29`
- Modify: `app/views/groceries/_shopping_list.html.erb:1,11`
- Test: `test/controllers/groceries_controller_test.rb`
- Test: `test/controllers/menu_controller_test.rb`

- [ ] **Step 1: Update GroceriesController**

In `app/controllers/groceries_controller.rb`, update `show`:

```ruby
def show
  plan = MealPlan.for_kitchen(current_kitchen)
  @shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).build
  @on_hand_names = plan.effective_on_hand.keys.to_set
  @custom_items = plan.custom_items
end
```

- [ ] **Step 2: Update show.html.erb**

In `app/views/groceries/show.html.erb`, line 29:

```erb
<%= render 'groceries/shopping_list', shopping_list: @shopping_list, on_hand_names: @on_hand_names %>
```

- [ ] **Step 3: Update _shopping_list.html.erb**

Line 1 — update locals declaration:

```erb
<%# locals: (shopping_list:, on_hand_names:) %>
```

Line 4 — update count text call:

```erb
<span id="item-count"><%= shopping_list_count_text(shopping_list, on_hand_names) %></span>
```

Line 11 — update partition:

```erb
<% unchecked, checked = items.partition { |i| on_hand_names.exclude?(i[:name]) } %>
```

- [ ] **Step 4: Update GroceriesHelper**

`shopping_list_count_text` — rename parameter for clarity but keep the interface
(it already accepts any object responding to `include?`):

```ruby
def shopping_list_count_text(shopping_list, on_hand_names)
  total = shopping_list.each_value.sum(&:size)
  return '' if total.zero?

  remaining = total - shopping_list.each_value.sum { |items| items.count { |i| on_hand_names.include?(i[:name]) } }

  return "\u2713 All done!" if remaining.zero?

  "#{remaining} #{'item'.pluralize(remaining)} to buy"
end
```

- [ ] **Step 5: Update MenuController**

In `app/controllers/menu_controller.rb`, lines 23-25:

```ruby
on_hand_names = plan.effective_on_hand.keys
recipes = @categories.flat_map(&:recipes)
@availability = RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off: on_hand_names, recipes:).call
```

- [ ] **Step 6: Run controller tests**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb && ruby -Itest test/controllers/menu_controller_test.rb`

Expected: Tests that set up `checked_off` state will fail. Fix them by
replacing `plan.apply_action('check', item: 'X', checked: true)` calls with
direct state manipulation:

```ruby
plan.state['on_hand'] = plan.state.fetch('on_hand', {}).merge(
  'Flour' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 7 }
)
plan.save!
```

- [ ] **Step 7: Fix groceries_controller_test.rb**

Update all tests that use `plan.apply_action('check', ...)` to set up on_hand
state directly. Key tests to update:
- `test 'show pre-checks checked-off items'`
- `test 'show renders all-checked aisle as collapsed summary'`
- `test 'show renders on-hand divider in mixed aisle'`

Also update assertion `assert_select 'input[type="checkbox"][data-item="Flour"][checked]'`
which should still work (the checkbox state comes from the on_hand_names set).

- [ ] **Step 8: Commit**

```bash
git add app/controllers/groceries_controller.rb app/controllers/menu_controller.rb \
  app/helpers/groceries_helper.rb app/views/groceries/show.html.erb \
  app/views/groceries/_shopping_list.html.erb \
  test/controllers/groceries_controller_test.rb test/controllers/menu_controller_test.rb
git commit -m "feat: wire effective_on_hand through controllers and views

GroceriesController passes effective_on_hand.keys.to_set to views.
MenuController passes effective_on_hand.keys to
RecipeAvailabilityCalculator (interface unchanged — still receives
a list of on-hand names). Views renamed checked_off to on_hand_names."
```

---

### Task 7: Update remaining test files

Fix tests in `recipe_availability_calculator_test.rb`,
`catalog_write_service_test.rb`, and
`ingredient_resolver_regression_test.rb` that reference `checked_off`.

**Files:**
- Modify: `test/services/recipe_availability_calculator_test.rb`
- Modify: `test/services/catalog_write_service_test.rb`
- Modify: `test/services/ingredient_resolver_regression_test.rb`

- [ ] **Step 1: Update recipe_availability_calculator_test.rb**

The calculator's interface is unchanged (`checked_off:` still accepts a list
of names). Tests pass arrays like `checked_off: %w[Flour Salt]` — these still
work. No changes to this file are needed unless the tests also set up
`plan.state['checked_off']` state.

Read the file. If tests only pass arrays to the calculator constructor, they're
fine. If any test reads `plan.checked_off`, update to use `plan.effective_on_hand.keys`.

Run: `ruby -Itest test/services/recipe_availability_calculator_test.rb`

Expected: PASS (calculator interface unchanged)

- [ ] **Step 2: Update catalog_write_service_test.rb**

Two tests reference `plan.state['checked_off']`:

`test 'upsert reconciles stale checked-off items when canonical name changes'`:
Replace `plan.apply_action('check', item: 'flour', checked: true)` with:
```ruby
plan.state['on_hand'] = { 'flour' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 7 } }
plan.save!
```
Replace assertion:
```ruby
assert_not plan.on_hand.key?('flour'),
          'stale on_hand item should be pruned after catalog name change'
```

`test 'destroy reconciles meal plan state'`:
Similar update — set up `on_hand` hash, assert against `plan.on_hand`.

Run: `ruby -Itest test/services/catalog_write_service_test.rb`

- [ ] **Step 3: Update ingredient_resolver_regression_test.rb**

Replace `plan.apply_action('check', item: 'Parmesan', checked: true)` with:
```ruby
plan.state['on_hand'] = { 'Parmesan' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 7 } }
plan.save!
```
Replace `checked_off = plan.checked_off` with:
```ruby
checked_off = plan.effective_on_hand.keys
```

Run: `ruby -Itest test/services/ingredient_resolver_regression_test.rb`

Expected: PASS

- [ ] **Step 4: Run full test suite**

Run: `rake test`

Expected: All tests pass. If any remaining tests reference `checked_off`,
fix them following the same pattern.

- [ ] **Step 5: Commit**

```bash
git add test/services/recipe_availability_calculator_test.rb \
  test/services/catalog_write_service_test.rb \
  test/services/ingredient_resolver_regression_test.rb
git commit -m "test: update remaining tests from checked_off to on_hand"
```

---

### Task 8: Data migration — convert `checked_off` to `on_hand`

Write a data migration that converts existing state in-place.

**Files:**
- Create: `db/migrate/012_convert_checked_off_to_on_hand.rb`

- [ ] **Step 1: Write the migration**

```ruby
class ConvertCheckedOffToOnHand < ActiveRecord::Migration[8.0]
  def up
    today = Date.current.iso8601

    execute("SELECT id, state FROM meal_plans").each do |row|
      state = JSON.parse(row['state'] || '{}')
      next unless state.key?('checked_off')

      checked_off = state.delete('checked_off')
      custom_items = state.fetch('custom_items', [])
      on_hand = state.fetch('on_hand', {})

      Array(checked_off).each do |item|
        custom = custom_items.any? { |c| c.downcase == item.downcase }
        on_hand[item] = { 'confirmed_at' => today, 'interval' => custom ? nil : 7 }
      end

      state['on_hand'] = on_hand
      execute(
        "UPDATE meal_plans SET state = #{connection.quote(JSON.generate(state))} WHERE id = #{row['id']}"
      )
    end
  end

  def down
    execute("SELECT id, state FROM meal_plans").each do |row|
      state = JSON.parse(row['state'] || '{}')
      next unless state.key?('on_hand')

      on_hand = state.delete('on_hand')
      state['checked_off'] = on_hand.keys

      execute(
        "UPDATE meal_plans SET state = #{connection.quote(JSON.generate(state))} WHERE id = #{row['id']}"
      )
    end
  end
end
```

- [ ] **Step 2: Run migration**

Run: `rails db:migrate`

Expected: Migration runs without errors.

- [ ] **Step 3: Run full test suite to verify nothing broke**

Run: `rake test`

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/012_convert_checked_off_to_on_hand.rb
git commit -m "data: migrate checked_off arrays to on_hand hashes

Recipe ingredients get interval 7 (cold start — re-verified next
week). Custom items (detected by membership in custom_items) get
interval null (never expires). checked_off key is removed."
```

---

### Task 9: JS — "in cart" sessionStorage boundary

Add `sessionStorage`-backed "in cart" set to `grocery_ui_controller.js` so
items checked during a shopping trip stay visible in the To Buy zone.

**Files:**
- Modify: `app/javascript/controllers/grocery_ui_controller.js`

- [ ] **Step 1: Add "in cart" tracking to `bindShoppingListEvents`**

In the change handler, after `sendAction`, add the item to sessionStorage:

```javascript
// In bindShoppingListEvents, inside the change handler:
if (cb.checked) {
  this.addToCart(name)
} else {
  this.removeFromCart(name)
}
```

- [ ] **Step 2: Add cart management methods**

```javascript
// --- In cart (shopping trip boundary) ---

get cartKey() {
  return `grocery-in-cart-${this.element.dataset.kitchenSlug}`
}

loadCart() {
  try {
    const raw = sessionStorage.getItem(this.cartKey)
    return raw ? new Set(JSON.parse(raw)) : new Set()
  } catch {
    return new Set()
  }
}

saveCart(cart) {
  try {
    sessionStorage.setItem(this.cartKey, JSON.stringify([...cart]))
  } catch { /* sessionStorage full */ }
}

addToCart(name) {
  const cart = this.loadCart()
  cart.add(name)
  this.saveCart(cart)
}

removeFromCart(name) {
  const cart = this.loadCart()
  cart.delete(name)
  this.saveCart(cart)
}
```

- [ ] **Step 3: Re-apply "in cart" treatment after morphs**

In `preserveOnHandStateOnRefresh`, after restoring on-hand state, also
re-apply "in cart" positioning:

```javascript
preserveOnHandStateOnRefresh(event) {
  if (!event.detail.render) return

  this.saveOnHandState()
  const originalRender = event.detail.render
  event.detail.render = async (...args) => {
    await originalRender(...args)
    this.restoreOnHandState()
    this.applyInCartState()
  }
}

applyInCartState() {
  const cart = this.loadCart()
  if (cart.size === 0) return

  cart.forEach(name => {
    // Find the item in the on-hand section and move it to the to-buy zone
    const onHandItem = this.element.querySelector(
      `.on-hand-items li[data-item="${CSS.escape(name)}"]`
    )
    if (!onHandItem) return

    const aisle = onHandItem.closest('.aisle-group')
    if (!aisle) return

    let toBuyList = aisle.querySelector('.to-buy-items')
    if (!toBuyList) {
      // Aisle was all-checked; the server rendered it collapsed.
      // Leave it as-is — the morph will handle the full restructure.
      return
    }

    // Move item to to-buy zone with strikethrough
    onHandItem.classList.add('in-cart')
    const cb = onHandItem.querySelector('input[type="checkbox"]')
    if (cb) cb.checked = true
    toBuyList.appendChild(onHandItem)
  })

  this.updateItemCount()
}
```

- [ ] **Step 4: Also apply on initial connect**

In `connect()`, after `this.restoreOnHandState()`:

```javascript
this.applyInCartState()
```

- [ ] **Step 5: Add CSS for `.in-cart` treatment**

In `app/assets/stylesheets/groceries.css`, add:

```css
.in-cart .item-text {
  text-decoration: line-through;
  opacity: 0.6;
}
```

- [ ] **Step 6: Manual test**

Start `bin/dev`, navigate to groceries, check off items. Verify:
1. Checked items stay in the To Buy zone with strikethrough
2. Navigate to a recipe page and back — items still in cart
3. Close the tab and reopen — cart is cleared, items are in On Hand

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js \
  app/assets/stylesheets/groceries.css
git commit -m "feat: add sessionStorage-backed 'in cart' shopping boundary

Items checked during a shopping trip stay visible in the To Buy zone
with strikethrough rather than immediately collapsing into On Hand.
State persists across mid-shopping navigation via sessionStorage
(scoped to kitchen slug). Cleared on tab close or PWA termination."
```

---

### Task 10: Update header comments and CLAUDE.md

Update architectural comments on modified files and CLAUDE.md references.

**Files:**
- Modify: `app/models/meal_plan.rb` (header comment)
- Modify: `app/services/meal_plan_write_service.rb` (header comment)
- Modify: `CLAUDE.md` (if needed)

- [ ] **Step 1: Update MealPlan header comment**

```ruby
# Singleton-per-kitchen JSON state record for shared meal planning: selected
# recipes/quick bites, custom grocery items, on-hand ingredient tracking with
# exponential backoff intervals. Both menu and groceries pages read/write
# this model.
#
# - .reconcile_kitchen!(kitchen) — computes visible ingredient names (via
#   ShoppingListBuilder) and runs four cleanup passes on on_hand state:
#   prune orphans, prune expired, fix orphaned null intervals, re-canonicalize
#   keys. Called by Kitchen.run_finalization; not called directly by services.
# - #effective_on_hand(now:) — single source of truth for on-hand status:
#   returns only non-expired entries. All display/availability code calls this.
# - #reconcile!(visible_names:, resolver:, now:) — inner pruning for callers
#   already holding the plan inside a retry block.
```

- [ ] **Step 2: Update MealPlanWriteService header comment**

```ruby
# Orchestrates all direct MealPlan mutations: action application (select,
# check, custom items). Validates input (e.g. custom item length) before
# mutating. For check actions, canonicalizes item names via IngredientResolver
# and detects custom items by testing membership in plan.custom_items.
# Owns optimistic-locking retry for MealPlan state changes.
# Post-write finalization (reconciliation, broadcast) is handled by
# Kitchen.finalize_writes.
#
# - MealPlan: singleton-per-kitchen JSON state record
# - IngredientResolver: name canonicalization (check actions only)
# - Kitchen.finalize_writes: centralized post-write finalization
```

- [ ] **Step 3: Run lint**

Run: `bundle exec rubocop app/models/meal_plan.rb app/services/meal_plan_write_service.rb`

Fix any offenses.

- [ ] **Step 4: Run full test suite**

Run: `rake test`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/meal_plan.rb app/services/meal_plan_write_service.rb
git commit -m "docs: update architectural comments for grocery backoff"
```

---

### Task 11: Final verification

- [ ] **Step 1: Run full lint + test suite**

Run: `rake`

Expected: 0 RuboCop offenses, all tests pass.

- [ ] **Step 2: Run migration from scratch**

Run: `rails db:drop db:create db:migrate db:seed`

Expected: Clean setup with no errors.

- [ ] **Step 3: Verify `html_safe` allowlist**

Run: `rake lint:html_safe`

Expected: No new violations (we didn't add any `.html_safe` calls).

- [ ] **Step 4: Manual smoke test**

Start `bin/dev`. Navigate to menu, select a recipe. Go to groceries. Check
off items. Verify intervals in the database:

```bash
rails runner "p MealPlan.first.on_hand"
```

- [ ] **Step 5: Final commit if any cleanup needed, then report**

If all clean, this task is done. The feature branch `feature/grocery-backoff`
is ready for PR.
