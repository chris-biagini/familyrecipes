# Structured Self-Hosted Deployment Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Move to a repeatable, upgrade-safe Docker deployment targeting single-kitchen homelabbers.

**Architecture:** Consolidate schema into one migration, add single-kitchen enforcement via `site.yml`, move config to storage volume for persistence across image updates, replace real recipes with sample content that only seeds on first boot.

**Tech Stack:** Rails 8, SQLite, Docker, acts_as_tenant

---

### Task 0: Consolidate Migrations

Collapse three migration files into a single `001_create_schema.rb` that represents the full current schema.

**Files:**
- Modify: `db/migrate/001_create_schema.rb`
- Delete: `db/migrate/002_add_aliases_to_ingredient_catalog.rb`
- Delete: `db/migrate/003_add_nocase_to_ingredient_name.rb`

**Step 1: Merge migration 002 and 003 into 001**

Add the `aliases` column and `NOCASE` collation to the `ingredient_catalog` table definition in `001_create_schema.rb`. The `ingredient_name` column becomes:

```ruby
t.string :ingredient_name, null: false, collation: 'NOCASE'
```

And add after the `sources` line:

```ruby
t.json :aliases, default: []
```

**Step 2: Delete migrations 002 and 003**

```bash
rm db/migrate/002_add_aliases_to_ingredient_catalog.rb
rm db/migrate/003_add_nocase_to_ingredient_name.rb
```

**Step 3: Rebuild database from scratch and verify**

```bash
rm -f storage/development.sqlite3 storage/development_cable.sqlite3
bin/rails db:prepare
```

Expected: database created with single migration, no errors.

**Step 4: Run full test suite**

```bash
rake test
```

Expected: all tests pass.

**Step 5: Commit**

```bash
git add -A
git commit -m "chore: consolidate migrations into single schema (#187)"
```

---

### Task 1: Update site.yml and Config Initializer

Drop `github_url`, add `multi_kitchen: false`, update the initializer to load from `storage/site.yml` when available, and remove the homepage GitHub footer link.

**Files:**
- Modify: `config/site.yml`
- Modify: `config/initializers/site_config.rb`
- Modify: `app/views/homepage/show.html.erb:35-37` (remove footer)

**Step 1: Update `config/site.yml`**

Replace contents with:

```yaml
default: &default
  site_title: Family Recipes
  homepage_heading: Our Recipes
  homepage_subtitle: "A collection of our family\u2019s favorite recipes."
  multi_kitchen: false

development:
  <<: *default

test:
  <<: *default

production:
  <<: *default
```

**Step 2: Update `config/initializers/site_config.rb`**

Replace with logic that prefers `storage/site.yml` when it exists (Docker volume), falling back to the standard `config/site.yml` for local dev:

```ruby
# frozen_string_literal: true

# Loads site-wide configuration (title, homepage copy, kitchen mode) into
# Rails.configuration.site. In Docker, reads from storage/site.yml (persisted
# in the app volume so user edits survive image updates). Falls back to the
# bundled config/site.yml for local development.
#
# Collaborators:
# - config/site.yml — default template shipped in the Docker image
# - storage/site.yml — user-customizable copy in the persistent volume
# - Kitchen — checks multi_kitchen flag to enforce single-kitchen mode
storage_config = Rails.root.join('storage/site.yml')

if storage_config.exist?
  all_config = YAML.safe_load_file(storage_config, permitted_classes: [], aliases: true)
  env_config = all_config[Rails.env] || all_config['default'] || all_config
  Rails.configuration.site = ActiveSupport::InheritableOptions.new(env_config.symbolize_keys)
else
  Rails.configuration.site = Rails.application.config_for(:site)
end
```

**Step 3: Remove homepage GitHub footer**

In `app/views/homepage/show.html.erb`, delete lines 35-37:

```erb
  <footer>
    <p>For more information, visit <a href="<%= @site_config.github_url %>">our project page on GitHub</a>.</p>
  </footer>
```

**Step 4: Run tests**

```bash
rake test
```

