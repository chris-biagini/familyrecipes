# QuickBites `## Section` Header Syntax — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch QuickBites section headers from `Section:` to `## Section` markdown syntax.

**Architecture:** Pure find-and-replace across parser regex, serializer format string, CodeMirror classifier regex, seed data, and test fixtures. A data migration converts existing database content. No structural changes to the IR, domain model, or graphical editor.

**Tech Stack:** Ruby (parser/serializer), JavaScript (CodeMirror classifier), SQLite (migration)

**Spec:** `docs/plans/2026-03-16-quickbites-header-syntax-design.md`

---

## Chunk 1: Core Logic (Parser + Serializer + Classifier)

### Task 1: Update parser tests and parser

**Files:**
- Modify: `test/familyrecipes_test.rb`
- Modify: `lib/familyrecipes.rb:62`

- [ ] **Step 1: Update parser test fixtures to `##` syntax**

In `test/familyrecipes_test.rb`, replace all colon-terminated category headers
with `##` headers in test content strings:

```ruby
# test_parse_quick_bites_content_new_format (line 32)
content = <<~TXT
  ## Snacks
  - Peanut Butter on Bread: Peanut butter, Bread
  - Goldfish

  ## Breakfast
  - Cereal with Milk: Cereal, Milk
TXT

# test_parse_quick_bites_warns_on_unrecognized_lines (line 54)
content = <<~TXT
  ## Snacks
  - Goldfish
  this line is garbage
  - Dried fruit
TXT

# test_parse_quick_bites_ignores_blank_lines (line 69)
content = <<~TXT
  ## Snacks

  - Goldfish

TXT

# test_parse_quick_bites_category_with_apostrophe (line 90)
content = "## Kids' Lunches\n- RXBARs\n"
```

- [ ] **Step 2: Run parser tests to verify they fail**

Run: `ruby -Itest test/familyrecipes_test.rb`
Expected: 4 failures — `##` lines hit the `else` branch (unrecognized), categories are nil.

- [ ] **Step 3: Update parser regex**

In `lib/familyrecipes.rb`, line 62, change the category header regex:

```ruby
# Old:
when /^([^-].+):\s*$/
  current_subcat = ::Regexp.last_match(1).strip
# New:
when /^##\s+(.+)$/
  current_subcat = ::Regexp.last_match(1).strip
```

- [ ] **Step 4: Run parser tests to verify they pass**

Run: `ruby -Itest test/familyrecipes_test.rb`
Expected: 10 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/familyrecipes.rb test/familyrecipes_test.rb
git commit -m "feat: switch QuickBites parser to ## section headers (#249)"
```

---

### Task 2: Update serializer tests and serializer

**Files:**
- Modify: `test/quick_bites_serializer_test.rb`
- Modify: `lib/familyrecipes/quick_bites_serializer.rb:34`

- [ ] **Step 1: Update serializer test fixtures**

In `test/quick_bites_serializer_test.rb`:

```ruby
# test_round_trip_preserves_content (line 12): update input content
content = <<~TXT
  ## Snacks
  - Apples and Honey: Apples, Honey
  - Goldfish

  ## Breakfast
  - Cereal with Milk: Cereal, Milk
TXT

# test_item_without_ingredients_omits_colon (line 42): update expected output
assert_equal "## Snacks\n- Banana\n", output

# test_serialize_multiple_categories_have_blank_line_between (line 76):
assert_equal "## Snacks\n- Chips\n\n## Drinks\n- Lemonade: Lemons, Sugar, Water\n", output

# test_serialize_item_with_explicit_ingredients (line 93):
assert_equal "## Lunch\n- PB&J: Peanut butter, Jelly, Bread\n", output

# test_to_ir_extracts_subcategory_name (line 97): update input content
content = <<~TXT
  ## Kids' Lunches
  - RXBARs
TXT

# test_to_ir_maps_item_fields (line 108): update input content
content = <<~TXT
  ## Snacks
  - Trail Mix: Nuts, Raisins, Chocolate chips
TXT
```

- [ ] **Step 2: Run serializer tests to verify they fail**

Run: `ruby -Itest test/quick_bites_serializer_test.rb`
Expected: Failures on serialize output assertions (still emitting `Snacks:` not `## Snacks`).

- [ ] **Step 3: Update serializer format string**

In `lib/familyrecipes/quick_bites_serializer.rb`, line 34:

