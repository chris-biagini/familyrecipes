# CLAUDE.md

Rails 8 app backed by SQLite with multi-tenant "Kitchen" support and
trusted-header authentication.  Two-database architecture: primary (app data),
cable (Solid Cable pub/sub).  Docker image for homelab installs during
development, eventual move to hosted model with many users.

## Design Philosophy

- Default to simple UI. We can add complexity when it's necessary.
- Challenge assumptions, misconceptions, and poor design decisions.
- Suggest quality-of-life, performance, and feature improvements.
- Let's walk before we run. Don't solve scale problems I don't have.
- We're still early in development, so we are not beholden to legacy code and
  data. It's ok to break compatibility to keep things clean.
- DRY: if you find yourself copying code from elsewhere verbatim, stop and ask
  if you should refactor instead. 

## Ruby Style

Write idiomatic, expressive, opinionated Ruby — not Python or JavaScript
translated into Ruby syntax. Ruby code should read like English.

### Enumerable over imperative loops — this is non-negotiable

NEVER build collections with `each` + an accumulator. Use the right Enumerable
method:

```ruby
# WRONG — Claude's default, and it's unacceptable
result = []
items.each { |item| result << item.name if item.active? }
result

# RIGHT — idiomatic Ruby
items.select(&:active?).map(&:name)
```

