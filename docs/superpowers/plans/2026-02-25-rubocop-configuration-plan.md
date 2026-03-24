# RuboCop Configuration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Configure RuboCop properly with rubocop-rails and rubocop-performance plugins, tighten metric thresholds to aspirational levels, and expand linting scope.

**Architecture:** Single-commit big-bang: add gems, rewrite config, auto-fix safe corrections, manually fix remaining offenses, add inline disables for intentional violations, add one migration for a missing unique index.

**Tech Stack:** RuboCop, rubocop-rails, rubocop-performance, rubocop-minitest

---

### Task 1: Add gems to Gemfile

**Files:**
- Modify: `Gemfile`

**Step 1: Add rubocop-rails and rubocop-performance to development group**

```ruby
group :development do
  gem 'rubocop', require: false
  gem 'rubocop-minitest', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false
end
```

**Step 2: Install**

Run: `bundle install`
Expected: Gems installed, `Gemfile.lock` updated.

---

### Task 2: Rewrite `.rubocop.yml`

**Files:**
- Modify: `.rubocop.yml`

**Step 1: Replace `.rubocop.yml` with new configuration**

```yaml
inherit_mode:
  merge:
    - Exclude

AllCops:
  TargetRubyVersion: 3.2
  NewCops: enable
  SuggestExtensions: false
  Exclude:
    - vendor/**/*
    - db/migrate/**/*
    - db/schema.rb

plugins:
  - rubocop-minitest
  - rubocop-performance
  - rubocop-rails

# --- Project conventions ---

Style/Documentation:
  Enabled: false

Style/FrozenStringLiteralComment:
  EnforcedStyle: always

Naming/RescuedExceptionsVariableName:
  PreferredName: error

Layout/LineLength:
  Max: 120

# --- Aspirational metrics ---
# bin/ scripts and tests are exempt — they're inherently procedural.

Metrics/MethodLength:
  Max: 15
  Exclude:
    - bin/*
    - test/**/*

Metrics/AbcSize:
  Max: 25
  Exclude:
    - bin/*
    - test/**/*

Metrics/CyclomaticComplexity:
  Max: 10
  Exclude:
    - bin/*
    - test/**/*

Metrics/PerceivedComplexity:
  Max: 10
  Exclude:
    - bin/*
    - test/**/*

Metrics/BlockLength:
  Exclude:
    - bin/*
    - test/**/*

Metrics/ClassLength:
  Max: 125
  Exclude:
    - test/**/*

Metrics/ModuleLength:
  Max: 100

Minitest/MultipleAssertions:
  Max: 12

# --- Rails cops ---

# BuildValidator is a CLI build tool that intentionally uses puts
Rails/Output:
  Exclude:
    - lib/familyrecipes/build_validator.rb
```

**Step 2: Verify config parses**

Run: `rubocop --show-cops Metrics/MethodLength 2>&1 | head -5`
Expected: Shows the cop configuration without errors.

---

### Task 3: Run safe auto-correct

**Step 1: Run rubocop auto-correct**

Run: `rubocop -a 2>&1 | tail -20`

This auto-fixes ~95 offenses:
- `Rails/RefuteMethods` (59): `refute_*` → `assert_not_*`
- `Rails/ResponseParsedBody` (22): `JSON.parse(response.body)` → `response.parsed_body`
- `Rails/HttpStatusNameConsistency` (9): `:unprocessable_entity` → `:unprocessable_content`
- `Rails/Blank` (3): `.nil? || .empty?` → `.blank?`
- Plus any other safe auto-corrections

**Step 2: Run tests to verify nothing broke**

Run: `rake test`
Expected: All tests pass. The auto-corrections are semantically equivalent.

**Step 3: Check remaining offenses**

Run: `rubocop 2>&1`
Expected: Lists remaining manual-fix offenses. Use this output to guide Tasks 4-6.

---

### Task 4: Fix manual offenses — Rails cops

