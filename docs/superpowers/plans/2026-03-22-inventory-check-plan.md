# Inventory Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two-zone grocery model (To Buy / On Hand) with a three-zone model (Inventory Check / To Buy / On Hand) that fixes the SM-2 convergence trap by distinguishing "I still have this" from "I'm buying this."

**Architecture:** New `have_it` / `need_it` action types in `MealPlan#apply_action` anchor `confirmed_at` to the purchase date when users confirm they have an item. Actions flow through MealPlanWriteService with canonicalization, same pattern as existing `check` actions. The view renders Inventory Check as a flat list at the top of the page, sorted by recipe usage count. To Buy and On Hand remain aisle-grouped below.

**Note:** Renaming `add_to_on_hand` to clarify it's the purchase path (spec line 187) is deferred to a follow-up cleanup. The existing method stays as-is to minimize churn in this PR.

**Tech Stack:** Rails 8, SQLite, Stimulus, Turbo Streams, Minitest

**Spec:** `docs/superpowers/specs/2026-03-22-inventory-check-design.md`

---

### Task 1: MealPlan — `confirm_on_hand` method (Have It)

The anchor fix. "Have It" grows the interval but keeps `confirmed_at` at the
purchase date, so depletion observations capture the full consumption period.

**Files:**
- Modify: `app/models/meal_plan.rb`
- Modify: `test/models/meal_plan_test.rb`

- [ ] **Step 1: Write failing tests for confirm_on_hand**

Add tests to `test/models/meal_plan_test.rb`:

```ruby
# --- confirm_on_hand (Have It) ---

test 'confirm_on_hand grows interval and preserves confirmed_at' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 7, 'ease' => 2.0 }
  }
  plan.save!

  plan.apply_action('have_it', item: 'Flour', now: Date.new(2026, 3, 15))

  entry = plan.on_hand['Flour']

  assert_equal '2026-03-01', entry['confirmed_at'], 'confirmed_at must stay anchored'
  assert_in_delta 14.0, entry['interval'], 0.1, '7 * 2.0 = 14'
  assert_in_delta 2.1, entry['ease'], 0.01, 'ease bumped once'
end

test 'confirm_on_hand growth loop iterates until on_hand' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Pepper' => { 'confirmed_at' => '2026-01-01', 'interval' => 7, 'ease' => 2.0 }
  }
  plan.save!

  plan.apply_action('have_it', item: 'Pepper', now: Date.new(2026, 3, 22))

  entry = plan.on_hand['Pepper']

  assert_equal '2026-01-01', entry['confirmed_at'], 'confirmed_at stays anchored'
  # Jan 1 → Mar 22 = 81 days. Growth: 7→14→29.4→61.7→129.6. Need 3+ iterations.
  assert_in_delta 129.6, entry['interval'], 1.0, '7 * 2.1^3 ≈ 129.6 (3 loop iterations at ease 2.1)'
  assert_in_delta 2.1, entry['ease'], 0.01, 'ease bumped only once despite multiple loop iterations'
end

test 'confirm_on_hand resets confirmed_at for sentinel entries' do
  plan = MealPlan.for_kitchen(@kitchen)
  today = Date.new(2026, 3, 22)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => MealPlan::ORPHAN_SENTINEL, 'interval' => 28, 'ease' => 1.5 }
  }
  plan.save!

  plan.apply_action('have_it', item: 'Flour', now: today)

  entry = plan.on_hand['Flour']

  assert_equal today.iso8601, entry['confirmed_at'], 'sentinel entries reset confirmed_at'
  assert_in_delta 42.0, entry['interval'], 0.1, '28 * 1.5 = 42'
end

test 'confirm_on_hand falls back to reset when MAX_INTERVAL cannot reach today' do
  plan = MealPlan.for_kitchen(@kitchen)
  today = Date.new(2026, 3, 22)
  plan.state['on_hand'] = {
    'Ancient' => { 'confirmed_at' => '2024-01-01', 'interval' => 7, 'ease' => 1.1 }
  }
  plan.save!

  plan.apply_action('have_it', item: 'Ancient', now: today)

  entry = plan.on_hand['Ancient']

  assert_equal today.iso8601, entry['confirmed_at'], 'should fall back to resetting confirmed_at'
  assert_in_delta 180.0, entry['interval'], 0.1, 'interval at MAX_INTERVAL'
end

test 'confirm_on_hand skips if entry already on_hand' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Salt' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 90, 'ease' => 2.0 }
  }
  plan.save!
  version_before = plan.lock_version

  plan.apply_action('have_it', item: 'Salt', now: Date.current)

  assert_equal version_before, plan.lock_version, 'no save when already on_hand'
end

test 'confirm_on_hand creates entry for new item' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'trigger', action: 'add')
  today = Date.new(2026, 3, 22)

  plan.apply_action('have_it', item: 'Flour', now: today)

  entry = plan.on_hand['Flour']

  assert_equal today.iso8601, entry['confirmed_at']
  assert_equal 7, entry['interval']
  assert_in_delta 2.0, entry['ease']
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb -n /confirm_on_hand/`
Expected: FAIL — `confirm_on_hand` not defined

