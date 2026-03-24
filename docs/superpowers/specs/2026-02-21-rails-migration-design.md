# Rails 8 Migration Design

## Goal

Add a Rails 8 app to the project as a second output path. The static GitHub Pages site (`bin/generate` → `output/web/`) stays as-is. Rails serves recipes dynamically for local development and future hosted deployment.

## Architecture: Dual Output Paths

Same domain model (`Recipe`, `Step`, `Ingredient`, etc.), two rendering paths:

1. **Static build** — `bin/generate` → SiteGenerator → ERB templates → HTML files → GitHub Pages
2. **Rails app** — `bin/rails server` → controllers → domain model → Rails views → dynamic HTML

The domain model in `lib/familyrecipes/` is shared. Templates are separate: `templates/web/` for static, `app/views/` for Rails.

## URL Strategy

### Current (single-tenant, no username prefix)

| URL | Purpose |
|-----|---------|
| `/` | Homepage |
| `/:id` | Individual recipe (e.g., `/chocolate-cake`) |
| `/index` | Ingredient index |
| `/groceries` | Grocery list builder |
| `/style.css`, etc. | Static assets |

Recipes live at root. Explicit routes (`/index`, `/groceries`) go first; the `/:id` catch-all goes last with a constraint like `{ id: /[a-z0-9-]+/ }`.

### Future (multi-tenant hosted version)

```
/:username                        → recipe list
/:username/:id                    → individual recipe
/:username/collections            → list of categories
/:username/collections/:category  → filtered by category
/settings                         → user settings
/about                            → about page
```

Reserved words (`settings`, `about`, `admin`, `api`) routed explicitly above the catch-all. The single-tenant version is the degenerate case — no username segment.

## Phase 2: Bootstrap Rails as Static File Server

### Rails setup

Minimal Rails 8 with aggressive skips:

```
rails new . --skip-active-record --skip-action-mailer \
  --skip-action-mailbox --skip-action-text --skip-active-job \
  --skip-active-storage --skip-action-cable --skip-test \
  --skip-system-test --skip-hotwire --skip-jbuilder \
  --skip-kamal --skip-solid --skip-thruster
```

No database, no background jobs, no email, no Hotwire, no deployment tooling. Just Rack + Action Pack + Action View.

### Serving output/web/

Rack::Static middleware configured to serve from `output/web/` at `/`. Rails' own `public/` stays clean for Rails-specific static files.

### Clean URLs

Small Rack middleware (~10 lines) that appends `.html` to requests when no exact file match exists. Mirrors the existing `CleanURLHandler` in `bin/serve`. This middleware becomes redundant for dynamically-served pages in Phase 3b but stays as a fallback for any remaining static files.

### Dev workflow

```
bin/generate && bin/rails server
```

## Phase 3a: File Watching

Use Rails' built-in `ActiveSupport::EventedFileUpdateChecker` (backed by the `listen` gem) to watch `recipes/**/*.md`. On change, trigger regeneration of the static site.

Configured in a Rails initializer. Watches all `.md` files under `recipes/` with a flat glob — no dependency on the subdirectory structure.

## Phase 3b: Dynamic Recipe Serving

### Controller

`RecipesController#show`:

1. Find markdown file by slug (flat glob across `recipes/**/*.md`, not dependent on subdirectory structure)
2. Parse with existing `Recipe` class — category comes from front matter, not directory name
3. Render through Rails view (`app/views/recipes/show.html.erb`)
4. Cache result keyed on file content hash or mtime
5. Cache invalidated by file watcher (Phase 3a)

### Views

New Rails-native ERB in `app/views/`:
- `layouts/application.html.erb` — replaces `_head.html.erb` + `_nav.html.erb`
- `recipes/show.html.erb` — recipe page
- `homepage/show.html.erb` — homepage
- `ingredient_index/show.html.erb` — ingredient index
- `groceries/show.html.erb` — grocery list builder

Visually identical output to the static templates. Uses Rails conventions: `render partial:`, `content_for`, `asset_path` helpers.

### Domain model

Used directly — `Recipe`, `Step`, `Ingredient`, `NutritionCalculator`, etc. No wrapping, no adapters. They're already clean Ruby objects with no framework dependencies.

## Audit Findings

### No blockers

- Domain model is pure Ruby POPOs — zero Rails conflicts
- No class naming collisions with Rails conventions
- Minitest is already the Rails default
- All JS is vanilla with no build toolchain
- Zero existing Rails dependencies

### Template incompatibilities (addressed in Phase 3b, not before)

- Templates use custom `render.call()` lambda → Rails uses `render partial:`
- `Recipe#to_html()` owns rendering → moves to view layer in Rails path
- `_head.html.erb` uses `defined?(extra_head)` → Rails uses `local_assigns.key?`
- `<base href>` for relative URLs → Rails uses `asset_path` helpers
- `FamilyRecipes::Inflector` shares name with `ActiveSupport::Inflector` (namespaced, no conflict)

### Static build path unchanged

`bin/generate`, `templates/web/`, `resources/web/`, and the GitHub Pages deployment pipeline are not modified. They continue to work exactly as they do today.
