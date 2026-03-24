# Alias Cross-Collisions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Detect and prevent alias collisions across ingredient catalog entries — fix the known seed data duplicate, add write-time validation, add sync-time reporting, and add collision logging in the lookup builder.

**Architecture:** Lightweight checks at three boundaries: (1) `add_alias_keys` logs collisions at lookup-build time, (2) `CatalogWriteService` validates before save, (3) `catalog:sync` reports cross-entry collisions. No schema changes.

**Tech Stack:** Rails 8, Minitest, SQLite with NOCASE collation.

---

### Task 1: Fix "Kosher salt" duplicate alias in seed YAML

**Files:**
- Modify: `db/seeds/resources/ingredient-catalog.yaml:2058-2060` (Salt/Table salt entry)

**Step 1: Remove "Kosher salt" from Salt (Table) aliases**

In the Salt (Table) entry (around line 2050), remove `- Kosher salt` from the aliases list, keeping only `- Table salt`.

Before:
```yaml
  aliases:
  - Table salt
  - Kosher salt
```

After:
```yaml
  aliases:
  - Table salt
```

**Step 2: Write a YAML catalog integrity test**

File: `test/lib/catalog_sync_test.rb`

Add a test that loads the full YAML and checks for alias collisions:

```ruby
test 'catalog aliases do not collide with other entries' do
  catalog_data = YAML.safe_load_file(CATALOG_PATH, permitted_classes: [], permitted_symbols: [], aliases: false)
  skip 'ingredient-catalog.yaml is empty' if catalog_data.blank?

  canonical_names = catalog_data.keys.map(&:downcase).to_set
  alias_owners = {}
  collisions = []

  catalog_data.each do |name, entry|
    (entry['aliases'] || []).each do |alias_name|
      lowered = alias_name.downcase

      if canonical_names.include?(lowered)
        collisions << "#{name}: alias '#{alias_name}' matches canonical entry"
      elsif alias_owners.key?(lowered)
        collisions << "#{name}: alias '#{alias_name}' also claimed by '#{alias_owners[lowered]}'"
      else
        alias_owners[lowered] = name
      end
    end
  end

  assert_empty collisions,
               "#{collisions.size} alias collision(s):\n  #{collisions.join("\n  ")}"
end
```

**Step 3: Run the test to verify both seed fix and collision detection**

Run: `ruby -Itest test/lib/catalog_sync_test.rb`
Expected: All tests pass (including the new collision test).

**Step 4: Commit**

```bash
git add db/seeds/resources/ingredient-catalog.yaml test/lib/catalog_sync_test.rb
git commit -m "fix: remove duplicate Kosher salt alias and add collision test (#193)"
```

---

### Task 2: Add collision logging to `add_alias_keys`

**Files:**
- Modify: `app/models/ingredient_catalog.rb:95-105` (`add_alias_keys`)
- Test: `test/models/ingredient_catalog_test.rb`

**Step 1: Write the failing test**

Add to `test/models/ingredient_catalog_test.rb` in the aliases section:

```ruby
test 'add_alias_keys logs warning when alias collides across entries' do
  IngredientCatalog.create!(
    ingredient_name: 'Salt (Table)',
    aisle: 'Baking',
    aliases: ['Kosher salt']
  )
  IngredientCatalog.create!(
    ingredient_name: 'Salt (Kosher)',
    aisle: 'Baking',
    aliases: ['Kosher salt']
  )

  warnings = []
  Rails.logger.stub(:warn, ->(msg) { warnings << msg }) do
    IngredientCatalog.lookup_for(@kitchen)
  end

  assert warnings.any? { |w| w.include?('Kosher salt') && w.include?('collides') },
         "Expected a collision warning for 'Kosher salt', got: #{warnings.inspect}"
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb -n test_add_alias_keys_logs_warning_when_alias_collides_across_entries`
Expected: FAIL — no warning is logged currently.

**Step 3: Implement collision logging in `add_alias_keys`**

Replace lines 95-105 of `ingredient_catalog.rb`:

```ruby
def self.add_alias_keys(extras, entry, lookup)
  return if entry.aliases.blank?

  entry.aliases.each do |alias_name|
    lowered = alias_name.downcase
    next if lookup.key?(alias_name) || lookup.key?(lowered)

    variants = alias_case_variants(alias_name) +
               FamilyRecipes::Inflector.ingredient_variants(alias_name)
    variants.each do |v|
      if extras.key?(v) && extras[v].ingredient_name != entry.ingredient_name
        Rails.logger.warn("Alias '#{alias_name}' on '#{entry.ingredient_name}' " \
                          "collides with '#{extras[v].ingredient_name}' — skipping")
        break
      end
      extras[v] ||= entry
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb -n test_add_alias_keys_logs_warning_when_alias_collides_across_entries`
Expected: PASS

