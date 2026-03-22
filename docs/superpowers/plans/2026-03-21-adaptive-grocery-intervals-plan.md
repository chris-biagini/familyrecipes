# Adaptive Grocery Intervals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed power-of-2 doubling system with an SM-2-inspired adaptive ease factor that lets each grocery ingredient converge on its own restock cycle.

**Architecture:** Each `on_hand` entry gains an `ease` field (per-item growth multiplier). Success grows the interval by `interval * ease`; failure (uncheck) sets the interval to the observed consumption period and penalizes ease. A new "depleted" state replaces the current delete-on-uncheck, preserving learned data. The tooltip surfaces restock estimates to the user.

**Tech Stack:** Ruby on Rails 8, SQLite (jsonb state), Minitest, ERB views

**Spec:** `docs/superpowers/specs/2026-03-21-adaptive-grocery-intervals-design.md`

---

### Task 1: Add Ease Constants and Update MAX_INTERVAL

**Files:**
- Modify: `app/models/meal_plan.rb:32-34` (constants section)

- [ ] **Step 1: Update constants in MealPlan**

Add new constants and update `MAX_INTERVAL`. These go right after the existing constants block (line 32-35):

```ruby
STARTING_INTERVAL = 7
MAX_INTERVAL = 180
ORPHAN_RETENTION = 180
ORPHAN_SENTINEL = '1970-01-01'

# SM-2-inspired adaptive ease factor — per-item growth multiplier
STARTING_EASE = 2.0
MIN_EASE = 1.1
MAX_EASE = 2.5
EASE_BONUS = 0.1
EASE_PENALTY = 0.3
```

Key change: `MAX_INTERVAL` goes from `56` to `180` (matches `ORPHAN_RETENTION`).

- [ ] **Step 2: Run tests to verify nothing breaks**

Run: `ruby -Itest test/models/meal_plan_test.rb`

One test will fail: `test 'interval caps at 56 days'` (line 533). This is expected — the cap changed. We'll fix it in Task 2 when we rewrite the interval tests.

- [ ] **Step 3: Commit**

```bash
git add app/models/meal_plan.rb
git commit -m "feat: add SM-2 ease constants, raise MAX_INTERVAL to 180"
```

---

### Task 2: Rewrite add_to_on_hand and next_interval for Ease-Based Growth

**Files:**
- Modify: `app/models/meal_plan.rb:115-142` (`add_to_on_hand`, `next_interval`)
- Modify: `test/models/meal_plan_test.rb` (update + add tests)

The current `add_to_on_hand` creates entries without `ease`. The current `next_interval` does fixed `* 2` doubling. Both must change.

**Implementation note:** The depleted re-check path must fire _before_ the same-day idempotency guard. A user can uncheck and re-check on the same day — the depleted entry has sentinel `confirmed_at` (not today), so the idempotency guard won't fire. But if we check for `depleted_at` after the guard, a depleted entry confirmed on a different day could be skipped. Check `depleted_at` first.

- [ ] **Step 1: Write failing tests for ease-based growth**

Add these tests to `test/models/meal_plan_test.rb`, replacing and extending the existing interval tests. The tests to update/add:

