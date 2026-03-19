# Uncounted Grocery Items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show "+N more" or "(N uses)" on the grocery list when ingredients have uncounted (nil-quantity) sources, so users know to buy extra.

**Architecture:** Extract nil counts from amounts arrays in `ShoppingListBuilder#merge_ingredient` before `IngredientAggregator` deduplicates them. Pass `uncounted` integer through to the view. `GroceriesHelper#format_amounts` renders the indicator.

**Tech Stack:** Ruby on Rails, Minitest, ERB

---

### Task 1: ShoppingListBuilder — track uncounted sources

**Files:**
- Modify: `app/services/shopping_list_builder.rb:57-61` (`merge_entries`)
- Modify: `app/services/shopping_list_builder.rb:92-96` (`merge_ingredient`)
- Modify: `app/services/shopping_list_builder.rb:102-109` (`organize_by_aisle`)
- Modify: `app/services/shopping_list_builder.rb:142-148` (`custom_item_entry`)
- Modify: `app/services/shopping_list_builder.rb:173-175` (`serialize_amounts`)
- Test: `test/services/shopping_list_builder_test.rb`

**Context:** `IngredientAggregator.merge_amounts` deduplicates all nils to a single boolean — by the time amounts reach `serialize_amounts`, the count of uncounted sources is lost. The fix extracts nils in `merge_ingredient` before they reach the aggregator.

Within a single recipe, `aggregate_amounts` produces at most one nil (boolean `has_unquantified`), so each recipe/quick bite contributes 0 or 1 uncounted. Quick Bites always contribute `[nil]` per ingredient.

- [ ] **Step 1: Write failing tests for uncounted tracking**

Add these tests to `test/services/shopping_list_builder_test.rb`:

```ruby
test 'tracks uncounted when recipe ingredient has no quantity' do
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Salad

    ## Toss (combine)

    - Olive oil
    - Salt, 1 tsp

    Toss.
  MD

  create_catalog_entry('Olive oil', basis_grams: 14, aisle: 'Oils')

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'salad', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  oil = result['Oils'].find { |i| i[:name] == 'Olive oil' }

  assert_equal 1, oil[:uncounted]
  assert_empty oil[:amounts]
end

test 'mixed counted and uncounted from two recipes' do
  create_catalog_entry('Red bell pepper', basis_grams: 150, aisle: 'Produce')

  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Stuffed Peppers

    ## Prep (slice)

    - Red bell pepper, 1

    Prep.
  MD

  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Stir Fry

    ## Cook (stir-fry)

    - Red bell pepper

    Cook.
  MD

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'stuffed-peppers', selected: true)
  list.apply_action('select', type: 'recipe', slug: 'stir-fry', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  pepper = result['Produce'].find { |i| i[:name] == 'Red bell pepper' }

  assert_equal [[1.0, nil]], pepper[:amounts]
  assert_equal 1, pepper[:uncounted]
end

test 'multiple uncounted sources tracked separately' do
  create_catalog_entry('Garlic', basis_grams: 5, aisle: 'Produce')

  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Pasta

    ## Cook (boil)

    - Garlic

    Cook.
  MD

  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Stir Fry

    ## Cook (stir-fry)

    - Garlic

    Cook.
  MD

  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Soup

    ## Cook (simmer)

    - Garlic

    Cook.
  MD

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'pasta', selected: true)
  list.apply_action('select', type: 'recipe', slug: 'stir-fry', selected: true)
  list.apply_action('select', type: 'recipe', slug: 'soup', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  garlic = result['Produce'].find { |i| i[:name] == 'Garlic' }

  assert_equal 3, garlic[:uncounted]
  assert_empty garlic[:amounts]
end

test 'fully counted ingredients have zero uncounted' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  flour = result['Baking'].find { |i| i[:name] == 'Flour' }

  assert_equal 0, flour[:uncounted]
end

test 'quick bite merged with counted recipe ingredient increments uncounted' do
  create_catalog_entry('Hummus', basis_grams: 30, aisle: 'Deli')

  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Veggie Plate

    ## Assemble (plate)

    - Hummus, 1 cup

    Arrange.
  MD

  @kitchen.update!(quick_bites_content: <<~MD)
    ## Snacks
    - Hummus with Pretzels: Hummus, Pretzels
  MD

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'veggie-plate', selected: true)
  list.apply_action('select', type: 'quick_bite', slug: 'hummus-with-pretzels', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  hummus = result['Deli'].find { |i| i[:name] == 'Hummus' }

  assert_equal [[1.0, 'cup']], hummus[:amounts]
  assert_equal 1, hummus[:uncounted]
end

test 'custom items have zero uncounted' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('custom_items', item: 'birthday candles', action: 'add')

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  custom = result['Miscellaneous'].find { |i| i[:name] == 'birthday candles' }

  assert_equal 0, custom[:uncounted]
end

test 'cross-reference uncounted ingredient tracked in parent recipe' do
  create_catalog_entry('Garlic', basis_grams: 5, aisle: 'Produce')

  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Garlic Butter

    ## Melt (combine)

    - Garlic

    Melt.
  MD

  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Garlic Bread

    ## Prep.
    > @[Garlic Butter]

    ## Toast (bake)

    - Garlic, 2 cloves

    Toast.
  MD

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'garlic-bread', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  garlic = result['Produce'].find { |i| i[:name] == 'Garlic' }

  assert_equal [[2.0, 'cloves']], garlic[:amounts]
  assert_equal 1, garlic[:uncounted]
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n '/uncounted|zero uncounted/'`
Expected: FAIL — `nil` returned for `item[:uncounted]` (key doesn't exist yet).

- [ ] **Step 3: Implement uncounted tracking**

In `app/services/shopping_list_builder.rb`, make these changes:

**`merge_ingredient`** — extract nils before merging, count them:

```ruby
def merge_ingredient(merged, name, amounts, source:)
  key = canonical_name(name)
  uncounted = amounts.count(nil)
  clean = amounts.compact

  if merged.key?(key)
    merge_into_existing(merged[key], clean, uncounted, source)
  else
    merged[key] = { amounts: clean, sources: [source], uncounted: uncounted }
  end
end

def merge_into_existing(entry, clean_amounts, uncounted, source)
  entry[:amounts] = merge_clean_amounts(entry[:amounts], clean_amounts)
  entry[:sources] = (entry[:sources] + [source]).uniq
  entry[:uncounted] += uncounted
end

def merge_clean_amounts(existing, incoming)
  return existing if incoming.empty?
  return incoming if existing.empty?

  IngredientAggregator.merge_amounts(existing, incoming)
end
```

**`merge_entries`** — sum uncounted from both sides (used by `merge_all_ingredients` when recipe and quick bite ingredients overlap):

```ruby
def merge_entries(existing, incoming)
  {
    amounts: merge_clean_amounts(existing[:amounts], incoming[:amounts]),
    sources: (existing[:sources] + incoming[:sources]).uniq,
    uncounted: existing[:uncounted] + incoming[:uncounted]
  }
end
```

**`organize_by_aisle`** — pass uncounted through:

```ruby
def organize_by_aisle(ingredients)
  visible = ingredients.reject { |name, _| @resolver.omitted?(name) }
  grouped = visible.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(name, entry), result|
    result[aisle_for(name)] << {
      name: name,
      amounts: serialize_amounts(entry[:amounts]),
      sources: entry[:sources],
      uncounted: entry[:uncounted]
    }
  end

  sort_aisles(grouped)
end
```

**`serialize_amounts`** — amounts are nil-free now, remove `.compact`:

```ruby
def serialize_amounts(amounts)
  amounts.map { |q| [q.value.to_f, display_unit(q)] }
end
```

**`custom_item_entry`** — add `uncounted: 0`:

```ruby
def custom_item_entry(raw_item, organized, existing)
  name, aisle_hint = parse_custom_item(raw_item)
  canonical = canonical_name(name)
  return if existing.include?(canonical)

  aisle = aisle_hint ? resolve_aisle_hint(aisle_hint, organized) : aisle_for(canonical)
  [aisle, { name: canonical, amounts: [], sources: [], uncounted: 0 }]
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb`
Expected: ALL PASS (new and existing tests).

- [ ] **Step 5: Commit**

```bash
git add app/services/shopping_list_builder.rb test/services/shopping_list_builder_test.rb
git commit -m "Track uncounted ingredient sources in ShoppingListBuilder

Extract nil entries from amounts arrays in merge_ingredient before
IngredientAggregator deduplicates them. Each item now carries an
uncounted integer indicating how many sources contributed without
a specified quantity."
```

---

### Task 2: GroceriesHelper — render uncounted indicators

**Files:**
- Modify: `app/helpers/groceries_helper.rb:10-15` (`format_amounts`)
- Test: `test/helpers/groceries_helper_test.rb`

**Context:** `format_amounts` currently accepts only an amounts array. It needs an `uncounted:` keyword to render "+N more" (mixed) or "(N uses)" (all-uncounted). Display rules from spec:
- amounts present + uncounted > 0 → `"(1 +1 more)"`
- amounts empty + uncounted > 1 → `"(3 uses)"`
- amounts empty + uncounted <= 1 → `""` (no parenthetical)
- amounts present + uncounted == 0 → existing behavior `"(1)"`

- [ ] **Step 1: Write failing tests for uncounted rendering**

Add these tests to `test/helpers/groceries_helper_test.rb`:

```ruby
test 'format_amounts with uncounted appends +N more' do
  assert_equal "(1 +1\u00a0more)", format_amounts([[1.0, nil]], uncounted: 1)
end

test 'format_amounts with multiple uncounted appends +N more' do
  assert_equal "(3\u00a0Tbsp +2\u00a0more)", format_amounts([[3.0, 'Tbsp']], uncounted: 2)
end

test 'format_amounts all uncounted with multiple uses shows count' do
  assert_equal "(3\u00a0uses)", format_amounts([], uncounted: 3)
end

test 'format_amounts single uncounted returns empty string' do
  assert_equal '', format_amounts([], uncounted: 1)
end

test 'format_amounts zero uncounted preserves existing behavior' do
  assert_equal "(2)", format_amounts([[2.0, nil]], uncounted: 0)
end

test 'format_amounts defaults uncounted to zero' do
  assert_equal "(2)", format_amounts([[2.0, nil]])
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/helpers/groceries_helper_test.rb -n '/uncounted/'`
Expected: FAIL — `format_amounts` doesn't accept `uncounted:` keyword yet.

- [ ] **Step 3: Implement format_amounts changes**

In `app/helpers/groceries_helper.rb`:

```ruby
def format_amounts(amounts, uncounted: 0)
  return uncounted_only_text(uncounted) if amounts.blank?

  parts = amounts.map { |value, unit| format_amount_part(value, unit) }
  inner = parts.join(' + ')
  inner += " +#{format_uncounted(uncounted)}" if uncounted > 0
  "(#{inner})"
end
```

Add two private helpers:

```ruby
def uncounted_only_text(count)
  return '' if count <= 1

  "(#{count}\u00a0uses)"
end

def format_uncounted(count)
  "#{count}\u00a0more"
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/helpers/groceries_helper_test.rb`
Expected: ALL PASS (new and existing tests — existing tests use the default `uncounted: 0`).

- [ ] **Step 5: Commit**

```bash
git add app/helpers/groceries_helper.rb test/helpers/groceries_helper_test.rb
git commit -m "Render uncounted ingredient indicators in format_amounts

format_amounts now accepts uncounted: keyword. Mixed items show
'+N more' after the quantity; all-uncounted items with multiple
sources show '(N uses)'. Single uncounted items stay bare."
```

---

### Task 3: View partial — pass uncounted to format_amounts

**Files:**
- Modify: `app/views/groceries/_shopping_list.html.erb` (lines 26, 41, 58 — three call sites)
- Test: `test/controllers/groceries_controller_test.rb` (integration verification)

**Context:** The partial calls `format_amounts(item[:amounts])` in three places (checked items in completed aisles, unchecked items, and checked items in mixed aisles). Each needs to pass `uncounted:`.

- [ ] **Step 1: Update all three call sites**

In `app/views/groceries/_shopping_list.html.erb`, change all three occurrences of:

```erb
format_amounts(item[:amounts])
```

to:

```erb
format_amounts(item[:amounts], uncounted: item[:uncounted])
```

There are exactly 3 occurrences — lines 26, 41, and 58.

- [ ] **Step 2: Write integration test**

Add a test to `test/controllers/groceries_controller_test.rb` that verifies the "+N more" indicator renders in the HTML. Find the test setup pattern used in that file and add:

```ruby
test 'shopping list shows uncounted indicator for mixed quantities' do
  @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  create_catalog_entry('Red bell pepper', basis_grams: 150, aisle: 'Produce')

  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Stuffed Peppers

    ## Prep (slice)

    - Red bell pepper, 1

    Prep.
  MD

  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Stir Fry

    ## Cook (stir-fry)

    - Red bell pepper

    Cook.
  MD

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'stuffed-peppers', selected: true)
  list.apply_action('select', type: 'recipe', slug: 'stir-fry', selected: true)

  log_in
  get groceries_path(kitchen_slug: kitchen_slug)
  assert_response :success

  assert_select '.item-amount', text: /\+1\s*more/
end

test 'shopping list shows uses indicator for all-uncounted multi-source' do
  @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  create_catalog_entry('Garlic', basis_grams: 5, aisle: 'Produce')

  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Pasta

    ## Cook (boil)

    - Garlic

    Cook.
  MD

  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Stir Fry

    ## Cook (stir-fry)

    - Garlic

    Cook.
  MD

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'pasta', selected: true)
  list.apply_action('select', type: 'recipe', slug: 'stir-fry', selected: true)

  log_in
  get groceries_path(kitchen_slug: kitchen_slug)
  assert_response :success

  assert_select '.item-amount', text: /2\s*uses/
end
```

- [ ] **Step 3: Run all tests**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb && ruby -Itest test/services/shopping_list_builder_test.rb && ruby -Itest test/helpers/groceries_helper_test.rb`
Expected: ALL PASS.

- [ ] **Step 4: Run full test suite**

Run: `rake test`
Expected: ALL PASS, 0 RuboCop offenses.

- [ ] **Step 5: Commit**

```bash
git add app/views/groceries/_shopping_list.html.erb test/controllers/groceries_controller_test.rb
git commit -m "Wire uncounted indicators into grocery list view

Pass item[:uncounted] to format_amounts at all three call sites
in _shopping_list.html.erb. Add integration tests verifying both
'+N more' and '(N uses)' render correctly. Resolves #255."
```