Use `map`, `select`/`reject`, `flat_map`, `each_with_object`,
`any?`/`all?`/`none?`, `tally`, `group_by`, `sum`. Always use `&:method_name`
(Symbol#to_proc) when the block just calls one method.

When appending to an existing collection, use `concat` + `map` — not `each` +
`<<`:

```ruby
# WRONG
custom.each { |item| list << { name: item, amounts: [] } }

# RIGHT
list.concat(custom.map { |item| { name: item, amounts: [] } })
```

### Method design

- Methods should be ≤ 5 lines. Extract smaller methods with descriptive names
  instead of adding comments.
- NEVER use explicit `return` at the end of a method. Ruby returns the last
  expression implicitly.
- Use guard clauses and early returns to flatten conditionals. Never nest more
  than 2 levels.
- Use postfix `if`/`unless` for single-line expressions: `return if
  list.empty?`
- Prefer `size` over `length` everywhere. `length` is Java/Python; `size` is
  Ruby.
- Prefer keyword arguments over positional arguments for clarity at call sites.
- Prefer `map` over `collect`, `select` over `find_all`, `key?` over
  `has_key?`.
- Never prefix with `get_` or `is_`. Use `name` not `get_name`. Use `valid?`
  not `is_valid?`.

### Comments — LLMs get this wrong constantly

Comments that narrate code are the #1 tell of LLM-generated Ruby. This is a
hard rule:

- **Never** write a comment that restates the method name, class name, or what
  the code obviously does.
- **Never** write `# ClassName` or `# ClassName class` above a class
  definition.
- **Do** add comments that explain *why* — business rules, non-obvious
  constraints, or links to external references.
- If code needs a comment explaining *what*, extract a method with a
  descriptive name instead.

```ruby
# WRONG — restates what the code does
# Build a recipe from parsed tokens
def build_recipe
# Check if the ingredient is valid
def valid_ingredient?(name)

# RIGHT — the names are clear; no comment needed
def build_recipe
def valid_ingredient?(name)

# RIGHT — explains WHY, not WHAT
# Miscellaneous defaults to last unless explicitly ordered
return [2, 0] if aisle == 'Miscellaneous'
```

## Architectural Comments

To avoid overburdening this file, documentation on architecture is located
primarily in the code itself, next to the classes it describes. 

Every Ruby class/module and every JavaScript controller/utility gets a header
comment explaining its **role**, **key collaborators**, and **non-obvious
constraints**. Plain prose. Short, around 5 lines, with a bulleted list of
collaborators. The comments answer: *what role does this play?*, *who does it
talk to?*, and *why is it this way?* 

This file need only contain a concise map of conventions and workflows.
CLAUDE.md is the map; the comments are the territory. 

Add a header comment when creating a new file. Update comments when
responsibilities change — a stale comment is worse than none. Update CLAUDE.md
when adding new conventions or workflows.

## HTML & Security

A strict CSP is enforced (`config/initializers/content_security_policy.rb`). No
inline styles, no external resources (Google Fonts is the sole exception). Update
the CSP initializer before adding any.

- **Never** call `.html_safe` on a string that interpolates user content
  without first escaping via `ERB::Util.html_escape`.
- **Never** use `raw()` on user content.
- In JavaScript, use `textContent` / `createTextNode` — never `innerHTML`.
- `rake lint:html_safe` audits `.html_safe` and `raw()` calls against
  `config/html_safe_allowlist.yml`. The allowlist uses `file:line_number` keys
— update it whenever edits shift line numbers.
- Use semantic HTML. Recipes are **documents first** — marked-up text, not an
  app that happens to contain text.

## Architecture

Every class has an architectural header comment — read them first. This section
covers only cross-cutting concerns that no single file explains.

**Multi-tenant scoping — non-negotiable.** All queries MUST go through
`current_kitchen` (e.g., `current_kitchen.recipes.find_by!`). Never use
unscoped model queries like `Recipe.find_by`.

**Two namespaces.** Rails app module: `Familyrecipes` (lowercase r). Domain
parser module: `FamilyRecipes` (uppercase R). Different constants, no
collision. Parser pipeline: `LineClassifier` → `RecipeBuilder` →
`FamilyRecipes::Recipe`; `MarkdownImporter` is the sole write-path entry point.

**Routing.** Optional `(/kitchens/:kitchen_slug)` scope:
- One Kitchen → root-level URLs (`/recipes/bagels`)
- Multiple → prefixed (`/kitchens/ours/recipes/bagels`)
- `default_url_options` auto-injects `kitchen_slug` — always use `_path`
  helpers, never hard-code URL strings.
- Use `home_path` (not `kitchen_root_path`) for homepage links.
- `MealPlan` (one row per kitchen) backs both the menu and groceries pages.

**Editor dialogs.** Use `render layout: 'shared/editor_dialog'` with Stimulus
data attributes — no JS needed. For custom content, add a controller listening
to editor lifecycle events.
- Open `<dialog>` elements are protected from Turbo morph via
  `turbo:before-morph-element` in `application.js`.
- `turbo:before-cache` closes all open dialogs before page snapshots.
- Do NOT use `data-turbo-permanent` on dialogs.
- CodeMirror 6 powers syntax-highlighted plaintext editors for both
  recipes and Quick Bites. `ViewPlugin` classifiers in
  `app/javascript/codemirror/` apply `.hl-*` CSS decorations.
  `foldService` provides step block and front matter folding for recipes.
- To add a new plaintext editor type: create a classifier ViewPlugin in
  `codemirror/`, register it in `codemirror/registry.js`, then use
  `plaintext-editor` controller with the registry key as the `classifier` value.
- `ordered_list_editor_controller` is a single parameterized controller for
  both aisle and category list editors.
- **Dual-mode editors** (recipe + Quick Bites) use a coordinator/child pattern:
  `editor_controller` (dialog lifecycle) → `dual_mode_editor_controller`
  (coordinator) → `plaintext_editor_controller` or graphical child controller.
  Coordinator manages mode toggle (persisted in `localStorage`), routes
  lifecycle events to the active child, and handles mode-switch serialization
  via server round-trips (`/parse` and `/serialize` endpoints).
- `RecipeSerializer` and `QuickBitesSerializer` are pure-function modules that
  convert IR hashes ↔ Markdown/plaintext — the inverse of the parser pipeline.
  Used by mode switching, structured writes, content loading, export, and the
  raw endpoint. `RecipeSerializer` is also the source for editor loading since
  AR records are the sole source of truth (no stored `markdown_source`).
- Graphical controllers build DOM entirely via `createElement`/`textContent`
  (strict CSP). Cross-reference steps render read-only in graphical mode.

**Scale panel.** `scale_panel_controller` provides inline recipe scaling
(presets + free-form input), dispatching `scale-panel:change` events consumed
by `recipe_state_controller`. Uses dual-restoration for async Stimulus
connection: event-based (`recipe-state:restored`) with attribute fallback
(`data-restored-scale-factor`). Embedded cross-reference recipes carry
`data-base-multiplier` — effective scale = base × user factor.

**Ingredient quantities.** AR `Ingredient` has `quantity_low`/`quantity_high`
decimal columns (populated at import) alongside the raw `quantity` string
(fallback for non-numeric values like "a pinch"). Ranges: both columns set;
non-ranges: only `quantity_low`. `quantity_value` returns the high end (for
nutrition). Display uses vulgar fractions + en-dash (`½–1`); storage and
serialization use ASCII fractions + hyphen (`1/2-1`). Normalization
(vulgar→ASCII, en-dash→hyphen) happens in `MarkdownImporter#import_ingredient`.

**Ingredient tooltips.** Native browser `title` attributes on ingredient `<li>`
elements show per-line gram conversion and compact nutrition (6 nutrients).
Data flows: `NutritionCalculator` stores `ingredient_details` in
`Recipe#nutrition_data` JSON → `_recipe_content` extracts `ingredient_info` →
`_step` passes to `ingredient_data_attrs` helper → `title` attribute. Embedded
cross-reference recipes get no tooltips (nil ingredient_info).

**Hotwire stack.** Turbo Drive + Turbo Streams, Stimulus controllers,
jsbundling-rails + esbuild for JS bundling.
- New JS modules go in `app/javascript/`; new Stimulus controllers must
  be imported and registered in `app/javascript/application.js`.
- `npm run build` bundles JS to `app/assets/builds/`; `bin/dev` runs
  both Puma and esbuild watcher via foreman.
- CSP requires a nonce for both `<script>` and `<style>` tags — the nonce
  generator uses `request.session.id` (see `content_security_policy.rb`).
  The layout includes `<%= csp_meta_tag %>` which exposes the nonce via
  `<meta name="csp-nonce">` so JS libraries (CodeMirror) can read it at
  runtime for injected `<style>` tags. Without this meta tag, CodeMirror's
  layout styles are blocked by CSP and the editor breaks silently.
- Turbo's progress bar styles live in `style.css` (not Turbo's dynamic
  `<style>` injection) to satisfy strict CSP — the harmless console error
  from Turbo's blocked injection is expected.