```ruby
test 'checking off a new item creates on_hand entry with starting ease' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('check', item: 'Flour', checked: true)

  entry = plan.on_hand['Flour']

  assert_equal 7, entry['interval']
  assert_in_delta 2.0, entry['ease']
end

test 'checking off a custom item creates entry with null ease' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('check', item: 'Candles', checked: true, custom: true)

  entry = plan.on_hand['Candles']

  assert_nil entry['interval']
  assert_nil entry['ease']
end

test 'confirming existing item uses ease-based growth' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 7, 'ease' => 2.0 }
  }
  plan.save!

  plan.apply_action('check', item: 'Flour', checked: true, now: Date.new(2026, 3, 10))

  entry = plan.on_hand['Flour']

  assert_in_delta 14.0, entry['interval']
  assert_in_delta 2.1, entry['ease'], 0.01
end

test 'ease grows by EASE_BONUS on each success' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Salt' => { 'confirmed_at' => '2026-01-01', 'interval' => 14, 'ease' => 2.1 }
  }
  plan.save!

  plan.apply_action('check', item: 'Salt', checked: true, now: Date.new(2026, 3, 10))

  assert_in_delta 2.2, plan.on_hand['Salt']['ease'], 0.01
end

test 'ease caps at MAX_EASE' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Salt' => { 'confirmed_at' => '2026-01-01', 'interval' => 14, 'ease' => 2.5 }
  }
  plan.save!

  plan.apply_action('check', item: 'Salt', checked: true, now: Date.new(2026, 3, 10))

  assert_in_delta 2.5, plan.on_hand['Salt']['ease'], 0.01
end

test 'interval caps at MAX_INTERVAL (180)' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Salt' => { 'confirmed_at' => '2026-01-01', 'interval' => 100, 'ease' => 2.5 }
  }
  plan.save!

  plan.apply_action('check', item: 'Salt', checked: true, now: Date.new(2026, 3, 10))

  assert_equal 180, plan.on_hand['Salt']['interval']
end

test 'nil existing interval treated as STARTING_INTERVAL for ease growth' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Towels' => { 'confirmed_at' => '2026-03-01', 'interval' => nil, 'ease' => 2.0 }
  }
  plan.save!

  plan.apply_action('check', item: 'Towels', checked: true, custom: false, now: Date.new(2026, 3, 10))

  assert_in_delta 14.0, plan.on_hand['Towels']['interval']
  assert_in_delta 2.1, plan.on_hand['Towels']['ease'], 0.01
end

test 'pruned item re-confirmed uses ease-based growth' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => '1970-01-01', 'interval' => 28, 'ease' => 1.5,
                 'orphaned_at' => '2026-03-01' }
  }
  plan.save!

  plan.apply_action('check', item: 'Flour', checked: true, now: Date.new(2026, 3, 21))

  entry = plan.on_hand['Flour']

  assert_in_delta 42.0, entry['interval']
  assert_in_delta 1.6, entry['ease'], 0.01
  assert_equal '2026-03-21', entry['confirmed_at']
  assert_not entry.key?('orphaned_at'), 'orphaned_at should be cleared on re-confirm'
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb`

Expected: New tests fail because `add_to_on_hand` doesn't produce `ease` field yet.

- [ ] **Step 3: Implement ease-based growth**

Replace `add_to_on_hand` and `next_interval` in `app/models/meal_plan.rb`:

```ruby
def add_to_on_hand(item, custom:, now:)
  hash = state['on_hand']
  stored_key = find_on_hand_key(item)
  existing = stored_key ? hash[stored_key] : nil

  if existing&.key?('depleted_at')
    return recheck_depleted(hash, item, stored_key, now)
  end

  return if existing && existing['confirmed_at'] == now.iso8601

  hash.delete(stored_key) if stored_key && stored_key != item
  hash[item] = build_on_hand_entry(existing, custom:, now:)
  save!
end

def build_on_hand_entry(existing, custom:, now:)
  if existing
    new_interval, new_ease = next_interval_and_ease(existing, custom)
    { 'confirmed_at' => now.iso8601, 'interval' => new_interval, 'ease' => new_ease }
  else
    { 'confirmed_at' => now.iso8601,
      'interval' => custom ? nil : STARTING_INTERVAL,
      'ease' => custom ? nil : STARTING_EASE }
  end
end

def next_interval_and_ease(existing, custom)
  return [nil, nil] if custom

  base_interval = existing['interval'] || STARTING_INTERVAL
  ease = existing['ease'] || STARTING_EASE
  new_interval = [base_interval * ease, MAX_INTERVAL].min
  new_ease = [ease + EASE_BONUS, MAX_EASE].min
  [new_interval, new_ease]
end
```

Note: `recheck_depleted` will be implemented in Task 4 (depleted state). For now, add a stub that raises so tests are clear about what's pending:

