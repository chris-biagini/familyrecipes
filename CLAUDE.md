# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a fully dynamic Rails 8 app backed by SQLite with multi-tenant "Kitchen" support. Two-database architecture: primary (app data), cable (Solid Cable pub/sub). Trusted-header authentication: in production, Authelia/Caddy sets `Remote-User`/`Remote-Email`/`Remote-Name` headers; the app reads them to find-or-create users and establish sessions. In dev/test, `DevSessionsController` provides direct login. No OmniAuth, no passwords.
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

### XSS prevention — trust Rails, distrust `.html_safe`

A strict Content Security Policy is enforced (`config/initializers/content_security_policy.rb`). All directives use `'self'` only, plus `ws:`/`wss:` for ActionCable in `connect-src`. A nonce generator (`request.session.id`) is configured for `script-src` — importmap-rails uses this to permit its inline module-loading script. No inline styles, no external resources are allowed. If you need to add any of these, update the CSP initializer first.

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
`Data.define` classes with custom `to_json` must also define `as_json` — ActiveSupport calls `as_json` (not `to_json`) on nested objects. See `Quantity` for the pattern. Without both, value objects serialize as hashes instead of the intended format when embedded in arrays/hashes passed to `.to_json`.

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
A post-commit hook (`.git/hooks/post-commit`) rewrites commit timestamps for privacy. The hook replaces time-of-day with synthetic UTC timestamps while preserving the calendar date and chronological commit order. Since `.git/hooks/` is not tracked by git, the hook must be installed manually on fresh clones. See `docs/plans/2026-02-23-commit-privacy-design.md` for details.

## Database Setup

Ruby 3.2+ and SQLite3 are required. Install dependencies first:

```bash
bundle install
rails db:create db:migrate db:seed
```

Two databases: primary (`storage/production.sqlite3`), cable (`storage/production_cable.sqlite3`). Development/test use parallel files under `storage/`. `db:seed` imports all markdown files from `db/seeds/recipes/` into the database via `MarkdownImporter` and loads ingredient catalog from `db/seeds/resources/ingredient-catalog.yaml`. The seed is idempotent — safe to re-run.

### Background Jobs