- [ ] **Step 3: Implement confirm_on_hand**

Add to `app/models/meal_plan.rb`. First, add `'have_it'` and `'need_it'` to
the `apply_action` dispatch (alongside existing `check`/`select`/`custom_items`):

```ruby
when 'have_it' then apply_have_it(**params)
when 'need_it' then apply_need_it(**params)
```

Then add private methods near the existing `add_to_on_hand`:

```ruby
def apply_have_it(item:, now: Date.current, **)
  hash = state['on_hand']
  stored_key = find_on_hand_key(item)
  existing = stored_key ? hash[stored_key] : nil

  unless existing
    hash[item] = { 'confirmed_at' => now.iso8601,
                   'interval' => STARTING_INTERVAL, 'ease' => STARTING_EASE }
    return save!
  end

  return if entry_on_hand?(existing, now)

  hash.delete(stored_key) if stored_key != item

  if existing['confirmed_at'] == ORPHAN_SENTINEL
    grow_standard(existing, now)
  else
    grow_anchored(existing, now)
  end

  hash[item] = existing
  save!
end

def grow_standard(entry, now)
  entry['interval'] = [entry['interval'] * entry['ease'], MAX_INTERVAL].min
  entry['ease'] = [entry['ease'] + EASE_BONUS, MAX_EASE].min
  entry['confirmed_at'] = now.iso8601
  entry.delete('orphaned_at')
end

def grow_anchored(entry, now)
  entry['ease'] = [entry['ease'] + EASE_BONUS, MAX_EASE].min
  confirmed = Date.parse(entry['confirmed_at'])
  loop do
    entry['interval'] = [entry['interval'] * entry['ease'], MAX_INTERVAL].min
    break if confirmed + entry['interval'].to_i >= now
    break if entry['interval'] >= MAX_INTERVAL
  end
  entry['confirmed_at'] = now.iso8601 if confirmed + entry['interval'].to_i < now
end
```

Also update the MealPlan header comment (lines 1-18) to mention the
`have_it` / `need_it` action types and the anchor fix for Inventory Check.

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/meal_plan_test.rb -n /confirm_on_hand/`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "Add MealPlan#confirm_on_hand with anchor fix for Have It"
```

---

### Task 2: MealPlan — "Need It" for new and sentinel items

"Need It" on a new item (no entry) must create a depleted entry so it moves
to To Buy. "Need It" on a sentinel entry must preserve the learned interval
instead of computing a nonsensical observation.