```ruby
def recheck_depleted(hash, item, stored_key, now)
  raise NotImplementedError, 'depleted re-check — implemented in Task 4'
end
```

Also delete the old `next_interval` method (line 138-142).

- [ ] **Step 4: Update existing tests that reference old behavior**

Several existing tests need updating:

1. `test 'checking off a new item creates on_hand entry with interval 7'` — add ease assertion
2. `test 'checking off a custom item creates on_hand entry with null interval'` — add ease assertion
3. `test 'checking off an existing item on a different day doubles the interval'` — update to test ease-based growth (add ease to seed data)
4. `test 'next_interval treats nil existing interval as starting interval'` — add ease to seed data
5. `test 'interval caps at 56 days'` — change to cap at 180, add ease to seed data
6. `test 'expired item re-confirmed doubles interval from previous value'` — add ease to seed data, update expected interval
7. `test 'pruned item reappearing doubles interval on re-confirmation'` — add ease to seed data, update expected values
8. `test 'checking re-keys on_hand entry to new canonical form'` — add ease to seed data
9. `test 'unchecking then re-checking starts fresh at interval 7'` — **delete this test**. Its assertion (`interval == 7`) is no longer correct. The replacement test (`'uncheck and re-check on same day preserves learned interval'`) is added in Task 4

For each, ensure the seed `on_hand` entries include `'ease' => 2.0` (or appropriate value) and that assertions match ease-based math (`interval * ease` instead of `interval * 2`).

- [ ] **Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/models/meal_plan_test.rb`

Expected: All tests pass (except the skipped one for Task 3).

- [ ] **Step 6: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "feat: ease-based interval growth (SM-2 adaptation)"
```

---

### Task 3: Implement Depleted State (Soft Failure on Uncheck)

**Files:**
- Modify: `app/models/meal_plan.rb:131-136` (`remove_from_on_hand`)
- Modify: `test/models/meal_plan_test.rb`

Currently `remove_from_on_hand` deletes the entry. For non-custom items, it should mark the entry as depleted instead, preserving interval and ease while setting `confirmed_at` to sentinel and recording `depleted_at`.

Custom items still delete (they cannot be depleted — the observed period is not meaningful for non-recipe items).

- [ ] **Step 1: Write failing tests for depleted state**

```ruby
test 'unchecking a recipe item marks it as depleted instead of deleting' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Milk' => { 'confirmed_at' => '2026-03-10', 'interval' => 14, 'ease' => 2.0 }
  }
  plan.save!

  plan.apply_action('check', item: 'Milk', checked: false, now: Date.new(2026, 3, 20))

  entry = plan.on_hand['Milk']

  assert entry, 'Entry should be preserved, not deleted'
  assert_equal '1970-01-01', entry['confirmed_at']
  assert_equal '2026-03-20', entry['depleted_at']
  assert_in_delta 10.0, entry['interval'], 0.01, 'Interval should be observed period (20 - 10 = 10)'
  assert_in_delta 1.4, entry['ease'], 0.01, 'Ease should be penalized: 2.0 * 0.7 = 1.4'
end

test 'uncheck observed period is floored at STARTING_INTERVAL' do
  plan = MealPlan.for_kitchen(@kitchen)
  today = Date.new(2026, 3, 21)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => today.iso8601, 'interval' => 14, 'ease' => 2.0 }
  }
  plan.save!

  plan.apply_action('check', item: 'Flour', checked: false, now: today)

  assert_equal 7, plan.on_hand['Flour']['interval'], 'Observed period of 0 should floor to 7'
end

test 'uncheck ease penalty floors at MIN_EASE' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Milk' => { 'confirmed_at' => '2026-03-10', 'interval' => 10, 'ease' => 1.2 }
  }
  plan.save!

  plan.apply_action('check', item: 'Milk', checked: false, now: Date.new(2026, 3, 20))

  assert_in_delta 1.1, plan.on_hand['Milk']['ease'], 0.01, 'Ease 1.2 * 0.7 = 0.84, floors to 1.1'
end

test 'unchecking a custom item still deletes the entry' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Candles' => { 'confirmed_at' => '2026-03-10', 'interval' => nil, 'ease' => nil }
  }
  plan.save!

  plan.apply_action('check', item: 'Candles', checked: false, custom: true)

  assert_not plan.on_hand.key?('Candles'), 'Custom items should be deleted, not depleted'
end

test 'depleted item is not in effective_on_hand' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Milk' => { 'confirmed_at' => '1970-01-01', 'interval' => 10, 'ease' => 1.4,
                'depleted_at' => '2026-03-20' }
  }
  plan.save!

  assert_empty plan.effective_on_hand(now: Date.new(2026, 3, 21))
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb`

