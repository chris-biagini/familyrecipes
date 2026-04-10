# CLAUDE.md

Rails 8 app backed by SQLite with multi-tenant "Kitchen" support.
Passwordless auth via join codes, with a parallel trusted-header path for
homelab installs.  Two-database architecture: primary (app data), cable
(Solid Cable pub/sub).  Docker image for homelab installs, plan to also have
hosted model with many users.

## Design Philosophy

- Default to simple UI. We can add complexity when it's necessary.
- Retro theme: skeuomorphism with mid-century cookbook vibes
- Rely on Rails conventions and "free" features whenever possible 

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

### Comments

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

**CSS.** Propshaft serves files individually; no bundling. Global (in layout):
`base.css`, `navigation.css`, `editor.css`, `nutrition.css`, `recipe.css`,
`print.css`. Page-specific (via `content_for(:head)`): `auth.css`, `menu.css`,
`groceries.css`, `ingredients.css`. See `base.css` header comment for design
tokens, shared patterns, and naming conventions. Data is embedded via
`<script type="application/json">` + `el.textContent`, not `data-` attributes.

**`hidden` attribute gotcha.** Explicit CSS `display` values override
`[hidden]`. Add `selector[hidden] { display: none }` when needed.

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

**Editor dialogs.** `render layout: 'shared/editor_dialog'` + Stimulus data
attributes. Custom dialogs hook via lifecycle events (`editor:content-loaded`,
`editor:collect`, `editor:save`, `editor:modified`, `editor:reset`). Do NOT
use `data-turbo-permanent` on dialogs. AR records are the sole source of
truth — `RecipeSerializer` / `QuickBitesSerializer` handle IR ↔ text.
See `editor_controller.js` header for the coordinator/child pattern.

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
response rendering. Shared controller logic lives in
`app/controllers/concerns/` (authentication, meal-plan actions, structure
validation). Services own all post-write side effects (reconcile,
broadcast). Don't call `MarkdownImporter` directly for web operations.
Read write service header comments for details. Background jobs:
`RecipeNutritionJob` recomputes nutrition after recipe saves;
`CascadeNutritionJob` propagates catalog changes across all recipes that
use an ingredient.

**Services.** `app/services/` has ~20 services. Write services
(`*WriteService`) handle CRUD + side effects for their domain.
`ShoppingListBuilder` computes grocery lists; `IngredientResolver` handles
nutrition lookups; `RecipeAvailabilityCalculator` builds the dinner picker
pool. `RecipeBroadcaster` and `CrossReferenceUpdater` run as post-write
hooks. All have architectural header comments.

**Import/export.** ZIP backup/restore (`ExportService`/`ImportService`).
AI recipe import (`AiImportService`) sends text to Anthropic API; two modes
(faithful/expert). See service headers for details. Evaluation tooling in
`test/ai_import/` (not part of `rake test`).

**Settings.** Kitchen-scoped branding (title, heading, subtitle), API keys
(USDA, Anthropic), and feature flags (`show_nutrition`, `decorate_tags`)
— all columns on `Kitchen`, edited via the settings dialog.
`Kitchen::AI_MODEL` defines the Anthropic model for AI import (currently
`claude-sonnet-4-6`). Haiku was evaluated and rejected — it hallucinated
quantities and instructions when inputs were incomplete.

**Tags.** Tag management dialog supports bulk rename/delete via
`TagWriteService`. Tags are also auto-synced from recipe front matter on save.

**Dinner picker / wake lock.** See JS controller headers for details.

**Auth flow.** Passwordless join-code system: `JoinCodeGenerator` (in `lib/`)
creates human-readable codes; `JoinsController` validates codes and creates
`Membership` records. `SessionsController` handles sign-in/sign-out;
`DevSessionsController` provides test-only session shortcuts.
`WelcomeController` and `LandingController` handle post-join and pre-auth
landing pages. `TransfersController` manages kitchen ownership transfer.
See each controller's header comment for details.