**Files:**
- Modify: `app/models/meal_plan.rb`
- Modify: `test/models/meal_plan_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# --- need_it (Inventory Check → To Buy) ---

test 'need_it on new item creates depleted entry with starting values' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'trigger', action: 'add')
  today = Date.new(2026, 3, 22)

  plan.apply_action('need_it', item: 'Flour', now: today)

  entry = plan.on_hand['Flour']

  assert entry, 'should create an entry'
  assert_equal MealPlan::ORPHAN_SENTINEL, entry['confirmed_at']
  assert_equal today.iso8601, entry['depleted_at']
  assert_equal MealPlan::STARTING_INTERVAL, entry['interval']
  assert_in_delta MealPlan::STARTING_EASE, entry['ease']
end

test 'need_it on sentinel entry preserves interval and penalizes ease' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => MealPlan::ORPHAN_SENTINEL, 'interval' => 28,
                 'ease' => 1.5, 'orphaned_at' => '2026-03-01' }
  }
  plan.save!
  today = Date.new(2026, 3, 22)

  plan.apply_action('need_it', item: 'Flour', now: today)

  entry = plan.on_hand['Flour']

  assert_equal 28, entry['interval'], 'should preserve learned interval for sentinel'
  assert_in_delta 1.1, entry['ease'], 0.01, '1.5 * 0.7 = 1.05, floored to 1.1'
  assert_equal today.iso8601, entry['depleted_at']
end

test 'need_it on normal expired entry uses observed period' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Milk' => { 'confirmed_at' => '2026-03-01', 'interval' => 14, 'ease' => 1.5 }
  }
  plan.save!
  today = Date.new(2026, 3, 22)

  plan.apply_action('need_it', item: 'Milk', now: today)

  entry = plan.on_hand['Milk']

  assert_equal 21, entry['interval'], 'observed = Mar 22 - Mar 1 = 21 days'
  assert_in_delta 1.1, entry['ease'], 0.01
  assert_equal today.iso8601, entry['depleted_at']
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb -n /need_it/`

- [ ] **Step 3: Implement need_it**

Add private methods to `app/models/meal_plan.rb` (the `apply_action` dispatch
for `'need_it'` was already added in Task 1):

```ruby
def apply_need_it(item:, now: Date.current, **)
  hash = state['on_hand']
  stored_key = find_on_hand_key(item)
  existing = stored_key ? hash[stored_key] : nil

  if existing
    hash.delete(stored_key) if stored_key != item
    if existing['confirmed_at'] == ORPHAN_SENTINEL
      mark_depleted_sentinel(existing, now)
    else
      mark_depleted(existing, now)
    end
    hash[item] = existing
  else
    hash[item] = { 'confirmed_at' => ORPHAN_SENTINEL,
                   'interval' => STARTING_INTERVAL,
                   'ease' => STARTING_EASE,
                   'depleted_at' => now.iso8601 }
  end
  save!
end

def mark_depleted_sentinel(entry, now)
  entry['ease'] = [(entry['ease'] || STARTING_EASE) * (1 - EASE_PENALTY), MIN_EASE].max
  entry['depleted_at'] = now.iso8601
  entry.delete('orphaned_at')
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/meal_plan_test.rb -n /need_it/`

- [ ] **Step 5: Run full model test suite**

Run: `ruby -Itest test/models/meal_plan_test.rb`
Expected: all PASS (no regressions)

- [ ] **Step 6: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "Add MealPlan#need_it for Inventory Check depletion"
```

---

### Task 3: MealPlanWriteService — new action types

Route `have_it` and `need_it` actions through the write service, with
canonicalization.

**Files:**
- Modify: `app/services/meal_plan_write_service.rb`
- Modify: `test/services/meal_plan_write_service_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
test 'have_it action calls confirm_on_hand with canonical name' do
  plan = build_plan_with_flour
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 7, 'ease' => 2.0 }
  }
  plan.save!

  MealPlanWriteService.apply_action(
    kitchen: @kitchen, action_type: 'have_it', item: 'flour'
  )
  plan.reload

  assert plan.effective_on_hand.key?('Flour'), 'should be on hand after have_it'
end

test 'need_it action calls need_it with canonical name' do
  plan = build_plan_with_flour
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 7, 'ease' => 2.0 }
  }
  plan.save!

  MealPlanWriteService.apply_action(
    kitchen: @kitchen, action_type: 'need_it', item: 'flour'
  )
  plan.reload

  entry = plan.on_hand['Flour']

  assert entry['depleted_at'], 'should be depleted after need_it'
end
```

Use existing test helpers to build the kitchen/recipe. Check the test file for
`build_plan_with_flour` or create a similar setup method.

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/meal_plan_write_service_test.rb -n /have_it\|need_it/`

