# Seed Data Reorganization & Static Build Cleanup — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move all seed data under `db/seeds/`, make all YAML resources database-backed via SiteDocument, and remove static build vestiges.

**Architecture:** Seed files relocate to `db/seeds/recipes/` and `db/seeds/resources/`. All YAML resources (site-config, nutrition-data, grocery-info) become SiteDocuments seeded from those files. Controllers load from DB with disk fallback. GitHub Actions workflow gets build/deploy commented out; README rewritten.

**Tech Stack:** Rails 8, PostgreSQL, SiteDocument model, YAML

---

### Task 1: Move seed files to `db/seeds/`

This is a pure file move — no code changes yet.

**Step 1: Create the new directory structure and move files**

```bash
mkdir -p db/seeds/recipes db/seeds/resources
git mv recipes/Bread db/seeds/recipes/Bread
git mv recipes/Breakfast db/seeds/recipes/Breakfast
git mv recipes/Dessert db/seeds/recipes/Dessert
git mv recipes/Drinks db/seeds/recipes/Drinks
git mv recipes/Holiday db/seeds/recipes/Holiday
git mv recipes/Mains db/seeds/recipes/Mains
git mv recipes/Pizza db/seeds/recipes/Pizza
git mv recipes/Sides db/seeds/recipes/Sides
git mv recipes/Snacks db/seeds/recipes/Snacks
git mv "recipes/Quick Bites.md" "db/seeds/recipes/Quick Bites.md"
git mv resources/grocery-info.yaml db/seeds/resources/grocery-info.yaml
git mv resources/nutrition-data.yaml db/seeds/resources/nutrition-data.yaml
git mv resources/site-config.yaml db/seeds/resources/site-config.yaml
```

**Step 2: Remove empty parent directories**

```bash
rmdir recipes resources
```

If `resources/` or `recipes/` aren't empty (hidden files, etc.), check what's left before removing.

**Step 3: Commit**

```bash
git add -A
git commit -m "chore: move seed data to db/seeds/"
```

---

### Task 2: Update `db/seeds.rb` to seed all SiteDocuments

**Files:**
- Modify: `db/seeds.rb`

**Step 1: Update seeds.rb**

Replace the full file content. Changes:
- Line 18: `recipes_dir` path changes from `Rails.root.join('recipes')` to `Rails.root.join('db/seeds/recipes')`
- Line 55: `grocery_yaml_path` changes from `Rails.root.join('resources/grocery-info.yaml')` to `Rails.root.join('db/seeds/resources/grocery-info.yaml')`
- Add: seed `site_config` SiteDocument from `db/seeds/resources/site-config.yaml`
- Add: seed `nutrition_data` SiteDocument from `db/seeds/resources/nutrition-data.yaml`

```ruby
# frozen_string_literal: true

# Create kitchen and user
kitchen = Kitchen.find_or_create_by!(slug: 'biagini-family') do |k|
  k.name = 'Biagini Family'
end

user = User.find_or_create_by!(email: 'chris@example.com') do |u|
  u.name = 'Chris'
end

Membership.find_or_create_by!(kitchen: kitchen, user: user)

puts "Kitchen: #{kitchen.name} (#{kitchen.slug})"
puts "User: #{user.name} (#{user.email})"

# Import recipes
seeds_dir = Rails.root.join('db/seeds')
recipes_dir = seeds_dir.join('recipes')
resources_dir = seeds_dir.join('resources')
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

puts "Done! #{Recipe.count} recipes, #{Category.count} categories."

# Seed Quick Bites document
quick_bites_path = recipes_dir.join('Quick Bites.md')
if File.exist?(quick_bites_path)
  SiteDocument.find_or_create_by!(kitchen: kitchen, name: 'quick_bites') do |doc|
    doc.content = File.read(quick_bites_path)
  end
  puts 'Quick Bites document loaded.'
end

# Seed Grocery Aisles document (convert YAML to markdown)
grocery_yaml_path = resources_dir.join('grocery-info.yaml')
if File.exist?(grocery_yaml_path)
  SiteDocument.find_or_create_by!(kitchen: kitchen, name: 'grocery_aisles') do |doc|
    raw = YAML.safe_load_file(grocery_yaml_path, permitted_classes: [], permitted_symbols: [], aliases: false)
    doc.content = raw.map do |aisle, items|
      heading = "## #{aisle.tr('_', ' ')}"
      item_lines = items.map do |item|
        name = item.respond_to?(:fetch) ? item.fetch('name') : item
        "- #{name}"
      end
      [heading, *item_lines, ''].join("\n")
    end.join("\n")
  end
  puts 'Grocery Aisles document loaded.'
end

# Seed Site Config document
site_config_path = resources_dir.join('site-config.yaml')
if File.exist?(site_config_path)
  SiteDocument.find_or_create_by!(kitchen: kitchen, name: 'site_config') do |doc|
    doc.content = File.read(site_config_path)
  end
  puts 'Site Config document loaded.'
end

# Seed Nutrition Data document
nutrition_path = resources_dir.join('nutrition-data.yaml')
if File.exist?(nutrition_path)
  SiteDocument.find_or_create_by!(kitchen: kitchen, name: 'nutrition_data') do |doc|
    doc.content = File.read(nutrition_path)
  end
  puts 'Nutrition Data document loaded.'
end
```

