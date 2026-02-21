# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Design Philosophy

Your goal is a high-quality, well-crafted user experience. Improve the end product. Make it delightful, charming, and fun. Finish the back of the cabinet even though no one will see it. Always feel free to challenge assumptions, misconceptions, and poor design decisions. Be as opinionated as this document and push back on my ideas when you need to. Suggest any quality-of-life, performance, or feature improvements that come to mind. Always use the superpowers skill and plan mode when getting ready to write code or build a new feature. 

Note that I would like to someday start serving this project via Rails, and upgrading it to allow web-based editing of data. I'd also like to someday package it for deployment in Docker for homelab users. Don't prematurely optimize, but keep these goals in mind when planning.  

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

`groceries-template.html.erb` has a looser mandate. Slightly heavier JavaScript is more permissible there. Custom UI is ok. Third-party dependencies should still be avoided, but the overall restraint is relaxed.

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

### GitHub Issues
If I mention a GitHub issue (e.g., "#99"), review it and plan a fix. Close it via the commit message once confirmed.

## Build Command

```bash
bin/generate
```

This parses all recipes, generates HTML files in `output/web/`, and copies static resources. Dependencies are managed via `Gemfile` (Ruby 3.2+, Bundler, and `bundle install` required).

## Lint Command

```bash
rake lint
```

Runs RuboCop on all Ruby files. Configuration is in `.rubocop.yml`. The default `rake` task runs both lint and test. CI also runs `bundle exec rubocop` before tests.

## Test Command

```bash
rake test
```

Runs all tests in `test/` via Minitest. `rake clean` removes the `output/` directory if you need a fresh build.

## Dev Server

```bash
bin/serve [port]
```

WEBrick server (default port 8888) serving `output/web/` with clean/extensionless URLs, matching GitHub Pages behavior. Binds `0.0.0.0` (LAN-accessible). Exits cleanly if port is taken. Typical dev workflow: `bin/generate && bin/serve` (reuse the existing server if it's already running).

## Deployment

The site is hosted on **GitHub Pages** at `biaginifamily.recipes`. Pushing to `main` automatically triggers a build and deploy via GitHub Actions (`.github/workflows/deploy.yml`). The workflow:

1. Runs `bundle exec rubocop` (build fails if linting doesn't pass)
2. Runs `bundle exec rake test` (build fails if tests don't pass)
3. Runs `bin/generate` to build the site
4. Deploys `output/web/` to GitHub Pages

The custom domain is configured in the repo's GitHub Pages settings, not in the workflow file, so forks don't need to modify the workflow.

## URL Portability

All templates use relative paths resolved via an HTML `<base>` tag, so the site works regardless of deployment root (e.g., `biaginifamily.recipes/` or `username.github.io/familyrecipes/`). Root-level pages use `<base href="./">` and subdirectory pages (`index/`, `groceries/`) use `<base href="../">`. When adding new links or asset references in templates, use relative paths (e.g., `style.css`, not `/style.css`).

## Architecture

**Core Classes** (`lib/familyrecipes/`):
- `SiteGenerator` - Orchestrates the full build: parsing, rendering, resource copying, and validation
- `Recipe` - Parses markdown recipe files into structured data (title, description, front matter, steps, footer)
- `Step` - A recipe step containing a tldr summary, ingredients list, and instructions
- `Ingredient` - Individual ingredient with name, quantity, and prep note
- `QuickBite` - Simple recipe from Quick Bites.md (name and ingredients only)
- `LineClassifier` - Classifies raw recipe text lines into typed tokens (title, step header, ingredient, front_matter, etc.)
- `RecipeBuilder` - Consumes LineTokens and produces a structured document hash for Recipe
- `IngredientParser` - Parses ingredient line text into structured data; also detects cross-references
- `IngredientAggregator` - Sums ingredient quantities by unit for grocery list display
- `CrossReference` - A reference from one recipe to another (e.g., `@[Pizza Dough]`), renders as a link
- `ScalableNumberPreprocessor` - Wraps numbers in `<span class="scalable">` tags for client-side scaling
- `NutritionCalculator` - Calculates nutrition facts using density-first data model (nutrients/basis_grams + density)
- `NutritionEntryHelpers` - Shared helpers for nutrition entry: serving size parsing, fractions, singularization
- `PdfGenerator` - Generates PDF output (uses templates in `templates/pdf/`)
- `Inflector` - Pluralization/singularization with irregular forms and uncountables; used for ingredient canonicalization
- `VulgarFractions` - Converts decimal quantities to Unicode vulgar fraction glyphs (½, ¾, etc.)
- `BuildValidator` - Validates cross-references, ingredients, and nutrition data during site generation
- `Quantity` - Immutable `Data.define` value object (value + unit) replacing bare tuples; has JSON serialization

**Data Flow**:
1. `bin/generate` creates a `SiteGenerator` and calls `generate`, then a `PdfGenerator` (requires `typst` CLI; skips gracefully if not installed)
2. `SiteGenerator` reads `.md` files from `recipes/` subdirectories
3. Each file is parsed by `Recipe` class using markdown conventions
4. ERB templates in `templates/web/` render HTML output
5. Static assets from `resources/web/` are copied to output

**Output Pages**:
- Individual recipe pages (from recipe-template.html.erb)
- Homepage with recipes grouped by category (homepage-template.html.erb)
- Ingredient index (index-template.html.erb)
- Grocery list builder (groceries-template.html.erb)

**Shared Partials**:
- `_head.html.erb` - Common HTML head (doctype, meta, base tag, stylesheet, favicon)
- `_nav.html.erb` - Site navigation bar (Home, Index, Groceries)

**Resources**:
- `resources/site-config.yaml` - site identity (title, homepage heading/subtitle, GitHub URL); loaded by `SiteGenerator` and passed to homepage, index, and groceries templates
- `resources/grocery-info.yaml` - ingredient-to-aisle mappings
- `resources/nutrition-data.yaml` - density-first nutrition data (nutrients per basis_grams, density, portions)
- `resources/web/style.css` - main stylesheet; `groceries.css` for the grocery page
- `resources/web/recipe-state-manager.js` - scaling, cross-off, state persistence; `groceries.js` for the grocery page
- `resources/web/` also contains: service worker (`sw.js`), wake lock, notifications, QR codes, 404 page, favicons

**Design History**:
- `docs/plans/` contains dated design documents for major features and architectural decisions

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

During `bin/generate`, the build validates that all recipe ingredients have nutrition data and prints warnings for any that are missing.
