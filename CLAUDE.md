# CLAUDE.md

Rails 8 app backed by SQLite with multi-tenant "Kitchen" support and
trusted-header authentication.  Two-database architecture: primary (app data),
cable (Solid Cable pub/sub).  Docker image for homelab installs during
development, eventual move to hosted model with many users.

## Design Philosophy

- Default to simple UI. We can add complexity when it's necessary.
- Retro theme: skeuomorphism with mid-century cookbook vibes
- Err on the side of less JavaScript

## Development Notes
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

A strict CSP is enforced (`config/initializers/content_security_policy.rb`).
No inline styles, no external resources (Google Fonts is the sole exception).
Update the CSP initializer before adding any.

- **Never** call `.html_safe` on a string that interpolates user content
  without first escaping via `ERB::Util.html_escape`.
- **Never** use `raw()` on user content.
- In JavaScript, use `textContent` / `createTextNode` — never `innerHTML`.
- `rake lint:html_safe` audits `.html_safe` and `raw()` calls against
  `config/html_safe_allowlist.yml`. The allowlist uses `file:line_number` keys
— update it whenever edits shift line numbers.
- Use semantic HTML. Recipes are **documents first** — marked-up text, not an
  app that happens to contain text.

**CSS color tokens.** The canonical tokens are defined in `style.css` `:root`.
Key names: `--ground` (background), `--text`, `--text-soft`, `--text-light`
(foreground), `--surface-alt` (offset bg), `--rule`/`--rule-faint` (borders),
`--red` (accent/links), `--dialog-backdrop`, `--shadow-dialog`. Never invent
generic names like `--bg`, `--fg`, `--fg-muted` — always check `:root` first.

**Embedded JSON blobs.** `SearchDataHelper` and smart tag data are embedded as
`<script type="application/json">` tags read via `el.textContent`, not as
`data-` attributes. Search data target: `[data-search-overlay-target="data"]`.
Smart tags: `[data-smart-tags]`. Always check the actual partial before
assuming how data is embedded.

**`hidden` attribute gotcha.** Explicit CSS `display` values (flex, grid)
override the `[hidden]` user-agent style. When using `el.hidden = true` on
elements with explicit display rules, add `selector[hidden] { display: none }`
to the stylesheet.

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
- To add a new plaintext editor type: create a classifier ViewPlugin in
  `codemirror/`, register it in `codemirror/registry.js`, then use
  `plaintext-editor` controller with the registry key as the `classifier` value.
- `ordered_list_editor_controller` is a single parameterized controller for
  both aisle and category list editors.
- **Dual-mode editors** (recipe + Quick Bites) use a coordinator/child pattern:
  `editor_controller` → `dual_mode_editor_controller` → child controller.
  Coordinator manages mode toggle, routes lifecycle events, handles
  mode-switch serialization via `/parse` and `/serialize` endpoints.
- `RecipeSerializer` and `QuickBitesSerializer` convert IR hashes ↔
  Markdown/plaintext. AR records are the sole source of truth — no stored
  `markdown_source`. Graphical controllers build DOM via
  `createElement`/`textContent` (strict CSP).

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

**ActionCable.** Kitchen-wide stream `[kitchen, :updates]` powers all
page-refresh morphs via `Kitchen#broadcast_update`. `RecipeBroadcaster`
handles only delete/rename targeted notifications. No async jobs needed.

**Write path.** Controllers are thin adapters: param parsing → service call →
response rendering. Services own all post-write side effects (reconcile,
broadcast). Don't call `MarkdownImporter` directly for web operations.
- Write services: `RecipeWriteService`, `CatalogWriteService`,
  `MealPlanWriteService`, `QuickBitesWriteService`, `AisleWriteService`,
  `CategoryWriteService`, `TagWriteService`. Read their header comments.
- `ListWriteService` is the template method base class for
  `AisleWriteService`, `CategoryWriteService`, and `TagWriteService`.
  Subclasses override `validate_changeset`, `apply_renames`,
  `apply_deletes`, and `apply_ordering` hooks.
- `MarkdownImporter` has two entry points: `import` (markdown string) and
  `import_from_structure` (IR hash). AR records are the sole source of truth.
- `Kitchen.finalize_writes(kitchen)` — single post-write entry point:
  orphan cleanup, meal plan reconciliation, broadcast.
- `Kitchen.batch_writes(kitchen)` — defers finalization to one pass on
  block exit.
- `MealPlanActions` concern provides `rescue_from StaleObjectError`.

**Adding a new setting.** 5 touch points: migration, dialog HTML,
`SettingsController` (show JSON + params), `settings_editor_controller.js`
(targets + all 7 methods). `multi_kitchen` is an env var, not a DB setting.

**Tags.** Single-word (`[a-zA-Z-]`), stored lowercase. Smart tag decorations
driven by `FamilyRecipes::SmartTagRegistry` in `lib/familyrecipes/`.

**Nutrition pipeline.** `IngredientCatalog` → `IngredientResolver` →
`UnitResolver` → `NutritionCalculator`. Read their header comments for
details. `rake catalog:sync` pushes YAML seed changes into the database.

**AI import.** `AiImportService` + `AiImportController`. API key stored
encrypted on Kitchen (`anthropic_api_key`); button hidden when no key set.

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

### Git Strategy — trunk-based with short-lived feature branches

**`main` is always deployable.** CI gates every push. Tag releases trigger
Docker builds.

**Commit directly to `main` when:** the change is small, self-contained, and
low-risk — a single-file bug fix, doc update, CLAUDE.md edit, or cleanup.

**Use a feature branch + PR when:** the change touches multiple files, adds a
feature, refactors code, or is anything the user would want to review first.
When in doubt, branch — it's easy to merge, hard to undo a bad commit to main.

**Branch workflow:**
```bash
git checkout -b feature/short-description    # branch from main
# ... work, committing as you go ...
git push -u origin feature/short-description # push to GitHub
gh pr create --title "..." --body "..."      # open PR for review
# after merge on GitHub:
git checkout main && git pull && git branch -D feature/short-description
```

**Key rules:**
- **Squash-merge PRs** (`gh pr merge --squash`) for clean, linear history.
- **`-D` not `-d`** for local branch deletion — the post-commit timestamp
  hook amends SHAs, making `-d`'s "is it merged?" check fail.
- **No manual git worktrees.** Use simple `git checkout -b` branching. The
  Agent tool's built-in `isolation: "worktree"` handles subagent isolation
  automatically when needed — never create worktrees manually. This overrides
  any superpowers skill that recommends worktrees.
- **GitHub auto-deletes remote branches** after PR merge.
- Reference GitHub issues in commit messages to auto-close on push
  (e.g., "Resolves #nn" or "Resolves #nn1, resolves #nn2").
- Commit after finishing edits to a file — don't batch unrelated changes.

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
the user's browser in this remote setup. When providing links to the
companion, substitute your current LAN IP or hostname in place of `localhost`.
You have explicit permission to use the visual companion server; you don't
need to ask before spawning it.

**Skills.** Always use the superpowers skill when getting ready to write code.

**Subagents.** ALWAYS use Opus subagents for coding tasks.

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
