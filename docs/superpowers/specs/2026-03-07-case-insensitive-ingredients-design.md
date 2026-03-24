# Case-Insensitive Ingredient Name Deduplication — Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Prevent case-variant duplicate ingredient catalog entries and fix the overlay merge so kitchen overrides properly replace global entries regardless of casing.

**Architecture:** SQLite's `COLLATE NOCASE` on the `ingredient_name` column handles DB-level uniqueness and lookups. Rails validator mirrors with `case_sensitive: false`. The Ruby-level `lookup_for` merge switches from exact-key to downcased-key merging so kitchen entries reliably override globals even when casing differs.

**GH Issue:** #192

---

## Context

`IngredientCatalog` uses an overlay model: global entries (`kitchen_id: nil`) provide seed data, kitchens can add overrides. `lookup_for` merges both sets, and `IngredientResolver` wraps the result with case-insensitive fallback.

### Problem 1: Same-scope case-variant duplicates

The DB unique indexes and Rails validator are case-sensitive. A user could create "butter" alongside global "Butter" in the same scope, or a kitchen could have both "Flour" and "flour".

### Problem 2: Cross-scope overlay merge ignores case

`lookup_for` uses `Hash#merge` keyed by exact `ingredient_name`. If global has "All purpose flour" and a kitchen override uses "All Purpose Flour", the merge produces two hash keys instead of one. The kitchen override doesn't replace the global entry — it sits alongside it. Worse, `IngredientResolver`'s `@ci_lookup` uses `||=` (first-wins), so the global entry wins the case-insensitive slot.

### Design decisions

