# Catalog/Seed Separation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Separate ingredient catalog loading from recipe seeding so the catalog syncs independently, the entrypoint is resilient, and CI catches data/validation mismatches.

**Architecture:** New `catalog:sync` rake task owns catalog loading with a dirty-check to skip unchanged records. Seeds lose the catalog block and get generic sample data names. Docker entrypoint runs `db:prepare` → `catalog:sync` → `db:seed` as distinct steps.

**Tech Stack:** Rails rake tasks, Minitest, Docker entrypoint shell script

---

### Task 1: Create `catalog:sync` rake task

**Files:**
- Create: `lib/tasks/catalog.rake` (add to existing file — wait, this is the test/lint config; create a new file)
- Create: `lib/tasks/catalog_sync.rake`

**Step 1: Create the rake task**

Create `lib/tasks/catalog_sync.rake`:

```ruby
# frozen_string_literal: true

namespace :catalog do
  desc 'Sync ingredient catalog from YAML to database'
  task sync: :environment do
    catalog_path = Rails.root.join('db/seeds/resources/ingredient-catalog.yaml')

    unless File.exist?(catalog_path)
      puts 'No ingredient catalog file found — skipping.'
      next
    end

    catalog_data = YAML.safe_load_file(catalog_path, permitted_classes: [], permitted_symbols: [],
                                                      aliases: false)
    created = 0
    updated = 0
    unchanged = 0

    catalog_data.each do |name, entry|
      record = IngredientCatalog.find_or_initialize_by(kitchen_id: nil, ingredient_name: name)
      assign_catalog_attributes(record, entry)

      if record.new_record?
        record.save!
        created += 1
      elsif record.changed?
        record.save!
        updated += 1
      else
        unchanged += 1
      end
    end

    puts "Catalog sync: #{created} created, #{updated} updated, #{unchanged} unchanged."
  end
end

def assign_catalog_attributes(record, entry) # rubocop:disable Metrics/MethodLength
  attrs = { aisle: entry['aisle'] }

  if (nutrients = entry['nutrients'])
    attrs.merge!(
      basis_grams: nutrients['basis_grams'],
      calories: nutrients['calories'],
      fat: nutrients['fat'],
      saturated_fat: nutrients['saturated_fat'],
      trans_fat: nutrients['trans_fat'],
      cholesterol: nutrients['cholesterol'],
      sodium: nutrients['sodium'],
      carbs: nutrients['carbs'],
      fiber: nutrients['fiber'],
      total_sugars: nutrients['total_sugars'],
      added_sugars: nutrients['added_sugars'],
      protein: nutrients['protein']
    )
  end

  if (density = entry['density'])
    attrs.merge!(
      density_grams: density['grams'],
      density_volume: density['volume'],
      density_unit: density['unit']
    )
  end

  attrs[:portions] = entry['portions'] || {}
  attrs[:sources] = entry['sources'] || []

  record.assign_attributes(attrs)
end
```

**Step 2: Run the task to verify it works**

Run: `bin/rails catalog:sync`
Expected: Summary line like `Catalog sync: 0 created, 0 updated, 47 unchanged.` (entries already exist from previous seeds)

**Step 3: Commit**

```bash
git add lib/tasks/catalog_sync.rake
git commit -m "feat: add catalog:sync rake task for ingredient catalog loading"
```

---

### Task 2: Write CI validation test

**Files:**
- Create: `test/lib/catalog_sync_test.rb`

**Step 1: Write the test**

Create `test/lib/catalog_sync_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class CatalogSyncTest < ActiveSupport::TestCase
  CATALOG_PATH = Rails.root.join('db/seeds/resources/ingredient-catalog.yaml')

  test 'all catalog entries pass model validations' do
    catalog_data = YAML.safe_load_file(CATALOG_PATH, permitted_classes: [], permitted_symbols: [],
                                                      aliases: false)
    failures = []

    catalog_data.each do |name, entry|
      record = IngredientCatalog.new(kitchen_id: nil, ingredient_name: name)
      assign_entry_attributes(record, entry)

      failures << "#{name}: #{record.errors.full_messages.join(', ')}" unless record.valid?
    end

    assert_empty failures, "Catalog entries failing validation:\n#{failures.join("\n")}"
  end

  test 'catalog YAML file exists' do
    assert_path_exists CATALOG_PATH
  end

  test 'catalog entries have unique names' do
    catalog_data = YAML.safe_load_file(CATALOG_PATH, permitted_classes: [], permitted_symbols: [],
                                                      aliases: false)
    names = catalog_data.keys

    assert_equal names.size, names.uniq.size, 'Duplicate ingredient names in catalog YAML'
  end

  private

  def assign_entry_attributes(record, entry) # rubocop:disable Metrics/MethodLength
    attrs = { aisle: entry['aisle'] }

    if (nutrients = entry['nutrients'])
      attrs.merge!(
        basis_grams: nutrients['basis_grams'],
        calories: nutrients['calories'],
        fat: nutrients['fat'],
        saturated_fat: nutrients['saturated_fat'],
        trans_fat: nutrients['trans_fat'],
        cholesterol: nutrients['cholesterol'],
        sodium: nutrients['sodium'],
        carbs: nutrients['carbs'],
        fiber: nutrients['fiber'],
        total_sugars: nutrients['total_sugars'],
        added_sugars: nutrients['added_sugars'],
        protein: nutrients['protein']
      )
    end

    if (density = entry['density'])
      attrs.merge!(
        density_grams: density['grams'],
        density_volume: density['volume'],
        density_unit: density['unit']
      )
    end

    attrs[:portions] = entry['portions'] || {}
    attrs[:sources] = entry['sources'] || []

    record.assign_attributes(attrs)
  end
end
```

