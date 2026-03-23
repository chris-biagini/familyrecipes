# Grocery Quick-Add Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a grocery action row to the search overlay so users can add items to their grocery list from anywhere in the app with a single keystroke.

**Architecture:** Extends the existing search overlay with a new "grocery action" result type that appears above recipe results. A new `POST /groceries/need` endpoint handles the server-side logic. Custom items migrate from a flat string array to a structured hash in MealPlan state with lifecycle tracking (add → To Buy → On Hand for a day → gone, 45-day autocomplete memory).

**Tech Stack:** Rails 8, Stimulus, esbuild, SQLite, Minitest

**Spec:** `docs/superpowers/specs/2026-03-23-grocery-quick-add-design.md`

---

## File Map

### New files
- `app/javascript/utilities/ingredient_match.js` — Client-side fuzzy matching for ingredient autocomplete (prefix + substring)
- `test/javascript/ingredient_match_test.mjs` — Node.js tests for the matching utility
- `app/javascript/utilities/grocery_action.js` — Builds the grocery action row DOM, handles flash-and-close confirmation

### Modified files
- `app/helpers/search_data_helper.rb` — Add `ingredients` and `custom_items` keys to the JSON blob
- `app/javascript/controllers/search_overlay_controller.js` — Load ingredient data, render grocery action row, handle Enter on grocery row, alternate matches
- `app/javascript/utilities/search_match.js` — No changes (recipe matching stays the same)
- `config/routes.rb` — Add `POST /groceries/need` route
- `app/controllers/groceries_controller.rb` — Add `need` action
- `app/services/meal_plan_write_service.rb` — Add `quick_add` action type with "already needed" detection
- `app/models/meal_plan.rb` — Migrate custom_items from flat array to structured hash; add `apply_quick_add`, custom item lifecycle methods, 45-day pruning
- `app/helpers/groceries_helper.rb` — Update `item_zone` and `parse_custom_item` to work with structured custom items
- `app/services/shopping_list_builder.rb` — Update `visible_names` and `add_custom_items` for structured format
- `app/views/groceries/_shopping_list.html.erb` — Adapt rendering for structured custom items; add X button for custom items in To Buy
- `app/views/groceries/_custom_items.html.erb` — Adapt for structured format, remove per-item X buttons (moved to shopping list)
- `app/javascript/controllers/grocery_ui_controller.js` — Update custom item remove to work with new format
- `app/views/shared/_search_overlay.html.erb` — Add `data-need-url` attribute for the grocery endpoint
- `app/views/layouts/application.html.erb` — Add `data-search-overlay-need-url` attribute
- `app/assets/stylesheets/navigation.css` — Grocery action row styling (green tint, cart icon)
- `db/migrate/0XX_migrate_custom_items_format.rb` — Data migration from flat array to structured hash

### Test files
- `test/helpers/search_data_helper_test.rb` — New/augmented tests for ingredient + custom_items keys
- `test/controllers/groceries_controller_test.rb` — Tests for `need` action (all four status paths)
- `test/services/meal_plan_write_service_test.rb` — Tests for `quick_add` action type
- `test/models/meal_plan_test.rb` — Tests for structured custom items, lifecycle, 45-day pruning
- `test/services/shopping_list_builder_test.rb` — Tests for structured custom items in visible_names and build
- `test/helpers/groceries_helper_test.rb` — Tests for updated item_zone with structured custom items
- `test/javascript/ingredient_match_test.mjs` — Node.js tests for fuzzy matching

---

## Task 1: Data Migration — Structured Custom Items

Migrate `custom_items` from a flat string array to a structured hash in MealPlan state. This is the foundation everything else builds on.

**Files:**
- Create: `db/migrate/0XX_migrate_custom_items_format.rb`
- Modify: `app/models/meal_plan.rb` (lines 30-36, 82-84, 98-109, 330-332, 348-350, 352-371)
- Modify: `app/services/shopping_list_builder.rb` (lines 30-33, and `add_custom_items` method)
- Modify: `app/helpers/groceries_helper.rb` (lines 19-27, 58-66)
- Modify: `app/services/meal_plan_write_service.rb` (lines 47-57, 59-65)
- Test: `test/models/meal_plan_test.rb`, `test/services/shopping_list_builder_test.rb`, `test/helpers/groceries_helper_test.rb`, `test/services/meal_plan_write_service_test.rb`

### Overview

The current format stores custom items as `["birthday candles@Party Supplies", "paper towels"]`. The new format is a hash:

```json
{
  "custom_items": {
    "birthday candles": { "aisle": "Party Supplies", "last_used_at": "2026-03-23", "on_hand_at": null },
    "paper towels": { "aisle": "Miscellaneous", "last_used_at": "2026-03-20", "on_hand_at": null }
  }
}
```

This task changes the MealPlan model, ShoppingListBuilder, GroceriesHelper, and MealPlanWriteService to read/write the new format, then writes a data migration to convert existing data.

- [ ] **Step 1: Write MealPlan model tests for structured custom items**

Add tests to `test/models/meal_plan_test.rb`:

```ruby
# --- Structured custom items ---

test "custom_items returns empty hash when no custom items" do
  plan = MealPlan.for_kitchen(@kitchen)
  assert_equal({}, plan.custom_items)
end

test "apply_custom_items add creates structured entry" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'Paper Towels', aisle: 'Miscellaneous', action: 'add')
  plan.reload

  entry = plan.custom_items['Paper Towels']
  assert entry
  assert_equal 'Miscellaneous', entry['aisle']
  assert_equal Date.current.iso8601, entry['last_used_at']
  assert_nil entry['on_hand_at']
end

test "apply_custom_items add with aisle hint stores aisle" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'Birthday Candles', aisle: 'Party Supplies', action: 'add')
  plan.reload

  assert_equal 'Party Supplies', plan.custom_items['Birthday Candles']['aisle']
end

test "apply_custom_items add is case-insensitive on existing" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'Paper Towels', aisle: 'Miscellaneous', action: 'add')
  plan.apply_action('custom_items', item: 'paper towels', aisle: 'Cleaning', action: 'add')
  plan.reload

  assert_equal 1, plan.custom_items.size
  entry = plan.custom_items.values.first
  assert_equal 'Cleaning', entry['aisle']
  assert_equal Date.current.iso8601, entry['last_used_at']
end

test "apply_custom_items remove deletes entry entirely" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'Paper Towels', aisle: 'Miscellaneous', action: 'add')
  plan.apply_action('custom_items', item: 'Paper Towels', action: 'remove')
  plan.reload

  assert_empty plan.custom_items
end

test "apply_custom_items remove is case-insensitive" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'Paper Towels', aisle: 'Miscellaneous', action: 'add')
  plan.apply_action('custom_items', item: 'paper towels', action: 'remove')
  plan.reload

  assert_empty plan.custom_items
end

test "custom item check-off sets on_hand_at" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'Paper Towels', aisle: 'Miscellaneous', action: 'add')
  plan.apply_action('check', item: 'Paper Towels', checked: true, custom: true)
  plan.reload

  entry = plan.custom_items['Paper Towels']
  assert_equal Date.current.iso8601, entry['on_hand_at']
end

test "custom item uncheck clears on_hand_at" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'Paper Towels', aisle: 'Miscellaneous', action: 'add')
  plan.apply_action('check', item: 'Paper Towels', checked: true, custom: true)
  plan.apply_action('check', item: 'Paper Towels', checked: false, custom: true)
  plan.reload

  entry = plan.custom_items['Paper Towels']
  assert_nil entry['on_hand_at']
end

test "custom item with on_hand_at in the past is not visible" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['custom_items'] = {
    'Paper Towels' => { 'aisle' => 'Miscellaneous', 'last_used_at' => '2026-03-22', 'on_hand_at' => '2026-03-22' }
  }
  plan.save!

  assert_empty plan.visible_custom_items
end

test "custom item with on_hand_at today is visible" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['custom_items'] = {
    'Paper Towels' => { 'aisle' => 'Miscellaneous', 'last_used_at' => Date.current.iso8601, 'on_hand_at' => Date.current.iso8601 }
  }
  plan.save!

  assert_equal 1, plan.visible_custom_items.size
end

test "prune_custom_items removes entries older than 45 days" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['custom_items'] = {
    'Old Item' => { 'aisle' => 'Miscellaneous', 'last_used_at' => (Date.current - 46).iso8601, 'on_hand_at' => nil },
    'Recent Item' => { 'aisle' => 'Miscellaneous', 'last_used_at' => Date.current.iso8601, 'on_hand_at' => nil }
  }
  plan.save!

  resolver = IngredientCatalog.resolver_for(@kitchen)
  visible = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan, resolver:).visible_names
  plan.reconcile!(visible_names: visible, resolver:)

  assert_not plan.custom_items.key?('Old Item')
  assert plan.custom_items.key?('Recent Item')
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb -n '/custom_items/'`
Expected: Multiple failures (methods don't exist, format is wrong)

- [ ] **Step 3: Update MealPlan model for structured custom items**

In `app/models/meal_plan.rb`:

1. Change `STATE_DEFAULTS` — `'custom_items'` default from `[]` to `{}`.

2. Add constants:
```ruby
CUSTOM_ITEM_RETENTION = 45
```

3. Replace `custom_items` accessor:
```ruby
def custom_items
  state.fetch('custom_items', {})
end

def visible_custom_items(now: Date.current)
  custom_items.select { |_, entry| custom_item_visible?(entry, now) }
end
```

4. Add private helper:
```ruby
def custom_item_visible?(entry, now)
  return true if entry['on_hand_at'].nil?
  Date.parse(entry['on_hand_at']) >= now
end
```

5. Replace `apply_custom_items`:
```ruby
def apply_custom_items(item:, action:, aisle: 'Miscellaneous', now: Date.current, **)
  hash = state['custom_items']
  if action == 'add'
    existing_key = hash.each_key.find { |k| k.casecmp?(item) }
    hash.delete(existing_key) if existing_key
    hash[item] = { 'aisle' => aisle, 'last_used_at' => now.iso8601, 'on_hand_at' => nil }
  else
    key = hash.each_key.find { |k| k.casecmp?(item) } || item
    hash.delete(key)
  end
  save!
end
```

6. Update `apply_check` to set `on_hand_at` for custom items:
In `add_to_on_hand`, after the existing logic, when `custom: true` and a structured custom item exists, set its `on_hand_at`.
In `remove_from_on_hand`, when `custom: true`, clear `on_hand_at`.

```ruby
# Add to add_to_on_hand, after the existing save!:
def sync_custom_on_hand(item, on_hand:, now:)
  hash = state['custom_items']
  key = hash.each_key.find { |k| k.casecmp?(item) }
  return unless key
  hash[key]['on_hand_at'] = on_hand ? now.iso8601 : nil
end
```

Call `sync_custom_on_hand(item, on_hand: true, now:)` at the end of `add_to_on_hand` when `custom: true`.
Call `sync_custom_on_hand(item, on_hand: false, now:)` at the end of `remove_from_on_hand` when `custom: true`.

7. Update `CASE_INSENSITIVE_KEYS` — remove `'custom_items'` from the list since it's now a hash, not an array. The toggle_array/list_include?/list_remove methods no longer apply.

8. Add custom item pruning to `prune_on_hand`:
```ruby
def prune_custom_items(now)
  hash = state['custom_items']
  cutoff = now - CUSTOM_ITEM_RETENTION
  before = hash.size
  hash.reject! { |_, e| Date.parse(e['last_used_at']) < cutoff }
  hash.size < before
end
```

Call `prune_custom_items(now)` from `reconcile!`:
```ruby
def reconcile!(visible_names:, resolver: nil, now: Date.current)
  ensure_state_keys
  changed = prune_on_hand(visible_names:, resolver:, now:)
  changed |= prune_stale_selections
  changed |= prune_custom_items(now)
  save! if changed
end
```

9. Update `expire_orphaned_on_hand` — it currently checks `custom.any? { |c| c.casecmp?(key) }` where `custom` is the flat array. Since custom_items is now a hash, update to check `custom.any? { |k, _| k.casecmp?(key) }`:

```ruby
def expire_orphaned_on_hand(hash, visible_names, custom, now)
  changed = false
  hash.each do |key, entry|
    next if visible_names.include?(key) || custom.any? { |k, _| k.casecmp?(key) }
    # ... rest unchanged
  end
  changed
end
```

10. Update `fix_orphaned_null_intervals` similarly:
```ruby
next if custom.any? { |k, _| k.casecmp?(key) }
```

- [ ] **Step 4: Update ShoppingListBuilder for structured custom items**

In `app/services/shopping_list_builder.rb`:

1. Update `visible_names` (line 31):
```ruby
def visible_names
  custom = @meal_plan.visible_custom_items.keys.map { |name| canonical_name(name) }
  (canonical_recipe_names + canonical_quick_bite_names + custom)
    .reject { |name| @resolver.omitted?(name) }.to_set
end
```

2. Update `add_custom_items` to parse from structured hash:
Find the existing `add_custom_items` method. Currently it iterates `@meal_plan.custom_items` (an array of strings) and calls `parse_custom_item`. Replace to iterate the hash:

```ruby
def add_custom_items(organized)
  custom = @meal_plan.visible_custom_items
  return if custom.empty?

  existing = existing_canonical_names(organized)
  new_items = custom.filter_map { |name, entry| custom_item_entry_from_hash(name, entry, organized, existing) }
  return if new_items.empty?

  new_items.each { |aisle, item| (organized[aisle] ||= []) << item }
  organized.replace(sort_aisles(organized))
end

def custom_item_entry_from_hash(name, entry, organized, existing)
  canonical = canonical_name(name)
  return if existing.include?(canonical)

  aisle = resolve_aisle_hint(entry['aisle'], organized)
  [aisle, { name: canonical, amounts: [], sources: [], uncounted: 0 }]
end
```

Key changes: iterates `visible_custom_items` (hash) instead of the flat array, reads `aisle` from the entry directly, uses existing `resolve_aisle_hint(hint, organized)` for fuzzy aisle matching, and uses `organized.replace(sort_aisles(organized))` (the existing sort pattern — there is no `sort_aisles!` method).

- [ ] **Step 5: Update GroceriesHelper for structured custom items**

In `app/helpers/groceries_helper.rb`:

1. Update `item_zone` (line 24) — custom_items is now a hash:
```ruby
return :to_buy if custom_items.any? { |k, _| k.casecmp?(name) }
```

2. Update `shopping_list_count_text` default parameter (line 29) — change `custom_items: []` to `custom_items: {}` since custom_items is now a hash.

3. The `parse_custom_item` method is no longer needed by the shopping list template (entries already have separate name/aisle). Keep it for the grocery page custom input (parsing the `@aisle` hint from user text input).

- [ ] **Step 6: Update MealPlanWriteService for structured custom items**

In `app/services/meal_plan_write_service.rb`:

1. Update `enrich_check_params` (line 55) — custom detection now checks hash keys:
```ruby
custom = plan.custom_items.any? { |k, _| k.casecmp?(params[:item].to_s) }
```

2. Update `validate_action` — also validate `custom_items` action:
```ruby
def validate_action(action_type, **params)
  return [] unless %w[custom_items quick_add].include?(action_type)

  max = MealPlan::MAX_CUSTOM_ITEM_LENGTH
  return ["Custom item name is too long (max #{max} characters)"] if params[:item].to_s.size > max
  []
end
```

- [ ] **Step 7: Update views for structured custom items**

In `app/views/groceries/_custom_items.html.erb`:
The template currently iterates `custom_items` as strings and calls `parse_custom_item`. Update to iterate the hash:

```erb
<%# locals: (custom_items: {}) %>
<div id="custom-items-section">
  <div id="custom-input-row">
    <label for="custom-input" class="sr-only">Add a custom item</label>
    <input type="text" id="custom-input" class="input-base input-lg" placeholder="Add an item... (@ Aisle)">
    <button id="custom-add" class="btn-icon-round btn-icon-round-lg btn-primary" type="button" aria-label="Add item"><%= icon(:plus, size: 18) %></button>
  </div>
  <ul id="custom-items-list">
    <% custom_items.each do |name, entry| %>
      <li>
        <span><%= name %><% if entry['aisle'] != 'Miscellaneous' %> <span class="custom-item-aisle"><%= entry['aisle'] %></span><% end %></span>
        <button class="custom-item-remove" type="button" aria-label="Remove <%= name %>" data-item="<%= name %>">×</button>
      </li>
    <% end %>
  </ul>
</div>
```

In `app/views/groceries/show.html.erb`:
The `@custom_items` passed to the shopping list partial is now a hash. Update `GroceriesController#show` — `@custom_items` already comes from `plan.custom_items` which now returns a hash. The `visible_custom_items` method should be used for the custom items partial display. Update:

```ruby
def show
  plan = MealPlan.for_kitchen(current_kitchen)
  @shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).build
  @on_hand_names = plan.effective_on_hand.keys.to_set
  @on_hand_data = plan.on_hand
  @custom_items = plan.custom_items
  @visible_custom_items = plan.visible_custom_items
end
```

Pass `@visible_custom_items` to the custom items partial, `@custom_items` to the shopping list partial (for zone detection).

In `app/views/groceries/_shopping_list.html.erb`:
The `custom_items:` local is now a hash. The `item_zone` helper already handles this via the updated code in Step 5. Add an X button for custom items in the To Buy zone:

After the checkbox `<label>` in the to_buy items loop, add:
```erb
<% if custom_items.any? { |k, _| k.casecmp?(item[:name]) } %>
  <button class="custom-item-remove" type="button" aria-label="Remove <%= item[:name] %>" data-item="<%= item[:name] %>">×</button>
<% end %>
```

- [ ] **Step 8: Update grocery_ui_controller.js for structured custom items**

In `app/javascript/controllers/grocery_ui_controller.js`:

The `addCustomItem` method currently sends `{ item: text, action_type: "add" }`. It needs to parse the `@aisle` hint and send the aisle separately:

```javascript
addCustomItem(url) {
  const input = document.getElementById("custom-input")
  if (!input) return

  const text = input.value.trim()
  if (!text) return

  const { name, aisle } = parseCustomItemText(text)
  sendAction(url, { item: name, aisle: aisle || "Miscellaneous", action_type: "add" })
  input.value = ""
  input.focus()
}
```

Add a `parseCustomItemText` helper at the top of the file or as a method:
```javascript
function parseCustomItemText(text) {
  const atIndex = text.lastIndexOf("@")
  if (atIndex <= 0) return { name: text.trim(), aisle: null }

  const hint = text.slice(atIndex + 1).trim()
  if (!hint) return { name: text.trim(), aisle: null }

  return { name: text.slice(0, atIndex).trim(), aisle: hint }
}
```

The remove button handler (`custom-item-remove` click) already sends `{ item: btn.dataset.item, action_type: "remove" }` — this still works since the server-side `apply_custom_items` uses case-insensitive key lookup.

Also bind the X buttons that now appear in the shopping list To Buy zone (not just in the custom items section). The existing delegated listener on `this.element` for `.custom-item-remove` clicks should already catch these since they use the same class.

- [ ] **Step 9: Write the data migration**

Create `db/migrate/0XX_migrate_custom_items_format.rb`:

```ruby
class MigrateCustomItemsFormat < ActiveRecord::Migration[8.0]
  class MealPlan < ApplicationRecord
    self.table_name = 'meal_plans'
  end

  def up
    MealPlan.find_each do |plan|
      state = plan.state || {}
      custom = state['custom_items']
      next unless custom.is_a?(Array)

      structured = {}
      custom.each do |raw|
        name, aisle = parse_item(raw)
        structured[name] = {
          'aisle' => aisle || 'Miscellaneous',
          'last_used_at' => Date.current.iso8601,
          'on_hand_at' => nil
        }
      end
      state['custom_items'] = structured
      plan.update_column(:state, state)
    end
  end

  def down
    MealPlan.find_each do |plan|
      state = plan.state || {}
      custom = state['custom_items']
      next unless custom.is_a?(Hash)

      flat = custom.map do |name, entry|
        aisle = entry['aisle']
        aisle && aisle != 'Miscellaneous' ? "#{name}@#{aisle}" : name
      end
      state['custom_items'] = flat
      plan.update_column(:state, state)
    end
  end

  private

  def parse_item(text)
    prefix, separator, hint = text.rpartition('@')
    return [text.strip, nil] if separator.empty?

    stripped = hint.strip
    stripped.empty? ? [prefix.strip, nil] : [prefix.strip, stripped]
  end
end
```

- [ ] **Step 10: Update ShoppingListBuilder tests**

Update tests in `test/services/shopping_list_builder_test.rb` that set up custom items to use the new hash format. Find tests that set `plan.state['custom_items'] = [...]` and change to the hash format:
```ruby
plan.state['custom_items'] = { 'Paper Towels' => { 'aisle' => 'Miscellaneous', 'last_used_at' => Date.current.iso8601, 'on_hand_at' => nil } }
```

Also find tests that call `plan.apply_action('custom_items', item: ..., action: 'add')` and add `aisle:` parameter.

- [ ] **Step 11: Update GroceriesHelper tests**

Update `test/helpers/groceries_helper_test.rb` — any test that passes `custom_items:` as an array to `item_zone` needs to pass a hash instead.

- [ ] **Step 12: Update MealPlanWriteService tests**

Update `test/services/meal_plan_write_service_test.rb` — tests for custom_items action need `aisle:` parameter.

- [ ] **Step 13: Update GroceriesController tests**

Update `test/controllers/groceries_controller_test.rb` — tests that set up custom items need the new format.

- [ ] **Step 14: Run full test suite, fix remaining failures**

Run: `rake test`
Expected: All tests pass. Fix any remaining failures from the format change.

- [ ] **Step 15: Run linter**

Run: `bundle exec rubocop`
Expected: No new offenses.

- [ ] **Step 16: Commit**

```bash
git add -A
git commit -m "Migrate custom_items from flat array to structured hash

Structured entries track aisle, last_used_at, and on_hand_at for
custom item lifecycle (add → To Buy → On Hand for a day → gone).
45-day autocomplete aging prunes stale entries during reconciliation.
Includes data migration for existing MealPlan records."
```

---

## Task 2: POST /groceries/need Endpoint

Add the server-side endpoint that the search overlay will call to add items to the grocery list.

**Files:**
- Modify: `config/routes.rb` (add route)
- Modify: `app/controllers/groceries_controller.rb` (add `need` action)
- Modify: `app/services/meal_plan_write_service.rb` (add `quick_add` action type)
- Modify: `app/models/meal_plan.rb` (add `apply_quick_add`)
- Test: `test/controllers/groceries_controller_test.rb`, `test/services/meal_plan_write_service_test.rb`

- [ ] **Step 1: Write controller tests for the need endpoint**

Add to `test/controllers/groceries_controller_test.rb`:

```ruby
# --- Quick-add (need) endpoint ---

test "need adds unknown custom item to grocery list" do
  create_kitchen_and_user
  log_in

  post groceries_need_path(kitchen_slug: kitchen_slug),
       params: { item: 'Birthday Candles', aisle: 'Party Supplies' },
       as: :json

  assert_response :ok
  body = response.parsed_body
  assert_equal 'added', body['status']

  plan = MealPlan.for_kitchen(@kitchen)
  assert plan.custom_items.key?('Birthday Candles')
end

test "need returns already_needed for item in to-buy" do
  create_kitchen_and_user
  log_in
  create_recipe_with_ingredient('Flour')
  select_recipe('focaccia')
  mark_need_it('Flour')

  post groceries_need_path(kitchen_slug: kitchen_slug),
       params: { item: 'Flour' },
       as: :json

  assert_response :ok
  assert_equal 'already_needed', response.parsed_body['status']
end

test "need depletes on-hand item" do
  create_kitchen_and_user
  log_in
  create_recipe_with_ingredient('Flour')
  select_recipe('focaccia')
  check_on_hand('Flour')

  post groceries_need_path(kitchen_slug: kitchen_slug),
       params: { item: 'Flour' },
       as: :json

  assert_response :ok
  assert_equal 'moved_to_buy', response.parsed_body['status']
end

test "need depletes inventory-check item" do
  create_kitchen_and_user
  log_in
  create_recipe_with_ingredient('Flour')
  select_recipe('focaccia')

  post groceries_need_path(kitchen_slug: kitchen_slug),
       params: { item: 'Flour' },
       as: :json

  assert_response :ok
  assert_equal 'moved_to_buy', response.parsed_body['status']
end

test "need validates item length" do
  create_kitchen_and_user
  log_in

  post groceries_need_path(kitchen_slug: kitchen_slug),
       params: { item: 'x' * 101 },
       as: :json

  assert_response :unprocessable_content
end

test "need validates item presence" do
  create_kitchen_and_user
  log_in

  post groceries_need_path(kitchen_slug: kitchen_slug),
       params: { item: '' },
       as: :json

  assert_response :unprocessable_content
end

test "need requires membership" do
  create_kitchen_and_user

  post groceries_need_path(kitchen_slug: kitchen_slug),
       params: { item: 'Flour' },
       as: :json

  assert_response :forbidden
end
```

Add these private helpers to the test class:

```ruby
private

def create_recipe_with_ingredient(ingredient_name)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia
    ## Mix
    - #{ingredient_name}, 3 cups
    Mix well.
  MD
end

def select_recipe(slug)
  MealPlanWriteService.apply_action(
    kitchen: @kitchen, action_type: 'select',
    type: 'recipe', slug: slug, selected: true
  )
end

def mark_need_it(item)
  MealPlanWriteService.apply_action(
    kitchen: @kitchen, action_type: 'need_it', item: item
  )
end

def check_on_hand(item)
  MealPlanWriteService.apply_action(
    kitchen: @kitchen, action_type: 'check', item: item, checked: true
  )
end
```

Note: `create_kitchen_and_user` also sets up `@category` — if not, add `setup_test_category(name: 'Bread')` in the test setup.

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb -n '/need/'`
Expected: Failures — route doesn't exist, action doesn't exist.

- [ ] **Step 3: Add route**

In `config/routes.rb`, after line 43 (`groceries/need_it`):
```ruby
post 'groceries/need', to: 'groceries#need', as: :groceries_need
```

- [ ] **Step 4: Add MealPlanWriteService quick_add action**

In `app/services/meal_plan_write_service.rb`, add the `quick_add` logic. The service needs to determine the item's current status before acting:

```ruby
def apply_action(action_type:, **params)
  errors = validate_action(action_type, **params)
  return Result.new(success: false, errors:) if errors.any?

  if action_type == 'quick_add'
    return apply_quick_add(**params)
  end

  mutate_plan do |plan|
    enriched = enrich_check_params(plan, action_type, **params)
    plan.apply_action(action_type, **enriched)
  end
  Kitchen.finalize_writes(kitchen)
  Result.new(success: true, errors: [])
end
```

Add a new `QuickAddResult` struct (separate from `Result` to avoid changing existing semantics):

```ruby
QuickAddResult = Data.define(:status, :errors) do
  def success? = errors.empty?
end
```

Add the `quick_add` method. Uses only public MealPlan methods (`effective_on_hand`, `on_hand`) — no `send` on private methods:

```ruby
def apply_quick_add(item:, aisle: 'Miscellaneous', **)
  resolver = IngredientCatalog.resolver_for(kitchen)
  canonical = resolver.resolve(item)
  plan = MealPlan.for_kitchen(kitchen)

  visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan, resolver:).visible_names
  effective_on_hand = plan.effective_on_hand

  status = quick_add_status(canonical, visible, effective_on_hand, plan.on_hand)
  execute_quick_add(status, canonical, aisle)

  QuickAddResult.new(status:, errors: [])