- [ ] **Step 3: Implement depleted marking in remove_from_on_hand**

Replace `remove_from_on_hand` in `app/models/meal_plan.rb`. The method needs the `custom` and `now` parameters, so `apply_check` must pass them through:

```ruby
def apply_check(item:, checked:, custom: false, now: Date.current, **)
  if checked
    add_to_on_hand(item, custom:, now:)
  else
    remove_from_on_hand(item, custom:, now:)
  end
end

def remove_from_on_hand(item, custom: false, now: Date.current)
  key = find_on_hand_key(item) || item
  entry = state['on_hand'][key]
  return unless entry

  if custom || entry['interval'].nil?
    state['on_hand'].delete(key)
  else
    mark_depleted(entry, now)
  end
  save!
end

def mark_depleted(entry, now)
  observed = (now - Date.parse(entry['confirmed_at'])).to_i
  entry['interval'] = [observed, STARTING_INTERVAL].max
  entry['ease'] = [entry['ease'] * (1 - EASE_PENALTY), MIN_EASE].max
  entry['confirmed_at'] = ORPHAN_SENTINEL
  entry['depleted_at'] = now.iso8601
  entry.delete('orphaned_at')
end
```

- [ ] **Step 4: Update the old "unchecking deletes" test**

The existing `test 'unchecking an item deletes it from on_hand'` now needs to check for depleted state instead. Also unskip `test 'unchecking then re-checking starts fresh at interval 7'` — this test's expected behavior changes (re-check after depletion preserves interval, not resets to 7). We'll fix its expectations in Task 4.

- [ ] **Step 5: Run tests**

Run: `ruby -Itest test/models/meal_plan_test.rb`

Expected: All pass except the skipped "uncheck then re-check" test.

- [ ] **Step 6: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "feat: depleted state preserves learned interval on uncheck"
```

---

### Task 4: Implement Depleted Re-Check (No Growth)

**Files:**
- Modify: `app/models/meal_plan.rb` (`recheck_depleted` stub → real implementation)
- Modify: `test/models/meal_plan_test.rb`

When a depleted item is re-checked (user bought more), confirm it with preserved interval and ease — no growth. This replaces the stub from Task 2.

- [ ] **Step 1: Write failing tests for depleted re-check**

```ruby
test 're-checking a depleted item preserves interval and ease without growth' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Milk' => { 'confirmed_at' => '1970-01-01', 'interval' => 10, 'ease' => 1.47,
                'depleted_at' => '2026-03-20' }
  }
  plan.save!

  plan.apply_action('check', item: 'Milk', checked: true, now: Date.new(2026, 3, 20))

  entry = plan.on_hand['Milk']

  assert_equal '2026-03-20', entry['confirmed_at']
  assert_in_delta 10.0, entry['interval'], 0.01, 'Interval preserved, not grown'
  assert_in_delta 1.47, entry['ease'], 0.01, 'Ease preserved, not grown'
  assert_not entry.key?('depleted_at'), 'depleted_at should be cleared'
end