**Step 5: Run full model test suite**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb`
Expected: All tests pass.

**Step 6: Commit**

```bash
git add app/models/ingredient_catalog.rb test/models/ingredient_catalog_test.rb
git commit -m "feat: log warning on alias collisions in lookup builder (#193)"
```

---

### Task 3: Add write-time alias validation to `CatalogWriteService`

**Files:**
- Modify: `app/models/ingredient_catalog.rb` (add `validate :aliases_do_not_collide`)
- Modify: `app/services/catalog_write_service.rb` (no changes needed — already returns validation errors)
- Test: `test/services/catalog_write_service_test.rb`

The validation belongs on the model so it fires on any save path. `CatalogWriteService#upsert` already checks `entry.save` and returns `persisted: false` on failure — no service changes needed.

**Step 1: Write the failing tests**

Add to `test/services/catalog_write_service_test.rb`:

```ruby
# --- alias collision validation ---

test 'upsert rejects alias that matches another canonical name' do
  IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Butter', aisle: 'Dairy')

  result = upsert_entry('Ghee', aliases: ['Butter'])

  assert_not result.persisted
  assert result.entry.errors.full_messages.any? { |m| m.include?('Butter') }
end

test 'upsert rejects alias that matches another canonical name case-insensitively' do
  IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Butter', aisle: 'Dairy')

  result = upsert_entry('Ghee', aliases: ['butter'])

  assert_not result.persisted
  assert result.entry.errors.full_messages.any? { |m| m.include?('butter') }
end

test 'upsert rejects alias that collides with another entry alias' do
  IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Salt (Table)',
                            aisle: 'Baking', aliases: ['Kosher salt'])

  result = upsert_entry('Salt (Kosher)', aliases: ['Kosher salt'])

  assert_not result.persisted
  assert result.entry.errors.full_messages.any? { |m| m.include?('Kosher salt') }
end

test 'upsert allows non-colliding aliases' do
  IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Butter', aisle: 'Dairy')

  result = upsert_entry('Ghee', aliases: ['Clarified butter'])

  assert_predicate result, :persisted
  assert_equal ['Clarified butter'], result.entry.aliases
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/catalog_write_service_test.rb -n /alias_collision/`
Expected: FAIL — no validation exists yet.

**Step 3: Add alias collision validation to `IngredientCatalog`**

Add to `ingredient_catalog.rb` after the existing `validate` calls (around line 34):

```ruby
validate :aliases_do_not_collide
```

Add the private method:

```ruby
def aliases_do_not_collide
  return if aliases.blank?

  scope = self.class.where(kitchen_id: [nil, kitchen_id])
  scope = scope.where.not(id:) if persisted?

  check_aliases_vs_canonical_names(scope)
  check_aliases_vs_other_aliases(scope)
end

def check_aliases_vs_canonical_names(scope)
  aliases.each do |alias_name|
    next unless scope.exists?(ingredient_name: alias_name)

    errors.add(:aliases, "entry '#{alias_name}' conflicts with an existing ingredient name")
  end
end

def check_aliases_vs_other_aliases(scope)
  other_aliases = scope.where.not(aliases: nil)
                       .pluck(:ingredient_name, :aliases)
  other_alias_map = other_aliases.each_with_object({}) do |(name, entry_aliases), map|
    entry_aliases.each { |a| map[a.downcase] = name }
  end

  aliases.each do |alias_name|
    owner = other_alias_map[alias_name.downcase]
    next unless owner

    errors.add(:aliases, "entry '#{alias_name}' conflicts with alias on '#{owner}'")
  end
end
```