end

def quick_add_status(canonical, visible, effective_on_hand, raw_on_hand)
  return 'moved_to_buy' if effective_on_hand.key?(canonical)

  raw_entry = raw_on_hand.find { |k, _| k.casecmp?(canonical) }&.last
  has_depleted = raw_entry&.key?('depleted_at')
  has_expired = raw_entry && !has_depleted

  return 'already_needed' if visible.include?(canonical) && (has_depleted || raw_entry.nil?)
  return 'moved_to_buy' if visible.include?(canonical) && has_expired

  'added'
end

def execute_quick_add(status, canonical, aisle)
  case status
  when 'moved_to_buy'
    mutate_plan { |p| p.apply_action('need_it', item: canonical) }
  when 'added'
    mutate_plan { |p| p.apply_action('custom_items', item: canonical, aisle:, action: 'add') }
  end
  Kitchen.finalize_writes(kitchen) unless status == 'already_needed'
end
```

State logic summary (uses only public methods):
- `effective_on_hand.key?(canonical)` → item is On Hand → deplete it → `moved_to_buy`
- `visible.include?(canonical)` + raw entry nil or depleted → already in To Buy → `already_needed`
- `visible.include?(canonical)` + raw entry exists but expired (not in effective_on_hand) → Inventory Check → deplete → `moved_to_buy`
- Not visible at all → add as custom item → `added`

Update `validate_action` to handle `quick_add`:
```ruby
def validate_action(action_type, **params)
  return [] unless %w[custom_items quick_add].include?(action_type)

  item = params[:item].to_s
  return ["Item name is required"] if item.blank?

  max = MealPlan::MAX_CUSTOM_ITEM_LENGTH
  return ["Custom item name is too long (max #{max} characters)"] if item.size > max

  []