**Files:**
- Modify: `app/services/cross_reference_updater.rb:31` — Performance/RedundantBlockCall
- Modify: `app/models/recipe.rb:10` — Rails/InverseOf
- Modify: `app/models/category.rb:14` — Rails/WhereMissing
- Modify: `app/controllers/dev_sessions_controller.rb:26` — Rails/EnvLocal
- Modify: `app/controllers/recipes_controller.rb:73` — Rails/RootPublicPath
- Modify: `lib/tasks/html_safe_audit.rake:5,8` — Rails/RakeEnvironment, Rails/FilePath
- Modify: `app/services/nutrition_label_parser.rb:93` — Rails/IndexWith
- Modify: `lib/familyrecipes/nutrition_calculator.rb:67,101` — Rails/IndexWith

**Step 1: Fix Performance/RedundantBlockCall in cross_reference_updater.rb**

In `app/services/cross_reference_updater.rb`, change `update_referencing_recipes(&block)` to use `yield`:

```ruby
# Before (line 31-39):
def update_referencing_recipes(&block)
  referencing = @recipe.referencing_recipes.includes(:category)
  return [] if referencing.empty?

  referencing.map do |ref_recipe|
    updated_source = block.call(ref_recipe.markdown_source, @recipe.title)
    MarkdownImporter.import(updated_source, kitchen: ref_recipe.kitchen)
    ref_recipe.title
  end
end

# After:
def update_referencing_recipes
  referencing = @recipe.referencing_recipes.includes(:category)
  return [] if referencing.empty?

  referencing.map do |ref_recipe|
    updated_source = yield(ref_recipe.markdown_source, @recipe.title)
    MarkdownImporter.import(updated_source, kitchen: ref_recipe.kitchen)
    ref_recipe.title
  end
end
```

**Step 2: Fix Rails/InverseOf in recipe.rb**

In `app/models/recipe.rb`, add `inverse_of:` to the `inbound_cross_references` association:

```ruby
# Before (line 10-12):
has_many :inbound_cross_references, class_name: 'CrossReference',
                                    foreign_key: :target_recipe_id,
                                    dependent: :destroy

# After:
has_many :inbound_cross_references, class_name: 'CrossReference',
                                    foreign_key: :target_recipe_id,
                                    inverse_of: :target_recipe,
                                    dependent: :destroy
```

**Step 3: Fix Rails/WhereMissing in category.rb**

In `app/models/category.rb`, replace `left_joins` + `where(... nil)` with `where.missing`:

```ruby
# Before (line 13-14):
def self.cleanup_orphans(kitchen)
  kitchen.categories.left_joins(:recipes).where(recipes: { id: nil }).destroy_all
end

# After:
def self.cleanup_orphans(kitchen)
  kitchen.categories.where.missing(:recipes).destroy_all
end
```

**Step 4: Fix Rails/EnvLocal in dev_sessions_controller.rb**

In `app/controllers/dev_sessions_controller.rb`, replace the environment check:

```ruby
# Before (line 25-27):
def require_non_production_environment
  head :not_found unless Rails.env.development? || Rails.env.test?
end

# After:
def require_non_production_environment
  head :not_found unless Rails.env.local?
end
```

**Step 5: Fix Rails/RootPublicPath in recipes_controller.rb**

In `app/controllers/recipes_controller.rb`, use `Rails.public_path`:

```ruby
# Before (line 72-73):
format.html { render file: Rails.root.join('public/404.html'), status: :not_found, layout: false }

# After:
format.html { render file: Rails.public_path.join('404.html'), status: :not_found, layout: false }
```

**Step 6: Fix Rails/RakeEnvironment and Rails/FilePath in html_safe_audit.rake**

In `lib/tasks/html_safe_audit.rake`:

```ruby
# Before (line 5):
task :html_safe do

# After:
task html_safe: :environment do
```

```ruby
# Before (line 8):
allowlist_file = Rails.root.join('config', 'html_safe_allowlist.yml')

# After:
allowlist_file = Rails.root.join('config/html_safe_allowlist.yml')
```

