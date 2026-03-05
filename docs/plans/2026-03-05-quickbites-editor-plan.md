# QuickBites Editor Simplification — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Simplify the Quick Bites format from Markdown headers (`## Category`) to plain `Category:` lines, strip boilerplate, and surface parse warnings in the editor.

**Architecture:** Parser returns a result struct with both quick_bites and warnings. Controller passes warnings through in the save response. Editor JS inspects the response and stays open when warnings are present.

**Tech Stack:** Ruby (parser), Rails controller, Stimulus JS (editor_controller), CSS (warning style), Minitest

---

### Task 1: Update parser to new format with warnings

**Files:**
- Modify: `lib/familyrecipes.rb:44-56`

**Step 1: Write failing tests for new format**

Add tests to `test/familyrecipes_test.rb`. Replace the existing `test_parse_quick_bites_content` test and add new ones:

```ruby
def test_parse_quick_bites_content_new_format
  content = <<~TXT
    Snacks:
    - Peanut Butter on Bread: Peanut butter, Bread
    - Goldfish

    Breakfast:
    - Cereal with Milk: Cereal, Milk
  TXT

  result = FamilyRecipes.parse_quick_bites_content(content)

  assert_equal 3, result.quick_bites.size
  assert_equal 'Peanut Butter on Bread', result.quick_bites[0].title
  assert_equal ['Peanut butter', 'Bread'], result.quick_bites[0].ingredients
  assert_equal 'Quick Bites: Snacks', result.quick_bites[0].category
  assert_equal 'Goldfish', result.quick_bites[1].title
  assert_equal ['Goldfish'], result.quick_bites[1].ingredients
  assert_equal 'Quick Bites: Breakfast', result.quick_bites[2].category
  assert_empty result.warnings
end

def test_parse_quick_bites_warns_on_unrecognized_lines
  content = <<~TXT
    Snacks:
    - Goldfish
    this line is garbage
    - Dried fruit
  TXT

  result = FamilyRecipes.parse_quick_bites_content(content)

  assert_equal 2, result.quick_bites.size
  assert_equal 1, result.warnings.size
  assert_match(/line 3/i, result.warnings.first)
end

def test_parse_quick_bites_ignores_blank_lines
  content = <<~TXT
    Snacks:

    - Goldfish

  TXT

  result = FamilyRecipes.parse_quick_bites_content(content)

  assert_equal 1, result.quick_bites.size
  assert_empty result.warnings
end

def test_parse_quick_bites_handles_empty_content
  result = FamilyRecipes.parse_quick_bites_content('')
  assert_empty result.quick_bites
  assert_empty result.warnings
end

def test_parse_quick_bites_category_with_apostrophe
  content = "Kids' Lunches:\n- RXBARs\n"
  result = FamilyRecipes.parse_quick_bites_content(content)

  assert_equal "Quick Bites: Kids' Lunches", result.quick_bites.first.category
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/familyrecipes_test.rb`
Expected: FAIL — `parse_quick_bites_content` returns an array, not a result struct

**Step 3: Define result struct and update parser**

Replace the `parse_quick_bites_content` method in `lib/familyrecipes.rb:44-56`:

```ruby
QuickBitesResult = Data.define(:quick_bites, :warnings)

def self.parse_quick_bites_content(content)
  current_subcat = nil
  quick_bites = []
  warnings = []

  content.each_line.with_index(1) do |line, line_number|
    stripped = line.strip
    next if stripped.empty?

    case line
    when /^\s*-\s+(.*)/
      category = [CONFIG[:quick_bites_category], current_subcat].compact.join(': ')
      quick_bites << QuickBite.new(text_source: ::Regexp.last_match(1).strip, category: category)
    when /^([^-].+):\s*$/
      current_subcat = ::Regexp.last_match(1).strip
    else
      warnings << "Line #{line_number} not recognized"
    end
  end

  QuickBitesResult.new(quick_bites:, warnings:)
end
```