end
```

- [ ] **Step 5: Add controller action**

In `app/controllers/groceries_controller.rb`:

```ruby
def need
  item_text = params[:item].to_s
  name, parsed_aisle = parse_custom_item(item_text)
  aisle = params[:aisle].presence || parsed_aisle || 'Miscellaneous'

  result = MealPlanWriteService.apply_action(
    kitchen: current_kitchen, action_type: 'quick_add',
    item: name, aisle: aisle
  )
  if result.errors.any?
    return render json: { status: 'error', message: result.errors.first }, status: :unprocessable_content
  end

  render json: { status: result.status }
end
```

Add `include GroceriesHelper` or move `parse_custom_item` to a shared location. Since `GroceriesHelper` is already a module, include it:
```ruby
class GroceriesController < ApplicationController
  include MealPlanActions
  include GroceriesHelper
  # ...
end
```

Wait — Rails controllers already include their own helper by convention. Check if `groceries_helper` methods are available. They should be via `helper :all` or the default helper inclusion. But for the controller (not the view), you need to explicitly include it. Add `include GroceriesHelper` at the top of the controller.

- [ ] **Step 6: Run tests**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb -n '/need/'`
Expected: All `need` tests pass.

- [ ] **Step 7: Run full test suite**

Run: `rake test`
Expected: All tests pass.