**Step 2: Verify seeds work**

```bash
rails db:seed
```

Expected: all recipes imported, all 4 SiteDocuments loaded (or "already exist" on re-run).

**Step 3: Commit**

```bash
git add db/seeds.rb
git commit -m "feat: seed site_config and nutrition_data as SiteDocuments"
```

---

### Task 3: Update HomepageController to load site config from DB

**Files:**
- Modify: `app/controllers/homepage_controller.rb:11`

**Step 1: Update `load_site_config`**

Replace the one-liner `load_site_config` method (line 11) with a DB-first pattern:

```ruby
def load_site_config
  doc = current_kitchen.site_documents.find_by(name: 'site_config')
  return YAML.safe_load(doc.content) if doc

  YAML.safe_load_file(Rails.root.join('db/seeds/resources/site-config.yaml'))
end
```

**Step 2: Verify homepage still renders**

```bash
rails runner "puts HomepageController.new.class"
```

Then test manually via `bin/dev` — homepage should show the same title, heading, subtitle, and GitHub link.

**Step 3: Commit**

```bash
git add app/controllers/homepage_controller.rb
git commit -m "feat: load site config from SiteDocument with disk fallback"
```

---

### Task 4: Update RecipesController to load nutrition data from DB

**Files:**
- Modify: `app/controllers/recipes_controller.rb:88-93` (`load_nutrition_data`)
- Modify: `app/controllers/recipes_controller.rb:99-104` (`load_grocery_aisles`)

**Step 1: Update `load_nutrition_data` (lines 88-93)**

Replace the disk-only method with a DB-first pattern:

```ruby
def load_nutrition_data
  doc = current_kitchen.site_documents.find_by(name: 'nutrition_data')
  if doc
    return YAML.safe_load(doc.content, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  path = Rails.root.join('db/seeds/resources/nutrition-data.yaml')
  return unless File.exist?(path)

  YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
end
```

**Step 2: Update `load_grocery_aisles` fallback path (lines 99-104)**

Change `resources/grocery-info.yaml` to `db/seeds/resources/grocery-info.yaml`:

```ruby
def load_grocery_aisles
  doc = current_kitchen.site_documents.find_by(name: 'grocery_aisles')
  return FamilyRecipes.parse_grocery_info(Rails.root.join('db/seeds/resources/grocery-info.yaml')) unless doc

  FamilyRecipes.parse_grocery_aisles_markdown(doc.content)
end
```

**Step 3: Verify a recipe page with nutrition still renders**

Test manually via `bin/dev` — navigate to a recipe that has nutrition data (e.g., Focaccia).

**Step 4: Commit**

```bash
git add app/controllers/recipes_controller.rb
git commit -m "feat: load nutrition data from SiteDocument with disk fallback"
```

---

### Task 5: Update remaining controller fallback paths

**Files:**
- Modify: `app/controllers/groceries_controller.rb:50-55` (`fallback_grocery_aisles`)
- Modify: `app/controllers/ingredients_controller.rb:30-35` (`load_grocery_aisles`)

**Step 1: Update GroceriesController fallback path (line 51)**

In `fallback_grocery_aisles`, change `resources/grocery-info.yaml` to `db/seeds/resources/grocery-info.yaml`:

```ruby
def fallback_grocery_aisles
  yaml_path = Rails.root.join('db/seeds/resources/grocery-info.yaml')
  return {} unless File.exist?(yaml_path)

  FamilyRecipes.parse_grocery_info(yaml_path)
end
```

**Step 2: Update IngredientsController fallback path (line 32)**

In `load_grocery_aisles`, change `resources/grocery-info.yaml` to `db/seeds/resources/grocery-info.yaml`:

```ruby
def load_grocery_aisles
  doc = current_kitchen.site_documents.find_by(name: 'grocery_aisles')
  return FamilyRecipes.parse_grocery_info(Rails.root.join('db/seeds/resources/grocery-info.yaml')) unless doc

  FamilyRecipes.parse_grocery_aisles_markdown(doc.content)
end
```

**Step 3: Commit**

```bash
git add app/controllers/groceries_controller.rb app/controllers/ingredients_controller.rb
git commit -m "fix: update disk fallback paths to db/seeds/resources/"
```

---

### Task 6: Update `bin/nutrition` paths

**Files:**
- Modify: `bin/nutrition:10-12`

**Step 1: Update the three path constants (lines 10-12)**