- [ ] **Step 3: Implement new action types**

In `app/services/meal_plan_write_service.rb`, update `apply_action` to handle
the new types. The key change is in how the plan is mutated inside the
`with_optimistic_retry` block. The `enrich_check_params` canonicalization
should also run for `have_it` and `need_it` — they need canonical item names.

Update `enrich_check_params` to also canonicalize for `have_it`/`need_it`.
These actions only need the canonical name — the `custom:` flag is irrelevant
(custom items never appear in Inventory Check). Strip `custom:` from the
returned params for these action types, or just don't add it:

```ruby
def enrich_check_params(plan, action_type, **params)
  return params unless %w[check have_it need_it].include?(action_type)

  resolver = IngredientCatalog.resolver_for(kitchen)
  canonical = resolver.resolve(params[:item].to_s)

  if action_type == 'check'
    custom = plan.custom_items.any? { |c| c.casecmp?(params[:item].to_s) }
    params.merge(item: canonical, custom:)
  else
    params.merge(item: canonical)
  end
end
```

The `MealPlan#apply_action` dispatch was already updated in Task 1.

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/meal_plan_write_service_test.rb`

- [ ] **Step 5: Commit**

```bash
git add app/services/meal_plan_write_service.rb app/models/meal_plan.rb \
        test/services/meal_plan_write_service_test.rb
git commit -m "Route have_it/need_it actions through MealPlanWriteService"
```

---

### Task 4: Routes and controller actions

Add `have_it` and `need_it` endpoints.

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/groceries_controller.rb`
- Modify: `test/controllers/groceries_controller_test.rb`

- [ ] **Step 1: Write failing controller tests**

```ruby
test 'have_it confirms item and returns no content' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 7, 'ease' => 2.0 }
  }
  plan.save!

  patch groceries_have_it_path(kitchen_slug:), params: { item: 'Flour' }, as: :turbo_stream

  assert_response :no_content
end

test 'need_it depletes item and returns no content' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['on_hand'] = {
    'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 7, 'ease' => 2.0 }
  }
  plan.save!

  patch groceries_need_it_path(kitchen_slug:), params: { item: 'Flour' }, as: :turbo_stream

  assert_response :no_content
end

test 'have_it requires membership' do
  log_in create_kitchen_and_user(role: nil)

  patch groceries_have_it_path(kitchen_slug:), params: { item: 'Flour' }, as: :turbo_stream

  assert_response :forbidden
end

test 'need_it requires membership' do
  log_in create_kitchen_and_user(role: nil)

  patch groceries_need_it_path(kitchen_slug:), params: { item: 'Flour' }, as: :turbo_stream

  assert_response :forbidden
end
```

Note: check existing controller tests for the correct membership test pattern.
The tests above use `role: nil` — adjust based on how existing tests set up
unauthorized users.

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb -n /have_it\|need_it/`

- [ ] **Step 3: Add routes**

In `config/routes.rb`, inside the existing groceries scope, add:

```ruby
patch 'groceries/have_it', to: 'groceries#have_it', as: :groceries_have_it
patch 'groceries/need_it', to: 'groceries#need_it', as: :groceries_need_it
```

- [ ] **Step 4: Add controller actions**

In `app/controllers/groceries_controller.rb`, add methods modeled on the
existing `check` action:

```ruby
def have_it
  MealPlanWriteService.apply_action(
    kitchen: current_kitchen, action_type: 'have_it',
    item: params[:item]
  )
  head :no_content
end

def need_it
  MealPlanWriteService.apply_action(
    kitchen: current_kitchen, action_type: 'need_it',
    item: params[:item]
  )
  head :no_content
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/groceries_controller.rb \
        test/controllers/groceries_controller_test.rb