Note: The `exists?(ingredient_name: alias_name)` check is case-insensitive because the column uses NOCASE collation (#192).

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/catalog_write_service_test.rb`
Expected: All tests pass.

**Step 5: Run full test suite to check for regressions**

Run: `rake test`
Expected: All tests pass.

**Step 6: Commit**

```bash
git add app/models/ingredient_catalog.rb test/services/catalog_write_service_test.rb
git commit -m "feat: write-time alias collision validation (#193)"
```

---

### Task 4: Add collision reporting to `catalog:sync`

**Files:**
- Modify: `lib/tasks/catalog_sync.rake`
- Test: `test/lib/catalog_sync_test.rb`

**Step 1: Write the failing test**

Add to `test/lib/catalog_sync_test.rb`:

```ruby
test 'sync reports alias collisions in YAML data' do
  collisions = detect_alias_collisions(
    'Salt (Table)' => { 'aliases' => ['Kosher salt'], 'aisle' => 'Baking' },
    'Salt (Kosher)' => { 'aliases' => ['Kosher salt'], 'aisle' => 'Baking' }
  )

  assert_equal 1, collisions.size
  assert_match(/Kosher salt/, collisions.first)
end

test 'sync reports no collisions for clean data' do
  collisions = detect_alias_collisions(
    'Salt (Table)' => { 'aliases' => ['Table salt'], 'aisle' => 'Baking' },
    'Salt (Kosher)' => { 'aliases' => ['Kosher salt'], 'aisle' => 'Baking' }
  )

  assert_empty collisions
end

private

def detect_alias_collisions(catalog_data)
  # Extract the method we'll add to the rake task as a testable helper
  AliasCollisionDetector.detect(catalog_data)
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/lib/catalog_sync_test.rb -n /alias_collision/`
Expected: FAIL — `AliasCollisionDetector` doesn't exist.

**Step 3: Create `AliasCollisionDetector` and integrate with `catalog:sync`**

Create `app/models/alias_collision_detector.rb`:

```ruby
# frozen_string_literal: true

# Detects alias collisions across a set of ingredient catalog entries.
# Used by catalog:sync to report cross-entry alias conflicts without
# blocking the sync. Checks alias-vs-alias and alias-vs-canonical-name.
#
# Collaborators:
# - catalog_sync.rake: calls detect() after loading YAML
# - CatalogSyncTest: unit tests collision detection logic
class AliasCollisionDetector
  def self.detect(catalog_data)
    canonical_names = catalog_data.keys.each_with_object({}) { |n, h| h[n.downcase] = n }
    alias_owners = {}
    collisions = []

    catalog_data.each do |name, entry|
      (entry['aliases'] || []).each do |alias_name|
        lowered = alias_name.downcase

        if canonical_names.key?(lowered) && canonical_names[lowered] != name
          collisions << "#{name}: alias '#{alias_name}' matches canonical entry '#{canonical_names[lowered]}'"
        elsif alias_owners.key?(lowered)
          collisions << "#{name}: alias '#{alias_name}' also claimed by '#{alias_owners[lowered]}'"
        else
          alias_owners[lowered] = name
        end
      end
    end

    collisions
  end
end
```

Update `lib/tasks/catalog_sync.rake` — add collision reporting after the sync line:

```ruby
counts = catalog_data.map { |name, entry| sync_catalog_entry(name, entry) }.tally

collisions = AliasCollisionDetector.detect(catalog_data)
collisions.each { |msg| puts "WARNING: alias collision — #{msg}" }
```

**Step 4: Update the test to use the real class**

Remove the private `detect_alias_collisions` method from the test and call `AliasCollisionDetector.detect` directly:

```ruby
test 'AliasCollisionDetector reports alias-vs-alias collisions' do
  collisions = AliasCollisionDetector.detect(
    'Salt (Table)' => { 'aliases' => ['Kosher salt'], 'aisle' => 'Baking' },
    'Salt (Kosher)' => { 'aliases' => ['Kosher salt'], 'aisle' => 'Baking' }
  )

  assert_equal 1, collisions.size
  assert_match(/Kosher salt/, collisions.first)
end

test 'AliasCollisionDetector reports alias-vs-canonical collisions' do
  collisions = AliasCollisionDetector.detect(
    'Butter' => { 'aisle' => 'Dairy' },
    'Ghee' => { 'aliases' => ['Butter'], 'aisle' => 'Dairy' }
  )

  assert_equal 1, collisions.size
  assert_match(/canonical/, collisions.first)
end

test 'AliasCollisionDetector reports no collisions for clean data' do
  collisions = AliasCollisionDetector.detect(
    'Salt (Table)' => { 'aliases' => ['Table salt'], 'aisle' => 'Baking' },
    'Salt (Kosher)' => { 'aliases' => ['Kosher salt'], 'aisle' => 'Baking' }
  )

  assert_empty collisions
end
```

**Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/lib/catalog_sync_test.rb`
Expected: All tests pass.

**Step 6: Run full test suite**

Run: `rake test`
Expected: All tests pass.

**Step 7: Commit**

```bash
git add app/models/alias_collision_detector.rb lib/tasks/catalog_sync.rake test/lib/catalog_sync_test.rb
git commit -m "feat: catalog:sync reports alias collisions (#193)"
```

---

### Task 5: Run lint and full test suite, fix any issues

**Step 1: Run RuboCop**

Run: `bundle exec rubocop`
Expected: 0 offenses. Fix any that arise.

**Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass.

**Step 3: Run html_safe lint**

Run: `rake lint:html_safe`
Expected: Pass (no new `.html_safe` calls).

**Step 4: Commit any lint fixes**

```bash
git commit -am "chore: lint fixes (#193)"
```
