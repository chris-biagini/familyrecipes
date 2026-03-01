# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Rails 8 app backed by SQLite with multi-tenant "Kitchen" support and trusted-header authentication (Authelia/Caddy in production, `DevSessionsController` in dev/test). Two-database architecture: primary (app data), cable (Solid Cable pub/sub). Eventually shipping as a Docker image for homelab installs and a hosted copy.

## Design Philosophy

- Your goal is a high-quality, well-crafted user experience.
- Improve the end product. Make it delightful, charming, and fun.
- Default to simple UI. We can add complexity when it's necessary.
- Always feel free to challenge assumptions, misconceptions, and poor design decisions.
- Suggest any quality-of-life, performance, or feature improvements that come to mind.
- Let's walk before we run. Don't solve scale problems I don't have.
- Always use the superpowers skill when getting ready to write code or build a new feature.

## Architectural comments — every file tells its own story

Class-level and module-level comments are the primary carrier of architectural context in this codebase. CLAUDE.md provides a map; the comments provide the territory. When you need to understand a class's role, read its header comment first.

### When to write them

Every Ruby class/module and every JavaScript controller/utility gets a header comment explaining its **role**, **key collaborators**, and **non-obvious constraints**. Add one when creating a new file. Update it when a file's responsibilities change.

### What they sound like

Plain prose. 2–5 lines. Answer: *what role does this play?*, *who does it talk to?*, and *why is it this way?*

```ruby
# The sole write path for getting recipes into the database. Parses Markdown
# through the FamilyRecipes parser pipeline, then upserts the Recipe and its
# Steps, Ingredients, and CrossReferences in a transaction.
#
# Kitchen-scoped (requires kitchen: keyword) and idempotent — db:seed
# calls this repeatedly. Views never call the parser; they render from
# stored ActiveRecord data exclusively.
class MarkdownImporter
```

### What they don't sound like

Never restate the class name, method name, or what the code obviously does. The general comment rules in "Ruby code conventions" apply here too — if a comment says `# The Recipe model` or `# Controller for recipes`, delete it.

### Keeping them honest

Header comments are code. When you change a class's responsibilities, update its comment in the same commit. A stale comment is worse than no comment — it's a lie that the next reader (human or AI) will trust.

## Recipe source files

- Recipe source files are Markdown. They should read naturally in plaintext, as if written for a person, not a parser. Some custom syntax is necessary but should be limited.
- Source files follow a strict, consistent format to keep parsing reliable.

## HTML, CSS, and JavaScript

### XSS prevention — trust Rails, distrust `.html_safe`

A strict Content Security Policy is enforced (`config/initializers/content_security_policy.rb`). No inline styles, no external resources. If you need to add any of these, update the CSP initializer first.

Rails auto-escapes all `<%= %>` output. The **only** XSS vectors are `.html_safe`, `raw()`, and rendering engines (like Redcarpet) whose output is marked safe. Rules:
- **Never** call `.html_safe` on a string that interpolates user content without first escaping it via `ERB::Util.html_escape`.
- **Never** use `raw()` on user content.
- When building HTML strings in Ruby (helpers, lib classes), escape every user-derived value with `ERB::Util.html_escape` before interpolation.
- In JavaScript, use `textContent` / `createTextNode` for user content — never `innerHTML`.
- The Redcarpet renderer uses `escape_html: true`. Do not remove this option.
- `rake lint:html_safe` audits all `.html_safe` and `raw()` calls. Run it before adding new ones.

Everywhere: use semantic HTML wherever possible and appropriate for the content.
Avoid littering the DOM with more `<div>`s than needed. Don't use a `<div>` when a semantic tag will do.

Recipes:
- Recipes are **documents first**. They are marked-up text that a browser can render, not an app that happens to contain text.
- CSS and JS are progressive enhancements. Every recipe page must be readable and functional with both disabled.
- JavaScript is used sparingly and only for optional features (scaling, state preservation, cross-off). These are guilty indulgences—they must not interfere with the document nature of the page.

Elsewhere (home page, ingredients editor, menu page, groceries page): the mandate here is looser.
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

When appending transformed items to an existing collection, use `concat` + `map` — not `each` + `<<`:
```ruby
# WRONG
custom.each { |item| list << { name: item, amounts: [] } }

# RIGHT
list.concat(custom.map { |item| { name: item, amounts: [] } })
```

### Method design

- Methods should be ≤ 5 lines. Extract smaller methods with descriptive names instead of adding comments.
- NEVER use explicit `return` at the end of a method. Ruby returns the last expression implicitly.
- Use guard clauses and early returns to flatten conditionals. Never nest more than 2 levels.
- Use postfix `if`/`unless` for single-line expressions: `return if list.empty?`
- Use `unless` for negative conditions. Never use `unless` with `else`.
- Use `until` instead of `while !`. When the negated `until` form has compound conditions that are harder to read, `while` is fine.
- Prefer `size` over `length` everywhere (arrays, strings, hashes). `length` is Java/Python; `size` is Ruby.
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