**ActionCable.** Turbo Streams over Solid Cable, using `turbo_stream_from` tags
in views.
- Kitchen-wide stream `[kitchen, :updates]` powers all page-refresh morphs via
  `Kitchen#broadcast_update` — each client re-fetches its own page and Turbo
  morphs the result.
- `RecipeBroadcaster` is retained only for delete/rename targeted notifications
  on per-recipe `[recipe, "content"]` streams.
- No async job needed — `broadcast_refresh_to` is cheap enough to run inline.

**Write path.** Controllers are thin adapters: param parsing → service call →
response rendering. Services own all post-write side effects (reconcile,
broadcast). Don't call `MarkdownImporter` directly for web operations.
- `RecipeWriteService` — recipe mutations, cross-reference cascades, category
  cleanup, tag sync, meal plan pruning, broadcast. `create`/`update` accept
  either markdown or IR hash; `_from_structure` variants are thin normalizers
  that extract front matter and delegate.
- `CatalogWriteService` — `IngredientCatalog` mutations, aisle sync, nutrition
  recalculation, broadcast.
- `MealPlanWriteService` — select/deselect, select-all, clear, reconciliation.
- `QuickBitesWriteService` — quick bites content persistence, parse
  validation, reconciliation, broadcast. Also has `update_from_structure`.