```ruby
NUTRITION_PATH = File.join(PROJECT_ROOT, 'db/seeds/resources/nutrition-data.yaml')
GROCERY_PATH = File.join(PROJECT_ROOT, 'db/seeds/resources/grocery-info.yaml')
RECIPES_DIR = File.join(PROJECT_ROOT, 'db/seeds/recipes')
```

**Step 2: Commit**

```bash
git add bin/nutrition
git commit -m "chore: update bin/nutrition paths to db/seeds/"
```

---

### Task 7: Update BuildValidator message

**Files:**
- Modify: `lib/familyrecipes/build_validator.rb:164`

**Step 1: Update the help text (line 164)**

Change `resources/nutrition-data.yaml` to `db/seeds/resources/nutrition-data.yaml`:

```ruby
puts 'Use bin/nutrition to add data, or edit db/seeds/resources/nutrition-data.yaml directly.'
```

Also fix the stale `bin/nutrition-entry` reference to `bin/nutrition`.

**Step 2: Commit**

```bash
git add lib/familyrecipes/build_validator.rb
git commit -m "chore: update build validator help text paths"
```

---

### Task 8: Clean up static build vestiges

**Files:**
- Modify: `.github/workflows/deploy.yml:40-45`
- Modify: `.gitignore:6-7`
- Modify: `README.md` (full rewrite)

**Step 1: Comment out build/deploy in deploy.yml (lines 40-45)**

Replace lines 40-45 with:

```yaml
      # Build and deploy steps disabled — static site generator removed.
      # Deployment pending Docker packaging for Rails app.
      # - name: Build site
      #   run: bin/generate
      #
      # - uses: actions/upload-pages-artifact@v3
      #   with:
      #     path: output/web
```

**Step 2: Update .gitignore — replace `output/` comment and entry (lines 6-7)**

Change:
```
# Generated output
output/
```
To:
```
# Generated output (legacy static build)
# output/
```

**Step 3: Rewrite README.md**

Replace the full content with an updated description reflecting the Rails app:

```markdown
# familyrecipes

_recipes by Chris, Kelly, Lucy, Nathan, and Cora_
_code by Chris, ChatGPT, and Claude_

## About

`familyrecipes` is a recipe publishing and archiving system built with Ruby on Rails. Recipes are authored in Markdown and stored in a PostgreSQL database. The app supports multi-tenant "Kitchens" with web-based editing for recipes, Quick Bites, and grocery aisles.

The project includes a collection of our favorite family recipes as seed data.

## Getting Started

```bash
bundle install
rails db:create db:migrate db:seed
bin/dev
```

This starts the app on `http://localhost:3030`. Seed data is loaded from `db/seeds/` — recipe markdown files, grocery aisle mappings, nutrition data, and site configuration.

## Tech Stack

- [Ruby on Rails 8](https://rubyonrails.org/) with [PostgreSQL](https://www.postgresql.org/)
- [Nova](https://nova.app) by [Panic](https://www.panic.com)
- [ChatGPT](https://chatgpt.com/) by [OpenAI](https://openai.com/)
- [Claude](https://claude.ai/) by [Anthropic](https://www.anthropic.com/)
- [RealFaviconGenerator](https://realfavicongenerator.net/)
```

**Step 4: Commit**

```bash
git add .github/workflows/deploy.yml .gitignore README.md
git commit -m "chore: remove static build vestiges, update README for Rails"
```

---

### Task 9: Update CLAUDE.md references

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update all path references**

Search CLAUDE.md for `recipes/`, `resources/`, and update:

- `recipes/*.md` → `db/seeds/recipes/*.md` (in Database Setup section)
- `recipes/` directory references → `db/seeds/recipes/`
- `resources/grocery-info.yaml` → `db/seeds/resources/grocery-info.yaml`
- `resources/nutrition-data.yaml` → `db/seeds/resources/nutrition-data.yaml`
- `resources/site-config.yaml` → `db/seeds/resources/site-config.yaml`
- `resources/` directory references → `db/seeds/resources/`
- Update the Data Files section header from `resources/` to `db/seeds/resources/`
- Update the SiteDocument description in Architecture section to include `site_config` and `nutrition_data`
- Update HomepageController description to note it loads from SiteDocument now

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md paths for db/seeds/ reorganization"
```

---

### Task 10: Run tests, lint, and verify

**Step 1: Run lint**

```bash
rake lint
```

Expected: all clean.

**Step 2: Run tests**

```bash
rake test
```

Expected: all pass. If any tests reference old paths, fix them.

**Step 3: Re-seed from scratch to verify the full pipeline**

```bash
rails db:drop db:create db:migrate db:seed
```

Expected: all recipes imported, all 4 SiteDocuments created.

**Step 4: Manual smoke test**

Start `bin/dev` and verify:
- Homepage loads with correct title/heading/subtitle
- Recipe pages render with nutrition data
- Groceries page loads Quick Bites and aisles
- Ingredients Index page loads

**Step 5: Final commit if any fixes needed, then done**