**Step 7: Fix Rails/IndexWith in nutrition_calculator.rb**

In `lib/familyrecipes/nutrition_calculator.rb`, replace `to_h { ... }` with `index_with`:

```ruby
# Before (line 67):
totals = NUTRIENTS.to_h { |n| [n, 0.0] }

# After:
totals = NUTRIENTS.index_with { 0.0 }
```

```ruby
# Before (line 101):
NUTRIENTS.to_h { |n| [n, totals[n] / divisor] } if divisor

# After:
NUTRIENTS.index_with { |n| totals[n] / divisor } if divisor
```

**Step 8: Fix Rails/IndexWith in nutrition_label_parser.rb**

Read the file to find the exact line (~93), then apply the same `index_with` pattern.

**Step 9: Fix any Rails/Pluck offenses in test files**

These are in test assertions using `.map { |i| i[:name] }` — change to `.pluck(:name)` or apply `rubocop -a` on test files (since `Pluck` is auto-correctable with `-A`).

**Step 10: Run tests**

Run: `rake test`
Expected: All tests pass.

---

### Task 5: Add inline disables for intentional violations

**Files:**
- Modify: `app/helpers/recipes_helper.rb` — Rails/OutputSafety (5 calls)
- Modify: `app/jobs/recipe_nutrition_job.rb:16` — Rails/SkipsModelValidations
- Modify: `app/models/cross_reference.rb:36` — Rails/SkipsModelValidations

**Step 1: Add Rails/OutputSafety disables in recipes_helper.rb**

These `.html_safe` calls are audited by `rake lint:html_safe` with an allowlist. Add inline disables:

```ruby
# Line 7:
FamilyRecipes::Recipe::MARKDOWN.render(text).html_safe # rubocop:disable Rails/OutputSafety

# Line 14:
ScalableNumberPreprocessor.process_instructions(html).html_safe # rubocop:disable Rails/OutputSafety

# Line 20:
ScalableNumberPreprocessor.process_yield_line(text).html_safe # rubocop:disable Rails/OutputSafety

# Line 26:
ScalableNumberPreprocessor.process_yield_with_unit(text, singular, plural).html_safe # rubocop:disable Rails/OutputSafety

# Line 59:
"Per Serving<br>(#{ERB::Util.html_escape(formatted_ups)} #{ERB::Util.html_escape(ups_unit)})".html_safe # rubocop:disable Rails/OutputSafety
```

**Step 2: Add Rails/SkipsModelValidations disables**

In `app/jobs/recipe_nutrition_job.rb:16`:
```ruby
recipe.update_column(:nutrition_data, serialize_result(result)) # rubocop:disable Rails/SkipsModelValidations
```

In `app/models/cross_reference.rb:36`:
```ruby
ref.update_column(:target_recipe_id, slug_to_id.fetch(ref.target_slug)) # rubocop:disable Rails/SkipsModelValidations
```

**Step 3: Check if test file has SkipsModelValidations offense too**

The audit found one in `test/jobs/recipe_nutrition_job_test.rb:115`. If it's in a test, add the inline disable there too.

---

### Task 6: Add inline disables for metric-exceeding methods