test 'uncheck and re-check on same day preserves learned interval' do
  plan = MealPlan.for_kitchen(@kitchen)
  today = Date.new(2026, 3, 21)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => '2026-03-11', 'interval' => 28, 'ease' => 1.5 }
  }
  plan.save!

  plan.apply_action('check', item: 'Flour', checked: false, now: today)
  plan.apply_action('check', item: 'Flour', checked: true, now: today)

  entry = plan.on_hand['Flour']

  assert_equal today.iso8601, entry['confirmed_at']
  assert_in_delta 10.0, entry['interval'], 0.01, 'Observed period: 21 - 11 = 10'
  assert_not entry.key?('depleted_at')
end

test 'full convergence scenario: milk settles around 10 days' do
  plan = MealPlan.for_kitchen(@kitchen)

  # Day 0: first check
  plan.apply_action('check', item: 'Milk', checked: true, now: Date.new(2026, 1, 1))

  assert_equal 7, plan.on_hand['Milk']['interval']

  # Day 8: expired, confirm (success)
  plan.apply_action('check', item: 'Milk', checked: true, now: Date.new(2026, 1, 9))

  assert_in_delta 14.0, plan.on_hand['Milk']['interval']

  # Day 18: ran out after 10 days (failure)
  plan.apply_action('check', item: 'Milk', checked: false, now: Date.new(2026, 1, 19))

  assert_in_delta 10.0, plan.on_hand['Milk']['interval']

  # Day 18: re-check (bought more, no growth)
  plan.apply_action('check', item: 'Milk', checked: true, now: Date.new(2026, 1, 19))

  assert_in_delta 10.0, plan.on_hand['Milk']['interval'], 0.01, 'No growth on depleted re-check'

  # Day 29: expired, confirm (success)
  plan.apply_action('check', item: 'Milk', checked: true, now: Date.new(2026, 1, 30))

  assert_in_delta 14.7, plan.on_hand['Milk']['interval'], 0.1

  # Day 39: ran out again (failure)
  plan.apply_action('check', item: 'Milk', checked: false, now: Date.new(2026, 2, 9))

  assert_in_delta 10.0, plan.on_hand['Milk']['interval']
  assert_in_delta 1.1, plan.on_hand['Milk']['ease'], 0.01, 'Ease should have hit floor'
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb`

Expected: `NotImplementedError` from the `recheck_depleted` stub.

- [ ] **Step 3: Implement recheck_depleted**

Replace the stub in `app/models/meal_plan.rb`:

```ruby
def recheck_depleted(hash, item, stored_key, now)
  entry = hash.delete(stored_key)
  entry['confirmed_at'] = now.iso8601
  entry.delete('depleted_at')
  hash[item] = entry
  save!
end
```

- [ ] **Step 4: Run tests**

Run: `ruby -Itest test/models/meal_plan_test.rb`

Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "feat: depleted re-check preserves interval without growth"
```

---

### Task 5: Update Reconciliation Passes for Depleted State and Ease

**Files:**
- Modify: `app/models/meal_plan.rb:155-221` (reconciliation methods)
- Modify: `test/models/meal_plan_test.rb`