```ruby
# Old:
"#{category[:name]}:\n#{lines.join("\n")}\n"
# New:
"## #{category[:name]}\n#{lines.join("\n")}\n"
```

- [ ] **Step 4: Run serializer tests to verify they pass**

Run: `ruby -Itest test/quick_bites_serializer_test.rb`
Expected: 9 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/familyrecipes/quick_bites_serializer.rb test/quick_bites_serializer_test.rb
git commit -m "feat: switch QuickBites serializer to ## headers (#249)"
```

---

### Task 3: Update CodeMirror classifier tests and classifier

**Files:**
- Modify: `test/javascript/quickbites_classifier_test.mjs`
- Modify: `app/javascript/codemirror/quickbites_classifier.js:13`

- [ ] **Step 1: Update JS classifier test fixtures**

In `test/javascript/quickbites_classifier_test.mjs`:

```javascript
// "classifies category header" (line 7): change input and expected span
test("classifies category header", () => {
  const spans = classifyQuickBitesLine("## Snacks")
  assert.deepEqual(spans, [{ from: 0, to: 9, class: "hl-category" }])
})

// "classifies category header with trailing space" (line 12): update
test("classifies category header with trailing space", () => {
  const spans = classifyQuickBitesLine("## Breakfast  ")
  assert.deepEqual(spans, [{ from: 0, to: 14, class: "hl-category" }])
})
```

- [ ] **Step 2: Run JS tests to verify they fail**

Run: `npm test`
Expected: 2 failures — `## Snacks` doesn't match old `CATEGORY_RE`.

- [ ] **Step 3: Update classifier regex**

In `app/javascript/codemirror/quickbites_classifier.js`, line 13:

```javascript
// Old:
const CATEGORY_RE = /^[^-].+:\s*$/
// New:
const CATEGORY_RE = /^##\s+.+$/
```

- [ ] **Step 4: Run JS tests to verify they pass**

Run: `npm test`
Expected: 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/codemirror/quickbites_classifier.js test/javascript/quickbites_classifier_test.mjs
git commit -m "feat: switch QuickBites CodeMirror classifier to ## headers (#249)"
```

---

## Chunk 2: Seed Data, Header Comment, Migration, and Test Fixtures

### Task 4: Update seed data and header comment

**Files:**
- Modify: `db/seeds/recipes/Quick Bites.md`
- Modify: `lib/familyrecipes/quick_bite.rb:5`

- [ ] **Step 1: Update seed file**

Replace `db/seeds/recipes/Quick Bites.md` with:

```
## Snacks
- Apples and Honey: Apples, Honey
- Crackers and Cheese: Ritz crackers, Cheddar

## Breakfast
- Cereal and Milk: Rolled oats, Milk
- Toast and Butter: Bread, Butter

## Quick Meals
- Grilled Cheese: Bread, American cheese, Butter
- Pasta with Sauce: Pasta, Pasta sauce (jarred), Parmesan
```

- [ ] **Step 2: Update QuickBite header comment**

In `lib/familyrecipes/quick_bite.rb`, line 5, change:

```ruby
# Old:
# Parsed from the Quick Bites format ("Category:\n- Name: Ing1, Ing2"). Lives on
# New:
# Parsed from the Quick Bites format ("## Category\n- Name: Ing1, Ing2"). Lives on
```

- [ ] **Step 3: Commit**

```bash
git add "db/seeds/recipes/Quick Bites.md" lib/familyrecipes/quick_bite.rb
git commit -m "chore: update QuickBites seed data and header comment for ## syntax (#249)"
```

---

### Task 5: Add data migration

**Files:**
- Create: `db/migrate/006_migrate_quick_bites_headers.rb`

- [ ] **Step 1: Write the migration**

Create `db/migrate/006_migrate_quick_bites_headers.rb`. SQLite lacks regex
replace, so iterate rows with Ruby regex and quoted SQL:

```ruby
# frozen_string_literal: true