**Step 2: Run test to verify it passes**

Run: `ruby -Itest test/lib/catalog_sync_test.rb`
Expected: 3 tests, 3 assertions, 0 failures

**Step 3: Commit**

```bash
git add test/lib/catalog_sync_test.rb
git commit -m "test: add CI validation for ingredient catalog data"
```

---

### Task 3: Remove catalog loading from seeds, rename sample data

**Files:**
- Modify: `db/seeds.rb`

**Step 1: Update seeds.rb**

Remove the entire catalog loading block (lines 59-101). Change the kitchen and user to generic names:

```ruby
# frozen_string_literal: true

# Create kitchen and user
kitchen = Kitchen.find_or_create_by!(slug: 'our-kitchen') do |k|
  k.name = 'Our Kitchen'
end

user = User.find_or_create_by!(email: 'user@example.com') do |u|
  u.name = 'Home Cook'
end

ActsAsTenant.current_tenant = kitchen
Membership.find_or_create_by!(kitchen: kitchen, user: user)

puts "Kitchen: #{kitchen.name} (#{kitchen.slug})"
puts "User: #{user.name} (#{user.email})"

# Import recipes
seeds_dir = Rails.root.join('db/seeds')
recipes_dir = seeds_dir.join('recipes')
quick_bites_filename = 'Quick Bites.md'

recipe_files = Dir.glob(recipes_dir.join('**', '*.md')).reject do |path|
  File.basename(path) == quick_bites_filename
end

puts "Importing #{recipe_files.size} recipes..."

recipe_files.each do |path|
  markdown = File.read(path)
  tokens = LineClassifier.classify(markdown)
  parsed = RecipeBuilder.new(tokens).build
  slug = FamilyRecipes.slugify(parsed[:title])

  existing = kitchen.recipes.find_by(slug: slug)
  if existing&.edited_at?
    puts "  [skipped] #{existing.title} (web-edited)"
    next
  end

  recipe = MarkdownImporter.import(markdown, kitchen: kitchen)
  puts "  #{recipe.title} (#{recipe.category.name})"
end

# Resolve any cross-references that were deferred during import
CrossReference.resolve_pending(kitchen: kitchen)
pending_count = CrossReference.pending.count
puts "  WARNING: #{pending_count} unresolved cross-references remain" if pending_count.positive?

puts "Done! #{Recipe.count} recipes, #{Category.count} categories."

# Seed Quick Bites content onto kitchen
quick_bites_path = recipes_dir.join('Quick Bites.md')
if File.exist?(quick_bites_path)
  kitchen.update!(quick_bites_content: File.read(quick_bites_path))
  puts 'Quick Bites content loaded.'
end
```

**Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass. Some tests use `create_kitchen_and_user` which creates its own test kitchen, so the seed rename has no effect on tests.

**Step 3: Commit**

```bash
git add db/seeds.rb
git commit -m "refactor: remove catalog from seeds, rename sample kitchen to Our Kitchen"
```

---

### Task 4: De-brand the site title

**Files:**
- Modify: `config/site.yml`
- Modify: `app/views/layouts/application.html.erb:7`
- Modify: `test/controllers/pwa_controller_test.rb:14`

**Step 1: Update site.yml**

Change `site_title` from `Biagini Family Recipes` to `Family Recipes`:

```yaml
default: &default
  site_title: Family Recipes
  homepage_heading: Our Recipes
  homepage_subtitle: "A collection of our family's favorite recipes."
  github_url: https://github.com/chris-biagini/familyrecipes
```

**Step 2: Update layout to use site config instead of hardcoded string**

In `app/views/layouts/application.html.erb`, line 7, change:
```erb
<title><%= content_for?(:title) ? content_for(:title) : 'Biagini Family Recipes' %></title>
```
to:
```erb
<title><%= content_for?(:title) ? content_for(:title) : Rails.configuration.site.site_title %></title>
```

**Step 3: Update PWA manifest test**

In `test/controllers/pwa_controller_test.rb`, line 14, change:
```ruby
assert_equal 'Biagini Family Recipes', data['name']
```
to:
```ruby
assert_equal 'Family Recipes', data['name']
```

**Step 4: Run tests**

Run: `rake test`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add config/site.yml app/views/layouts/application.html.erb test/controllers/pwa_controller_test.rb
git commit -m "refactor: de-brand site title from Biagini Family Recipes to Family Recipes"
```

---

### Task 5: Update Docker entrypoint

**Files:**
- Modify: `bin/docker-entrypoint`

**Step 1: Update entrypoint**

```bash
#!/bin/bash
set -e

echo "Preparing database..."
bin/rails db:prepare

echo "Syncing ingredient catalog..."
bin/rails catalog:sync

echo "Seeding sample data..."
bin/rails db:seed

echo "Starting server..."
exec "$@"
```

**Step 2: Verify entrypoint is executable**

Run: `ls -la bin/docker-entrypoint`
Expected: `-rwxr-xr-x` (already executable)

**Step 3: Commit**

```bash
git add bin/docker-entrypoint
git commit -m "refactor: split entrypoint into db:prepare, catalog:sync, db:seed"
```

---

### Task 6: Run full validation and push

**Step 1: Run lint**

Run: `rake lint`
Expected: No offenses

**Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass

**Step 3: Run catalog:sync manually to verify**

Run: `bin/rails catalog:sync`
Expected: Summary showing created/updated/unchanged counts

**Step 4: Push to main**

```bash
git push
```

Expected: CI passes, new Docker image builds.