Three reconciliation changes:
1. `expire_orphaned_on_hand` — skip entries with `depleted_at`
2. `fix_orphaned_null_intervals` — also set `ease: STARTING_EASE`
3. `purge_stale_orphans` — skip entries with `depleted_at` (don't backfill orphaned_at on them)

- [ ] **Step 1: Write failing tests**

```ruby
test 'reconcile! skips depleted entries during orphan expiration' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Milk' => { 'confirmed_at' => '1970-01-01', 'interval' => 10, 'ease' => 1.1,
                'depleted_at' => '2026-03-20' }
  }
  plan.save!

  reconcile_plan!(plan, now: Date.new(2026, 3, 21))
  plan.reload

  entry = plan.on_hand['Milk']

  assert entry.key?('depleted_at'), 'Depleted entry should not be converted to orphan'
  assert_not entry.key?('orphaned_at'), 'No orphaned_at should be added to depleted entry'
end

test 'reconcile! does not purge depleted entries regardless of age' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Milk' => { 'confirmed_at' => '1970-01-01', 'interval' => 10, 'ease' => 1.1,
                'depleted_at' => '2025-01-01' }
  }
  plan.save!

  reconcile_plan!(plan, now: Date.new(2026, 3, 21))
  plan.reload

  assert plan.on_hand.key?('Milk'), 'Depleted entry should be retained indefinitely'
end

test 'reconcile! fixes null interval and sets starting ease' do
  @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  md = "# Bread\n\n## Mix (combine)\n\n- Flour, 2 cups\n\nMix.\n"
  MarkdownImporter.import(md, kitchen: @kitchen, category: @category)

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'bread', selected: true)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => Date.current.iso8601, 'interval' => nil, 'ease' => nil }
  }
  plan.save!

  reconcile_plan!(plan)
  plan.reload

  assert_equal 7, plan.on_hand['Flour']['interval']
  assert_in_delta 2.0, plan.on_hand['Flour']['ease'], 0.01,
                  'Ease should be set to STARTING_EASE when null interval is fixed'
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb`

- [ ] **Step 3: Update reconciliation methods**

In `app/models/meal_plan.rb`:

**`expire_orphaned_on_hand`** — add depleted skip:

```ruby
def expire_orphaned_on_hand(hash, visible_names, custom, now)
  changed = false
  hash.each do |key, entry|
    next if visible_names.include?(key) || custom.any? { |c| c.casecmp?(key) }
    next if entry['confirmed_at'] == ORPHAN_SENTINEL
    next if entry.key?('depleted_at')

    entry['confirmed_at'] = ORPHAN_SENTINEL
    entry['orphaned_at'] = now.iso8601
    changed = true
  end
  changed
end
```

**`fix_orphaned_null_intervals`** — also set ease:

```ruby
def fix_orphaned_null_intervals(hash, custom)
  changed = false
  hash.each do |key, entry|
    next unless entry['interval'].nil?
    next if custom.any? { |c| c.casecmp?(key) }

    entry['interval'] = STARTING_INTERVAL
    entry['ease'] = STARTING_EASE
    changed = true
  end
  changed
end
```

**`purge_stale_orphans`** — skip depleted entries in backfill and purge:

```ruby
def purge_stale_orphans(hash, now)
  changed = false
  hash.each_value do |entry|
    next if entry.key?('depleted_at')
    next unless entry['confirmed_at'] == ORPHAN_SENTINEL && !entry.key?('orphaned_at')

    entry['orphaned_at'] = now.iso8601
    changed = true
  end
  cutoff = now - ORPHAN_RETENTION
  before = hash.size
  hash.reject! do |_, e|
    e['confirmed_at'] == ORPHAN_SENTINEL && !e.key?('depleted_at') &&
      e.key?('orphaned_at') && Date.parse(e['orphaned_at']) < cutoff
  end
  changed || hash.size < before
end
```

- [ ] **Step 4: Update existing reconciliation tests**

Add `'ease' => 2.0` (or appropriate value) to seed `on_hand` entries in existing reconciliation tests so they match the new data shape. Tests that check interval preservation should also check ease preservation.

- [ ] **Step 5: Run tests**

Run: `ruby -Itest test/models/meal_plan_test.rb`

Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "feat: reconciliation skips depleted entries, sets ease on null-interval fix"
```

---

### Task 6: Update Migration 012 to Include Ease

**Files:**
- Modify: `db/migrate/012_convert_checked_off_to_on_hand.rb`

- [ ] **Step 1: Update migration to include ease field**

In `db/migrate/012_convert_checked_off_to_on_hand.rb`, update the `on_hand` entry creation to include ease:

```ruby
on_hand[item] = {
  'confirmed_at' => today,
  'interval' => custom ? nil : 7,
  'ease' => custom ? nil : 2.0
}
```

- [ ] **Step 2: Run full migration from scratch to verify**

Run: `RAILS_ENV=test rake db:drop db:create db:migrate db:seed`

Expected: Clean migration with no errors.

- [ ] **Step 3: Commit**

```bash
git add db/migrate/012_convert_checked_off_to_on_hand.rb
git commit -m "feat: include ease field in checked_off-to-on_hand migration"
```

---

### Task 7: Tooltip — Restock Estimate in View

**Files:**
- Modify: `app/controllers/groceries_controller.rb:17-22` (pass on_hand data)
- Modify: `app/helpers/groceries_helper.rb` (add tooltip helper)
- Modify: `app/views/groceries/_shopping_list.html.erb` (add title attributes)
- Modify: `test/controllers/groceries_controller_test.rb` (verify data passed)

- [ ] **Step 1: Add tooltip helper method**

Add to `app/helpers/groceries_helper.rb`:

```ruby
def restock_tooltip(item_name, on_hand_data, on_hand_names, now: Date.current)
  entry = on_hand_data.find { |k, _| k.casecmp?(item_name) }&.last
  return nil unless entry
  return nil if entry['interval'].nil?

  if on_hand_names.include?(item_name)
    days_left = ((Date.parse(entry['confirmed_at']) + entry['interval'].to_f.round.days) - now).to_i
    "Estimated restock in ~#{[days_left, 0].max} days"
  elsif entry['interval'] > MealPlan::STARTING_INTERVAL ||
        (entry['ease'] && entry['ease'] != MealPlan::STARTING_EASE)
    "Restocks every ~#{entry['interval'].to_f.round} days"
  end
end
```

Note: This method intentionally checks if the item has been through at least one cycle (interval > STARTING_INTERVAL or ease != STARTING_EASE) before showing the "Restocks every" tooltip on To Buy items.

- [ ] **Step 2: Update controller to pass on_hand data**

In `app/controllers/groceries_controller.rb`, update `show`:

```ruby
def show
  plan = MealPlan.for_kitchen(current_kitchen)
  @shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).build
  @on_hand_data = plan.on_hand
  @on_hand_names = plan.effective_on_hand.keys.to_set
  @custom_items = plan.custom_items