**Trusted-header auto-join.** A trusted-header user with zero memberships is
auto-added as a member iff exactly one Kitchen exists (`Kitchen.limit(2).one?`).
Trust assumption: the reverse proxy strips inbound `Remote-User` headers.
Multi-kitchen installs are unaffected. Hardening tracked in #365.

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
bin/rails runner test/security/seed_security_kitchens.rb
npx playwright test test/security/              # all security specs
npx playwright test test/security/tenant_isolation.spec.mjs  # single spec
```
CI (`test.yml`) runs Brakeman and `bundler-audit` on every push and PR.

```bash
npm install                # install JS dependencies
npm run build              # bundle JS (esbuild)
npm test                   # run JS classifier tests
ruby test/sim/grocery_audit.rb         # standalone grocery audit simulation (excluded from RuboCop)
```

The default `rake` task runs both lint and test.

**Help site.** `docs/help/` — Jekyll on GitHub Pages (`docs.yml` workflow).
Docs are a behavioral contract — if a feature doesn't match the docs, fix
the code or update the docs. Build from outside the repo root (Jekyll picks
up the Rails `Gemfile` otherwise):
```bash
cd /tmp && jekyll build --source ~/familyrecipes/docs/help --destination ~/familyrecipes/_site
```

**Test conventions.** Plain `Minitest::Test` files (parser-layer tests in
`test/`) must be added to the `Rails/RefuteMethods` exclusion in `.rubocop.yml`
— they don't have `assert_not`. RuboCop also enforces blank lines before
assertions (`Minitest/EmptyLineBeforeAssertionMethods`).

**Standalone Ruby scripts.** Scripts in `test/ai_import/` run without Rails.
ActiveSupport methods (`blank?`, `present?`, `exclude?`, `pluck` on arrays)
are unavailable — use plain Ruby equivalents with `rubocop:disable` comments.
RuboCop's `Style/SelectByRegexp` cop suggests `grep` but this is WRONG when
testing an array of Regexps against a string (reversed operands) — use
`select { |p| str.match?(p) }` instead. Guard standalone scripts with
`if $PROGRAM_NAME == __FILE__` to prevent `rake test` from loading them.

## Release Audit

Three-tier quality gate: Tier 1 (CI, automatic), Tier 2 (before any release),
Tier 3 (before minor/major). Pre-push hook blocks tag pushes without a fresh
(< 48h) audit marker matching HEAD. Tier 3 requires a running dev server
(`bin/dev`). Config: `config/release_audit.yml`,
`config/debride_allowlist.txt`, `config/license_allowlist.yml`.

```bash
rake release:audit           # Tier 2 (before any release)
rake release:audit:full      # Tier 2 + Tier 3 (before minor/major)
rake release:audit:security  # just security pen tests
rake release:audit:explore   # just exploratory QA
rake release:audit:a11y      # just accessibility check
rake release:audit:perf      # just performance baseline
```

## Workflow

### Git Strategy — trunk-based with short-lived feature branches

**`main` is always deployable.** CI gates every push. Tag releases trigger
Docker builds.

**Commit directly to `main` when:** the change is small, self-contained, and
low-risk — a single-file bug fix, doc update, CLAUDE.md edit, or cleanup.
**Push immediately** — unpushed commits on local main cause rebase conflicts
after squash-merging PRs that touch the same files.

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

**Long-lived feature branches.** Some features (e.g., auth, billing) are too
large or security-sensitive to squash-merge after one session. These stay
open for iterative development and testing across multiple sessions.

- **Commit freely on the branch** — messy history is fine; it aids debugging
  during iteration. Don't squash mid-flight.
- **Small fixes go to main directly** — stash or commit WIP on the branch,
  checkout main, fix, push, checkout back.
- **Rebase onto main periodically** — `git rebase main` keeps the branch
  current. Force-push after rebase is expected and safe on feature branches.
- **No PR until ready** — just push to the branch. Open the PR as the final
  review gate when the feature is tested and ready for main.
- **Squash-merge when done** — `gh pr merge --squash`. The full commit
  history is preserved on the branch/PR in GitHub for forensics.
- **Design docs and plans live on the branch** — they're part of the feature
  work and merge with it.

Active long-lived branches are listed in the memory system, not here.

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

**Skills.** Always use the superpowers skill when getting ready to write code.

**Subagents.** ALWAYS use Opus subagents for coding tasks.

**Migrations.** Use `db/migrate/` for all schema and data changes — never use
one-off rake tasks for backfills.  Migrations are numbered sequentially
(`001_`, `002_`, …).  
- **Never call application models, services, or jobs from migrations.** Use raw
  SQL or define bare model stubs inside the migration file. Application code
  may depend on schema that doesn't exist yet, causing migration ordering bugs.
- Schema migrations (create/alter table) must come before any data migrations
  that depend on those tables.
- CI verifies migrations from scratch (`db:create db:migrate db:seed`) before
  building the Docker image.

**Releases.** Tag pushes trigger `docker.yml`: build → smoke test → push to
GHCR → create GitHub Release. Tag format determines tier: patch (`vX.Y.Z`),
minor (`vX.Y`), major (`vX`). Minor/major get curated release notes
(Claude generates before tagging). Four-part tags are not supported.
Run `rake release:audit` before any tag; `rake release:audit:full` for
minor/major (requires running dev server). Pre-push hook enforces this.
`REVISION` build arg bakes the version into the image
(`ApplicationHelper#app_version`). Pre-push hook runs lint (~5s); tests
run exclusively in CI.