Note: item lines (`- `) are matched first so that `- Coffee: Coffee, Distilled water` doesn't match as a category. The category regex requires: starts with a non-dash character, ends with `:` and optional whitespace, nothing else after.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/familyrecipes_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/familyrecipes.rb test/familyrecipes_test.rb
git commit -m "feat: new Quick Bites format with parse warnings"
```

---

### Task 2: Update callers to use new result struct

**Files:**
- Modify: `app/models/kitchen.rb:34-38`
- Modify: `app/controllers/menu_controller.rb:45-53`
- Modify: `lib/familyrecipes.rb:58-61` (the `parse_quick_bites` file-based method)

**Step 1: Write failing test for Kitchen#parsed_quick_bites**

Add to `test/models/kitchen_test.rb`:

```ruby
test 'parsed_quick_bites returns quick bites from new format' do
  @kitchen.update!(quick_bites_content: "Snacks:\n- Goldfish\n- Dried fruit\n")
  qbs = @kitchen.parsed_quick_bites

  assert_equal 2, qbs.size
  assert_equal 'Goldfish', qbs.first.title
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/kitchen_test.rb -n test_parsed_quick_bites_returns_quick_bites_from_new_format`
Expected: FAIL — `parsed_quick_bites` returns a result struct, not an array

**Step 3: Update Kitchen#parsed_quick_bites to unwrap result**

In `app/models/kitchen.rb:34-38`:

```ruby
def parsed_quick_bites
  return [] unless quick_bites_content

  FamilyRecipes.parse_quick_bites_content(quick_bites_content).quick_bites
end
```

**Step 4: Update parse_quick_bites file method**

In `lib/familyrecipes.rb:58-61`, update to also unwrap (this is only used by seeds, which don't need warnings):

```ruby
def self.parse_quick_bites(recipes_dir)
  file_path = File.join(recipes_dir, CONFIG[:quick_bites_filename])
  parse_quick_bites_content(File.read(file_path)).quick_bites
end
```

**Step 5: Run all tests**

Run: `rake test`
Expected: Some tests may still fail due to old `## ` format in test fixtures — that's addressed in Task 4.

**Step 6: Commit**

```bash
git add app/models/kitchen.rb lib/familyrecipes.rb test/models/kitchen_test.rb
git commit -m "refactor: update callers to unwrap QuickBitesResult"
```

---

### Task 3: Surface warnings in save endpoint and editor JS

**Files:**
- Modify: `app/controllers/menu_controller.rb:45-53`
- Modify: `app/javascript/controllers/editor_controller.js:85-106`
- Modify: `app/javascript/utilities/editor_utils.js:61-86`
- Modify: `app/assets/stylesheets/style.css:841-852`

**Step 1: Write failing controller test for warnings**

Add to `test/controllers/menu_controller_test.rb`:

```ruby
test 'update_quick_bites returns warnings for unrecognized lines' do
  log_in
  patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
        params: { content: "Snacks:\n- Goldfish\ngarbage line\n- Dried fruit" },
        as: :json

  assert_response :success
  json = response.parsed_body
  assert_equal 'ok', json['status']
  assert_equal 1, json['warnings'].size
  assert_match(/line 3/i, json['warnings'].first)
end

test 'update_quick_bites returns no warnings for clean content' do
  log_in
  patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
        params: { content: "Snacks:\n- Goldfish\n" },
        as: :json

  assert_response :success
  json = response.parsed_body
  assert_equal 'ok', json['status']
  assert_nil json['warnings']
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n /returns_warnings/`
Expected: FAIL — `warnings` key not in response

**Step 3: Update controller to parse and return warnings**

In `app/controllers/menu_controller.rb`, replace `update_quick_bites`:

```ruby
def update_quick_bites
  content = params[:content].to_s
  return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_content if content.blank?

  result = FamilyRecipes.parse_quick_bites_content(content)
  current_kitchen.update!(quick_bites_content: content)
  plan = MealPlan.for_kitchen(current_kitchen)
  plan.with_optimistic_retry { plan.prune_checked_off(visible_names: shopping_list_visible_names(plan)) }
  current_kitchen.broadcast_update

  response = { status: 'ok' }
  response[:warnings] = result.warnings if result.warnings.any?
  render json: response
end
```