git commit -m "Add have_it/need_it routes and controller actions"
```

---

### Task 5: Helper — zone classification and item count

Add `item_zone` helper for three-way partitioning and update the item count
text.

**Files:**
- Modify: `app/helpers/groceries_helper.rb`
- Modify: `test/helpers/groceries_helper_test.rb` (create if needed)

- [ ] **Step 1: Write failing tests**

Check whether `test/helpers/groceries_helper_test.rb` exists. If not, create
it. Add tests for `item_zone` (keyword arguments per CLAUDE.md style):

```ruby
test 'item_zone returns :on_hand for effective on-hand items' do
  on_hand_names = Set.new(['Flour'])
  on_hand_data = { 'Flour' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 7 } }

  assert_equal :on_hand, item_zone(name: 'Flour', on_hand_names:, on_hand_data:, custom_items: [])
end

test 'item_zone returns :to_buy for depleted items' do
  on_hand_data = { 'Flour' => { 'confirmed_at' => '1970-01-01', 'interval' => 7,
                                'depleted_at' => '2026-03-20' } }

  assert_equal :to_buy, item_zone(name: 'Flour', on_hand_names: Set.new, on_hand_data:, custom_items: [])
end

test 'item_zone returns :inventory_check for new items' do
  assert_equal :inventory_check, item_zone(name: 'Flour', on_hand_names: Set.new, on_hand_data: {}, custom_items: [])
end

test 'item_zone returns :inventory_check for expired non-depleted items' do
  on_hand_data = { 'Flour' => { 'confirmed_at' => '2026-01-01', 'interval' => 7 } }

  assert_equal :inventory_check, item_zone(name: 'Flour', on_hand_names: Set.new, on_hand_data:, custom_items: [])
end

test 'item_zone returns :on_hand for custom items with null interval' do
  on_hand_names = Set.new(['Candles'])
  on_hand_data = { 'Candles' => { 'confirmed_at' => '2026-01-01', 'interval' => nil } }

  assert_equal :on_hand, item_zone(name: 'Candles', on_hand_names:, on_hand_data:, custom_items: ['Candles'])
end

test 'item_zone returns :to_buy for unchecked custom items' do
  assert_equal :to_buy, item_zone(name: 'Candles', on_hand_names: Set.new, on_hand_data: {}, custom_items: ['Candles'])
end
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement item_zone**

In `app/helpers/groceries_helper.rb` (keyword args per CLAUDE.md style):

```ruby
def item_zone(name:, on_hand_names:, on_hand_data:, custom_items:)
  return :on_hand if on_hand_names.include?(name)

  entry = on_hand_data.find { |k, _| k.casecmp?(name) }&.last
  return :to_buy if entry&.key?('depleted_at')
  return :to_buy if custom_items.any? { |c| c.casecmp?(name) }

  :inventory_check
end
```

Also update `shopping_list_count_text` to count only To Buy items (not
Inventory Check). The current method counts all items not in `on_hand_names`.
Update it to use `item_zone` and count only `:to_buy` items.

Note: the `on_hand_data.find` linear scan is acceptable for grocery-scale
data (typically < 100 items). If performance becomes an issue, build a
case-insensitive lookup hash once per render.

- [ ] **Step 4: Run tests**

- [ ] **Step 5: Commit**

```bash
git add app/helpers/groceries_helper.rb test/helpers/groceries_helper_test.rb
git commit -m "Add item_zone helper for three-zone grocery partitioning"
```

---

### Task 6: View — three-zone rendering

The big view change. Inventory Check renders as a flat section at the top of
the page. To Buy and On Hand remain aisle-grouped below.

**Files:**
- Modify: `app/views/groceries/show.html.erb`
- Modify: `app/views/groceries/_shopping_list.html.erb`
- Modify: `app/controllers/groceries_controller.rb` (pass new data attributes)
- Modify: `test/controllers/groceries_controller_test.rb`

- [ ] **Step 1: Update controller and view to pass new data**

In `show.html.erb`:
- Add `data-have-it-url` and `data-need-it-url` data attributes to the
  groceries container, alongside the existing `data-check-url`.
- Pass `custom_items: @custom_items` to the `_shopping_list` partial render
  call (it currently only passes `shopping_list:`, `on_hand_names:`,
  `on_hand_data:`).

In `_shopping_list.html.erb`:
- Update the strict locals declaration (line 1) to add `custom_items:`:
  `<%# locals: (shopping_list:, on_hand_names:, on_hand_data:, custom_items:) %>`

