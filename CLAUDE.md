# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Design Philosophy

Your goal is a high-quality, well-crafted user experience. Improve the end product. Make it delightful, charming, and fun. Finish the back of the cabinet even though no one will see it. Always feel free to challenge assumptions, misconceptions, and poor design decisions. Be as opinionated as this document and push back on my ideas when you need to. Suggest any quality-of-life, performance, or feature improvements that come to mind. Always use the superpowers skill and plan mode when getting ready to write code or build a new feature. 

This is a fully dynamic Rails 8 app backed by PostgreSQL. All pages render live from the database — there is no static site generator. Next milestones: web-based recipe editing, and Docker packaging for homelab deployment. Don't prematurely optimize, but keep these goals in mind when planning.

### Visual language

The visual identity evokes **red-checked tablecloths** and **mid-century cookbooks** — the `<main>` content card is a cookbook page; the gingham background is the tablecloth peeking out around it. When designing new UI elements, ask: would this feel at home in a well-loved cookbook from the 1960s that somehow learned a few new tricks?

### Source files

- Recipe source files are Markdown. They should read naturally in plaintext, as if written for a person, not a parser. Some custom syntax is necessary but should be limited.
- Source files follow a strict, consistent format to keep parsing reliable.

### HTML, CSS, and JavaScript

- Recipes are **documents first**. They are marked-up text that a browser can render, not an app that happens to contain text.
- CSS and JS are progressive enhancements. Every page must be readable and functional with both disabled.
- JavaScript is used sparingly and only for optional features (scaling, state preservation, cross-off). These are guilty indulgences—they must not interfere with the document nature of the page.
- Prefer native HTML elements. Introduce as close to zero custom UI as possible.
- No third-party libraries, scripts, stylesheets, or fonts unless clearly the best solution—and ask before adding any.

### The groceries page is the exception

The groceries page (`app/views/groceries/show.html.erb`) has a looser mandate. Slightly heavier JavaScript is more permissible there. Custom UI is ok. Third-party dependencies should still be avoided, but the overall restraint is relaxed.

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
- Comments explain *why* — business rules, non-obvious constraints, or links to external references.

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

### GitHub Issues
If I mention a GitHub issue (e.g., "#99"), review it and plan a fix. Close it via the commit message once confirmed.

## Database Setup

```bash
rails db:create db:migrate db:seed
```

PostgreSQL is required. `db:seed` imports all markdown files from `recipes/` into the database via `MarkdownImporter`. The seed is idempotent — safe to re-run. Dependencies are managed via `Gemfile` (Ruby 3.2+, Bundler, and `bundle install` required).

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

## Dev Server

```bash
bin/dev
```

Starts Puma on port 3030, bound to `0.0.0.0` (LAN-accessible via `config/boot.rb`). This is the only dev server — there is no static site server.

## Deployment

The `main` branch still deploys a static site to **GitHub Pages** at `biaginifamily.recipes` via `.github/workflows/deploy.yml`. The `rails-development` branch is the dynamic Rails app — deployment infrastructure (Docker, CI updates) is not yet in place. Do not merge `rails-development` to `main` until the deployment story is resolved.

## Routes

Views use Rails route helpers (`root_path`, `recipe_path(slug)`, `ingredients_path`, `groceries_path`) — no `<base>` tags or relative paths. When adding links, always use the `_path` helpers.

## Architecture

### Two namespaces, no conflict

The Rails app module is `Familyrecipes` (lowercase r); the domain/parser module is `FamilyRecipes` (uppercase R). Different constants, no collision. Parser classes that would collide with ActiveRecord model names (`Recipe`, `Step`, `Ingredient`, `CrossReference`, `QuickBite`) are namespaced under `FamilyRecipes::`. Utility classes without collisions (`LineClassifier`, `RecipeBuilder`, etc.) remain top-level.

### Database

PostgreSQL with five tables: `categories`, `recipes`, `steps`, `ingredients`, `recipe_dependencies`. See `db/schema.rb` for the full schema. Recipes are seeded from `recipes/*.md` via `MarkdownImporter`.

### ActiveRecord Models (`app/models/`)

- `Category` — has_many :recipes, ordered by position, auto-generates slug
- `Recipe` — belongs_to :category, has_many :steps (ordered), has_many :ingredients (through steps), tracks outbound/inbound recipe dependencies
- `Step` — belongs_to :recipe, has_many :ingredients (ordered)
- `Ingredient` — belongs_to :step
- `RecipeDependency` — join table tracking which recipes reference which (source → target)

### Controllers (`app/controllers/`)

All controllers are thin — load from ActiveRecord, pass to views:

- `HomepageController#show` — categories with eager-loaded recipes, site config from YAML
- `RecipesController#show` — uses the "parsed-recipe bridge" pattern (see below)
- `IngredientsController#index` — all ingredients grouped by canonical name with recipe links
- `GroceriesController#show` — recipe selector with ingredient JSON, aisle-organized grocery list

### The parsed-recipe bridge

`RecipesController` loads the AR `Recipe` but also re-parses the original markdown via the parser pipeline. This is because the parser produces interleaved ingredient/cross-reference lists, scalable number markup, and nutrition data that would be complex to replicate from structured AR data alone. The AR model stores canonical data; the parser handles rendering concerns. This is intentional for v1 — the editor may change this.

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
- `NutritionCalculator` — calculates nutrition facts from YAML data at render time
- `NutritionEntryHelpers` — shared helpers for nutrition entry tool
- `BuildValidator` — validates cross-references, ingredients, and nutrition data
- `Inflector` — pluralization/singularization for ingredient canonicalization
- `VulgarFractions` — converts decimal quantities to Unicode vulgar fractions (½, ¾, etc.)
- `Quantity` — immutable `Data.define` value object (value + unit)

### Services (`app/services/`)

- `MarkdownImporter` — bridges parser and database: parses markdown, upserts Recipe/Step/Ingredient rows, rebuilds `recipe_dependencies`. Used by `db/seeds.rb` and will be used by the future editor.

### Views (`app/views/`)

```
layouts/application.html.erb    ← doctype, meta, Propshaft asset tags, nav, yield
shared/_nav.html.erb            ← Home, Index, Groceries links
homepage/show.html.erb          ← category TOC + recipe listings
recipes/show.html.erb           ← recipe page (steps, ingredients, nutrition)
recipes/_step.html.erb          ← step partial with ingredients and cross-references
recipes/_nutrition_table.html.erb ← FDA-style nutrition facts
ingredients/index.html.erb      ← alphabetical ingredient index with recipe links
groceries/show.html.erb         ← recipe selector + aisle-organized grocery list
```

Views use `content_for` blocks for page-specific titles, head tags, body attributes, and scripts. Cross-references are rendered using duck typing (`respond_to?(:target_slug)`) per project conventions.

### Assets (Propshaft)

Propshaft serves fingerprinted assets from `app/assets/`. No build step, no bundling, no Node.

- `app/assets/stylesheets/` — `style.css`, `groceries.css`
- `app/assets/javascripts/` — `recipe-state-manager.js`, `groceries.js`, `notify.js`, `wake-lock.js`, `qrcodegen.js`
- `app/assets/images/` — favicons

Views use `stylesheet_link_tag`, `javascript_include_tag`, `asset_path`.

### Data Files (`resources/`)

- `site-config.yaml` — site identity (title, homepage heading/subtitle, GitHub URL)
- `grocery-info.yaml` — ingredient-to-aisle mappings
- `nutrition-data.yaml` — density-first nutrition data (see Nutrition Data section)

### Design History

`docs/plans/` contains dated design documents and implementation plans for major features and architectural decisions.

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

**Recipe categories** are derived from directory names under `recipes/` (e.g., `recipes/Bread/` → category "Bread") and validated against the `Category:` front matter field. To add a new category, create a new subdirectory.

## Quick Bites

`recipes/Quick Bites.md` uses a different format for simple recipes:
```
## Category Name
  - Recipe Name: Ingredient1, Ingredient2
```

## Nutrition Data

Nutrition data uses a **density-first model** stored in `resources/nutrition-data.yaml`. Each entry has:

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
- Volume units (cup, tbsp, tsp) are **derived from `density` at build time** — never stored as portions
- `portions` only holds non-volume units like `stick`, `~unitless`, `slice`, etc.
- `NutritionCalculator` resolves units in order: weight > named portion > density-derived volume

**Entry tool:**

```bash
bin/nutrition "Cream cheese"   # Enter/edit data (USDA-first or manual)
bin/nutrition --missing         # Report + batch iterate missing ingredients
bin/nutrition --manual "Flour"  # Force manual entry from package labels
```

`bin/nutrition` auto-detects `USDA_API_KEY` (from `.env` or environment): when present, it searches the USDA SR Legacy dataset first and falls back to manual entry; when absent, it defaults to manual entry from package labels. Existing entries open in an edit menu for surgical fixes (e.g., adding missing portions). Requires `USDA_API_KEY` for USDA mode (free at https://fdc.nal.usda.gov/api-key-signup).

During `db:seed`, `BuildValidator` checks that all recipe ingredients have nutrition data and prints warnings for any that are missing.