- [ ] **Step 8: Run linter**

Run: `bundle exec rubocop`
Expected: No new offenses.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Add POST /groceries/need endpoint for quick-add

Handles four states: already in To Buy (no-op), On Hand (deplete),
Inventory Check (deplete), or unknown (create custom item). Returns
JSON status for the search overlay to show appropriate feedback."
```

---

## Task 3: Search Data Blob — Ingredient and Custom Item Keys

Add `ingredients` and `custom_items` keys to the search data JSON so the client has a fuzzy-match corpus.

**Files:**
- Modify: `app/helpers/search_data_helper.rb`
- Test: `test/helpers/search_data_helper_test.rb`

- [ ] **Step 1: Write tests for the new search data keys**

Add/create `test/helpers/search_data_helper_test.rb`:

```ruby
require 'test_helper'

class SearchDataHelperTest < ActiveSupport::TestCase
  include SearchDataHelper

  setup do
    setup_test_kitchen
    setup_test_category(name: 'Bread')
  end

  # Stub current_kitchen for the helper
  def current_kitchen
    @kitchen
  end

  test "search_data_json includes ingredients key" do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia
      ## Mix
      - Flour, 3 cups
      - Water, 1 cup
      Mix well.
    MD

    data = JSON.parse(search_data_json)
    assert data.key?('ingredients')
    assert_includes data['ingredients'], 'Flour'
    assert_includes data['ingredients'], 'Water'
  end

  test "ingredients are deduplicated across recipes" do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia
      ## Mix
      - Flour, 3 cups
      Mix well.
    MD
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Pizza Dough
      ## Mix
      - Flour, 2 cups
      Mix well.
    MD

    data = JSON.parse(search_data_json)
    assert_equal 1, data['ingredients'].count { |i| i == 'Flour' }
  end

  test "ingredients include on-hand item names" do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = { 'Milk' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 7, 'ease' => 1.5 } }
    plan.save!

    data = JSON.parse(search_data_json)
    assert_includes data['ingredients'], 'Milk'
  end

  test "search_data_json includes custom_items key" do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['custom_items'] = {
      'Birthday Candles' => { 'aisle' => 'Party Supplies', 'last_used_at' => Date.current.iso8601, 'on_hand_at' => nil }
    }
    plan.save!

    data = JSON.parse(search_data_json)
    assert data.key?('custom_items')
    custom = data['custom_items'].find { |c| c['name'] == 'Birthday Candles' }
    assert custom
    assert_equal 'Party Supplies', custom['aisle']
  end

  test "custom_items excludes items older than 45 days" do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['custom_items'] = {
      'Old Item' => { 'aisle' => 'Misc', 'last_used_at' => (Date.current - 46).iso8601, 'on_hand_at' => nil },
      'New Item' => { 'aisle' => 'Misc', 'last_used_at' => Date.current.iso8601, 'on_hand_at' => nil }
    }
    plan.save!

    data = JSON.parse(search_data_json)
    names = data['custom_items'].map { |c| c['name'] }
    assert_not_includes names, 'Old Item'
    assert_includes names, 'New Item'
  end

  test "ingredients are sorted alphabetically" do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia
      ## Mix
      - Zucchini, 1
      - Apple, 1
      Mix well.
    MD

    data = JSON.parse(search_data_json)
    assert_equal data['ingredients'].sort, data['ingredients']
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/helpers/search_data_helper_test.rb`
Expected: Failures — keys don't exist yet.

- [ ] **Step 3: Implement search data additions**

In `app/helpers/search_data_helper.rb`:

```ruby
def search_data_json
  recipes = current_kitchen.recipes.includes(:category, :ingredients, :tags).alphabetical
  plan = MealPlan.for_kitchen(current_kitchen)

  {
    all_tags: current_kitchen.tags.order(:name).pluck(:name),
    all_categories: current_kitchen.categories.ordered.pluck(:name),
    recipes: recipes.map { |r| search_entry_for(r) },
    ingredients: ingredient_corpus(recipes, plan),
    custom_items: custom_item_corpus(plan)
  }.to_json
