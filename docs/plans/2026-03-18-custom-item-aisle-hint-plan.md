# Custom Item Aisle Hint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users route custom grocery items to specific aisles via `@ Aisle` hint syntax.

**Architecture:** Parse `@` from custom item strings in `ShoppingListBuilder` and `GroceriesHelper`. Aisle hint overrides catalog lookup. Display hint in custom items list, strip from shopping list. No storage changes.

**Tech Stack:** Ruby on Rails, ERB, CSS

**Spec:** `docs/plans/2026-03-18-custom-item-aisle-hint-design.md`

---

### Task 1: ShoppingListBuilder — parse and route hinted custom items

**Files:**
- Modify: `app/services/shopping_list_builder.rb:125-138` (`add_custom_items` method)
- Modify: `app/services/shopping_list_builder.rb:30-38` (`visible_names` method)
- Test: `test/services/shopping_list_builder_test.rb`

- [ ] **Step 1: Write failing test — hinted item routes to specified aisle**

Add to `test/services/shopping_list_builder_test.rb`:

```ruby
test 'custom item with aisle hint routes to hinted aisle' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('custom_items', item: 'Shaving cream @ Personal', action: 'add')

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

  assert result.key?('Personal'), "Expected 'Personal' aisle"
  item = result['Personal'].find { |i| i[:name] == 'Shaving cream' }

  assert item, 'Expected "Shaving cream" (without hint) in Personal aisle'
  assert_empty item[:amounts]
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n test_custom_item_with_aisle_hint_routes_to_hinted_aisle`
Expected: FAIL — item goes to Miscellaneous with raw name including `@ Personal`

- [ ] **Step 3: Implement `parse_custom_item` and update `add_custom_items`**

In `app/services/shopping_list_builder.rb`, add private method and update `add_custom_items`:

```ruby
def parse_custom_item(text)
  prefix, separator, hint = text.rpartition('@')
  return [text.strip, nil] if separator.empty?

  stripped_hint = hint.strip
  return [prefix.strip, nil] if stripped_hint.empty?

  [prefix.strip, stripped_hint]
end

def resolve_aisle_hint(hint, organized)
  match = organized.keys.find { |k| k.casecmp(hint).zero? }
  return match if match

  order_match = @kitchen.parsed_aisle_order.find { |a| a.casecmp(hint).zero? }
  order_match || hint
end

def add_custom_items(organized)
  custom = @meal_plan.state.fetch('custom_items', [])
  return if custom.empty?

  existing = existing_canonical_names(organized)
  added = false

  custom.each do |raw_item|
    name, aisle_hint = parse_custom_item(raw_item)
    canonical = canonical_name(name)
    next if existing.include?(canonical)

    aisle = aisle_hint ? resolve_aisle_hint(aisle_hint, organized) : aisle_for(canonical)
    organized[aisle] ||= []
    organized[aisle] << { name: canonical, amounts: [], sources: [] }
    added = true
  end

  organized.replace(sort_aisles(organized)) if added
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n test_custom_item_with_aisle_hint_routes_to_hinted_aisle`
Expected: PASS

- [ ] **Step 5: Write failing test — trailing @ with empty hint falls back**

```ruby
test 'trailing @ with empty hint falls back to catalog lookup' do
  create_catalog_entry('Butter', basis_grams: 14, aisle: 'Dairy')
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('custom_items', item: 'Butter @ ', action: 'add')

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

  assert result.key?('Dairy'), 'Empty hint should fall back to catalog aisle'
  butter = result['Dairy'].find { |i| i[:name] == 'Butter' }

  assert butter
end
```

- [ ] **Step 6: Run test — should pass (empty hint guard returns nil)**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n test_trailing_@_with_empty_hint_falls_back_to_catalog_lookup`
Expected: PASS

- [ ] **Step 7: Write failing test — hinted item with no spaces around @**

```ruby
test 'custom item with no spaces around @ still parses hint' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('custom_items', item: 'soap@Personal', action: 'add')

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

  assert result.key?('Personal')
  item = result['Personal'].find { |i| i[:name] == 'soap' }

  assert item, 'Expected "soap" in Personal aisle'
end
```

- [ ] **Step 8: Run test — should pass immediately (rpartition handles this)**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n test_custom_item_with_no_spaces_around_@_still_parses_hint`
Expected: PASS

- [ ] **Step 9: Write failing test — multiple @ uses last one**

```ruby
test 'custom item with multiple @ splits on last one' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('custom_items', item: 'foo @ bar @ Baking', action: 'add')

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

  assert result.key?('Baking')
  item = result['Baking'].find { |i| i[:name] == 'foo @ bar' }

  assert item, 'Expected "foo @ bar" with last @ used as separator'
end
```