**Files:**
- Modify: `lib/familyrecipes/nutrition_entry_helpers.rb:9` — parse_serving_size (MethodLength, AbcSize, Cyclomatic, Perceived)
- Modify: `lib/familyrecipes/nutrition_calculator.rb:125` — to_grams (MethodLength, AbcSize, Cyclomatic, Perceived)
- Modify: `lib/familyrecipes/ingredient_aggregator.rb:19` — aggregate_amounts (AbcSize, Cyclomatic, Perceived)
- Modify: `app/helpers/recipes_helper.rb:30` — nutrition_columns (AbcSize, Cyclomatic, Perceived)
- Modify: `lib/familyrecipes/recipe_builder.rb:94,123` — parse_step (MethodLength, AbcSize), parse_footer (MethodLength, AbcSize, Cyclomatic, Perceived)
- Modify: `lib/familyrecipes/ingredient_parser.rb:9` — parse (MethodLength, AbcSize)
- Modify: `app/controllers/recipes_controller.rb:27` — update (MethodLength, AbcSize)
- Modify: `app/controllers/nutrition_entries_controller.rb:86` — assign_parsed_attributes (MethodLength, AbcSize)
- Modify: `app/services/markdown_importer.rb:50` — update_recipe_attributes (MethodLength, AbcSize)
- Modify: `lib/familyrecipes/build_validator.rb` — BuildValidator (ClassLength)
- Modify: `app/services/nutrition_label_parser.rb` — NutritionLabelParser (ClassLength)
- Modify: `lib/familyrecipes/recipe.rb` — FamilyRecipes::Recipe (ClassLength)
- Modify: `lib/familyrecipes/recipe_builder.rb` — RecipeBuilder (ClassLength)
- Modify: `app/services/markdown_importer.rb` — MarkdownImporter (ClassLength)

**Approach:** Run `rubocop` after Tasks 3-5, then add inline `# rubocop:disable` comments for each remaining metric offense. Use `# rubocop:disable`/`# rubocop:enable` pairs wrapping the method/class definition.

For method-level metrics, the pattern is:
```ruby
# TODO: refactor — extract smaller methods
def long_method # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  ...
end # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
```

For class-level metrics:
```ruby
class BigClass # rubocop:disable Metrics/ClassLength
  ...
end # rubocop:enable Metrics/ClassLength
```

**Step 1: Run rubocop to get the exact list of remaining metric offenses**

Run: `rubocop --only Metrics/ 2>&1`

**Step 2: Add inline disables for each offense**

Work through each file, adding `rubocop:disable`/`enable` pairs. Always include a `# TODO:` comment explaining what refactoring would help.

**Step 3: Run rubocop to verify zero offenses**

Run: `rubocop`
Expected: 0 offenses detected.

---

### Task 7: Add unique index migration for categories.name

**Files:**
- Create: `db/migrate/7_add_unique_index_on_categories_name.rb`

The `Rails/UniqueValidationWithoutIndex` cop flags `validates :name, uniqueness: { scope: :kitchen_id }` in `Category` because there's no unique index on `(kitchen_id, name)`. The slug has an index but name does not — this is a real race condition.

**Step 1: Create the migration**

```ruby
# frozen_string_literal: true

class AddUniqueIndexOnCategoriesName < ActiveRecord::Migration[8.1]
  def change
    add_index :categories, %i[kitchen_id name], unique: true
  end
end
```

**Step 2: Run the migration**

Run: `rails db:migrate`
Expected: Migration runs successfully.

---

### Task 8: Handle new offenses from expanded scope

Bringing `config/` and `db/` back into scope may surface new offenses from initializers, seeds, and other config files.

**Step 1: Run rubocop to see any new offenses**

Run: `rubocop`

**Step 2: Fix or disable each offense**

Work through any remaining offenses from the newly-scoped files. Most will be minor style issues in config files or seeds.

**Step 3: Verify zero offenses**

Run: `rubocop`
Expected: 0 offenses detected.

---

### Task 9: Final verification and commit

**Step 1: Run the full test suite**

Run: `rake test`
Expected: All tests pass.

**Step 2: Run the full lint suite**

Run: `rake lint`
Expected: 0 offenses.

**Step 3: Commit everything**

Run: `git status` to review all changes, then:

```bash
git add -A
git commit -m "feat: configure rubocop properly (closes #96)

Add rubocop-rails and rubocop-performance plugins. Tighten metric
thresholds to aspirational levels with targeted inline exclusions.
Expand linting scope to include config/ and db/ (except migrations).
Auto-fix ~95 mechanical offenses (refute→assert_not, parsed_body, etc.).
Add unique index on categories(kitchen_id, name).

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```
