# CLAUDE.md

Rails 8 app backed by SQLite with multi-tenant "Kitchen" support and trusted-header authentication. Two-database architecture: primary (app data), cable (Solid Cable pub/sub). Docker image for homelab installs.

## Design Philosophy

- Default to simple UI. We can add complexity when it's necessary.
- Challenge assumptions, misconceptions, and poor design decisions.
- Suggest quality-of-life, performance, and feature improvements.
- Let's walk before we run. Don't solve scale problems I don't have.
- Always use the superpowers skill when getting ready to write code.

## Ruby Style

Write idiomatic, expressive Ruby — not Python or JavaScript translated into Ruby syntax. Ruby code should read like English.

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

Use `map`, `select`/`reject`, `flat_map`, `each_with_object`, `any?`/`all?`/`none?`, `tally`, `group_by`, `sum`. Always use `&:method_name` (Symbol#to_proc) when the block just calls one method.

When appending to an existing collection, use `concat` + `map` — not `each` + `<<`:
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
- Prefer `size` over `length` everywhere. `length` is Java/Python; `size` is Ruby.
- Prefer keyword arguments over positional arguments for clarity at call sites.
- Prefer `map` over `collect`, `select` over `find_all`, `key?` over `has_key?`.
- Never prefix with `get_` or `is_`. Use `name` not `get_name`. Use `valid?` not `is_valid?`.

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

# RIGHT — no comment needed, the names say it all
class RecipeBuilder
  def peek
  def parse_title

# RIGHT — explains WHY, not WHAT
# Miscellaneous defaults to last unless explicitly ordered
return [2, 0] if aisle == 'Miscellaneous'
```

## Architectural Comments

Every Ruby class/module and every JavaScript controller/utility gets a header comment explaining its **role**, **key collaborators**, and **non-obvious constraints**. CLAUDE.md is the map; the comments are the territory. Read a class's header comment first.

Plain prose. 2–5 lines. Answer: *what role does this play?*, *who does it talk to?*, and *why is it this way?* Add one when creating a new file. Update it when responsibilities change — a stale comment is worse than none.

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

## HTML & Security

A strict CSP is enforced (`config/initializers/content_security_policy.rb`). No inline styles, no external resources. Update the CSP initializer before adding any.

- **Never** call `.html_safe` on a string that interpolates user content without first escaping via `ERB::Util.html_escape`.
- **Never** use `raw()` on user content.
- In JavaScript, use `textContent` / `createTextNode` — never `innerHTML`.
- `rake lint:html_safe` audits `.html_safe` and `raw()` calls against `config/html_safe_allowlist.yml`. The allowlist uses `file:line_number` keys — update it whenever edits shift line numbers.
- Use semantic HTML. Recipes are **documents first** — marked-up text, not an app that happens to contain text.

## Architecture

Every class has an architectural header comment — read them first. This section covers only cross-cutting concerns that no single file explains.

**Multi-tenant scoping — non-negotiable.** All queries MUST go through `current_kitchen` (e.g., `current_kitchen.recipes.find_by!`). Never use unscoped model queries like `Recipe.find_by`.

**Two namespaces.** Rails app module: `Familyrecipes` (lowercase r). Domain parser module: `FamilyRecipes` (uppercase R). Different constants, no collision.

**Routing.** Routes use an optional `(/kitchens/:kitchen_slug)` scope. `default_url_options` auto-injects `kitchen_slug` — always use `_path` helpers. Use `home_path` (not `kitchen_root_path`) for homepage links. `MealPlan` (one row per kitchen) backs both the menu and groceries pages.

**Editor dialogs.** Use `render layout: 'shared/editor_dialog'` with Stimulus data attributes — no JS needed. For custom content, add a controller listening to editor lifecycle events.

## Recipe & Data Formats

Recipe source files are Markdown with some custom syntax:

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

**Ingredient syntax**: `- Name, Quantity: Prep note` (quantity and prep note optional). Examples: `- Eggs, 4: Lightly scrambled.` / `- Salt` / `- Garlic, 4 cloves`

**Front matter** (between description and first step):
- **Category** (required) — must match the recipe's subdirectory name under `db/seeds/recipes/`.
- **Makes** (optional) — `Makes: <number> <unit noun>`. Countable output (e.g., `Makes: 30 gougères`).
- **Serves** (optional) — `Serves: <number>`. People count only, no unit noun.
- A recipe can have both, just one, or neither (Category is always required).

**Quick Bites** are grocery bundles (not recipes) living on the menu page. Source format in `db/seeds/recipes/Quick Bites.md`:
```
## Category Name
  - Recipe Name: Ingredient1, Ingredient2
```
Stored in `Kitchen#quick_bites_content`, web-editable via a dialog on the menu page.

**Nutrition data** uses a density-first model in `db/seeds/resources/ingredient-catalog.yaml`:
```yaml
Flour (all-purpose):
  nutrients:
    basis_grams: 30.0
    calories: 110.0
    fat: 0.0
    # ... (saturated_fat, trans_fat, cholesterol, sodium, carbs, fiber,
    #       total_sugars, added_sugars, protein)
  density:                    # optional — enables volume unit resolution
    grams: 30.0
    volume: 0.25
    unit: cup
  portions:                   # optional — non-volume named portions only
    stick: 113.0
    ~unitless: 50             # bare count (e.g., "Eggs, 3")
  sources:
    - type: usda              # usda | label | other
      dataset: SR Legacy
      fdc_id: 168913
      description: "Wheat flour, white, all-purpose, enriched, unbleached"
```

## Commands

```bash
rake lint          # RuboCop — always use `bundle exec rubocop`, not bare `rubocop`
rake lint:html_safe # audit .html_safe / raw() calls against allowlist
rake test          # all tests via Minitest
ruby -Itest test/controllers/recipes_controller_test.rb              # single file
ruby -Itest test/models/recipe_test.rb -n test_requires_title        # single test
bin/dev            # Puma on port 3030
```

The default `rake` task runs both lint and test.

## Workflow

**Worktree cleanup.** Never run `git worktree remove` directly — it deletes the CWD and bricks the Bash tool. Use the wrapper:
```bash
bin/worktree-remove <name>
```

**Screenshots.** Save to `~/screenshots/`, not inside the repo.

**`Data.define` + Rails JSON.** Classes with custom `to_json` must also define `as_json` — see `Quantity` in `lib/familyrecipes/quantity.rb`.

**Server restart.** Adding gems, new concerns, or modifying `lib/familyrecipes/` requires restarting Puma (`pkill -f puma; rm -f tmp/pids/server.pid` then `bin/dev`). Domain classes in `lib/` are loaded once at boot — they do not hot-reload.

**Commit timestamps.** A post-commit hook rewrites timestamps for privacy.