- Use duck typing. Never check `is_a?` or `.class` for domain objects — call the method or use `respond_to?`. Type checks are acceptable at system boundaries (validating parsed data, external input).
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
- Prefer `map` over `collect`, `select` over `find_all`, `key?` over `has_key?`.

### Comments — LLMs get this wrong constantly

Comments that narrate code are the #1 tell of LLM-generated Ruby. This is a hard rule:

- **Never** write a comment that restates the method name, class name, or what the code obviously does.
- **Never** write `# ClassName` or `# ClassName class` above a class definition.
- **Do** add comments that explain *why* — business rules, non-obvious constraints, or links to external references.
- If code needs a comment explaining *what*, extract a method with a descriptive name instead.
- Architectural header comments are covered in "Architectural comments" above — read that section.

```ruby
# WRONG — every one of these restates the obvious
# RecipeBuilder class
class RecipeBuilder

  # Get current token without advancing
  def peek

  # Parse the title
  def parse_title

  # Check if we've reached the end
  def at_end?

# RIGHT — no comment needed, the names say it all
class RecipeBuilder
  def peek
  def parse_title
  def at_end?

# RIGHT — explains WHY, not WHAT
# Miscellaneous defaults to last unless explicitly ordered
return [2, 0] if aisle == 'Miscellaneous'
```

### Views — keep logic out of templates

Extract anything beyond simple conditionals and loops into helper methods. Views should render data, not compute it.

## Workflow Preferences

### Worktree cleanup — use the wrapper script
When a session runs inside a worktree, `git worktree remove` deletes the CWD and bricks the Bash tool for the rest of the session. **Always use the wrapper script** which `cd`s to the repo root before removing:
```bash
bin/worktree-remove <name>              # e.g., bin/worktree-remove my-feature
bin/worktree-remove .claude/worktrees/<name>  # full path also works
```
**Never run `git worktree remove` directly.** The wrapper exists because the "cd first" convention was forgotten repeatedly.

### Screenshots and Playwright
Save screenshots and Playwright output to `~/screenshots/`, not inside the repo. When using browser tools, pass filenames like `/home/claude/screenshots/my-screenshot.png`. The `.gitignore` catches `.playwright-mcp/` and `*.png` as a safety net, but keep them out of the repo directory entirely.

### Data.define and Rails JSON serialization
`Data.define` classes with custom `to_json` must also define `as_json` — see `Quantity` in `lib/familyrecipes/quantity.rb` for the pattern and explanation.

### Stale server PID
If `bin/dev` fails with "A server is already running", kill the process and remove the PID file:
```bash
pkill -f puma; rm -f tmp/pids/server.pid
```

### Server restart after gem, concern, or lib changes
Adding gems, creating new files in `app/controllers/concerns/`, or modifying files in `lib/familyrecipes/` requires restarting Puma. Domain classes in `lib/` are loaded once at boot via an initializer — they do not hot-reload. Run `pkill -f puma; rm -f tmp/pids/server.pid` then `bin/dev`. If you see "undefined method" errors for methods that exist in source, a stale server is the likely cause.

### GitHub Issues
If I mention a GitHub issue (e.g., "#99"), review it and plan a fix. Close it via the commit message once confirmed.

### Commit timestamp privacy
A post-commit hook (`.git/hooks/post-commit`) rewrites commit timestamps for privacy. See `docs/plans/2026-02-23-commit-privacy-design.md` for details.

## Database Setup

Ruby 3.2+ and SQLite3 are required.

```bash
bundle install
rails db:create db:migrate db:seed
```

`db:seed` imports recipes from `db/seeds/recipes/` via `MarkdownImporter` and loads Quick Bites content. Idempotent — safe to re-run.

## Lint Command

```bash
rake lint
```

Runs RuboCop on all Ruby files. Configuration is in `.rubocop.yml`. Plugins: `rubocop-rails`, `rubocop-performance`, `rubocop-minitest`. The default `rake` task runs both lint and test. Always use `bundle exec rubocop` (not bare `rubocop`) — the plugins are Bundler-managed and won't load without it.

`rake lint:html_safe` is a separate audit that checks `.html_safe` and `raw()` calls against `config/html_safe_allowlist.yml`. The allowlist uses `file:line_number` keys — update it whenever edits shift line numbers in files containing `.html_safe` calls.

### RuboCop metric thresholds

Metric thresholds in `.rubocop.yml` are **aspirational** — tighter than what all code currently meets. Methods/classes that exceed them have inline `# rubocop:disable` comments. When writing new code, respect the thresholds. When modifying existing code with a disable, try to refactor below the threshold and remove the disable.

## Test Command

```bash
rake test
```

Runs all tests in `test/` via Minitest.

```bash
ruby -Itest test/controllers/recipes_controller_test.rb              # single file
ruby -Itest test/models/recipe_test.rb -n test_requires_title        # single test method
```

See `test/test_helper.rb` for test setup helpers (`create_kitchen_and_user`, `log_in`, `kitchen_slug`) and the two test hierarchy conventions.