end

private

def search_entry_for(recipe)
  {
    title: recipe.title,
    slug: recipe.slug,
    description: recipe.description.to_s,
    category: recipe.category.name,
    tags: recipe.tags.map(&:name).sort,
    ingredients: recipe.ingredients.map(&:name).uniq
  }
end

def ingredient_corpus(recipes, plan)
  names = recipes.flat_map { |r| r.ingredients.map(&:name) }
  names.concat(plan.on_hand.keys)
  names.uniq.sort
end

def custom_item_corpus(plan)
  cutoff = Date.current - MealPlan::CUSTOM_ITEM_RETENTION
  plan.custom_items
      .select { |_, e| Date.parse(e['last_used_at']) >= cutoff }
      .map { |name, entry| { name:, aisle: entry['aisle'] } }
end
```

- [ ] **Step 4: Run tests**

Run: `ruby -Itest test/helpers/search_data_helper_test.rb`
Expected: All pass.

- [ ] **Step 5: Run full test suite and linter**

Run: `rake`
Expected: All pass, no new offenses.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add ingredients and custom_items keys to search data blob

Pre-flattened ingredient list for client-side fuzzy matching.
Custom items include name and aisle for autocomplete with memory."
```

---

## Task 4: Client-Side Ingredient Matching

Build the fuzzy matching utility that powers autocomplete in the grocery action row.

**Files:**
- Create: `app/javascript/utilities/ingredient_match.js`
- Create: `test/javascript/ingredient_match_test.mjs`

- [ ] **Step 1: Write tests for ingredient matching**

Create `test/javascript/ingredient_match_test.mjs`:

```javascript
import assert from "node:assert/strict"
import { test } from "node:test"
import { matchIngredients } from "../../app/javascript/utilities/ingredient_match.js"

const corpus = [
  "Butter", "Buttermilk", "Milk", "Miso Paste", "Mint",
  "Mixed Greens", "Flour", "Peanut Butter"
]

test("prefix match ranks higher than substring", () => {
  const results = matchIngredients("mi", corpus)
  assert.equal(results[0], "Milk")
  assert.ok(results.includes("Mint"))
  assert.ok(results.includes("Miso Paste"))
})

test("exact match ranks first", () => {
  const results = matchIngredients("milk", corpus)
  assert.equal(results[0], "Milk")
})

test("case insensitive matching", () => {
  const results = matchIngredients("MILK", corpus)
  assert.equal(results[0], "Milk")
})

test("substring match finds interior matches", () => {
  const results = matchIngredients("nut", corpus)
  assert.ok(results.includes("Peanut Butter"))
})

test("no match returns empty array", () => {
  const results = matchIngredients("xyz", corpus)
  assert.equal(results.length, 0)
})

test("empty query returns empty array", () => {
  const results = matchIngredients("", corpus)
  assert.equal(results.length, 0)
})

test("results limited to max parameter", () => {
  const results = matchIngredients("m", corpus, { max: 3 })
  assert.equal(results.length, 3)
})

test("shorter names ranked higher among prefix matches", () => {
  const results = matchIngredients("butter", corpus)
  assert.equal(results[0], "Butter")
  assert.equal(results[1], "Buttermilk")
})

test("custom items included with aisle info preserved", () => {
  const customs = [{ name: "Birthday Candles", aisle: "Party Supplies" }]
  const results = matchIngredients("birth", corpus, { customItems: customs })
  assert.equal(results[0], "Birthday Candles")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test`
Expected: Cannot find module error.

- [ ] **Step 3: Implement ingredient matching**

Create `app/javascript/utilities/ingredient_match.js`:

```javascript
/**
 * Client-side fuzzy matching for ingredient autocomplete in the search overlay.
 * Matches against a combined corpus of recipe ingredients, on-hand items, and
 * custom items. Ranking: exact > prefix > substring, with shorter names first
 * among ties. Returns original-case names for display.
 *
 * Collaborators:
 *   - search_overlay_controller.js (sole consumer)
 *   - SearchDataHelper (provides the corpus via JSON blob)
 */

export function matchIngredients(query, ingredients, { max = 10, customItems = [] } = {}) {
  if (!query) return []

  const q = query.toLowerCase()
  const allNames = [...ingredients, ...customItems.map(c => c.name)]
  const scored = []

  for (const name of allNames) {
    const lower = name.toLowerCase()
    if (lower === q) {
      scored.push({ name, score: 0, len: name.length })
    } else if (lower.startsWith(q)) {
      scored.push({ name, score: 1, len: name.length })
    } else if (lower.includes(q)) {
      scored.push({ name, score: 2, len: name.length })
    }
  }

  scored.sort((a, b) => a.score - b.score || a.len - b.len || a.name.localeCompare(b.name))

  const seen = new Set()
  const results = []
  for (const { name } of scored) {
    const key = name.toLowerCase()
    if (seen.has(key)) continue
    seen.add(key)
    results.push(name)
    if (results.length >= max) break
  }

  return results
}
```

- [ ] **Step 4: Run tests**

Run: `npm test`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/utilities/ingredient_match.js test/javascript/ingredient_match_test.mjs
git commit -m "Add client-side ingredient fuzzy matching utility

Prefix > substring ranking with tie-breaking by name length.
Used by search overlay for grocery action row autocomplete."
```

---

## Task 5: Search Overlay — Grocery Action Row

Wire up the search overlay to show the grocery action row with autocomplete, alternate matches, and flash-and-close confirmation.

**Files:**
- Create: `app/javascript/utilities/grocery_action.js`
- Modify: `app/javascript/controllers/search_overlay_controller.js`
- Modify: `app/views/shared/_search_overlay.html.erb`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/assets/stylesheets/navigation.css`