- `MarkdownImporter` has two entry points: `import` (markdown string) and
  `import_from_structure` (IR hash). Both converge on the same AR upsert +
  cross-ref resolution path. AR records are the sole source of truth —
  `RecipeSerializer` generates markdown on demand (export, editor loading,
  raw endpoints).
- `AisleWriteService` — reorder, rename/delete cascades to catalog rows,
  new-aisle sync, broadcast.
- `CategoryWriteService` — ordering, renaming, deletion cascades, broadcast.
- `Kitchen.finalize_writes(kitchen)` — single post-write entry point for
  all write services: orphan cleanup (categories + tags), meal plan
  reconciliation, and broadcast. Respects `Kitchen.batching?` guard.
- `Kitchen.batch_writes(kitchen)` — block scope that defers finalization
  to a single pass on block exit. Write services inside a batch call
  `finalize_writes` as usual — it returns early, and the batch runs the
  same pipeline once on exit.
- `MealPlanActions` concern provides `rescue_from StaleObjectError` for
  controllers using `MealPlanWriteService`.

**AI import.** `AiImportService` calls the Anthropic API (`anthropic` gem)
with a system prompt (`lib/familyrecipes/ai_import_prompt.md`) to convert
pasted recipe text into the app's Markdown format. `AiImportController` is a
thin JSON adapter (`POST /ai_import`). The Stimulus `ai_import_controller`
manages the import dialog and hands off generated Markdown to the recipe
editor. API key stored encrypted on Kitchen (`anthropic_api_key`); model
hardcoded as `Kitchen::AI_MODEL`. Button hidden when no key configured.

**Settings.** Site branding, display preferences, and API keys live as columns
on Kitchen (no separate settings table). `usda_api_key` is encrypted via
Active Record Encryption. `SettingsController` is a thin show/update — no
write service. Adding a new setting requires 5 touch points: migration,
dialog HTML, `SettingsController` (show JSON + params), and
`settings_editor_controller.js` (targets + all 7 methods).
The `multi_kitchen` flag is an env var (`MULTI_KITCHEN=true`), not a database
setting.

**Tags.** Kitchen-scoped labels for cross-cutting recipe classification.
`Tag` + `RecipeTag` join table. `RecipeWriteService` handles tag sync on
recipe save; `TagWriteService` handles bulk rename/delete from the management
dialog. Tags are single-word (`[a-zA-Z-]`), stored lowercase. Orphan cleanup
via `Tag.cleanup_orphans(kitchen)`. Smart tag decorations (emoji + color
pills) are driven by `FamilyRecipes::SmartTagRegistry` — a frozen constant
in `lib/familyrecipes/smart_tag_registry.rb`. `SmartTagHelper` bridges the
registry to views; JS controllers read a JSON embed from the layout.
`Kitchen#decorate_tags` toggle disables decorations. Crossout "-free" tags
use a `<span class="smart-icon">` wrapper with CSS circle+slash overlay.

**Nutrition pipeline.** Key classes (read their header comments for details):
- `IngredientCatalog` — overlay model: global seed entries + per-kitchen
  overrides, merged by `lookup_for` with Inflector variant matching and
  `aliases` column.  `resolver_for(kitchen)` builds an `IngredientResolver`.
- `IngredientResolver` — single resolution point for ingredient names
  (case-insensitive fallback, variant collapsing). Shared across services
  within a request.
- `NutritionConstraints` — single source of truth for nutrient definitions
  (`NutrientDef`, FDA daily values) and validation rules.
- `UnitResolver` — wraps one `IngredientCatalog` entry, resolves quantities to
  grams via weight → portion → density chain. Owns canonical unit conversion
  tables (`VOLUME_TO_ML`, `WEIGHT_CONVERSIONS`) and Inflector-expanded variants.