- [ ] **Step 10: Run test — should pass immediately**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n test_custom_item_with_multiple_@_splits_on_last_one`
Expected: PASS

- [ ] **Step 11: Write failing test — case-insensitive aisle matching**

```ruby
test 'aisle hint matches existing aisle case-insensitively' do
  @kitchen.update!(aisle_order: "Spices\nBaking")
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  list.apply_action('custom_items', item: 'cinnamon sticks @ spices', action: 'add')

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

  assert result.key?('Spices'), 'Expected canonical "Spices" aisle, not lowercase'
  item = result['Spices'].find { |i| i[:name] == 'cinnamon sticks' }

  assert item, 'Expected item in existing Spices aisle via case-insensitive match'
end
```

- [ ] **Step 12: Run test to verify it passes**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n test_aisle_hint_matches_existing_aisle_case-insensitively`
Expected: PASS

- [ ] **Step 13: Write failing test — hint overrides catalog aisle**

```ruby
test 'aisle hint overrides catalog aisle for known ingredient' do
  create_catalog_entry('Butter', basis_grams: 14, aisle: 'Dairy')
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('custom_items', item: 'Butter @ Baking', action: 'add')

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build

  assert result.key?('Baking'), 'Hint should override catalog aisle'
  butter = result['Baking'].find { |i| i[:name] == 'Butter' }

  assert butter
end
```

- [ ] **Step 14: Run test to verify it passes**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n test_aisle_hint_overrides_catalog_aisle_for_known_ingredient`
Expected: PASS

- [ ] **Step 15: Write failing test — dedup uses parsed name**

```ruby
test 'hinted custom item deduped against recipe ingredient by parsed name' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  list.apply_action('custom_items', item: 'Flour @ Pantry', action: 'add')

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  all_names = result.values.flatten.pluck(:name)

  assert_equal 1, all_names.count { |n| n.casecmp('flour').zero? },
               'Hinted custom item should dedup against recipe Flour'
end
```

- [ ] **Step 16: Run test to verify it passes**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n test_hinted_custom_item_deduped_against_recipe_ingredient_by_parsed_name`
Expected: PASS

- [ ] **Step 17: Write failing test — visible_names parses hint**

```ruby
test 'visible_names parses hint from custom items' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('custom_items', item: 'Shaving cream @ Personal', action: 'add')

  names = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).visible_names

  assert_includes names, 'Shaving cream'
  assert_not_includes names, 'Shaving cream @ Personal'
end
```

- [ ] **Step 18: Update `visible_names` to parse hints**

In `app/services/shopping_list_builder.rb`, update the custom items line in `visible_names`:

```ruby
names.merge(@meal_plan.custom_items_list.map { |item| canonical_name(parse_custom_item(item).first) })
```

- [ ] **Step 19: Run test to verify it passes**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n test_visible_names_parses_hint_from_custom_items`
Expected: PASS

- [ ] **Step 20: Write failing test — hinted aisle respects sort order**

```ruby
test 'hinted custom item aisle respects kitchen sort order' do
  @kitchen.update!(aisle_order: "Personal\nBaking")
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  list.apply_action('custom_items', item: 'Shaving cream @ Personal', action: 'add')

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  aisle_names = result.keys

  assert_operator aisle_names.index('Personal'), :<, aisle_names.index('Baking'),
                  'Personal should sort before Baking per aisle_order'
end
```

- [ ] **Step 21: Run test to verify it passes**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n test_hinted_custom_item_aisle_respects_kitchen_sort_order`
Expected: PASS

- [ ] **Step 22: Run full shopping list builder test suite**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb`
Expected: All tests pass

- [ ] **Step 23: Commit**

```bash
git add app/services/shopping_list_builder.rb test/services/shopping_list_builder_test.rb
git commit -m "Add aisle hint parsing to ShoppingListBuilder (#242)"
```

---

### Task 2: GroceriesHelper — parse_custom_item view helper

**Files:**
- Modify: `app/helpers/groceries_helper.rb`
- Test: `test/helpers/groceries_helper_test.rb`

- [ ] **Step 1: Write failing tests for parse_custom_item helper**

Add to `test/helpers/groceries_helper_test.rb`:

```ruby
test 'parse_custom_item splits on last @' do
  name, aisle = parse_custom_item('Shaving cream @ Personal care')

  assert_equal 'Shaving cream', name
  assert_equal 'Personal care', aisle
end

test 'parse_custom_item returns nil aisle when no @' do
  name, aisle = parse_custom_item('Just milk')

  assert_equal 'Just milk', name
  assert_nil aisle