- **COLLATE NOCASE** on the column — ASCII-only, sufficient for ingredient names
- **Stored casing preserved as-is** — no normalization on write. Kitchen overrides can use their own preferred casing (e.g., "All Purpose Flour" instead of global's "All purpose flour")
- **Global entries are untouchable** — treated as baked-in app data
- **No changes to IngredientResolver** — once `lookup_for` merges correctly, the resolver's existing logic works as-is

---

### Task 1: Migration — COLLATE NOCASE on ingredient_name

**Files:**
- Create: `db/migrate/003_add_nocase_to_ingredient_name.rb`
- Modified by Rails: `db/schema.rb` (auto-updated by migration)

**Step 1: Write the migration**

```ruby
# frozen_string_literal: true

class AddNocaseToIngredientName < ActiveRecord::Migration[8.1]
  def up
    change_column :ingredient_catalog, :ingredient_name, :string,
                  null: false, collation: 'NOCASE'
  end

  def down
    change_column :ingredient_catalog, :ingredient_name, :string, null: false
  end
end
```

Rails' SQLite adapter recreates the table behind the scenes for `change_column`, which rebuilds all indexes. The existing unique indexes inherit the column's new NOCASE collation automatically.

**Step 2: Run the migration**

Run: `rails db:migrate`
Expected: Migration applies, `db/schema.rb` updated with collation

**Step 3: Verify the schema**

Confirm `db/schema.rb` shows the collation on `ingredient_name`. Check that both unique indexes still exist.

**Step 4: Verify NOCASE behavior in console**

```ruby
rails runner "
  IngredientCatalog.create!(ingredient_name: 'TestNocase')
  puts IngredientCatalog.find_by(ingredient_name: 'testnocase')&.ingredient_name
  IngredientCatalog.find_by(ingredient_name: 'TestNocase')&.destroy!
"
```
Expected: prints `TestNocase` (found via case-insensitive match, stored casing preserved)

**Step 5: Commit**

```
git add db/migrate/003_add_nocase_to_ingredient_name.rb db/schema.rb
git commit -m "feat: add COLLATE NOCASE to ingredient_catalog.ingredient_name"
```

---

### Task 2: Model validator — case_sensitive: false + tests

**Files:**
- Modify: `app/models/ingredient_catalog.rb:28` (validator)
- Modify: `test/models/ingredient_catalog_test.rb` (update + add tests)

**Step 1: Write the failing tests**

Add to `test/models/ingredient_catalog_test.rb`, after the existing uniqueness tests (around line 200):

```ruby
test 'rejects case-variant duplicate within same kitchen' do
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Butter', basis_grams: 100)
  duplicate = IngredientCatalog.new(kitchen: @kitchen, ingredient_name: 'butter', basis_grams: 100)

  assert_not_predicate duplicate, :valid?
end

test 'rejects case-variant duplicate in global scope' do
  IngredientCatalog.create!(ingredient_name: 'Butter', basis_grams: 100)
  duplicate = IngredientCatalog.new(ingredient_name: 'BUTTER', basis_grams: 100)

  assert_not_predicate duplicate, :valid?
end

test 'allows case-variant between global and kitchen scope' do
  IngredientCatalog.create!(ingredient_name: 'Butter', basis_grams: 100)
  override = IngredientCatalog.new(kitchen: @kitchen, ingredient_name: 'butter', basis_grams: 50)

  assert_predicate override, :valid?
end
```

**Step 2: Run tests to verify failures**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb -n /case-variant/`
Expected: First two tests FAIL (validator is still case-sensitive), third passes

**Step 3: Update the validator**

In `app/models/ingredient_catalog.rb`, line 28, change:

```ruby
validates :ingredient_name, presence: true, uniqueness: { scope: :kitchen_id }
```

to:

```ruby
validates :ingredient_name, presence: true, uniqueness: { scope: :kitchen_id, case_sensitive: false }
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb`
Expected: All tests pass (including existing ones)

**Step 5: Commit**

```
git add app/models/ingredient_catalog.rb test/models/ingredient_catalog_test.rb
git commit -m "feat: case-insensitive uniqueness validation for ingredient names"
```

---

### Task 3: Fix lookup_for — case-insensitive overlay merge

**Files:**
- Modify: `app/models/ingredient_catalog.rb:53-57` (lookup_for method)
- Modify: `test/models/ingredient_catalog_test.rb` (add test)

**Step 1: Write the failing test**

Add to `test/models/ingredient_catalog_test.rb`:

```ruby
test 'lookup_for kitchen override replaces global entry with different casing' do
  IngredientCatalog.create!(ingredient_name: 'All purpose flour', basis_grams: 30, calories: 110)
  kitchen_entry = IngredientCatalog.create!(
    kitchen: @kitchen, ingredient_name: 'All Purpose Flour', basis_grams: 30, calories: 100
  )

  result = IngredientCatalog.lookup_for(@kitchen)

  assert result.key?('All Purpose Flour'), 'should be keyed by kitchen casing'
  assert_not result.key?('All purpose flour'), 'global casing key should not exist'
  assert_predicate result['All Purpose Flour'], :custom?
  assert_equal kitchen_entry.id, result['All Purpose Flour'].id
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb -n /replaces_global_entry_with_different_casing/`
Expected: FAIL — both keys present, global casing not replaced

**Step 3: Fix lookup_for**

In `app/models/ingredient_catalog.rb`, replace lines 53-57:

```ruby
def self.lookup_for(kitchen)
  base = global.index_by(&:ingredient_name)
               .merge(for_kitchen(kitchen).index_by(&:ingredient_name))
  add_ingredient_variants(base)
end
```

with:

```ruby
def self.lookup_for(kitchen)
  keyed = {}
  global.each { |e| keyed[e.ingredient_name.downcase] = e }
  for_kitchen(kitchen).each { |e| keyed[e.ingredient_name.downcase] = e }
  base = keyed.each_with_object({}) { |(_, e), h| h[e.ingredient_name] = e }
  add_ingredient_variants(base)
end
```

Kitchen entries are processed second, so they win via last-write-wins on the downcased key. The final hash is re-keyed by the winner's actual `ingredient_name`, preserving the user's preferred casing.

**Step 4: Run all ingredient catalog tests**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb`
Expected: All tests pass

**Step 5: Run full test suite**

Run: `rake test`
Expected: All tests pass — the merge change is backward-compatible for same-cased overlays

**Step 6: Commit**

```
git add app/models/ingredient_catalog.rb test/models/ingredient_catalog_test.rb
git commit -m "fix: case-insensitive overlay merge in lookup_for (#192)"
```

---

## Acceptance criteria

- [ ] `ingredient_name` column has COLLATE NOCASE — verified in schema.rb
- [ ] Case-variant duplicates rejected within same scope (global or same kitchen)
- [ ] Case-variant allowed across scopes (global + kitchen override)
- [ ] `lookup_for` produces one entry per ingredient, kitchen override wins regardless of casing
- [ ] Stored casing preserved as-is (no normalization)
- [ ] All existing tests pass without modification (backward-compatible)
- [ ] Full test suite green