class MigrateQuickBitesHeaders < ActiveRecord::Migration[8.0]
  def up
    rows = select_all("SELECT id, quick_bites_content FROM kitchens WHERE quick_bites_content IS NOT NULL")
    rows.each do |row|
      converted = row["quick_bites_content"].gsub(/^([^-\n].+):\s*$/m, '## \1')
      quoted = ActiveRecord::Base.connection.quote(converted)
      execute("UPDATE kitchens SET quick_bites_content = #{quoted} WHERE id = #{row['id']}")
    end
  end

  def down
    rows = select_all("SELECT id, quick_bites_content FROM kitchens WHERE quick_bites_content IS NOT NULL")
    rows.each do |row|
      reverted = row["quick_bites_content"].gsub(/^##\s+(.+)$/m, '\1:')
      quoted = ActiveRecord::Base.connection.quote(reverted)
      execute("UPDATE kitchens SET quick_bites_content = #{quoted} WHERE id = #{row['id']}")
    end
  end
end
```

- [ ] **Step 2: Run migration**

Run: `rails db:migrate`
Expected: Success, no errors.

- [ ] **Step 3: Verify migration worked**

Run: `rails runner "Kitchen.where.not(quick_bites_content: nil).each { |k| puts k.quick_bites_content[0..80] }"`
Expected: Output starts with `## Snacks` (not `Snacks:`).

- [ ] **Step 4: Commit**

```bash
git add db/migrate/006_migrate_quick_bites_headers.rb
git commit -m "feat: data migration to convert QuickBites headers to ## syntax (#249)"
```

---

### Task 6: Update all remaining test fixtures

This task is mechanical: grep for old-format headers across test files and
replace them. The parser and serializer are already updated so tests using
the old format will fail.

Note: `test/quick_bite_test.rb` is listed in the spec but has no colon-header
patterns (it tests `QuickBite` objects with pre-parsed data) — no changes needed.

**Files:**
- Modify: `test/controllers/menu_controller_test.rb`
- Modify: `test/services/quick_bites_write_service_test.rb`
- Modify: `test/services/shopping_list_builder_test.rb`
- Modify: `test/services/recipe_availability_calculator_test.rb`
- Modify: `test/services/ingredient_row_builder_test.rb`
- Modify: `test/models/kitchen_test.rb`
- Modify: `test/models/meal_plan_test.rb`
- Modify: `test/integration/end_to_end_test.rb`
- Modify: `test/controllers/auth_test.rb`

- [ ] **Step 1: Find all old-format headers in test files**

Run: `grep -rn '^[^#-].*:\s*$' test/ --include='*.rb'` and
`grep -rn "^[^#-].*:\\\\s\*$" test/ --include='*.rb'`

Also search for string patterns like `Snacks:\n`, `Breakfast:\n`, `Quick Meals:\n`,
`Lunch:\n`, `Dinner:\n`, `Sides:\n` in heredocs and string literals.

The replacement rule is consistent:
- `Snacks:\n` → `## Snacks\n`
- `Breakfast:\n` → `## Breakfast\n`
- `Quick Meals:\n` → `## Quick Meals\n`
- etc.

In heredocs, `Snacks:` at line start becomes `## Snacks`.
In single-line strings, `"Snacks:\n- ..."` becomes `"## Snacks\n- ..."`.

- [ ] **Step 2: Update each test file**

For each file, replace every occurrence of a colon-terminated category header
in test content strings with the `##` equivalent. Do NOT change item lines
(those have colons after the item name, e.g., `- Grilled Cheese: Bread, Butter`).

The pattern to match in test strings: a line that is NOT an item (no leading `-`)
and ends with `:` optionally followed by whitespace — these are category headers.

- [ ] **Step 3: Run the full test suite**

Run: `rake test`
Expected: All tests pass. If any fail, the old-format header is still present
in that test file — find and fix it.

- [ ] **Step 4: Run JS tests too**

Run: `npm test`
Expected: All pass.

- [ ] **Step 5: Run lint**

Run: `bundle exec rubocop`
Expected: 0 offenses.

- [ ] **Step 6: Commit**

```bash
git add test/
git commit -m "test: update all test fixtures for ## QuickBites headers (#249)"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run full test suite + lint**

Run: `rake`
Expected: 0 RuboCop offenses, all tests pass.

- [ ] **Step 2: Run JS tests**

Run: `npm test`
Expected: All pass.

- [ ] **Step 3: Grep for any remaining old-format headers**

Run: `grep -rn '^[^#-].*:\s*$' lib/ test/ db/seeds/ app/javascript/ --include='*.rb' --include='*.md' --include='*.js' --include='*.mjs'`
Expected: No matches (or only false positives like item lines).

- [ ] **Step 4: Rebuild JS bundle**

Run: `npm run build`
Expected: Success.
