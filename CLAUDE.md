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

**CSS file structure.** Propshaft serves each file individually; no bundling.
- **Global** (loaded in layout): `base.css` (tokens, typography, buttons,
  inputs, collapse, scale, tags, notifications), `navigation.css` (nav,
  search overlay), `editor.css` (all editor dialogs, graphical editor),
  `nutrition.css` (FDA label, nf-editor, USDA search, density/portion/alias),
  `recipe.css` (embedded cards), `print.css`.
- **Page-specific** (via `content_for(:head)`): `menu.css`, `groceries.css`,
  `ingredients.css`.
- Editor-related classes use `editor-` prefix. Nutrition editor form classes
  use `editor-` prefix (e.g. `.editor-form-row`, `.editor-portion-row`,
  `.editor-alias-chip`).

**CSS conventions.** Icons: `IconHelper#icon(name, size:)` / JS `buildIcon(name, size)`
— never paste raw SVG. Inputs: `.input-base` + modifiers. Buttons: `.btn` +
modifiers. Collapse: `<details class="collapse-header">` pattern. Color tokens
live in `base.css :root` — always check before inventing names. Data is embedded
via `<script type="application/json">` + `el.textContent`, not `data-` attributes
— check partials before assuming how data is embedded.

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
- `MealPlan` (one row per kitchen) coordinates menu, groceries, and dinner
  picker — read its header comment for delegation details.
  `QuickBite` models live within `Category` alongside recipes.

**Editor dialogs.** Use `render layout: 'shared/editor_dialog'` with Stimulus
data attributes — no JS needed. Custom dialogs hook in via lifecycle events
(`editor:content-loaded`, `editor:collect`, `editor:save`, `editor:modified`,
`editor:reset`). All editor bodies load via Turbo Frames (eager preload).
- Open `<dialog>` elements are protected from Turbo morph via
  `turbo:before-morph-element` in `application.js`.
- `turbo:before-cache` closes all open dialogs before page snapshots.
- Do NOT use `data-turbo-permanent` on dialogs.
- AR records are the sole source of truth — no stored `markdown_source`.
  `RecipeSerializer` / `QuickBitesSerializer` handle IR ↔ text conversion.
- Read `editor_controller.js` and `dual_mode_editor_controller.js` header
  comments for the coordinator/child pattern and lifecycle routing.

**Hotwire stack.** Turbo Drive + Turbo Streams, Stimulus controllers,
jsbundling-rails + esbuild for JS bundling.
- New JS modules go in `app/javascript/`; shared utilities live in
  `app/javascript/utilities/`. New Stimulus controllers must be registered
  in `app/javascript/application.js`.
- Stimulus reserves `data-action` for its own dispatch syntax — use a
  prefixed attribute (e.g. `data-grocery-action`) for custom button actions.
- CSP nonce: see `content_security_policy.rb` header comment. The layout's
  `<%= csp_meta_tag %>` exposes the nonce for JS libraries (CodeMirror).

**Write path.** Controllers are thin adapters: param parsing → service call →
response rendering. Services own all post-write side effects (reconcile,
broadcast). Don't call `MarkdownImporter` directly for web operations.
Read write service header comments for details. `multi_kitchen` is an env
var, not a DB setting.

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

**Quick Bites** are grocery bundles, not recipes — a title plus a flat
ingredient list. Normalized into `QuickBite` and `QuickBiteIngredient` AR
models within `Category` (shared with recipes). The plaintext format and
parser (`FamilyRecipes::QuickBite`) are retained for editor mode-switching.
`QuickBitesSerializer.from_records` builds editor IR from AR models.

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
bin/dev            # Puma + esbuild watcher (port 3030)
# test helpers: create_kitchen_and_user, log_in, kitchen_slug (see test/test_helper.rb)
```

**Bullet.** Enabled in dev (page footer + Rails log) and test (raises on N+1).
If a test fails with a Bullet::Notification::UnoptimizedQueryError, add
`includes` or `preload` to the query — don't disable Bullet for that test.

**Security.** `rake security` runs Brakeman static analysis (medium+ confidence
warnings fail). `rake security:verbose` for full detail. False positives go in
`config/brakeman.ignore`. Playwright pen tests in `test/security/` require a
running dev server:
```bash
MULTI_KITCHEN=true bin/rails runner test/security/seed_security_kitchens.rb
npx playwright test test/security/              # all security specs
npx playwright test test/security/tenant_isolation.spec.mjs  # single spec
```
CI runs Brakeman and `bundler-audit` automatically on every push and PR.

```bash
npm install                # install JS dependencies
npm run build              # bundle JS (esbuild)
npm test                   # run JS classifier tests
ruby test/sim/grocery_convergence.rb   # standalone convergence simulation (excluded from RuboCop)
```

The default `rake` task runs both lint and test.

**Help site.** User-facing documentation lives in `docs/help/` as a Jekyll static
site deployed to GitHub Pages via `.github/workflows/docs.yml`. Design spec:
`docs/superpowers/specs/2026-03-26-help-site-design.md`. The docs are a
behavioral contract — if a feature doesn't match the docs, decide whether to fix
the code or update the docs. To build locally:
```bash
gem install jekyll kramdown-parser-gfm
cp app/assets/images/favicon.svg docs/help/assets/favicon.svg
cd /tmp && jekyll build --source ~/familyrecipes/docs/help --destination ~/familyrecipes/_site
```
Note: must run `jekyll build` from outside the repo root — Jekyll picks up the Rails `Gemfile` and fails if run from within the project.

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

**Branch early.** Create the feature branch before the first commit —
including design docs and plans. These are part of the feature work. If
committed to main first, squash-merging the PR creates duplicate changes
that cause rebase conflicts on pull.

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
(requires `rsvg-convert`/`librsvg2-bin`). Service worker is a minimal
install stub — see its header comment.

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

**Releases.** Tag pushes trigger `docker.yml`: build → smoke test (`/up`
health check) → push to GHCR → create GitHub Release. Three tiers based on
tag format:
- **Patch** (`vX.Y.Z`): auto-published with commit bullet list.
- **Minor** (`vX.Y`): draft release — a Claude Code hook fires on push,
  prompting you to draft curated notes and update via `gh release edit`.
- **Major** (`vX`): draft release — same hook, but prompts for
  marketing-quality notes with highlights, breaking changes, and upgrade
  notes.
The `REVISION` build arg bakes the version into the image (read by
`ApplicationHelper#app_version`). Only tag when code is known-good —
in-between commits on main are not built. The pre-push hook runs lint on
all files (~5s); tests run exclusively in CI.