- [ ] **Step 1: Add need-url data attribute to the search overlay**

In `app/views/layouts/application.html.erb`, on the `<body>` tag, add:
```erb
data-search-overlay-need-url="<%= groceries_need_path %>"
```

This provides the POST endpoint URL to the search overlay controller.

- [ ] **Step 2: Create grocery_action.js utility**

Create `app/javascript/utilities/grocery_action.js`:

```javascript
/**
 * Builds and manages the grocery action row in the search overlay. Renders the
 * "Need [item]?" prompt with alternate matches, handles the POST to
 * /groceries/need, and shows flash-and-close confirmation feedback.
 *
 * Collaborators:
 *   - search_overlay_controller.js (creates and positions the row)
 *   - ingredient_match.js (provides ranked matches)
 *   - turbo_fetch.js (sends the POST action)
 */
import { getCsrfToken } from "./editor_utils"

export function buildGroceryActionRow(topMatch, alternates, { customItems = [] } = {}) {
  const row = document.createElement("li")
  row.className = "search-result grocery-action-row"
  row.setAttribute("role", "option")
  row.dataset.groceryAction = "true"
  row.dataset.ingredient = topMatch

  const left = document.createElement("span")
  left.className = "grocery-action-label"

  const cart = document.createElement("span")
  cart.className = "grocery-action-cart"
  cart.textContent = "\uD83D\uDED2"
  left.appendChild(cart)

  const prompt = document.createElement("span")
  prompt.textContent = " Need "
  left.appendChild(prompt)

  const strong = document.createElement("strong")
  strong.textContent = topMatch
  left.appendChild(strong)

  const q = document.createElement("span")
  q.textContent = "?"
  left.appendChild(q)

  const customEntry = customItems.find(c => c.name.toLowerCase() === topMatch.toLowerCase())
  if (customEntry && customEntry.aisle && customEntry.aisle !== "Miscellaneous") {
    const aisle = document.createElement("span")
    aisle.className = "grocery-action-aisle"
    aisle.textContent = customEntry.aisle
    left.appendChild(aisle)
  }

  row.appendChild(left)

  const hint = document.createElement("span")
  hint.className = "grocery-action-hint"
  hint.textContent = "\u21B5"
  row.appendChild(hint)

  const container = document.createDocumentFragment()
  container.appendChild(row)

  if (alternates.length > 0) {
    const altRow = document.createElement("li")
    altRow.className = "grocery-alternates"
    altRow.setAttribute("role", "presentation")

    const prefix = document.createElement("span")
    prefix.className = "grocery-alternates-label"
    prefix.textContent = "also: "
    altRow.appendChild(prefix)

    alternates.forEach((alt, i) => {
      if (i > 0) {
        const sep = document.createTextNode(", ")
        altRow.appendChild(sep)
      }
      const link = document.createElement("button")
      link.type = "button"
      link.className = "grocery-alternate-btn"
      link.textContent = alt
      link.dataset.ingredient = alt
      altRow.appendChild(link)
    })

    container.appendChild(altRow)
  }

  return container
}

export function buildAlreadyNeededRow(name) {
  const row = document.createElement("li")
  row.className = "search-result grocery-action-row grocery-action-row--already"
  row.setAttribute("role", "option")

  const label = document.createElement("span")
  label.className = "grocery-action-label"
  label.textContent = "\u2713 "

  const strong = document.createElement("strong")
  strong.textContent = name
  label.appendChild(strong)

  const suffix = document.createTextNode(" is already on your list")
  label.appendChild(suffix)

  row.appendChild(label)
  return row
}

export async function postNeedAction(url, item, aisle) {
  const body = { item }
  if (aisle) body.aisle = aisle

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": getCsrfToken() || ""
    },
    body: JSON.stringify(body)
  })

  if (!response.ok) return { status: "error" }
  return response.json()
}

export function flashAndClose(row, status, closeCallback) {
  const message = status === "already_needed" ? "Already on your list" : "Added!"
  row.classList.add("grocery-action-row--flash")

  const label = row.querySelector(".grocery-action-label")
  if (label) label.textContent = message

  const hint = row.querySelector(".grocery-action-hint")
  if (hint) hint.remove()

  setTimeout(() => closeCallback(), 500)
}
```

- [ ] **Step 3: Update search_overlay_controller.js**

This is the largest change. The controller needs to:

1. Load ingredient + custom item data on connect
2. On each search, compute ingredient matches and render the grocery action row
3. Handle Enter on the grocery action row (POST, flash, close)
4. Handle alternate clicks (replace input, re-search)
5. Track the grocery action row in selection navigation

Key changes to `search_overlay_controller.js`:

```javascript
// Add imports at top
import { matchIngredients } from "../utilities/ingredient_match"
import {
  buildGroceryActionRow,
  buildAlreadyNeededRow,
  postNeedAction,
  flashAndClose
} from "../utilities/grocery_action"
```

In `loadData()`, add:
```javascript
this.ingredientCorpus = data.ingredients || []
this.customItems = data.custom_items || []
```

Add a `needUrl` getter:
```javascript
get needUrl() {
  return this.element.dataset.searchOverlayNeedUrl || ""
}
```

Modify `performSearch()` — after computing recipe results, compute ingredient matches and prepend the grocery action row:

```javascript
performSearch() {
  const query = normalizeForSearch(this.inputTarget.value).toLowerCase().trim()
  if (!query && this.activePills.length === 0) {
    this.resultsTarget.replaceChildren()
    this.selectedIndex = -1
    return
  }

  let candidates = this.recipes
  for (const pill of this.activePills) {
    candidates = candidates.filter(r => this.matchesPill(r, pill))
  }

  const tokens = query ? query.split(/\s+/).filter(Boolean) : []
  const recipes = tokens.length ? this.rankResults(tokens, candidates) : candidates

  // Grocery action row
  const ingredientMatches = query
    ? matchIngredients(query, this.ingredientCorpus, { customItems: this.customItems, max: 6 })
    : []

  this.renderResultsWithGrocery(recipes, ingredientMatches, query)
  this.selectFirst()
}
```