- `NutritionCalculator` — aggregates nutrient totals for a recipe, delegates
  unit resolution to `UnitResolver`. Produces `Result` with totals, per-serving,
  per-unit breakdowns, and per-ingredient detail (`nutrients_per_gram` rates +
  `grams_per_unit` conversion factors — NOT aggregated totals, so the view can
  compute per-line values when an ingredient appears in multiple steps).
- `RecipeNutritionJob` / `CascadeNutritionJob` — recompute nutrition; cascade
  fans out to cross-referencing recipes.
- `RecipeAvailabilityCalculator` — catalog coverage badges on the menu page.
- `rake catalog:sync` pushes YAML seed changes into the database.

**Ingredient editor.** `IngredientsController` shows a searchable, filterable
table with coverage stats. Clicking a row opens the `nutrition_editor_controller`
dialog.
- `IngredientRowBuilder` — row data, `needed_units`, `sources_for`, aggregate
  `coverage`.
- Editor form: nutrients, density, portions, aisle, aliases, USDA search panel.
- Inline USDA search (`UsdaSearchController` JSON endpoints) — click a result
  to auto-populate fields via `UsdaImportService`. Density candidate picker
  lets users choose among USDA volume-based portions.
- `NutritionEntriesController` handles upsert/destroy; `CatalogWriteService`
  orchestrates persistence.
- `UsdaClient` is the HTTP adapter; `UsdaPortionClassifier` classifies portions
  into density/portion/filtered buckets.

**Search overlay.** Spotlight-style `<dialog>` on every page, triggered by `/`
key or nav icon. `SearchDataHelper` embeds a JSON blob (recipes with title,
slug, description, category, tags, ingredients; plus `all_tags` and
`all_categories` lists); `search_overlay_controller` does client-side substring
matching with tiered ranking and pill-based tag/category filtering. No server
endpoint.

## Recipe & Data Formats

Recipe source is Markdown with custom syntax. The parser pipeline is the
authoritative implementation. Key parser classes: `LineClassifier`
(token types), `RecipeBuilder` (assembly), `IngredientParser` (ingredient
bullets), `CrossReferenceParser` (`> @[Title]` import syntax). Bare `@[Title]`
in prose or the footer renders as a clickable link to that recipe (render-time
only, no DB tracking). Seed files in `db/seeds/recipes/` are working examples.

**Front matter.** Recipes support optional front matter lines before the first
step: `Serves:`, `Makes:`, `Category:`, `Tags:`. Tags are comma-separated,
normalized to lowercase `[a-zA-Z-]`. Front matter category overrides the
explicit category parameter; tags sync to the `Tag`/`RecipeTag` join table
via `RecipeWriteService`.

**Quick Bites** are grocery bundles, not recipes. See
`FamilyRecipes::QuickBite` header comment for format. Stored in
`Kitchen#quick_bites_content`, web-editable on the menu page.

**Nutrition catalog** lives in `db/seeds/resources/ingredient-catalog.yaml`.
See `NutritionConstraints` for validation rules, `IngredientCatalog` for the
overlay model.

## Commands

```bash
bundle install && rails db:setup   # first-time setup (needs sqlite3-dev headers)
rake lint          # RuboCop — always use `bundle exec rubocop`, not bare `rubocop`
rake lint:html_safe # audit .html_safe / raw() calls against allowlist
rake test          # all tests via Minitest
rake catalog:sync  # push ingredient-catalog.yaml changes into the database
ruby -Itest test/controllers/recipes_controller_test.rb              # single file
ruby -Itest test/models/recipe_test.rb -n test_requires_title        # single test
bin/dev            # Puma on port 3030
# test helpers: create_kitchen_and_user, log_in, kitchen_slug (see test/test_helper.rb)
```