- [ ] **Step 2: Extract Inventory Check items in the shopping list partial**

Before the aisle loop in `_shopping_list.html.erb`, collect all Inventory
Check items across all aisles:

```erb
<%
  all_items = shopping_list.values.flatten
  inventory_items = all_items.select { |i| item_zone(i[:name], on_hand_names, on_hand_data, custom_items) == :inventory_check }
  inventory_items.sort_by! { |i| -i[:sources].size }
%>
```

Render the Inventory Check section (if any items):

```erb
<% if inventory_items.any? %>
  <section class="inventory-check-section">
    <h3 class="inventory-check-header">Inventory Check</h3>
    <ul class="inventory-check-items">
      <% inventory_items.each do |item| %>
        <li data-item="<%= item[:name] %>">
          <button class="btn btn-sm btn-need-it" data-action="need-it"
                  data-item="<%= item[:name] %>">Need It</button>
          <span class="item-text"><%= item[:name] %>
            <% if item[:amounts].any? %>
              <span class="item-amount"><%= format_amounts(item[:amounts], uncounted: item[:uncounted]) %></span>
            <% end %>
          </span>
          <button class="btn btn-sm btn-have-it" data-action="have-it"
                  data-item="<%= item[:name] %>">Have It</button>
        </li>
      <% end %>
    </ul>
  </section>
<% end %>
```

- [ ] **Step 3: Update aisle partitioning for To Buy / On Hand only**

In the aisle loop, change the partition logic. Items in Inventory Check have
already been rendered at the top, so exclude them from the aisle sections.
Update the partition to use `item_zone`:

```erb
<% zone = ->(i) { item_zone(i[:name], on_hand_names, on_hand_data, custom_items) } %>
<% to_buy = items.select { |i| zone.(i) == :to_buy } %>
<% on_hand = items.select { |i| zone.(i) == :on_hand } %>
```

Skip aisles where both `to_buy` and `on_hand` are empty (all items were in
Inventory Check).

- [ ] **Step 4: Add controller tests for three-zone rendering**

Test that the Inventory Check section appears with the right items and
structure. Test that To Buy only shows depleted items. Test sort order
(items used in more recipes appear first in Inventory Check).

- [ ] **Step 5: Run all controller tests**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`

- [ ] **Step 6: Commit**

```bash
git add app/views/groceries/ app/controllers/groceries_controller.rb \
        test/controllers/groceries_controller_test.rb
git commit -m "Render three-zone grocery layout with Inventory Check at top"
```

---

### Task 7: Stimulus controller — Have It / Need It handlers

Wire up the Have It / Need It buttons to send the appropriate actions.

**Files:**
- Modify: `app/javascript/controllers/grocery_ui_controller.js`

- [ ] **Step 1: Add button click handlers**

In `grocery_ui_controller.js`, add a listener for Have It / Need It button
clicks. These fire on `.btn-have-it` and `.btn-need-it` buttons inside the
`#shopping-list` container. Use the existing `sendAction` utility to send
the request.

```javascript
// In connect() or a setup method:
this.listeners.add(this.element, 'click', (e) => {
  const btn = e.target.closest('[data-action="have-it"], [data-action="need-it"]')
  if (!btn) return

  const name = btn.dataset.item
  const action = btn.dataset.action
  const url = action === 'have-it'
    ? this.element.dataset.haveItUrl
    : this.element.dataset.needItUrl

  sendAction(url, { item: name })

  // Optimistic: remove the item from the Inventory Check list
  const li = btn.closest('li')
  if (li) li.remove()
  this.updateItemCount()
})
```

- [ ] **Step 2: Update item count logic**

`updateItemCount` currently counts unchecked items in `#shopping-list`. Update
it to count only `.to-buy-items` checkboxes (not Inventory Check items).
Inventory Check items are questions, not "to buy" items.

- [ ] **Step 3: Manual test in browser**