Save-time operations (nutrition calculation, cross-reference cascades) run synchronously
via `perform_now`. When this becomes too slow, add Solid Queue (`gem 'solid_queue'`) with
a dedicated database and Puma plugin. Job classes:
- `RecipeNutritionJob` — recalculates a recipe's `nutrition_data` json from its ingredients
- `CascadeNutritionJob` — recalculates nutrition for all recipes that reference a given recipe (triggered after a recipe's nutrition changes)

## Lint Command

```bash
rake lint
```

Runs RuboCop on all Ruby files. Configuration is in `.rubocop.yml`. Plugins: `rubocop-rails`, `rubocop-performance`, `rubocop-minitest`. The default `rake` task runs both lint and test. Always use `bundle exec rubocop` (not bare `rubocop`) — the plugins are Bundler-managed and won't load without it.

`rake lint:html_safe` is a separate audit that checks `.html_safe` and `raw()` calls against `config/html_safe_allowlist.yml`. The allowlist uses `file:line_number` keys — update it whenever edits shift line numbers in files containing `.html_safe` calls.

### RuboCop metric thresholds

Metric thresholds in `.rubocop.yml` are **aspirational** — tighter than what all code currently meets. Methods/classes that exceed them have inline `# rubocop:disable` comments. When writing new code, respect the thresholds. When modifying existing code with a disable, try to refactor below the threshold and remove the disable. The 6 worst offenders are documented in `docs/plans/2026-02-25-rubocop-configuration-design.md`.

## Test Command

```bash
rake test
```

Runs all tests in `test/` via Minitest.

```bash
ruby -Itest test/controllers/recipes_controller_test.rb              # single file
ruby -Itest test/models/recipe_test.rb -n test_requires_title        # single test method
```

Test layout: `test/controllers/`, `test/models/`, `test/services/`, `test/jobs/`, `test/integration/`, `test/channels/`, `test/lib/`, plus top-level parser unit tests. `test/test_helper.rb` provides `create_kitchen_and_user` (sets `@kitchen`, `@user`, and tenant), `log_in` (logs in `@user` via dev login), and `kitchen_slug` for controller tests. **Two test hierarchies:** controller/model/integration tests inherit `ActiveSupport::TestCase`; top-level parser unit tests (`test/recipe_test.rb`, `test/nutrition_calculator_test.rb`, etc.) inherit `Minitest::Test` directly and do NOT have ActiveSupport extensions like `assert_not_*`.

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

## Routes

Routes use an optional `(/kitchens/:kitchen_slug)` scope. When exactly one kitchen exists, URLs are root-level (`/recipes/bagels`, `/ingredients`, `/groceries`). When multiple kitchens exist, URLs are scoped (`/kitchens/:slug/recipes/bagels`). `default_url_options` returns `{ kitchen_slug: }` or `{}` based on whether the request arrived via a scoped URL. Kitchen-scoped routes include recipes (`show`, `create`, `update`, `destroy` — no index/new/edit), ingredients index, groceries (`show`, `state`, `select`, `check`, `custom_items`, `clear`, `quick_bites`, `aisle_order`, `aisle_order_content`), and nutrition entries (`POST`/`DELETE` at `/nutrition/:ingredient_name`). Views use `home_path` (not `kitchen_root_path`) for the homepage link — it returns `root_path` or `kitchen_root_path` depending on mode. Other helpers (`recipe_path`, `ingredients_path`, `groceries_path`) auto-adapt via `default_url_options`. When adding links, always use the `_path` helpers.

## Architecture

### Two namespaces, no conflict

The Rails app module is `Familyrecipes` (lowercase r); the domain/parser module is `FamilyRecipes` (uppercase R). Different constants, no collision. Parser classes that would collide with ActiveRecord model names (`Recipe`, `Step`, `Ingredient`, `CrossReference`, `QuickBite`) are namespaced under `FamilyRecipes::`. Utility classes without collisions (`LineClassifier`, `RecipeBuilder`, etc.) remain top-level.

### Multi-tenant scoping — non-negotiable

All queries MUST go through `current_kitchen` (e.g., `current_kitchen.recipes.find_by!`). Never use unscoped model queries like `Recipe.find_by` — that crosses kitchen boundaries. `Kitchen` is the tenant container; most data tables have a `kitchen_id` FK.

### Parse-on-save architecture

The parser runs only on the write path (`MarkdownImporter`). The database is the complete source of truth for rendering: `Step#processed_instructions` stores scalable number markup, `CrossReference` records store interleaved recipe links, and `Recipe#nutrition_data` stores pre-computed nutrition as json. Views render entirely from AR data.

### Trusted-header authentication

In production behind Authelia/Caddy, `Remote-User`/`Remote-Email`/`Remote-Name` HTTP headers identify users. `ApplicationController#authenticate_from_headers` reads these via `request.env['HTTP_REMOTE_USER']` (not `request.headers` — `Remote-User` collides with the CGI `REMOTE_USER` variable). Subsequent requests authenticate via the session cookie — headers are only read when establishing a new session. In dev/test (no headers), `DevSessionsController` provides direct login at `/dev/login/:id`. No OmniAuth, no passwords, no login page. The session layer (`User`, `Session`, `Membership`, `Authentication` concern) is auth-agnostic — OAuth providers can be re-added later by adding a new "front door" that calls `start_new_session_for`.

When a new user has zero memberships and exactly one Kitchen exists, `auto_join_sole_kitchen` auto-creates the membership.

### Auth gates

Homepage and recipe pages are public reads. Ingredients and groceries pages require membership entirely (`require_membership` on all actions). Write paths on recipes also require membership. In development, `auto_login_in_development` logs in as `User.first` automatically (simulating Authelia); `/logout` sets a `skip_dev_auto_login` cookie to test the logged-out experience. `ActionCable::Connection` identifies users from the session cookie; `GroceryListChannel` checks kitchen membership. See `docs/plans/2026-02-25-dev-auth-optimization-design.md` for the current auth design.

### Real-time sync (ActionCable)

Grocery list state syncs across browser tabs/devices via ActionCable backed by Solid Cable (separate SQLite database for pub/sub). `GroceryListChannel` broadcasts version numbers on state changes; clients poll for fresh state when their version is stale. Connections require authentication (session cookie); subscriptions require kitchen membership.

### PWA & Service Worker

The app is installable as a PWA. `public/service-worker.js` uses runtime caching:
- `/assets/*`: cache-first (Propshaft-fingerprinted, immutable)
- HTML pages: network-first with cache fallback, offline fallback at `public/offline.html`
- Grocery/nutrition API endpoints and `/cable`: skipped (not cached)

The SW skip-list regex covers all grocery and nutrition API routes at both root and kitchen-scoped paths. **When adding new API endpoints**, update the `API_PATTERN` regex in `public/service-worker.js` or they'll be cached as HTML pages.

`public/manifest.json` is static. The grocery shortcut URL (`/groceries`) works with the optional kitchen scope when one kitchen exists.

### Icon generation

PWA icons in `public/icons/` are committed to the repo and served as static files. To regenerate them from `app/assets/images/favicon.svg`, run `rake pwa:icons` (requires `rsvg-convert` from `librsvg2-bin`). Neither CI nor the Docker build generates icons — they come straight from the repo.

### Error pages

Static error pages (`public/404.html`, `public/offline.html`) share `public/error.css` with per-page emoji via body class (`.error-404`, `.error-offline`). Static files in `public/` bypass the Rails CSP middleware, so inline styles and external CSS both work without CSP changes.

### IngredientCatalog overlay model

Seed entries are global (`kitchen_id: nil`); kitchens can add overrides. `lookup_for(kitchen)` merges global + kitchen entries with kitchen taking precedence.

### Hotwire (Stimulus + Turbo)

All client-side JavaScript uses the Hotwire stack: **Stimulus** for behavior, **Turbo Drive** for SPA-like navigation, **Turbo Streams** for server-pushed HTML updates. ES modules are loaded via **importmap-rails** (`config/importmap.rb`) — no Node, no bundler, no build step.

**Stimulus controllers** (`app/javascript/controllers/`):
- `editor_controller` — generic `<dialog>` lifecycle: open, save (PATCH/POST), dirty-check, close. Configurable via Stimulus values (`url`, `method`, `on-success`, `body-key`). Simple dialogs need zero custom JS — just data attributes on the `<dialog>`. Custom dialogs (nutrition editor) dispatch lifecycle events (`editor:collect`, `editor:save`, `editor:modified`, `editor:reset`).
- `nutrition_editor_controller` — hooks into editor lifecycle events for the multi-row nutrition form on the ingredients page.
- `grocery_sync_controller` — ActionCable subscription for grocery list state. Polls for fresh state when version is stale. Preserves checkbox state across Turbo Stream replacements.
- `grocery_ui_controller` — shopping list rendering, recipe/quick-bite selection, custom items, checked items. Communicates with `grocery_sync_controller` via `this.application.getControllerForElementAndIdentifier()`.
- `recipe_state_controller` — recipe page scaling, cross-off, and localStorage state persistence.
- `wake_lock_controller` — Screen Wake Lock API for recipe pages (keeps screen on while cooking).

**Shared utilities** (`app/javascript/utilities/`): `notify.js` (toast notifications), `editor_utils.js` (CSRF token helper), `vulgar_fractions.js` (number display).

**Turbo Drive** is enabled globally for SPA-like page transitions. The progress bar is disabled (`Turbo.config.drive.progressBarDelay = Infinity`) because its inline styles conflict with the strict CSP.

**Turbo Streams** broadcast grocery page content changes (quick bites edits) via `Turbo::StreamsChannel`. The groceries view subscribes with `turbo_stream_from`. When quick bites are saved, the server broadcasts a `replace` targeting `#recipe-selector` with fresh HTML. Grocery list *state* sync (selections, checks) still uses the version-polling ActionCable channel — Turbo Streams handle only content structure changes.

To add a new simple editor dialog, use `render layout: 'shared/editor_dialog'` with a textarea block and Stimulus data attributes — no JS changes needed. For custom content, add a controller that listens for the editor lifecycle events.

### Key conventions

- Domain classes in `lib/familyrecipes/` are loaded via `config/initializers/familyrecipes.rb` (not Zeitwerk-autoloaded).
- Propshaft serves assets from `app/assets/`. importmap-rails handles JS module loading — no build step, no bundling, no Node.
- Views use `content_for` blocks for page-specific titles, head tags, and body attributes.
- Cross-references in views are rendered using duck typing (`respond_to?(:target_slug)`).
- Edit UI is wrapped in `current_kitchen.member?(current_user)` checks — read-only visitors see no edit controls.
- `config/site.yml` holds site identity; loaded as `Rails.configuration.site`.
- `MarkdownImporter` requires `kitchen:` keyword. `CrossReferenceUpdater.rename_references` also requires `kitchen:`.

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
