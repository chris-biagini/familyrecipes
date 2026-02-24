# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a fully dynamic Rails 8 app backed by SQLite with multi-tenant "Kitchen" support. Three-database architecture: primary (app data), cable (Solid Cable pub/sub), queue (Solid Queue background jobs). OmniAuth-based auth with database-backed sessions is in place (`:developer` strategy for dev/test; production OAuth providers not yet configured).
Eventually, the goal is to ship this app as a Docker image for homelab install, while also maintaining a for-pay hosted copy (e.g., at fly.io).

## Design Philosophy

- Your goal is a high-quality, well-crafted user experience.
- Improve the end product. Make it delightful, charming, and fun.
- Default to simple UI. We can add complexity when it's necessary.
- Always feel free to challenge assumptions, misconceptions, and poor design decisions.
- Suggest any quality-of-life, performance, or feature improvements that come to mind.
- Let's walk before we run. Don't solve scale problems I don't have.
- Always use the superpowers skill when getting ready to write code or build a new feature.

## Recipe source files

- Recipe source files are Markdown. They should read naturally in plaintext, as if written for a person, not a parser. Some custom syntax is necessary but should be limited.
- Source files follow a strict, consistent format to keep parsing reliable.

## HTML, CSS, and JavaScript

Everywhere: use semantic HTML wherever possible and appropriate for the content.
Avoid littering the DOM with  more `<div>`s than needed. Don't use a `<div>` when a semantic tag will do.

Recipes:
- Recipes are **documents first**. They are marked-up text that a browser can render, not an app that happens to contain text.
- CSS and JS are progressive enhancements. Every recipe page must be readable and functional with both disabled.
- JavaScript is used sparingly and only for optional features (scaling, state preservation, cross-off). These are guilty indulgences—they must not interfere with the document nature of the page.

Elsewhere (home page, ingredients editor, groceries page): the mandate here is looser.
More JavaScript is permitted, but keep things lean.
Ask before adding any third-party resources.

## Ruby code conventions

This is a Ruby project. Write idiomatic, expressive Ruby — not Python or JavaScript translated into Ruby syntax. Ruby code should read like English.

### Enumerable over imperative loops — this is non-negotiable

NEVER build collections with `each` + an accumulator. Use the right Enumerable method:
```ruby
# WRONG — Claude's default, and it's unacceptable
result = []
items.each { |item| result << item.name if item.active? }
result

# RIGHT — idiomatic Ruby
items.select(&:active?).map(&:name)
```