## Dev Server

```bash
bin/dev
```

Starts Puma on port 3030, bound to `0.0.0.0` (LAN-accessible via `config/boot.rb`). This is the only dev server — there is no static site server.

## Deployment

Docker image built by GitHub Actions on push to `main`, pushed to `ghcr.io/chris-biagini/familyrecipes`. Tagged with `latest` and the git SHA. Two-stage CI: `test.yml` runs lint + tests on every push/PR to `main`; `docker.yml` only builds the image after tests pass.

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

Set `ALLOWED_HOSTS` (comma-separated domains) to enable DNS rebinding protection in production. Omit to allow all hosts. See `.env.example` for all environment variables.

**Cloudflare cache purge:** After deploying changes to non-fingerprinted static files (error pages, icons, `robots.txt`), purge Cloudflare's edge cache. Fingerprinted assets (`/assets/*`) self-bust and don't need purging. The service worker and manifest are served via Rails with `no-cache` headers, so Cloudflare revalidates them automatically.
```bash
curl -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"purge_everything":true}'
```

## Routes

Routes use an optional `(/kitchens/:kitchen_slug)` scope — see `config/routes.rb` for the full routing table. Key conventions:

- `default_url_options` auto-injects `kitchen_slug` when the request arrived via a scoped URL — all `_path` helpers adapt automatically. Always use `_path` helpers when adding links.
- Use `home_path` (not `kitchen_root_path`) for homepage links — it returns `root_path` or `kitchen_root_path` depending on mode.
- `MealPlan` (one row per kitchen) backs both the menu and groceries pages.

## Architecture

Every class has an architectural header comment explaining its role, collaborators, and constraints. Read them first — this section covers only cross-cutting concerns that no single file explains.

### Multi-tenant scoping — non-negotiable

All queries MUST go through `current_kitchen` (e.g., `current_kitchen.recipes.find_by!`). Never use unscoped model queries like `Recipe.find_by` — that crosses kitchen boundaries.

### Two namespaces

Rails app module: `Familyrecipes` (lowercase r). Domain parser module: `FamilyRecipes` (uppercase R). Different constants, no collision. See `lib/familyrecipes.rb`.

### Caching layers

Three layers, each opt-in:
- **Cloudflare edge**: static files from `public/` (1 hour). Propshaft-fingerprinted `/assets/*` get far-future headers.
- **Service worker**: assets + icons (cache-first), HTML (network-first with offline fallback). Everything else passes through. See `app/views/pwa/service_worker.js.erb`.
- **Browser HTTP cache**: JSON API → `no-store`. Member-only HTML → `private, no-cache`. Public pages → Rails defaults.

### Icon generation

Run `rake pwa:icons` to regenerate PWA icons from `app/assets/images/favicon.svg` (requires `rsvg-convert` from `librsvg2-bin`).

### Adding a new editor dialog

Use `render layout: 'shared/editor_dialog'` with Stimulus data attributes — no JS needed. For custom content, add a controller listening to editor lifecycle events (see `editor_controller.js`).

### Design History

`docs/plans/` contains dated design documents (`*-design.md`) and implementation plans (`*-plan.md`) for major features and architectural decisions. Consult when working on related features.

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
- `NutritionCalculator` uses Serves (preferred) or Makes quantity for per-serving nutrition.
- In HTML, front matter renders as an inline metadata line: `Category · Makes X · Serves Y` (class `recipe-meta`), with the category linking to its homepage section.

**Recipe categories** are derived from directory names under `db/seeds/recipes/` (e.g., `db/seeds/recipes/Bread/` → category "Bread") and validated against the `Category:` front matter field. To add a new category, create a new subdirectory.

## Quick Bites

Quick Bites are "grocery bundles" (not recipes) — simple name + ingredient lists for quick shopping. They live on the **menu page**, not the homepage. Source format in `db/seeds/recipes/Quick Bites.md`:
```
## Category Name
  - Recipe Name: Ingredient1, Ingredient2
```
Content is stored in `Kitchen#quick_bites_content` and web-editable via a dialog on the menu page. See `FamilyRecipes::QuickBite` for the parsed representation.

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

See `FamilyRecipes::NutritionCalculator` for unit resolution logic and `IngredientCatalog` for the overlay model.

**Entry tool:**

```bash
bin/nutrition "Cream cheese"   # Enter/edit data (USDA-first or manual)
bin/nutrition --missing         # Report + batch iterate missing ingredients
bin/nutrition --manual "Flour"  # Force manual entry from package labels
```

`bin/nutrition` auto-detects `USDA_API_KEY` (from `.env` or environment): when present, it searches the USDA SR Legacy dataset first and falls back to manual entry; when absent, it defaults to manual entry from package labels. Existing entries open in an edit menu for surgical fixes (e.g., adding missing portions). Requires `USDA_API_KEY` for USDA mode (free at https://fdc.nal.usda.gov/api-key-signup).