end
```

- [ ] **Step 3: Update shopping list partial**

In `app/views/groceries/_shopping_list.html.erb`, update the locals declaration and title attributes.

Update the locals line:
```erb
<%# locals: (shopping_list:, on_hand_names:, on_hand_data:) %>
```

For each `<li>` with a title attribute, build the title to include restock info. The pattern for each item (appears 3 times in the partial — checked-only aisle, unchecked items, and checked items under unchecked):

```erb
<% sources_tip = item[:sources].present? ? "Needed for: #{h item[:sources].join(', ')}" : nil %>
<% restock_tip = restock_tooltip(item[:name], on_hand_data, on_hand_names) %>
<% full_tip = [sources_tip, restock_tip].compact.join("\n") %>
<li data-item="<%= item[:name] %>"<%= " title=\"#{h full_tip}\"".html_safe if full_tip.present? %>>
```

- [ ] **Step 4: Update the show view to pass on_hand_data to partial**

In `app/views/groceries/show.html.erb`, find where `_shopping_list` is rendered and add the `on_hand_data:` local. The render call should pass `on_hand_data: @on_hand_data`.

- [ ] **Step 5: Write helper test**

Add a test for the tooltip helper in an appropriate test file (e.g., `test/helpers/groceries_helper_test.rb` if it exists, or within the groceries controller test):

```ruby
test 'restock_tooltip shows days remaining for on-hand items' do
  on_hand_data = { 'Milk' => { 'confirmed_at' => '2026-03-15', 'interval' => 10, 'ease' => 1.1 } }
  on_hand_names = Set.new(['Milk'])
  result = restock_tooltip('Milk', on_hand_data, on_hand_names, now: Date.new(2026, 3, 20))

  assert_equal 'Estimated restock in ~5 days', result
end

test 'restock_tooltip shows cycle length for to-buy items with history' do
  on_hand_data = { 'Milk' => { 'confirmed_at' => '2026-03-01', 'interval' => 10, 'ease' => 1.1 } }
  on_hand_names = Set.new
  result = restock_tooltip('Milk', on_hand_data, on_hand_names, now: Date.new(2026, 3, 20))

  assert_equal 'Restocks every ~10 days', result