**Step 4: Run controller tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: PASS

**Step 5: Update editor JS to handle warnings**

The `handleSave` function in `editor_utils.js:61-86` calls `onSuccess(responseData)` on 200. The `onSuccess` callback in `editor_controller.js:85-106` currently always closes/redirects. We need to check for warnings before closing.

In `editor_controller.js`, update the `save()` method's `onSuccess` callback (lines 85-106). Replace the body of the `handleSave` call:

```javascript
handleSave(this.saveButtonTarget, this.errorsTarget, saveFn, (responseData) => {
  if (responseData.warnings?.length > 0) {
    this.showWarnings(responseData.warnings)
    this.originalContent = this.hasTextareaTarget ? this.textareaTarget.value : ""
    return
  }

  this.guard.markSaving()

  if (this.onSuccessValue === "reload") {
    window.location.reload()
  } else if (this.onSuccessValue === "close") {
    this.element.close()
  } else {
    let redirectUrl = responseData.redirect_url
    if (!redirectUrl || !redirectUrl.startsWith("/")) {
      window.location.reload()
      return
    }
    if (responseData.updated_references?.length > 0) {
      const param = encodeURIComponent(responseData.updated_references.join(", "))
      const separator = redirectUrl.includes("?") ? "&" : "?"
      redirectUrl += `${separator}refs_updated=${param}`
    }
    window.location = redirectUrl
  }
})
```

Add the `showWarnings` method to the controller:

```javascript
showWarnings(warnings) {
  let messages
  if (warnings.length <= 3) {
    messages = warnings
  } else {
    const lines = warnings.map(w => {
      const match = w.match(/\d+/)
      return match ? match[0] : "?"
    })
    messages = [`${warnings.length} lines were not recognized (lines ${lines.join(", ")})`]
  }
  showErrors(this.errorsTarget, messages)
  this.errorsTarget.classList.add("editor-warnings")
}
```

Also update `clearErrorDisplay` to remove the warning class:

```javascript
clearErrorDisplay() {
  if (this.hasErrorsTarget) {
    clearErrors(this.errorsTarget)
    this.errorsTarget.classList.remove("editor-warnings")
  }
}
```

Note: after a warning save, `originalContent` is updated to match the textarea so the user isn't prompted about unsaved changes when closing.

**Step 6: Add warning CSS**

Add to `app/assets/stylesheets/style.css` after the `.editor-errors ul` rule (after line 852):

```css
.editor-warnings {
  color: var(--text-secondary-color);
}
```

This overrides the `--danger-color` from `.editor-errors` with a softer tone. The warnings use the same layout (padding, border, `<ul>`) but aren't alarming.

**Step 7: Commit**

```bash
git add app/controllers/menu_controller.rb app/javascript/controllers/editor_controller.js app/assets/stylesheets/style.css
git commit -m "feat: surface Quick Bites parse warnings in editor"
```

---

### Task 4: Update seed file, test fixtures, and remaining tests

**Files:**
- Modify: `db/seeds/recipes/Quick Bites.md`
- Modify: `test/familyrecipes_test.rb` (already done in Task 1, verify)
- Modify: `test/controllers/menu_controller_test.rb` (update `## ` format references)
- Modify: any other test files using old format

**Step 1: Update seed file**

Replace `db/seeds/recipes/Quick Bites.md` with new format:

```
Snacks:
- Peanut Butter on Bread: Peanut butter, Bread
- Apples and Peanut Butter: Apples, Peanut butter
- Fruit: Bananas, Grapes, Clementines, Apples, Berries
- Yogurt Shake: Yogurt shakes
- Hummus with Pretzels: Hummus, Pretzels
- Tortilla chips with Salsa: Tortilla chips, Salsa
- Peanut butter pretzels
- Dried fruit
- String cheese
- Goldfish
- Triscuits
- Protein shake: Protein shake mix

Breakfast and Light Meals:
- RXBARs
- Fried eggs: Eggs, Olive oil, Bread
- Breakfast Hash: Frozen potatoes, Onions, Red bell pepper, Eggs, Olive oil
- Cereal with Milk: Cereal, Milk
- Grilled cheese: Sandwich bread, American cheese, Butter

Kids' Lunches:
- Yogurt and Jelly: Greek yogurt, Fruit preserves, Oranges, Dried fruit, Asian snacks, Peanut M&Ms
- Yogurt Cups: Yogurt cups, Oranges, Dried fruit, Asian snacks, Peanut M&Ms

Mains:
- Chik'n Nuggets and Fries: Chik'n nuggets, French fries, Ketchup
- Impossible Burgers and Fries: Hamburger buns, Impossible burgers, French fries, Ketchup, American cheese

Dessert:
- Sorbet
- Ice cream
- Fro-yo bars

Drinks:
- Diet Coke
- Root beer
- Fruit juice
- Chocolate milk
- Coffee: Coffee, Distilled water
- Wine
```

**Step 2: Update test fixtures to new format**

In `test/controllers/menu_controller_test.rb`, search for `## ` in quick bites content and replace with new format. Key lines to update:

- Line 209: `"## Snacks\n  - Goldfish: Goldfish crackers"` → `"Snacks:\n- Goldfish: Goldfish crackers"`
- Line 285: `"## Snacks\n  - Goldfish"` → `"Snacks:\n- Goldfish"`
- Line 293: expected value `"## Snacks\n  - Goldfish"` → `"Snacks:\n- Goldfish"`
- Line 309: `"## Snacks\n  - Goldfish"` → `"Snacks:\n- Goldfish"`
- Line 313: expected value `"## Snacks\n  - Goldfish"` → `"Snacks:\n- Goldfish"`
- Line 331: `"## Snacks\n  - Goldfish"` → `"Snacks:\n- Goldfish"`

Search all test files for `##.*Snacks` or `## ` patterns in quick bites context and update.

**Step 3: Run full test suite**

Run: `rake test`
Expected: PASS

**Step 4: Run linter**

Run: `bundle exec rubocop`
Expected: No new offenses

**Step 5: Commit**

```bash
git add db/seeds/recipes/Quick\ Bites.md test/
git commit -m "chore: migrate Quick Bites seed and tests to new format"
```

---

### Task 5: Update QuickBite header comment and CLAUDE.md

**Files:**
- Modify: `lib/familyrecipes/quick_bite.rb:4-7` (update header comment to mention new format)
- Modify: `CLAUDE.md` (if any references to `## Category` syntax)

**Step 1: Update QuickBite header comment**

Update the format description in `lib/familyrecipes/quick_bite.rb:4-7`:

```ruby
# A "grocery bundle" — a simple name + ingredient list that isn't a full recipe.
# Parsed from the Quick Bites format ("Category:\n- Name: Ing1, Ing2"). Lives on
# the menu page, not the homepage. Responds to the same #ingredients_with_quantities
# duck type as Recipe so ShoppingListBuilder can treat both uniformly.
```

**Step 2: Run full test suite and linter**

Run: `rake`
Expected: All green

**Step 3: Commit**

```bash
git add lib/familyrecipes/quick_bite.rb CLAUDE.md
git commit -m "docs: update Quick Bites format references"
```

---

### Task 6: Final verification

**Step 1: Run full suite**

Run: `rake`
Expected: All tests pass, no RuboCop offenses

**Step 2: Verify seed data loads**

Run: `rails db:seed` (or `rails db:reset` if needed)
Expected: "Quick Bites content loaded." with no errors

**Step 3: Manual smoke test (optional)**

Start `bin/dev`, open the menu page, click Edit QuickBites. Verify:
- Content loads in new format (no `##` headers, no `# Quick Bites` title)
- Saving clean content closes the dialog
- Adding a garbage line and saving keeps the dialog open with a warning
- Fixing the line and re-saving closes the dialog
