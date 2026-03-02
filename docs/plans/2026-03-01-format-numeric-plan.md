# Format Numeric Consolidation — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Extract a single `format_numeric` helper to replace three duplicate float-formatting patterns (issue #136).

**Architecture:** Create `ApplicationHelper#format_numeric` as the canonical method. Remove `Recipe#makes` (presentation logic) and replace it with `RecipesHelper#format_makes`. Update two other call sites to delegate.

**Tech Stack:** Rails helpers, Minitest

---

### Task 1: Create ApplicationHelper with format_numeric

**Files:**
- Create: `app/helpers/application_helper.rb`
- Create: `test/helpers/application_helper_test.rb`

**Step 1: Write the failing test**

Create `test/helpers/application_helper_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class ApplicationHelperTest < ActionView::TestCase
  test 'format_numeric returns integer string for whole float' do
    assert_equal '3', format_numeric(3.0)
  end

  test 'format_numeric returns float string for non-whole float' do
    assert_equal '1.5', format_numeric(1.5)
  end

  test 'format_numeric handles zero' do
    assert_equal '0', format_numeric(0.0)
  end

  test 'format_numeric handles integer input' do
    assert_equal '12', format_numeric(12)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/helpers/application_helper_test.rb`
Expected: FAIL — `format_numeric` not defined

**Step 3: Write the implementation**

Create `app/helpers/application_helper.rb`:

```ruby
# frozen_string_literal: true

# Shared view helpers available across all controllers and views.
module ApplicationHelper
  def format_numeric(value)
    value == value.to_i ? value.to_i.to_s : value.to_s
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/helpers/application_helper_test.rb`
Expected: 4 tests, 4 assertions, 0 failures

**Step 5: Commit**

```bash
git add app/helpers/application_helper.rb test/helpers/application_helper_test.rb
git commit -m "feat: add ApplicationHelper#format_numeric (#136)"
```

---

### Task 2: Add RecipesHelper#format_makes and remove Recipe#makes

**Files:**
- Modify: `app/helpers/recipes_helper.rb` — add `format_makes` method
- Modify: `app/models/recipe.rb` — remove `makes` method (lines 32-37)
- Modify: `app/views/recipes/_recipe_content.html.erb` — use `format_makes` + `makes_quantity`
- Modify: `lib/familyrecipes/nutrition_calculator.rb:172` — change `recipe.makes` to `recipe.makes_quantity`
- Modify: `test/models/recipe_model_test.rb` — update 4 tests to test helper instead

**Step 1: Write the failing test for format_makes**

Create `test/helpers/recipes_helper_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class RecipesHelperTest < ActionView::TestCase
  test 'format_makes returns formatted string with whole quantity' do
    recipe = Recipe.new(makes_quantity: 30.0, makes_unit_noun: 'cookies')

    assert_equal '30 cookies', format_makes(recipe)
  end

  test 'format_makes returns formatted string with decimal quantity' do
    recipe = Recipe.new(makes_quantity: 1.5, makes_unit_noun: 'loaves')

    assert_equal '1.5 loaves', format_makes(recipe)
  end

  test 'format_makes returns nil when makes_quantity is nil' do
    recipe = Recipe.new(makes_quantity: nil)

    assert_nil format_makes(recipe)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/helpers/recipes_helper_test.rb`
Expected: FAIL — `format_makes` not defined

**Step 3: Add format_makes to RecipesHelper**

Add after the `format_yield_with_unit` method (after line 32) in `app/helpers/recipes_helper.rb`:

```ruby
  def format_makes(recipe)
    return unless recipe.makes_quantity

    "#{format_numeric(recipe.makes_quantity)} #{recipe.makes_unit_noun}"
  end
```

**Step 4: Run helper test to verify it passes**

Run: `ruby -Itest test/helpers/recipes_helper_test.rb`
Expected: 3 tests, 3 assertions, 0 failures

**Step 5: Remove Recipe#makes method**

In `app/models/recipe.rb`, delete lines 32-37 (the `makes` method):

```ruby
  def makes
    return unless makes_quantity

    unit = makes_unit_noun
    "#{makes_quantity.to_i == makes_quantity ? makes_quantity.to_i : makes_quantity} #{unit}"
  end
```

**Step 6: Update _recipe_content.html.erb**

Change lines 10-13 from:

```erb
<%= link_to recipe.category.name, home_path(anchor: recipe.category.slug) %><%- if recipe.makes -%>
<%- if nutrition&.dig('makes_unit_singular') -%>
&middot; Makes <%= format_yield_with_unit(recipe.makes, nutrition['makes_unit_singular'], nutrition['makes_unit_plural']) %><%- else -%>
&middot; Makes <%= format_yield_line(recipe.makes) %><%- end -%><%- end -%>
```

To:

```erb
<%= link_to recipe.category.name, home_path(anchor: recipe.category.slug) %><%- if recipe.makes_quantity -%>
<%- if nutrition&.dig('makes_unit_singular') -%>
&middot; Makes <%= format_yield_with_unit(format_makes(recipe), nutrition['makes_unit_singular'], nutrition['makes_unit_plural']) %><%- else -%>
&middot; Makes <%= format_yield_line(format_makes(recipe)) %><%- end -%><%- end -%>
```

**Step 7: Update NutritionCalculator**

In `lib/familyrecipes/nutrition_calculator.rb`, change line 172 from:

```ruby
      elsif recipe.makes
```

To:

```ruby
      elsif recipe.makes_quantity
```

Note: this is the parser `FamilyRecipes::Recipe`, which has `makes_quantity` as a method extracting from the `@makes` string. The truthy check works the same way since `makes_quantity` returns nil when `@makes` is nil.

**Step 8: Update model tests**

In `test/models/recipe_model_test.rb`, remove the 4 `recipe.makes` tests (lines 78-107) since this behavior is now tested via the helper test. Replace with a simpler test confirming the raw data is stored:

```ruby
  test 'stores makes_quantity and makes_unit_noun' do
    recipe = Recipe.create!(
      title: 'Cookies', category: @category, markdown_source: BASIC_MD,
      makes_quantity: 30, makes_unit_noun: 'cookies'
    )

    assert_equal 30, recipe.makes_quantity
    assert_equal 'cookies', recipe.makes_unit_noun
  end
```

**Step 9: Run full test suite**

Run: `rake test`
Expected: All tests pass

**Step 10: Commit**

```bash
git add app/helpers/recipes_helper.rb test/helpers/recipes_helper_test.rb \
  app/models/recipe.rb app/views/recipes/_recipe_content.html.erb \
  lib/familyrecipes/nutrition_calculator.rb test/models/recipe_model_test.rb
git commit -m "refactor: replace Recipe#makes with RecipesHelper#format_makes (#136)"
```

---

### Task 3: Update _embedded_recipe.html.erb and IngredientsHelper

**Files:**
- Modify: `app/views/recipes/_embedded_recipe.html.erb:17` — use `format_numeric`
- Modify: `app/helpers/ingredients_helper.rb:49-53` — delegate to `format_numeric`
- Modify: `test/helpers/ingredients_helper_test.rb` — add test via `format_numeric`

**Step 1: Update _embedded_recipe.html.erb**

Change line 17 from:

```erb
    <span class="embedded-multiplier">&times; <%= cross_reference.multiplier == cross_reference.multiplier.to_i ? cross_reference.multiplier.to_i : cross_reference.multiplier %></span>
```

To:

```erb
    <span class="embedded-multiplier">&times; <%= format_numeric(cross_reference.multiplier) %></span>
```

**Step 2: Update IngredientsHelper#format_nutrient_value**

Change `format_nutrient_value` in `app/helpers/ingredients_helper.rb` from:

```ruby
  def format_nutrient_value(value)
    return '0' unless value

    value == value.to_i ? value.to_i.to_s : value.to_s
  end
```

To:

```ruby
  def format_nutrient_value(value)
    return '0' unless value

    format_numeric(value)
  end
```

**Step 3: Run tests**

Run: `rake test`
Expected: All tests pass. Existing `IngredientsHelperTest#format_nutrient_value` tests continue passing since the behavior is identical.

**Step 4: Run lint**

Run: `bundle exec rubocop app/helpers/application_helper.rb app/helpers/recipes_helper.rb app/helpers/ingredients_helper.rb app/models/recipe.rb app/views/recipes/_embedded_recipe.html.erb`
Expected: 0 offenses

**Step 5: Check html_safe allowlist**

The `_embedded_recipe.html.erb` edit doesn't involve `.html_safe`. The `_recipe_content.html.erb` edit doesn't change any `.html_safe` calls. No allowlist updates needed.

Run: `rake lint:html_safe`
Expected: Pass

**Step 6: Commit**

```bash
git add app/views/recipes/_embedded_recipe.html.erb app/helpers/ingredients_helper.rb
git commit -m "refactor: use format_numeric in remaining call sites (#136)"
```