Use `map` for transformation, `select`/`reject` for filtering, `flat_map` for nested flattening, `each_with_object` for building hashes, `any?`/`all?`/`none?` for boolean reduction, `tally` for counting, `group_by` for categorization, `sum` for totals. Always use `&:method_name` (Symbol#to_proc) when the block just calls one method.

### Method design

- Methods should be ≤ 5 lines. Extract smaller methods with descriptive names instead of adding comments.
- NEVER use explicit `return` at the end of a method. Ruby returns the last expression implicitly.
- Use guard clauses and early returns to flatten conditionals. Never nest more than 2 levels.
- Use postfix `if`/`unless` for single-line expressions: `return if list.empty?`
- Use `unless` for negative conditions. Never use `unless` with `else`.
- Prefer keyword arguments over positional arguments for clarity at call sites.

```ruby
# WRONG
def process(user)
  if user
    if user.active?
      result = do_work(user)
      return result
    end
  end
end

# RIGHT
def process(user)
  return unless user&.active?

  do_work(user)
end
```

### Ruby's object model — trust it

- Use duck typing. Never check `is_a?` or `.class` — call the method or use `respond_to?`.
- Use `Hash#fetch` instead of `Hash#[]` when the key must exist. Use `fetch(:key, default)` for defaults.
- Only `false` and `nil` are falsy in Ruby. Never write `if x != nil` or `if x == true` — write `if x`.
- Use `&.` (safe navigation) instead of `x && x.method`.
- Prefer composition with modules over deep inheritance hierarchies.

### Error handling

- Use `raise`/`rescue`, not generic exception handling.
- Rescue specific exceptions, never bare `rescue` or `rescue Exception`.
- Use method-level rescue (no extra `begin`/`end` wrapping the whole method body).
- Name the error variable `error`, not `e`.

```ruby
# WRONG
def read_recipe(path)
  begin
    content = File.read(path)
    parse(content)
  rescue => e
    puts e.message
  end
end

# RIGHT
def read_recipe(path)
  content = File.read(path)
  parse(content)
rescue Errno::ENOENT => error
  log_missing_file(path, error)
end
```

### Modern Ruby features — use them

- Single-quoted strings unless interpolation or special characters are needed (RuboCop enforces this).
- `# frozen_string_literal: true` at the top of every file.
- Pattern matching (`case/in`) for complex data destructuring.
- Endless methods (`def full_name = "#{first} #{last}"`) for trivial one-liners.
- `Data.define` for immutable value objects.
- `Hash#except` to drop keys. `Array#tally` for frequency counts.
- String interpolation always — never concatenate with `+`.
- Use symbol keys for hashes (`{ name: "value" }`), not string keys.

### Naming

- `snake_case` for methods, variables, files. `CamelCase` for classes/modules. `SCREAMING_SNAKE_CASE` for constants.
- Predicate methods end with `?`. Dangerous/mutating methods end with `!`.
- Never prefix with `get_` or `is_`. Use `name` not `get_name`. Use `valid?` not `is_valid?`.
- Prefer `map` over `collect`, `select` over `find_all`, `size` over `length`, `key?` over `has_key?`.

### Comments

- Never write comments that restate what the code does. If code needs a comment explaining *what*, extract a method with a descriptive name instead.
- Add comments to explain *why* — business rules, non-obvious constraints, or links to external references.

## Workflow Preferences

### Worktree cleanup — ALWAYS cd first
When a session runs inside a worktree, `git worktree remove` deletes the CWD and bricks the Bash tool for the rest of the session. **Before removing a worktree, always `cd` to the main repo first:**
```bash
cd /home/claude/familyrecipes && git worktree remove .claude/worktrees/<name> && git worktree prune
```

### Screenshots and Playwright
Save screenshots and Playwright output to `~/screenshots/`, not inside the repo. When using browser tools, pass filenames like `/home/claude/screenshots/my-screenshot.png`. The `.gitignore` catches `.playwright-mcp/` and `*.png` as a safety net, but keep them out of the repo directory entirely.

### Data.define and Rails JSON serialization
`Data.define` classes with custom `to_json` must also define `as_json` — ActiveSupport calls `as_json` (not `to_json`) on nested objects. See `Quantity` for the pattern. Without both, value objects serialize as hashes instead of the intended format when embedded in arrays/hashes passed to `.to_json`.

### Stale server PID
If `bin/dev` fails with "A server is already running", kill the process and remove the PID file:
```bash
pkill -f puma; rm -f tmp/pids/server.pid
```

### Server restart after gem or concern changes
Adding gems (e.g., `omniauth`) or creating new files in `app/controllers/concerns/` requires restarting Puma. The dev server does not hot-reload these. Run `pkill -f puma; rm -f tmp/pids/server.pid` then `bin/dev`.

### GitHub Issues
If I mention a GitHub issue (e.g., "#99"), review it and plan a fix. Close it via the commit message once confirmed.

### Commit timestamp privacy
This repo uses a post-commit hook (`.githooks/post-commit`) that rewrites commit timestamps for privacy. After cloning, activate it:
```bash
git config core.hooksPath .githooks
```
The hook replaces time-of-day with synthetic UTC timestamps while preserving the calendar date and chronological commit order. See `docs/plans/2026-02-23-commit-privacy-design.md` for details.

## Database Setup

```bash
rails db:create db:migrate db:seed
```

SQLite3 is required. Three databases: primary (`storage/production.sqlite3`), cable (`storage/production_cable.sqlite3`), queue (`storage/production_queue.sqlite3`). Development/test use parallel files under `storage/`. `db:seed` imports all markdown files from `db/seeds/recipes/` into the database via `MarkdownImporter` and loads ingredient catalog from `db/seeds/resources/ingredient-catalog.yaml`. The seed is idempotent — safe to re-run. Dependencies are managed via `Gemfile` (Ruby 3.2+, Bundler, and `bundle install` required).

### Background Jobs

Save-time operations (nutrition calculation, cross-reference cascades) run synchronously via `perform_now`. Solid Queue is configured (`config/queue.yml`) and runs inside Puma via `plugin :solid_queue` — no separate process needed. Switch to `perform_later` when synchronous becomes too slow. Job classes:
- `RecipeNutritionJob` — recalculates a recipe's `nutrition_data` json from its ingredients
- `CascadeNutritionJob` — recalculates nutrition for all recipes that reference a given recipe (triggered after a recipe's nutrition changes)

## Lint Command

```bash
rake lint
```

Runs RuboCop on all Ruby files. Configuration is in `.rubocop.yml`. The default `rake` task runs both lint and test. CI also runs `bundle exec rubocop` before tests.

## Test Command

```bash
rake test
```

Runs all tests in `test/` via Minitest.

```bash
ruby -Itest test/controllers/recipes_controller_test.rb              # single file
ruby -Itest test/models/recipe_test.rb -n test_requires_title        # single test method
```

Test layout: `test/controllers/`, `test/models/`, `test/services/`, `test/jobs/`, `test/integration/`, plus top-level parser unit tests. `test/test_helper.rb` provides `create_kitchen_and_user` (sets `@kitchen`, `@user`, and tenant), `log_in` (logs in `@user` via dev login), and `kitchen_slug` for controller tests. OmniAuth test mode is enabled globally.

## Dev Server

```bash
bin/dev
```

Starts Puma on port 3030, bound to `0.0.0.0` (LAN-accessible via `config/boot.rb`). This is the only dev server — there is no static site server.

## Deployment

Docker image built by GitHub Actions on push to `main`, pushed to `ghcr.io/chris-biagini/familyrecipes`. Tagged with `latest` and the git SHA.

**On the server:**
```bash
docker compose pull && docker compose up -d
```

The container entrypoint runs `db:prepare` and `db:seed` automatically. Health check at `/up` is ready for container orchestration.

**Local Docker testing:**
```bash
docker build -t familyrecipes:test .
```

See `docker-compose.example.yml` for a reference deployment configuration. No external database needed — SQLite files are stored in a Docker volume mounted at `/app/storage`.

## Routes

All routes live under `/kitchens/:kitchen_slug/` except the landing page (`/`), auth routes (`/auth/:provider/callback`, `/auth/failure`, `/logout`), login (`/login`), dev login (`/dev/login/:id`), and health check (`/up`). Kitchen-scoped routes include recipes (CRUD), ingredients index, groceries (`show`, `state`, `select`, `check`, `custom_items`, `clear`, `quick_bites`), and nutrition entries (`POST`/`DELETE` at `/nutrition/:ingredient_name`). Views use Rails route helpers — `root_path` (landing), `kitchen_root_path` (kitchen homepage), `recipe_path(slug)`, `ingredients_path`, `groceries_path`. `ApplicationController#default_url_options` auto-fills `kitchen_slug` from `current_kitchen`, so most helpers work without explicitly passing it. When adding links, always use the `_path` helpers.

## Architecture

### Two namespaces, no conflict

The Rails app module is `Familyrecipes` (lowercase r); the domain/parser module is `FamilyRecipes` (uppercase R). Different constants, no collision. Parser classes that would collide with ActiveRecord model names (`Recipe`, `Step`, `Ingredient`, `CrossReference`, `QuickBite`) are namespaced under `FamilyRecipes::`. Utility classes without collisions (`LineClassifier`, `RecipeBuilder`, etc.) remain top-level.

### Database

Three SQLite databases. **Primary** with twelve tables: `kitchens`, `users`, `memberships`, `sessions`, `connected_services`, `categories`, `recipes`, `steps`, `ingredients`, `cross_references`, `ingredient_catalog`, `grocery_lists`. Most data tables have a `kitchen_id` FK; `sessions` and `connected_services` belong to `users` directly. **Cable** database stores `solid_cable_messages` for ActionCable pub/sub. **Queue** database stores Solid Queue tables (jobs, executions, processes, etc.). See `db/schema.rb` for the primary schema. Recipes are seeded from `db/seeds/recipes/*.md` via `MarkdownImporter`.

### ActiveRecord Models (`app/models/`)

- `Kitchen` — multi-tenant container; has_many :users (through :memberships), :categories, :recipes, :ingredient_catalog; has_one :grocery_list; `quick_bites_content` text column for Quick Bites source; `member?(user)` checks membership
- `User` — has_many :kitchens (through :memberships), :sessions, :connected_services; email required and unique
- `Session` — database-backed login session; belongs_to :user; stores ip_address, user_agent
- `Current` — `ActiveSupport::CurrentAttributes` with `:session` attribute; delegates `:user` to session
- `ConnectedService` — OAuth identity (provider + uid); belongs_to :user; unique on [provider, uid]
- `Membership` — joins User to Kitchen; `role` column (default: "member") for future use
- `Category` — has_many :recipes, ordered by position, auto-generates slug
- `Recipe` — belongs_to :kitchen and :category, has_many :steps (ordered), has_many :ingredients (through steps), has_many :cross_references (through steps), has_many :inbound_cross_references; `referencing_recipes` derives from CrossReference joins
- `Step` — belongs_to :recipe, has_many :ingredients (ordered)
- `Ingredient` — belongs_to :step
- `CrossReference` — AR model for `@[Recipe]` links within steps; stores target_recipe, multiplier, prep_note, position
- `IngredientCatalog` — one row per ingredient with FDA-label nutrients, density, portions, and aisle; supports an overlay model where seed entries are global (`kitchen_id: nil`) and kitchens can add overrides. `lookup_for(kitchen)` merges global + kitchen entries with kitchen taking precedence. Seeded from `ingredient-catalog.yaml`. Used by `RecipeNutritionJob` and `ShoppingListBuilder`
- `GroceryList` — one per kitchen; json `state` column stores `selected_recipes`, `selected_quick_bites`, `custom_items`, `checked_off`; integer `version` counter for optimistic sync via ActionCable

### Controllers (`app/controllers/`)

All controllers are thin — load from ActiveRecord, pass to views. All queries MUST go through `current_kitchen` (e.g., `current_kitchen.recipes.find_by!`). Never use unscoped model queries like `Recipe.find_by` — that crosses kitchen boundaries.

- `ApplicationController` — includes `Authentication` concern; provides `current_user`, `current_kitchen`, `logged_in?` helpers; `allow_unauthenticated_access` makes all pages public by default; `require_membership` guards write endpoints
- `LandingController#show` — root page listing available kitchens
- `DevSessionsController` — dev/test-only session login (`/dev/login/:id`) and logout; uses `start_new_session_for`/`terminate_session` from Authentication concern
- `OmniauthCallbacksController` — handles OmniAuth callbacks (`/auth/:provider/callback`); finds or creates user via ConnectedService, starts database-backed session
- `HomepageController#show` — categories with eager-loaded recipes, site config from `Rails.configuration.site` (loaded from `config/site.yml`)
- `RecipesController` — `show` uses the "parsed-recipe bridge" pattern (see below); `create`/`update`/`destroy` are editor endpoints guarded by `require_membership`, using `MarkdownValidator` and `MarkdownImporter`
- `IngredientsController#index` — all ingredients grouped by canonical name with recipe links and nutrition status badges
- `NutritionEntriesController` — `upsert`/`destroy` endpoints for web-based nutrition editing via the ingredients page; parses label text with `NutritionLabelParser`, recalculates affected recipes; guarded by `require_membership`
- `GroceriesController` — `show` renders recipe/quick-bite selectors; `state` returns JSON shopping list built by `ShoppingListBuilder`; `select`, `check`, `update_custom_items`, `clear` mutate `GroceryList` state and broadcast via ActionCable; `update_quick_bites` edits `Kitchen#quick_bites_content` directly
- `SessionsController#new` — login page at `/login`

### Parse-on-save architecture

The parser runs only on the write path (`MarkdownImporter`). The database is the complete source of truth for rendering: `Step#processed_instructions` stores scalable number markup, `CrossReference` records store interleaved recipe links, and `Recipe#nutrition_data` stores pre-computed nutrition as json. Views render entirely from AR data.

### Real-time sync (ActionCable)

Grocery list state syncs across browser tabs/devices via ActionCable backed by Solid Cable (separate SQLite database for pub/sub). `GroceryListChannel` broadcasts version numbers on state changes; clients poll for fresh state when their version is stale.

### Parser / Domain Classes (`lib/familyrecipes/`)

These are the import engine and render-time helpers. Loaded via `config/initializers/familyrecipes.rb` (not Zeitwerk-autoloaded).

- `FamilyRecipes::Recipe` — parses markdown into structured data (title, description, front matter, steps, footer)
- `FamilyRecipes::Step` — a recipe step containing a tldr summary, ingredients list, and instructions
- `FamilyRecipes::Ingredient` — individual ingredient with name, quantity, and prep note
- `FamilyRecipes::CrossReference` — a reference from one recipe to another (e.g., `@[Pizza Dough]`), renders as a link
- `FamilyRecipes::QuickBite` — simple recipe from Quick Bites.md (name and ingredients only)
- `LineClassifier` — classifies raw recipe text lines into typed tokens
- `RecipeBuilder` — consumes LineTokens and produces a structured document hash
- `IngredientParser` — parses ingredient line text into structured data; detects cross-references
- `IngredientAggregator` — sums ingredient quantities by unit for grocery list display
- `ScalableNumberPreprocessor` — wraps numbers in `<span class="scalable">` tags for client-side scaling
- `NutritionCalculator` — calculates nutrition facts; used by `RecipeNutritionJob` at save time
- `NutritionEntryHelpers` — shared helpers for nutrition entry tool
- `BuildValidator` — validates cross-references, ingredients, and nutrition data
- `Inflector` — pluralization/singularization for ingredient canonicalization
- `VulgarFractions` — converts decimal quantities to Unicode vulgar fractions (½, ¾, etc.)
- `Quantity` — immutable `Data.define` value object (value + unit)

### Services (`app/services/`)

- `MarkdownImporter` — bridges parser and database: parses markdown, upserts Recipe/Step/Ingredient/CrossReference rows. Requires `kitchen:` keyword argument. Used by `db/seeds.rb` and the recipe editor.
- `CrossReferenceUpdater` — updates `@[Title]` cross-references when recipes are renamed or deleted. `rename_references` requires `kitchen:` keyword; `strip_references` gets kitchen from the recipe.
- `MarkdownValidator` — validates markdown source before import; checks for blank content, missing Category front matter, and at least one step. Used by `RecipesController` for editor input validation.
- `NutritionLabelParser` — parses plaintext FDA-style nutrition labels into structured data (nutrients, density, portions). `Result` is a `Data.define` with `success?` predicate. Used by `NutritionEntriesController`.
- `ShoppingListBuilder` — builds aisle-organized shopping list from selected recipes/quick bites; uses `IngredientCatalog` for aisle lookup and `IngredientAggregator`-style quantity merging. Used by `GroceriesController#state`.

### Helpers (`app/helpers/`)

- `RecipesHelper` — view helpers for rendering recipe content: `render_markdown(text)`, `scalable_instructions(text)` (wraps numbers in scalable spans then renders), `format_yield_line(text)`, `format_yield_with_unit(text, singular, plural)`. Used in recipe views for all markdown-to-HTML conversion.

### Views (`app/views/`)

```
layouts/application.html.erb    ← doctype, meta, Propshaft asset tags, nav, yield
shared/_nav.html.erb            ← Home, Index, Groceries links
landing/show.html.erb           ← kitchen listing (root page)
homepage/show.html.erb          ← category TOC + recipe listings
recipes/show.html.erb           ← recipe page (steps, ingredients, nutrition)
recipes/_step.html.erb          ← step partial with ingredients and cross-references
recipes/_nutrition_table.html.erb ← FDA-style nutrition facts
ingredients/index.html.erb      ← alphabetical ingredient index with nutrition status badges and editor dialog
sessions/new.html.erb           ← login page
groceries/show.html.erb         ← recipe/quick-bite selectors, server-driven shopping list via JS
```

Views use `content_for` blocks for page-specific titles, head tags, body attributes, and scripts. Cross-references are rendered using duck typing (`respond_to?(:target_slug)`) per project conventions. Edit buttons and editor dialogs are wrapped in `current_kitchen.member?(current_user)` checks — read-only visitors see no edit UI.

### Assets (Propshaft)

Propshaft serves fingerprinted assets from `app/assets/`. No build step, no bundling, no Node.

- `app/assets/stylesheets/` — `style.css`, `groceries.css`
- `app/assets/javascripts/` — `recipe-state-manager.js`, `recipe-editor.js`, `groceries.js`, `nutrition-editor.js`, `notify.js`, `wake-lock.js`
- `app/assets/images/` — favicons

Views use `stylesheet_link_tag`, `javascript_include_tag`, `asset_path`.

### Data Files

- `config/site.yml` — site identity (title, homepage heading/subtitle, GitHub URL); loaded as `Rails.configuration.site` via `config/initializers/site_config.rb`
- `db/seeds/resources/ingredient-catalog.yaml` — merged ingredient reference data: nutrition facts, density, portions, aisle mappings, and sources; seeded into `ingredient_catalog` table during `db:seed`

### Editor dialogs

`recipe-editor.js` is a data-driven multi-dialog handler. It finds all `.editor-dialog` elements and configures each via data attributes (`data-editor-open`, `data-editor-url`, `data-editor-method`, `data-editor-on-success`, `data-editor-body-key`). To add a new editor dialog, create a `<dialog class="editor-dialog">` with the right data attributes — no JS changes needed. See `recipes/_editor_dialog.html.erb` and `groceries/show.html.erb` for examples.

### Design History

`docs/plans/` contains dated design documents (`*-design.md`) and implementation plans (`*-plan.md`) for major features and architectural decisions. Files are date-prefixed (e.g., `2026-02-23-web-nutrition-editor-design.md`). Consult these when working on related features to understand past decisions.

## Recipe Format

Recipes are plain text files using this markdown structure:

```
# Recipe Title

Optional description line.

Category: Bread
Makes: 12 rolls
Serves: 4

## Step Name (short summary)

- Ingredient name, quantity: prep note
- Another ingredient
- @[Different Recipe], 2: Recipe cross-reference, with optional quantity and prep note.

Instructions for this step as prose.

## Another Step

- More ingredients

More instructions.

---

Optional footer content (notes, source, etc.)
```

**Ingredient syntax**: `- Name, Quantity: Prep note` where quantity and prep note are optional. Examples:
- `- Eggs, 4: Lightly scrambled.`
- `- Salt`
- `- Garlic, 4 cloves`

**Front matter**: Structured `Key: value` lines between the description and first step. Parsed by `LineClassifier` as `:front_matter` tokens and consumed by `RecipeBuilder#parse_front_matter`.
- **Category** (required) — must match the recipe's subdirectory name. Build error if missing or mismatched.
- **Makes** (optional) — `Makes: <number> <unit noun>`. Unit noun required when present. Represents countable output (e.g., `Makes: 30 gougères`).
- **Serves** (optional) — `Serves: <number>`. People count only, no unit noun.
- A recipe can have both Makes and Serves, just one, or neither (Category is always required).
- `NutritionCalculator` uses Serves (preferred) or Makes quantity for per-serving nutrition. `Recipe` exposes `makes_quantity` and `makes_unit_noun` for the parsed components.
- In HTML, front matter renders as an inline metadata line: `Category · Makes X · Serves Y` (class `recipe-meta`), with the category linking to its homepage section.

**Recipe categories** are derived from directory names under `db/seeds/recipes/` (e.g., `db/seeds/recipes/Bread/` → category "Bread") and validated against the `Category:` front matter field. To add a new category, create a new subdirectory.

## Quick Bites

Quick Bites are "grocery bundles" (not recipes) — simple name + ingredient lists for quick shopping. They live on the **groceries page**, not the homepage. Source format in `db/seeds/recipes/Quick Bites.md`:
```
## Category Name
  - Recipe Name: Ingredient1, Ingredient2
```
At seed time, the file content is stored in `Kitchen#quick_bites_content` and is web-editable via a dialog on the groceries page. `FamilyRecipes.parse_quick_bites_content(string)` parses the content.

## Nutrition Data

Nutrition data uses a **density-first model** stored in `db/seeds/resources/ingredient-catalog.yaml`. Each entry has:

```yaml
Flour (all-purpose):
  nutrients:
    basis_grams: 30.0        # gram weight these nutrient values are based on
    calories: 110.0           # 11 FDA-label nutrients follow
    fat: 0.0
    # ... (saturated_fat, trans_fat, cholesterol, sodium, carbs, fiber,
    #       total_sugars, added_sugars, protein)
  density:                    # optional — enables volume unit resolution
    grams: 30.0
    volume: 0.25
    unit: cup
  portions:                   # optional — non-volume named portions only
    stick: 113.0              # e.g., "1 stick" = 113g
    ~unitless: 50             # bare count (e.g., "Eggs, 3")
  sources:                    # provenance metadata (array of typed objects)
    - type: usda              # usda | label | other
      dataset: SR Legacy      # FDC dataset name
      fdc_id: 168913          # FoodData Central ID
      description: "Wheat flour, white, all-purpose, enriched, unbleached"
```

**Key principles:**
- `basis_grams` is the gram weight the nutrient values correspond to (not necessarily 100g)
- Volume units (cup, tbsp, tsp) are **derived from `density` at runtime** — never stored as portions
- `portions` only holds non-volume units like `stick`, `~unitless`, `slice`, etc.
- `NutritionCalculator` resolves units in order: weight > named portion > density-derived volume

**Entry tool:**

```bash
bin/nutrition "Cream cheese"   # Enter/edit data (USDA-first or manual)
bin/nutrition --missing         # Report + batch iterate missing ingredients
bin/nutrition --manual "Flour"  # Force manual entry from package labels
```

`bin/nutrition` auto-detects `USDA_API_KEY` (from `.env` or environment): when present, it searches the USDA SR Legacy dataset first and falls back to manual entry; when absent, it defaults to manual entry from package labels. Existing entries open in an edit menu for surgical fixes (e.g., adding missing portions). Requires `USDA_API_KEY` for USDA mode (free at https://fdc.nal.usda.gov/api-key-signup).

During `db:seed`, `BuildValidator` checks that all recipe ingredients have entries in the ingredient catalog and prints warnings for any that are missing.