Expected: all tests pass. Any test referencing `github_url` will need updating (check for failures).

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add multi_kitchen config flag, drop github_url (#187)"
```

---

### Task 2: Single-Kitchen Validation on Kitchen Model

Add a validation that prevents creating a second kitchen when `multi_kitchen` is `false`.

**Files:**
- Modify: `app/models/kitchen.rb`
- Modify: `test/models/kitchen_test.rb`

**Step 1: Write failing tests**

Add to `test/models/kitchen_test.rb`:

```ruby
test 'allows first kitchen when multi_kitchen is false' do
  Kitchen.destroy_all
  kitchen = Kitchen.new(name: 'First', slug: 'first')

  assert kitchen.valid?
end

test 'blocks second kitchen when multi_kitchen is false' do
  Kitchen.destroy_all
  Kitchen.create!(name: 'First', slug: 'first')
  second = Kitchen.new(name: 'Second', slug: 'second')

  assert_not second.valid?
  assert_includes second.errors[:base], 'Only one kitchen is allowed in single-kitchen mode'
end

test 'allows second kitchen when multi_kitchen is true' do
  Kitchen.destroy_all
  original_config = Rails.configuration.site
  Rails.configuration.site = ActiveSupport::InheritableOptions.new(
    original_config.to_h.merge(multi_kitchen: true)
  )

  Kitchen.create!(name: 'First', slug: 'first')
  second = Kitchen.new(name: 'Second', slug: 'second')

  assert second.valid?
ensure
  Rails.configuration.site = original_config
end

test 'allows updating existing kitchen when multi_kitchen is false' do
  Kitchen.destroy_all
  kitchen = Kitchen.create!(name: 'First', slug: 'first')
  kitchen.name = 'Updated'

  assert kitchen.valid?
end
```

**Step 2: Run tests to verify they fail**

```bash
ruby -Itest test/models/kitchen_test.rb -n '/multi_kitchen/'
```

Expected: 2 failures (blocks second, allows second when true).

**Step 3: Add validation to Kitchen model**

Add to `app/models/kitchen.rb`, after existing validations:

```ruby
validate :enforce_single_kitchen_mode, on: :create

private

def enforce_single_kitchen_mode
  return if Rails.configuration.site.multi_kitchen

  errors.add(:base, 'Only one kitchen is allowed in single-kitchen mode') if Kitchen.exists?
end
```

Note: The `on: :create` ensures updates to existing kitchens are not blocked. The `Kitchen.exists?` check uses an unscoped query — this is intentional and correct here since we're checking the global kitchen count, not tenant-scoped data.

**Step 4: Run tests to verify they pass**

```bash
ruby -Itest test/models/kitchen_test.rb
```

Expected: all kitchen tests pass.

**Step 5: Run full test suite**

```bash
rake test
```

Expected: all tests pass. Watch for tests that create multiple kitchens — they may need `multi_kitchen: true` in their setup. The test helper's `create_kitchen_and_user` creates one kitchen per test, but `acts_as_tenant` test isolation should handle this. If tests fail, wrap multi-kitchen test setups with a config override.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: enforce single-kitchen mode via site config (#187)"
```

---

### Task 3: Replace Seed Recipes with Sample Content

Replace the ~35 real family recipes with ~5-6 made-up sample recipes demonstrating all syntax features. Replace the real Quick Bites with a sample version.

**Files:**
- Delete: all files under `db/seeds/recipes/` (every subdirectory and file)
- Create: `db/seeds/recipes/Basics/Toast.md`
- Create: `db/seeds/recipes/Basics/Scrambled Eggs.md`
- Create: `db/seeds/recipes/Basics/Simple Salad.md`
- Create: `db/seeds/recipes/Baking/Pancakes.md`
- Create: `db/seeds/recipes/Baking/Oatmeal Cookies.md`
- Create: `db/seeds/recipes/Baking/Quick Pizza.md`
- Create: `db/seeds/recipes/Quick Bites.md`

**Step 1: Delete all existing seed recipes**

```bash
rm -rf db/seeds/recipes/*
```

**Step 2: Create sample recipes**

Each recipe demonstrates specific syntax features. All ingredients must exist in the catalog.

**`db/seeds/recipes/Basics/Toast.md`** — Implicit single step, simple ingredients, description:

```markdown
# Toast

The simplest recipe there is. A good starting point for building your collection.

Serves: 2

- Bread, 2 slices
- Butter

Toast the bread until golden. Spread butter on each slice while still warm.
```

**`db/seeds/recipes/Basics/Scrambled Eggs.md`** — Explicit steps, prep notes, description:

```markdown
# Scrambled Eggs

A breakfast staple. Low and slow is the key to creamy eggs.

Serves: 2

## Prep the eggs.

- Eggs, 4: Crack into a bowl.
- Salt
- Black pepper

Whisk eggs with a pinch of salt and pepper until uniform.

## Cook.

- Butter, 1 tbsp

Melt butter in a non-stick pan over low heat. Add eggs and stir continuously with a spatula, pulling curds from the edges to the center. Remove from heat while still slightly wet — they will finish cooking on the plate.
```

**`db/seeds/recipes/Basics/Simple Salad.md`** — Minimal recipe, single implicit step:

```markdown
# Simple Salad

Serves: 2

- Salad greens, 150 g
- Tomatoes (fresh), 1
- Olive oil, 1 tbsp
- Vinegar (balsamic), 1 tsp
- Salt

Toss greens and sliced tomato with oil, vinegar, and a pinch of salt.
```

**`db/seeds/recipes/Baking/Pancakes.md`** — Makes quantity, multi-step, footer:

```markdown
# Pancakes

Fluffy weekend pancakes. Double the batch and freeze extras for weekday breakfasts.

Makes: 12 pancakes

## Mix the batter.

- Flour (all-purpose), 190 g
- Sugar (white), 2 tbsp
- Baking powder, 2 tsp
- Salt, 0.5 tsp
- Milk, 240 g
- Eggs, 1
- Butter, 2 tbsp: Melted.

Whisk dry ingredients together. In a separate bowl, whisk milk, egg, and melted butter. Pour wet into dry and stir until just combined — lumps are fine.

## Cook the pancakes.

- Butter

Heat a pan or griddle over medium heat. Add a small pat of butter. Pour about 60 g of batter per pancake. Cook until bubbles form on the surface and edges look set, about 2 minutes. Flip and cook 1 minute more.

---

A good basic pancake. Try adding blueberries or chocolate chips to the batter.
```

**`db/seeds/recipes/Baking/Oatmeal Cookies.md`** — Makes quantity, cross-reference not needed for this one, but demonstrates scaling and a footer:

```markdown
# Oatmeal Cookies

Chewy oatmeal cookies with a hint of cinnamon. Great for lunch boxes.

Makes: 24 cookies

## Make the dough.

- Butter, 115 g: Softened to room temperature.
- Sugar (brown), 150 g
- Sugar (white), 50 g
- Eggs, 1
- Vanilla extract, 1 tsp
- Flour (all-purpose), 155 g
- Baking soda, 0.5 tsp
- Cinnamon, 1 tsp
- Salt, 0.5 tsp
- Rolled oats, 150 g
- Raisins, 80 g

Beat butter with both sugars until fluffy. Add egg and vanilla, mix well. Stir in flour, baking soda, cinnamon, and salt. Fold in oats and raisins. Chill dough for 30 minutes.

## Bake.

Preheat oven to 175°C. Scoop rounded tablespoons of dough onto a lined baking sheet, spacing 5 cm apart. Bake 10-12 minutes until edges are golden but centers still look soft. Cool on the sheet for 5 minutes before transferring to a rack.

---

Substitute walnuts or chocolate chips for the raisins if you like.
```

**`db/seeds/recipes/Baking/Quick Pizza.md`** — Cross-reference, multi-step:

```markdown
# Quick Pizza

A simple weeknight pizza using pantry staples.

Makes: 2 pizzas
Serves: 4

## Make the dough.

- Flour (all-purpose), 300 g
- Yeast, 1 tsp
- Salt, 1 tsp
- Sugar (white), 1 tsp
- Olive oil, 2 tbsp
- Water, 190 g: Warm.

Combine flour, yeast, salt, and sugar. Add oil and warm water. Mix until a shaggy dough forms, then knead 5 minutes until smooth. Cover and rest 30 minutes.

## Assemble and bake.

- Pasta sauce (jarred), 120 g
- Mozzarella (low-moisture), 200 g: Shredded.

Preheat oven to 230°C. Divide dough in half and stretch each piece into a round on a floured surface. Spread sauce, top with cheese, and add any other toppings you like. Bake directly on a hot baking sheet or stone for 10-12 minutes until crust is golden and cheese is bubbly.
```

**`db/seeds/recipes/Quick Bites.md`** — Sample Quick Bites:

```markdown
Snacks:
- Apples and Peanut Butter: Apples, Peanut butter
- Crackers and Cheese: Ritz crackers, Cheddar

Breakfast:
- Cereal and Milk: Rolled oats, Milk
- Toast and Butter: Bread, Butter

Quick Meals:
- Grilled Cheese: Bread, American cheese, Butter
- Pasta with Sauce: Pasta, Pasta sauce (jarred), Parmesan
```

**Step 3: Verify sample recipes parse correctly**

```bash
bin/rails runner "
  Dir.glob('db/seeds/recipes/**/*.md').reject { |p| p.include?('Quick Bites') }.each do |path|
    tokens = LineClassifier.classify(File.read(path))
    parsed = RecipeBuilder.new(tokens).build
    puts \"OK: #{parsed[:title]}\"
  end
"
```

Expected: all 6 recipes print OK with their titles.

**Step 4: Verify Quick Bites parse correctly**

```bash
bin/rails runner "
  content = File.read('db/seeds/recipes/Quick Bites.md')
  qbs = FamilyRecipes.parse_quick_bites_content(content).quick_bites
  puts \"#{qbs.size} quick bites parsed\"
  qbs.each { |qb| puts \"  #{qb.title}\" }
"
```

Expected: 6 quick bites parsed.

**Step 5: Run full test suite**

```bash
rake test
```

Expected: all pass. Tests don't depend on seed recipe content.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: replace real recipes with sample content (#187)"
```

---

### Task 4: Make db:seed First-Boot Only

Update `db/seeds.rb` to skip recipe/Quick Bites seeding when recipes already exist. Keep kitchen and user creation idempotent.

**Files:**
- Modify: `db/seeds.rb`

**Step 1: Update `db/seeds.rb`**

Replace the current file with:

```ruby
# frozen_string_literal: true

# Populates a fresh database with a default kitchen, user, sample recipes,
# Quick Bites, and aisle ordering. Only installs sample content on first boot
# (when no recipes exist). Kitchen, user, and aisle order are always idempotent.
#
# Collaborators:
# - MarkdownImporter — parses and persists each recipe Markdown file
# - CrossReference.resolve_pending — links deferred @[Title] references
# - db/seeds/recipes/ — sample Markdown files including Quick Bites.md
# - db/seeds/resources/ — aisle-order.txt for grocery aisle display order
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

# Seed aisle order (idempotent — always update to latest)
seeds_dir = Rails.root.join('db/seeds')
aisle_order_path = seeds_dir.join('resources/aisle-order.txt')
if aisle_order_path.exist?
  kitchen.update!(aisle_order: File.read(aisle_order_path).strip)
  puts 'Aisle order loaded.'
end

# Sample content — first boot only
if Recipe.count.zero?
  recipes_dir = seeds_dir.join('recipes')
  quick_bites_filename = 'Quick Bites.md'

  recipe_files = Dir.glob(recipes_dir.join('**', '*.md')).reject do |path|
    File.basename(path) == quick_bites_filename
  end

  puts "Importing #{recipe_files.size} sample recipes..."

  recipe_files.each do |path|
    category_name = File.basename(File.dirname(path))
    category_slug = FamilyRecipes.slugify(category_name)
    category = kitchen.categories.find_or_create_by!(slug: category_slug) do |cat|
      cat.name = category_name
      cat.position = kitchen.categories.maximum(:position).to_i + 1
    end

    recipe = MarkdownImporter.import(File.read(path), kitchen: kitchen, category: category)
    puts "  #{recipe.title} (#{recipe.category.name})"
  end

  CrossReference.resolve_pending(kitchen: kitchen)
  pending_count = CrossReference.pending.count
  puts "  WARNING: #{pending_count} unresolved cross-references remain" if pending_count.positive?

  quick_bites_path = recipes_dir.join(quick_bites_filename)
  if quick_bites_path.exist?
    kitchen.update!(quick_bites_content: File.read(quick_bites_path))
    puts 'Quick Bites content loaded.'
  end

  puts "Done! #{Recipe.count} recipes in #{Category.count} categories."
else
  puts "Recipes already exist (#{Recipe.count}) — skipping sample content."
end
```

**Step 2: Test first-boot behavior**

```bash
rm -f storage/development.sqlite3 storage/development_cable.sqlite3
bin/rails db:prepare
bin/rails catalog:sync
bin/rails db:seed
```

Expected: sample recipes imported, Quick Bites loaded.

**Step 3: Test idempotent re-run**

```bash
bin/rails db:seed
```

Expected: "Recipes already exist (6) — skipping sample content." No new recipes created.

**Step 4: Run full test suite**

```bash
rake test
```

Expected: all tests pass.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: seed sample content on first boot only (#187)"
```

---

### Task 5: Update Docker Entrypoint

Add the site.yml copy step to the entrypoint, between `db:prepare` and `catalog:sync`.

**Files:**
- Modify: `bin/docker-entrypoint`

**Step 1: Update `bin/docker-entrypoint`**

Replace with:

```bash
#!/bin/bash
#
# Docker container entry point. Prepares the database, copies the default site
# config to the persistent volume on first boot, syncs the ingredient catalog,
# seeds sample data (first boot only), then execs the CMD (typically Puma).
# All operations are idempotent — safe to run on every container start.
set -e

echo "Preparing database..."
bin/rails db:prepare

# Copy default site config to storage volume on first boot.
# Users can edit storage/site.yml to customize their instance.
if [ ! -f storage/site.yml ]; then
  echo "Installing default site configuration..."
  cp config/site.yml storage/site.yml
fi

echo "Syncing ingredient catalog..."
bin/rails catalog:sync

echo "Seeding data..."
bin/rails db:seed

echo "Starting server..."
exec "$@"
```

**Step 2: Verify entrypoint is executable**

```bash
ls -la bin/docker-entrypoint
```

Expected: should already have `+x`. If not: `chmod +x bin/docker-entrypoint`.

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: copy default site.yml to storage volume on first boot (#187)"
```

---

### Task 6: Update docker-compose.example.yml

Add a comment about `site.yml` customization so users know the config exists.

**Files:**
- Modify: `docker-compose.example.yml`

**Step 1: Read current file**

Read `docker-compose.example.yml` to see current structure.

**Step 2: Add comment about site config**

Add a comment in the volumes section or near the top explaining that `storage/site.yml` can be edited to customize the site title and other settings. No structural changes needed — the existing `app_storage:/app/storage` volume already covers the config file.

**Step 3: Commit**

```bash
git add -A
git commit -m "docs: note site.yml customization in docker-compose example (#187)"
```

---

### Task 7: Full Integration Verification

Verify the complete flow end-to-end.

**Files:** None (verification only)

**Step 1: Run RuboCop**

```bash
bundle exec rubocop
```

Expected: 0 offenses.

**Step 2: Run full test suite**

```bash
rake test
```

Expected: all tests pass.

**Step 3: Test fresh database flow**

```bash
rm -f storage/development.sqlite3 storage/development_cable.sqlite3 storage/site.yml
bin/rails db:prepare
bin/rails catalog:sync
bin/rails db:seed
```

Expected: database created, catalog synced, 6 sample recipes + Quick Bites seeded.

**Step 4: Test image-update flow (re-run)**

```bash
bin/rails db:prepare
bin/rails catalog:sync
bin/rails db:seed
```

Expected: db:prepare is no-op, catalog syncs (0 created, 0 updated, N unchanged), seed skips sample content.

**Step 5: Verify app boots and renders**

```bash
bin/dev &
sleep 3
curl -s http://localhost:3030 | head -20
kill %1
```

Expected: HTML response with sample recipes visible.

**Step 6: Check html_safe allowlist**

If lines shifted in `homepage/show.html.erb`, run:

```bash
rake lint:html_safe
```

Fix any allowlist entries if needed.

**Step 7: Commit any fixes, then final commit if needed**