Run: `bin/dev`
Navigate to the groceries page. Select some recipes. Verify:
- New ingredients appear in Inventory Check at the top
- Tapping "Have It" removes the item and it appears in On Hand after refresh
- Tapping "Need It" removes the item and it appears in To Buy
- Checking off a To Buy item works as before
- In-cart strikethrough still works for To Buy items

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js
git commit -m "Wire Have It / Need It buttons in grocery Stimulus controller"
```

---

### Task 8: CSS — Inventory Check styles

Style the Inventory Check section and Have It / Need It buttons.

**Files:**
- Modify: `app/assets/stylesheets/groceries.css`

- [ ] **Step 1: Add Inventory Check section styles**

Follow the existing design system from `base.css` — use `--ground`,
`--surface-alt`, `--text`, `--rule` tokens. Use `.btn` + `.btn-sm` as base
for the buttons. The Inventory Check section should be visually distinct from
the aisle groups (perhaps a subtle background or border) to signal "this is a
different kind of interaction."

Key classes to style:
- `.inventory-check-section` — container
- `.inventory-check-header` — section title
- `.inventory-check-items` — list
- `.inventory-check-items li` — item row (flex, with buttons on either side)
- `.btn-need-it` — left button (ghost/outline style)
- `.btn-have-it` — right button (primary/solid style)

- [ ] **Step 2: Update print styles**

The print section of `groceries.css` hides on-hand items and interactive
elements. Inventory Check items should print as unchecked items (they're
things the user might need to buy). Hide the Have It / Need It buttons in
print.

- [ ] **Step 3: Visual test in browser**

Run: `bin/dev`
Check the groceries page at various viewport widths. Verify the Inventory
Check section looks right, buttons are tappable on mobile, and the overall
page feels cohesive.

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/groceries.css
git commit -m "Style Inventory Check section and Have It / Need It buttons"
```

---

### Task 9: Update simulation and run convergence tests

Update the simulation to model the three-zone interaction and verify
convergence matches the spec's predictions.

**Files:**
- Modify: `test/sim/grocery_convergence.rb`

- [ ] **Step 1: Add three-zone simulation mode**

Add a new mode to the simulation that models the three-zone interaction:
- Items with no entry or expired entry → Inventory Check
- User responds "Have It" (confirm with anchor) or "Need It" (deplete)
- Depleted items → To Buy → user checks off (purchase, confirmed_at resets)
- On Hand items that expire → back to Inventory Check

This should match scenario B (anchor confirm only) from the existing sim,
but with the "Need It on new items" path included.

- [ ] **Step 2: Run simulation and verify convergence**

Run: `ruby test/sim/grocery_convergence.rb`
Verify all items converge within the error bounds from the spec.

- [ ] **Step 3: Commit**

```bash
git add test/sim/grocery_convergence.rb
git commit -m "Update convergence simulation for three-zone model"
```

---

### Task 10: Integration test and cleanup

End-to-end verification that the full flow works.

**Files:**
- Modify: `test/controllers/groceries_controller_test.rb`
- Modify: `app/helpers/groceries_helper.rb` (restock tooltip for anchored items)

- [ ] **Step 1: Write integration test for full Have It → depletion cycle**

```ruby
test 'full cycle: new item → have it → expire → need it → buy' do
  # Setup: recipe with flour
  # 1. GET groceries — flour appears in Inventory Check section
  # 2. PATCH have_it — flour moves to On Hand
  # 3. Advance time past interval
  # 4. GET groceries — flour appears in Inventory Check again
  # 5. PATCH need_it — flour moves to To Buy
  # 6. PATCH check (checked: true) — flour moves to On Hand
end
```

- [ ] **Step 2: Update restock tooltip for anchored confirmed_at**

The `restock_tooltip` helper computes "Estimated restock in ~N days" using
`confirmed_at + interval - today`. With the anchor fix, `confirmed_at` stays
at the purchase date, so this calculation still works correctly (it shows
when the item will next expire into Inventory Check). Verify this is correct
and add a test if needed.

- [ ] **Step 3: Run full test suite**

Run: `rake test`
Expected: all PASS

- [ ] **Step 4: Run linter**

Run: `bundle exec rubocop`
Fix any offenses in modified files.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "Integration tests and cleanup for Inventory Check"
```