```bash
npm install                # install JS dependencies
npm run build              # bundle JS (esbuild)
npm test                   # run JS classifier tests
```

The default `rake` task runs both lint and test.

**Test conventions.** Plain `Minitest::Test` files (parser-layer tests in
`test/`) must be added to the `Rails/RefuteMethods` exclusion in `.rubocop.yml`
— they don't have `assert_not`. RuboCop also enforces blank lines before
assertions (`Minitest/EmptyLineBeforeAssertionMethods`).

## Workflow

**Git hygiene.** Always commit after finishing up edits to a file. When
completing work on a GitHub issue, reference it in the commit message so that
it will close on push (e.g., "Resolves #nn" or "Resolves #nn1, resolves #nn2,
resolves #nn3")

**Worktrees.** Most projects can be completed on main. For major projects, ask
me whether I want to move to a worktree.

**Worktree cleanup.** Never run `git worktree remove` directly — it deletes the
CWD and bricks the Bash tool. Use the wrapper: `bash bin/worktree-remove
<name>`

**Screenshots.** Save to `~/screenshots/`, not inside the repo.

**`Data.define` + Rails JSON.** Classes with custom `to_json` must also define
`as_json` — see `Quantity` in `lib/familyrecipes/quantity.rb`.

**`rails runner` + multi-tenancy.** `ActsAsTenant` scoping applies outside web
requests too. Wrap all `rails runner` model queries in
`ActsAsTenant.with_tenant(kitchen) { ... }`.

**Server restart.** Adding gems, new concerns, or modifying
`lib/familyrecipes/` requires restarting Puma (`pkill -f puma; rm -f
tmp/pids/server.pid` then `bin/dev`). Domain classes in `lib/` are loaded once
at boot — they do not hot-reload.

**PWA.** `rake pwa:icons` generates PNGs from `app/assets/images/favicon.svg`
(requires `rsvg-convert`/`librsvg2-bin`). Service worker
(`app/views/pwa/service_worker.js.erb`) is a minimal PWA-install stub — no
caching, no fetch interception. The browser handles all requests normally.

**JS changes.** Adding npm packages requires `npm install`. Adding new
Stimulus controllers requires registering them in `application.js`.
The esbuild watcher (`bin/dev`) auto-rebuilds on file changes.

**Visual companion.** The brainstorming visual companion server must bind to
`0.0.0.0` (`--host 0.0.0.0`) — the default `127.0.0.1` is unreachable from
the user's browser in this remote setup.

**Skills.** Always use the superpowers skill when getting ready to write code.

**Subagents.** ALWAYS use Opus subagents for coding tasks.

**Commit timestamps.** A post-commit hook rewrites timestamps for privacy.
This changes commit SHAs, so `git branch -d` fails after fast-forward merges
— use `git branch -D` when you've verified the content is merged.

**Migrations.** Use `db/migrate/` for all schema and data changes — never use
one-off rake tasks for backfills.  Migrations are numbered sequentially
(`001_`, `002_`, …).  When it is time to ship v1.0, consolidate all
migrations into a single `001_create_schema.rb` to keep things clean.
- **Never call application models, services, or jobs from migrations.** Use raw
  SQL or define bare model stubs inside the migration file. Application code
  may depend on schema that doesn't exist yet, causing migration ordering bugs.
- Schema migrations (create/alter table) must come before any data migrations
  that depend on those tables.
- CI verifies migrations from scratch (`db:create db:migrate db:seed`) before
  building the Docker image.

**Releases.** Tag pushes (`v0.2.5`) trigger `docker.yml`: build → smoke test
(`/up` health check) → push to GHCR. No redundant test job — `test.yml` already
ran on the push to main. The `REVISION` build arg bakes the version into the
image (read by `ApplicationHelper#app_version`). Only tag when code is
known-good — in-between commits on main are not built. The pre-push hook runs
lint on all files (~5s); tests run exclusively in CI.
