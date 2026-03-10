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
method: ```ruby # WRONG — Claude's default, and it's unacceptable result = []
items.each { |item| result << item.name if item.active? } result

# RIGHT — idiomatic Ruby
items.select(&:active?).map(&:name)
```

Use `map`, `select`/`reject`, `flat_map`, `each_with_object`,
`any?`/`all?`/`none?`, `tally`, `group_by`, `sum`. Always use `&:method_name`
(Symbol#to_proc) when the block just calls one method.

When appending to an existing collection, use `concat` + `map` — not `each` +
`<<`: ```ruby # WRONG custom.each { |item| list << { name: item, amounts: [] }
}

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
inline styles, no external resources. Update the CSP initializer before adding
any.

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

**Routing.** Routes use an optional `(/kitchens/:kitchen_slug)` scope.  When
exactly one Kitchen exists, URLs are root-level (`/recipes/bagels`); when
multiple exist, URLs include the prefix (`/kitchens/ours/recipes/bagels`).
`default_url_options` auto-injects `kitchen_slug` — always use `_path` helpers,
never hard-code URL strings.  Use `home_path` (not `kitchen_root_path`) for
homepage links.  `MealPlan` (one row per kitchen) backs both the menu and
groceries pages.

**Editor dialogs.** Use `render layout: 'shared/editor_dialog'` with Stimulus
data attributes — no JS needed. For custom content, add a controller listening
to editor lifecycle events.  Open `<dialog>` elements are protected from Turbo
morph via a `turbo:before-morph-element` listener in `application.js`. A
`turbo:before-cache` listener closes all open dialogs before page snapshots.
Both editor controllers guard unsaved changes on `turbo:before-visit`. Do NOT
use `data-turbo-permanent` on dialogs.  `HighlightOverlay` (shared utility)
powers syntax-colored overlays for both Quick Bites and recipe editors.
`ordered_list_editor_controller` is a single parameterized controller for both
aisle and category list editors.

**Hotwire stack.** Turbo Drive + Turbo Streams, Stimulus controllers,
importmap-rails for ES modules.  New JS modules must be pinned in
`config/importmap.rb`; new Stimulus controllers auto-register via
`pin_all_from`.  CSP requires nonces for importmap's inline `<script>` — the
nonce generator uses `request.session.id` (see `content_security_policy.rb`).
Turbo's progress bar styles live in `style.css` (not Turbo's dynamic `<style>`
injection) to satisfy strict CSP — the harmless console error from Turbo's
blocked injection is expected.

**ActionCable.** Turbo Streams over Solid Cable, using `turbo_stream_from` tags
in views.  A single kitchen-wide stream `[kitchen, :updates]` powers all
page-refresh morphs via `Kitchen#broadcast_update` — each client re-fetches its
own page and Turbo morphs the result.  `RecipeBroadcaster` is retained only for
delete/rename targeted notifications on per-recipe `[recipe, "content"]`
streams (recipe deleted or URL changed).  No async job needed —
`broadcast_refresh_to` is cheap enough to run inline.

**Write path.** `RecipeWriteService` orchestrates all recipe mutations —
import, cross-reference cascades, category cleanup, meal plan pruning, and
`Kitchen#broadcast_update`.
`CatalogWriteService` orchestrates all `IngredientCatalog` mutations — aisle
sync, nutrition recalculation, and `Kitchen#broadcast_update`.
`MealPlanWriteService` orchestrates all direct `MealPlan` mutations —
select/deselect, select-all, clear, and standalone reconciliation.
`AisleWriteService` orchestrates all `Kitchen#aisle_order` mutations — reorder,
rename/delete cascades to catalog rows, new-aisle sync, and
`Kitchen#broadcast_update`.
`CategoryWriteService` orchestrates category ordering, renaming, deletion
cascades, and `Kitchen#broadcast_update`.
Controllers are thin adapters: param parsing → service call → response
rendering. Services own all post-write side effects (reconcile, broadcast).
Don't call `MarkdownImporter` directly for web operations.
`MealPlanActions` concern provides `rescue_from StaleObjectError` for
controllers whose write paths use `MealPlanWriteService`.
`MealPlan#reconcile!` is the single pruning entry point — removes stale
checked-off items and stale selections based on current shopping list state.
Called after recipe CRUD, quick bites edits, catalog changes, and deselects.

**Nutrition pipeline.** `IngredientCatalog` is an overlay model — global seed
entries plus per-kitchen overrides, merged by `lookup_for` with `Inflector`
variant matching and a JSON `aliases` column for alternate names.
`IngredientResolver` is the single resolution point for ingredient names —
wraps `IngredientCatalog.lookup_for` with case-insensitive fallback and
uncataloged variant collapsing.  Constructed via
`IngredientCatalog.resolver_for(kitchen)`, shared across services within a
request.  `RecipeNutritionJob` recomputes nutrition; `CascadeNutritionJob` fans
out to cross-referencing recipes.  `IngredientRowBuilder` computes ingredient
table rows, summaries, and next-needing-attention — shared by
`IngredientsController` and `NutritionEntriesController`.
`NutritionConstraints` is the single source of truth for nutrient definitions
(NutrientDef) and validation rules — all downstream nutrient constants derive
from it.  `RecipeAvailabilityCalculator` checks catalog coverage per recipe for
availability badges on the menu page — uses `IngredientResolver` and refreshes
automatically via Turbo morph when catalog entries change.  `bin/nutrition` is
a standalone TUI (not loaded by Rails); `rake catalog:sync` pushes YAML changes
into the database.

## Recipe & Data Formats

Recipe source is Markdown with custom syntax — the parser pipeline is the
authoritative spec. Read the header comments on `LineClassifier` (token types),
`RecipeBuilder` (assembly), `IngredientParser` (ingredient bullets), and
`CrossReferenceParser` (`>>> @[Title]` syntax). Seed files in
`db/seeds/recipes/` are working examples.

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

The default `rake` task runs both lint and test.

## Workflow

**Worktree cleanup.** Never run `git worktree remove` directly — it deletes the
CWD and bricks the Bash tool. Use the wrapper: ```bash bin/worktree-remove
<name> ```

**Screenshots.** Save to `~/screenshots/`, not inside the repo.

**`Data.define` + Rails JSON.** Classes with custom `to_json` must also define
`as_json` — see `Quantity` in `lib/familyrecipes/quantity.rb`.

**Server restart.** Adding gems, new concerns, or modifying
`lib/familyrecipes/` requires restarting Puma (`pkill -f puma; rm -f
tmp/pids/server.pid` then `bin/dev`). Domain classes in `lib/` are loaded once
at boot — they do not hot-reload.

**PWA.** `rake pwa:icons` generates PNGs from `app/assets/images/favicon.svg`
(requires `rsvg-convert`/`librsvg2-bin`). Service worker
(`app/views/pwa/service_worker.js.erb`) is a minimal PWA-install stub — no
caching, no fetch interception. The browser handles all requests normally.

**Skills.** Always use the superpowers skill when getting ready to write code.

**Commit timestamps.** A post-commit hook rewrites timestamps for privacy.