end

test 'restock_tooltip returns nil for custom items' do
  on_hand_data = { 'Candles' => { 'confirmed_at' => '2026-03-15', 'interval' => nil, 'ease' => nil } }
  on_hand_names = Set.new(['Candles'])

  assert_nil restock_tooltip('Candles', on_hand_data, on_hand_names)
end

test 'restock_tooltip returns nil for fresh items with no history' do
  on_hand_data = { 'Flour' => { 'confirmed_at' => '2026-03-15', 'interval' => 7, 'ease' => 2.0 } }
  on_hand_names = Set.new

  assert_nil restock_tooltip('Flour', on_hand_data, on_hand_names, now: Date.new(2026, 3, 25))
end
```

- [ ] **Step 6: Run all tests**

Run: `rake test`

Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/groceries_controller.rb app/helpers/groceries_helper.rb \
       app/views/groceries/_shopping_list.html.erb app/views/groceries/show.html.erb \
       test/
git commit -m "feat: restock estimate tooltip on grocery items"
```

---

### Task 8: Update Help Documentation

**Files:**
- Modify: `docs/help/groceries.md:46-87` ("How the System Learns Your Pantry" section)
- Modify: `docs/help/groceries.md:100-104` (unchecking language)

- [ ] **Step 1: Rewrite "How the System Learns Your Pantry"**

Replace lines 46-87 with updated content. Key changes:
- Remove fixed `7→14→28→56` progression
- Remove "eight weeks is the longest"
- Frame as per-item confidence
- Make timeline examples less specific

The section should explain in plain language:
1. The system starts by checking every week
2. Each item learns at its own pace based on your track record
3. Items you always have get asked about less often
4. Running out teaches the system to check sooner for that specific item
5. Over time, each ingredient settles into its own rhythm

- [ ] **Step 2: Update unchecking language**

In the "What Happens When Recipes Change" section (around line 100-104), update:
- Old: "unchecking resets the schedule to one week"
- New: "unchecking adjusts the schedule based on how long you had the item — the system learns from what happened rather than starting from scratch"

- [ ] **Step 3: Commit**

```bash
git add docs/help/groceries.md
git commit -m "docs: update grocery help for adaptive interval system"
```

---

### Task 9: Update CLAUDE.md and MealPlan Header Comment

**Files:**
- Modify: `CLAUDE.md` (MealPlan description)
- Modify: `app/models/meal_plan.rb:1-16` (header comment)

- [ ] **Step 1: Update CLAUDE.md**

In the Architecture section, update the MealPlan description. The current text mentions "spaced-repetition backoff — intervals double on re-confirmation." Update to mention ease-based growth and depleted state:

Find: `intervals double on re-confirmation, expired entries reappear on the shopping list`

Replace with: `SM-2-inspired adaptive ease — per-item growth rate converges on each ingredient's natural restock cycle; depleted state preserves learned intervals when user runs out`

- [ ] **Step 2: Update MealPlan header comment**

Update the header comment to mention ease factor, depleted state, and SM-2 inspiration.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md app/models/meal_plan.rb
git commit -m "docs: update CLAUDE.md and MealPlan header for adaptive intervals"
```

---

### Task 10: Run Full Test Suite and Lint

- [ ] **Step 1: Run full test suite**

Run: `rake test`

Expected: All tests pass, 0 failures.

- [ ] **Step 2: Run RuboCop**

Run: `bundle exec rubocop`

Fix any offenses (line length, method length, ABC size). Add `rubocop:disable` comments with justification if needed for methods that slightly exceed metrics.

- [ ] **Step 3: Run html_safe lint**

Run: `rake lint:html_safe`

If the tooltip adds any `.html_safe` calls, ensure they're in the allowlist.

- [ ] **Step 4: Final commit if any lint fixes**

Stage only the files that were modified for lint fixes and commit:

```bash
git commit -m "fix: lint and style fixes for adaptive grocery intervals"
```