end

test 'parse_custom_item strips whitespace from both parts' do
  name, aisle = parse_custom_item('  soap  @  Health  ')

  assert_equal 'soap', name
  assert_equal 'Health', aisle
end

test 'parse_custom_item handles no spaces around @' do
  name, aisle = parse_custom_item('foo@bar')

  assert_equal 'foo', name
  assert_equal 'bar', aisle
end

test 'parse_custom_item with multiple @ uses last' do
  name, aisle = parse_custom_item('foo @ bar @ Baz')

  assert_equal 'foo @ bar', name
  assert_equal 'Baz', aisle
end

test 'parse_custom_item with trailing @ returns nil aisle' do
  name, aisle = parse_custom_item('foo @ ')

  assert_equal 'foo', name
  assert_nil aisle
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/helpers/groceries_helper_test.rb -n /parse_custom_item/`
Expected: FAIL — method not defined

- [ ] **Step 3: Implement parse_custom_item in GroceriesHelper**

Add to `app/helpers/groceries_helper.rb` in the public section (before `private`):

```ruby
def parse_custom_item(text)
  prefix, separator, hint = text.rpartition('@')
  return [text.strip, nil] if separator.empty?

  stripped_hint = hint.strip
  return [prefix.strip, nil] if stripped_hint.empty?

  [prefix.strip, stripped_hint]
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/helpers/groceries_helper_test.rb`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add app/helpers/groceries_helper.rb test/helpers/groceries_helper_test.rb
git commit -m "Add parse_custom_item helper to GroceriesHelper (#242)"
```

---

### Task 3: View and CSS — display aisle hint in custom items list

**Files:**
- Modify: `app/views/groceries/_custom_items.html.erb`
- Modify: `app/assets/stylesheets/groceries.css:85-97`
- Modify: `app/assets/stylesheets/style.css:41-42` (light) and `style.css:90-91` (dark)

- [ ] **Step 1: Update the custom items partial**

Replace `app/views/groceries/_custom_items.html.erb` with:

```erb
<%# locals: (custom_items: []) %>
<div id="custom-items-section">
  <div id="custom-input-row">
    <label for="custom-input" class="sr-only">Add a custom item</label>
    <input type="text" id="custom-input" placeholder="Add an item... (@ Aisle)">
    <button id="custom-add" type="button" aria-label="Add item"><svg viewBox="0 0 24 24" width="18" height="18"><line x1="12" y1="5" x2="12" y2="19" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="5" y1="12" x2="19" y2="12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button>
  </div>
  <ul id="custom-items-list">
    <% custom_items.each do |raw_item| %>
      <% name, aisle_hint = parse_custom_item(raw_item) %>
      <li>
        <span><%= name %><% if aisle_hint %> <span class="custom-item-aisle"><%= aisle_hint %></span><% end %></span>
        <button class="custom-item-remove" type="button" aria-label="Remove <%= name %>" data-item="<%= raw_item %>">×</button>
      </li>
    <% end %>
  </ul>
</div>
```

- [ ] **Step 2: Add CSS variable for aisle hint color**

In `app/assets/stylesheets/style.css`, add after `--custom-item-remove: #bbb;` (line 42):

```css
  --custom-item-aisle: #a09788;
```

In the dark mode section, add after `--custom-item-remove: rgb(110, 106, 102);` (line 91):

```css
    --custom-item-aisle: rgb(110, 106, 102);
```

- [ ] **Step 3: Add .custom-item-aisle CSS rule**

In `app/assets/stylesheets/groceries.css`, add after `.custom-item-remove:hover` block (after line 112):

```css
.custom-item-aisle {
  font-size: 0.8rem;
  color: var(--custom-item-aisle);
  margin-left: 0.25rem;
}

.custom-item-aisle::before {
  content: '\b7\a0';
}
```

The `\b7` is a middle dot (·) separator and `\a0` is a non-breaking space, giving "Shaving cream · Personal care".

- [ ] **Step 4: Verify visually**

Run: `bin/dev`
Add a custom item "Test item @ Produce" on the groceries page. Verify:
- Item appears in Produce aisle in shopping list (if recipes selected) or standalone
- Custom items list shows "Test item" with "Produce" in lighter text after a dot separator
- Remove button still works (stores full raw string)

- [ ] **Step 5: Run full test suite to catch regressions**

Run: `rake test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add app/views/groceries/_custom_items.html.erb app/assets/stylesheets/groceries.css app/assets/stylesheets/style.css
git commit -m "Display aisle hint in custom items list (#242)

Resolves #242"
```