Add `renderResultsWithGrocery`:
```javascript
renderResultsWithGrocery(recipes, ingredientMatches, query) {
  this.clearResults()
  const list = this.resultsTarget

  this.groceryRowCount = 0

  if (ingredientMatches.length > 0 || (query && this.activePills.length === 0)) {
    const topMatch = ingredientMatches[0] || query
    const alternates = ingredientMatches.slice(1, 4)

    const fragment = buildGroceryActionRow(topMatch, alternates, { customItems: this.customItems })
    list.appendChild(fragment)
    this.groceryRowCount = 1

    // Bind alternate clicks
    list.querySelectorAll(".grocery-alternate-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        this.inputTarget.value = btn.dataset.ingredient
        this.search()
      })
    })
  }

  if (recipes.length === 0 && this.groceryRowCount === 0) {
    const li = document.createElement("li")
    li.className = "search-no-results"
    li.textContent = "No matches"
    li.setAttribute("role", "option")
    list.appendChild(li)
    return
  }

  recipes.forEach((recipe, index) => {
    const li = document.createElement("li")
    li.className = "search-result"
    li.setAttribute("role", "option")
    li.dataset.index = index + this.groceryRowCount
    li.dataset.slug = recipe.slug

    const title = document.createElement("span")
    title.className = "search-result-title"
    title.textContent = recipe.title

    const category = document.createElement("span")
    category.className = "search-result-category"
    category.textContent = recipe.category

    li.appendChild(title)
    li.appendChild(category)
    li.addEventListener("click", () => this.navigateTo(recipe.slug))
    list.appendChild(li)
  })
}
```

Update `selectCurrent()` to handle the grocery action row:
```javascript
selectCurrent() {
  const items = this.resultsTarget.querySelectorAll(".search-result")
  const index = this.selectedIndex >= 0 ? this.selectedIndex : 0
  if (items.length === 0) return

  const selected = items[index]
  if (selected.dataset.groceryAction) {
    this.executeGroceryAction(selected)
    return
  }

  this.navigateTo(selected.dataset.slug)
}
```

Add `executeGroceryAction`:
```javascript
async executeGroceryAction(row) {
  const ingredient = row.dataset.ingredient
  const customEntry = this.customItems.find(c => c.name.toLowerCase() === ingredient.toLowerCase())
  const aisle = customEntry?.aisle

  const result = await postNeedAction(this.needUrl, ingredient, aisle)
  flashAndClose(row, result.status, () => this.close())
}
```

- [ ] **Step 4: Add CSS for the grocery action row**

In `app/assets/stylesheets/navigation.css`, add styles for the grocery action row:

```css
/* Grocery action row in search overlay */
.grocery-action-row {
  background: color-mix(in srgb, var(--green, #4a7c59) 8%, var(--ground));
  border: 1px solid color-mix(in srgb, var(--green, #4a7c59) 20%, var(--rule));
  border-radius: 6px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 12px;
  margin-bottom: 4px;
}

.grocery-action-row.selected {
  background: color-mix(in srgb, var(--green, #4a7c59) 16%, var(--ground));
}

.grocery-action-row--already {
  background: color-mix(in srgb, var(--amber, #b8860b) 8%, var(--ground));
  border-color: color-mix(in srgb, var(--amber, #b8860b) 20%, var(--rule));
}

.grocery-action-row--flash {
  background: color-mix(in srgb, var(--green, #4a7c59) 25%, var(--ground));
  transition: background 0.3s ease;
}

.grocery-action-label {
  font-size: 0.95rem;
}

.grocery-action-cart {
  margin-right: 6px;
}

.grocery-action-aisle {
  color: var(--text-soft);
  font-size: 0.8rem;
  margin-left: 8px;
}

.grocery-action-hint {
  color: var(--text-light);
  font-size: 0.8rem;
  border: 1px solid var(--rule-faint);
  border-radius: 4px;
  padding: 1px 6px;
}

.grocery-alternates {
  padding: 2px 12px 6px 36px;
  color: var(--text-soft);
  font-size: 0.8rem;
  list-style: none;
}

.grocery-alternates-label {
  color: var(--text-light);
}

.grocery-alternate-btn {
  background: none;
  border: none;
  color: var(--text-soft);
  cursor: pointer;
  padding: 0;
  font-size: inherit;
  text-decoration: underline;
  text-decoration-style: dotted;
}

.grocery-alternate-btn:hover {
  color: var(--text);
}
```

Note: Check `base.css` `:root` for actual color token names. The above uses `var(--green)` and `var(--amber)` — these may not exist. If not, use the closest available tokens or define inline fallbacks. The `color-mix` approach keeps it theme-aware.

- [ ] **Step 5: Run the full test suite**

Run: `rake`
Expected: All Ruby tests pass. JS tests pass.

- [ ] **Step 6: Run npm build to verify no JS errors**

Run: `npm run build`
Expected: Clean build, no errors.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add grocery action row to search overlay

Type an ingredient name to see 'Need [item]?' as the top result.
Enter fires POST /groceries/need, flashes confirmation, closes overlay.
Alternate matches shown below with click-to-replace. Styled with
green-tinted background and cart icon."
```

---

## Task 6: Manual Testing and Polish

Verify end-to-end behavior in the browser and fix any issues.

**Files:** Various (bug fixes as discovered)

- [ ] **Step 1: Start dev server and verify in browser**

Run: `bin/dev`

Test the following scenarios:
1. Open search overlay (`/`), type "milk" → see grocery action row + recipe results
2. Press Enter → item added to grocery list, flash confirmation, overlay closes
3. Open search, type "milk" again → see "already on your list" amber row
4. Open search, type "birthday candles@Party Supplies" → see grocery action row for unknown item, press Enter → added as custom item
5. Navigate to grocery page → see "birthday candles" in To Buy under Party Supplies
6. Check off "birthday candles" → moves to On Hand with bold-today styling
7. Open search, type "birth" → autocomplete suggests "birthday candles" with "Party Supplies" aisle hint
8. On grocery page, click X on a custom item in To Buy → item removed
9. On grocery page, use the custom item input → add works with new format

- [ ] **Step 2: Fix any issues found**

Address CSS, JS, or server-side issues discovered during manual testing.

- [ ] **Step 3: Run full test suite and linter**

Run: `rake`
Expected: All pass.

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "Polish grocery quick-add: [describe fixes]"
```

---

## Task 7: Update html_safe allowlist and CLAUDE.md

Update documentation and the html_safe allowlist if any `.html_safe` calls shifted.

**Files:**
- Possibly: `config/html_safe_allowlist.yml`
- Modify: `app/models/meal_plan.rb` (header comment — update action types list)
- Modify: `CLAUDE.md` (add grocery quick-add to architecture section if needed)

- [ ] **Step 1: Run html_safe lint**

Run: `rake lint:html_safe`
Expected: No new violations. If line numbers shifted, update the allowlist.

- [ ] **Step 2: Update MealPlan header comment**

Add `quick_add` to the action types list in the header comment.

- [ ] **Step 3: Update CLAUDE.md if needed**

Add a brief note about the grocery quick-add endpoint and the structured custom items format if it affects other developers.

- [ ] **Step 4: Run full suite**

Run: `rake`
Expected: All pass.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "Update docs and allowlist for grocery quick-add"
```
