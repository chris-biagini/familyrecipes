# Architecture Audit Design

**Date:** 2026-02-22
**Scope:** Full architectural roadmap — decisions that are expensive to change later, evaluated across all planned milestones (OmniAuth, Docker, PWA, API).

## Decisions

| Area | Decision | Timing |
|------|----------|--------|
| Parsed-recipe bridge | Parse on save, store everything. Parser is write-path only. No parser at render time. | Milestone 1–2 |
| Multi-tenancy | Adopt `acts_as_tenant` gem. Add `kitchen_id` to `recipe_dependencies`. | Milestone 1 |
| Authentication | Cherry-pick Rails 8 auth patterns. OmniAuth with `:developer` strategy. `ConnectedService` model. No passwords. | Milestone 3 |
| URL structure | Keep `/kitchens/:kitchen_slug/...`. Rename `/index` to `/ingredients`. | Milestone 4 |
| SiteDocument | Extract `NutritionEntry` model. Keep other three as SiteDocuments. Consolidate fallback pattern. | Milestone 1 |
| Rails 8 features | ActiveJob classes with `perform_now`. Add Solid Queue when synchronous becomes too slow. PWA manifest stub. | Milestone 2 (jobs), 4 (PWA) |
| Docker | Health check, `.env.example`, remove filesystem deps. Generate Dockerfile at deploy time. | Milestone 4 (prep) |

## Guiding Principle: Backend Gems Are Fine

Backend dependencies are acceptable when they solve a real problem at current scale and don't cause performance issues. Frontend dependencies (JS/CSS/fonts loaded by the browser) remain restricted — lean over the wire. This distinction applies throughout.

---

## 1. Parse on Save — Eliminating the Render-Time Parser

### Problem

`RecipesController#show` loads an AR `Recipe` then re-parses the original markdown via the parser pipeline. This exists because the database doesn't store everything the renderer needs:

- Cross-reference multipliers (`@[Pizza Dough], 2` — the `2` is lost in `RecipeDependency`)
- Cross-reference prep notes
- Ingredient/cross-reference interleaving order within a step
- Scalable number markup (`<span class="scalable">`)
- Computed nutrition (calculated from parsed ingredients + nutrition data)

Additionally, every recipe page rebuilds a `recipe_map` by parsing ALL recipes in the kitchen, because `NutritionCalculator` needs to expand cross-references recursively.

### Design

**Make the database the complete source of truth for rendering.** The parser runs on the write path only (editor save, seed import). The read path loads from AR models exclusively.

#### New model: `CrossReference`

Stores what `RecipeDependency` can't — the rendering metadata for cross-references within a step's ingredient list.

```
cross_references
  id
  step_id          (FK, NOT NULL)
  kitchen_id       (FK, NOT NULL — acts_as_tenant)
  target_recipe_id (FK, NOT NULL)
  multiplier       (decimal, default: 1.0)
  prep_note        (string, nullable)
  position         (integer, NOT NULL — interleaving order with ingredients)
```

`position` shares the same sequence as `Ingredient#position` within a step. This preserves the interleaving order: ingredient at position 0, cross-reference at position 1, ingredient at position 2, etc.

`RecipeDependency` remains for graph queries (which recipes reference which, inbound/outbound traversal). `CrossReference` handles the per-step rendering data. They serve different purposes and are populated from the same parse pass.

#### Changed model: `Recipe`

Add `nutrition_data` (jsonb) — stores the pre-computed nutrition output from `NutritionCalculator`. Structure matches the current `NutritionCalculator::Result`: `totals`, `per_serving`, `per_unit`, `missing_ingredients`, `partial_ingredients`.

#### Changed model: `Step`

Add `processed_instructions` (text) — stores instructions with scalable number spans already applied by `ScalableNumberPreprocessor`. The raw `instructions` column stays for editing; `processed_instructions` is the render-ready HTML.

`has_many :cross_references, -> { order(:position) }, dependent: :destroy`

The view iterates a merged, position-ordered list of ingredients and cross-references for each step.

#### New model: `NutritionEntry`

Replaces the `nutrition_data` SiteDocument (a ~500-entry YAML blob). One row per ingredient.

```
nutrition_entries
  id
  kitchen_id       (FK, NOT NULL — acts_as_tenant)
  ingredient_name  (string, NOT NULL)
  basis_grams      (decimal, NOT NULL)
  calories         (decimal)
  fat              (decimal)
  saturated_fat    (decimal)
  trans_fat        (decimal)
  cholesterol      (decimal)
  sodium           (decimal)
  carbs            (decimal)
  fiber            (decimal)
  total_sugars     (decimal)
  added_sugars     (decimal)
  protein          (decimal)
  density_grams    (decimal, nullable)
  density_volume   (decimal, nullable)
  density_unit     (string, nullable)
  portions         (jsonb, default: {})
  sources          (jsonb, default: [])
  unique index: [kitchen_id, ingredient_name]
```

#### Write path

```
Markdown submitted (editor or seed import)
  → MarkdownValidator validates structure
  → MarkdownImporter parses via existing pipeline:
      LineClassifier → RecipeBuilder → IngredientParser
  → Stores to AR:
      Recipe (title, slug, description, footer, markdown_source, etc.)
      Steps (title, instructions, processed_instructions)
      Ingredients (name, quantity, unit, prep_note, position)
      CrossReferences (target_recipe_id, multiplier, prep_note, position)
      RecipeDependencies (source → target, for graph queries)
  → RecipeNutritionJob.perform_now(recipe):
      Loads NutritionEntry rows for all ingredients
      Expands cross-references (loads target recipe ingredients via AR)
      Calculates totals, per_serving, per_unit
      Stores result as recipe.nutrition_data (jsonb)
  → CrossReferenceNutritionJob.perform_now(recipe):
      Finds all recipes that reference this one (inbound dependencies)
      Re-runs RecipeNutritionJob for each
```

#### Read path

```
RecipesController#show
  → recipe = current_kitchen.recipes
      .includes(steps: [:ingredients, :cross_references])
      .find_by!(slug: params[:slug])
  → View renders from AR data:
      recipe.title, .description, .category.name, .footer
      step.processed_instructions (already has scalable spans)
      step.ingredients + step.cross_references (merged by position)
      recipe.nutrition_data (pre-computed JSON)
```

No parser. No recipe_map. No NutritionCalculator at render time.

#### What happens to the parser pipeline

The parser classes (`LineClassifier`, `RecipeBuilder`, `IngredientParser`, `FamilyRecipes::Recipe`, `FamilyRecipes::Step`, `FamilyRecipes::Ingredient`, `FamilyRecipes::CrossReference`) remain. They run on the write path inside `MarkdownImporter`. The domain objects are intermediate — produced by the parser, consumed by the importer, never seen by views.

`ScalableNumberPreprocessor` runs on save (processes `instructions` → `processed_instructions`).

`NutritionCalculator` runs on save (reads `NutritionEntry` rows, writes `recipe.nutrition_data`).

`IngredientAggregator` still runs at request time on the groceries page — it aggregates ingredients across selected recipes for the shopping list. This is fine because it reads from AR models (no parser needed) and the aggregation depends on which recipes the user selects (not cacheable on save).

---

## 2. Multi-Tenancy with `acts_as_tenant`

### Problem

Every controller manually scopes through `current_kitchen`. This works but relies on developer discipline — one unscoped `Recipe.find_by` is a cross-tenant data leak.

### Design

Adopt `acts_as_tenant` (v1.0+). The gem provides:

- Automatic `default_scope` filtering by `kitchen_id` on all tenanted models
- Auto-assignment of `kitchen_id` on create
- `require_tenant!` safety net (raises if no tenant set — catches mistakes in new code, background jobs, console)
- `ActsAsTenant.without_tenant { ... }` for tenant-agnostic queries (landing page, admin)

#### Configuration

```ruby
# config/initializers/acts_as_tenant.rb
ActsAsTenant.configure do |config|
  config.require_tenant = true
end
```

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  set_current_tenant_through_filter
  before_action :set_kitchen_from_path

  private

  def set_kitchen_from_path
    return unless params[:kitchen_slug]
    set_current_tenant(Kitchen.find_by!(slug: params[:kitchen_slug]))
  end

  def current_kitchen = ActsAsTenant.current_tenant
end
```

#### Models that get `acts_as_tenant(:kitchen)`

Direct `kitchen_id` (apply the declaration, remove manual `belongs_to :kitchen`):
- `Recipe`
- `Category`
- `SiteDocument`
- `Membership`
- `RecipeDependency` (after adding `kitchen_id` column)
- `CrossReference` (new model, has `kitchen_id` from the start)
- `NutritionEntry` (new model, has `kitchen_id` from the start)

#### Models that do NOT get `acts_as_tenant`

Inherited through associations (no direct `kitchen_id`):
- `Step` (accessed through `recipe.steps`)
- `Ingredient` (accessed through `step.ingredients`)

Tenant-agnostic:
- `Kitchen` (is the tenant)
- `User` (belongs to multiple kitchens through memberships)
- `Session` (belongs to user, not kitchen-scoped)
- `ConnectedService` (belongs to user, not kitchen-scoped)

#### Controllers that skip the tenant filter

```ruby
class LandingController < ApplicationController
  skip_before_action :set_kitchen_from_path
  # Uses ActsAsTenant.without_tenant implicitly (no tenant set)
end

class OmniauthCallbacksController < ApplicationController
  skip_before_action :set_kitchen_from_path
  # Auth happens outside kitchen context
end
```

#### Migration: Add `kitchen_id` to `recipe_dependencies`

```ruby
add_reference :recipe_dependencies, :kitchen, null: false, foreign_key: true
```

Populated from `source_recipe.kitchen_id` in a data migration.

---

## 3. Authentication

### Problem

Dev-only auth (`DevSessionsController` sets `session[:user_id]`) works but doesn't establish the patterns needed for OmniAuth. No `Session` model, no `Current` model, no `Authentication` concern.

### Design

Cherry-pick the Rails 8 auth generator's session infrastructure. Skip `has_secure_password` and all password-related code. Add OmniAuth with `:developer` strategy for dev/test.

#### New model: `Session`

Database-backed sessions with metadata for security auditing.

```
sessions
  id
  user_id     (FK, NOT NULL)
  ip_address  (string)
  user_agent  (string)
  timestamps
```

#### New model: `ConnectedService`

OAuth identity storage. Supports multiple providers per user.

```
connected_services
  id
  user_id   (FK, NOT NULL)
  provider  (string, NOT NULL)
  uid       (string, NOT NULL)
  timestamps
  unique index: [provider, uid]
```

#### New model: `Current`

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true
end
```

Note: `acts_as_tenant` manages its own thread-local tenant storage internally. `Current` handles auth state. They coexist without conflict.

#### `Authentication` concern

Adapted from the Rails 8 generator (~50 lines):

- `require_authentication` — before_action that redirects to login if no session
- `allow_unauthenticated_access` — class method to skip auth on specific actions
- `resume_session` — loads `Session` from signed cookie, sets `Current.session`
- `start_new_session_for(user)` — creates `Session` row, sets signed cookie
- `terminate_session` — destroys session row, clears cookie
- `authenticated?` — helper for views

Key difference from generator: `request_authentication` redirects to `/auth/developer` (dev) or a login page with OAuth buttons (production), not a password form.

#### `OmniauthCallbacksController`

```ruby
class OmniauthCallbacksController < ApplicationController
  allow_unauthenticated_access only: [:create, :failure]
  skip_before_action :set_kitchen_from_path

  def create
    auth = request.env['omniauth.auth']
    service = ConnectedService.find_by(provider: auth.provider, uid: auth.uid)

    if service
      start_new_session_for(service.user)
    else
      user = User.find_by(email: auth.info.email) || User.create!(
        name: auth.info.name,
        email: auth.info.email
      )
      user.connected_services.create!(provider: auth.provider, uid: auth.uid)
      start_new_session_for(user)
    end

    redirect_to after_authentication_url
  end
end
```

#### OmniAuth configuration

```ruby
# config/initializers/omniauth.rb
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :developer if Rails.env.development? || Rails.env.test?
  # Future: provider :google_oauth2, ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET']
end
```

#### Gems

- `omniauth` — core middleware
- `omniauth-rails_csrf_protection` — CSRF safety for OAuth POST routes

Google/Apple provider gems added later when credentials are available.

#### Changes to `User`

- Make `email` required: `validates :email, presence: true, uniqueness: true`
- Add associations: `has_many :sessions`, `has_many :connected_services`
- Remove the partial unique index on email (replace with full unique index)

#### What gets deleted

- `DevSessionsController` — replaced by OmniAuth `:developer` strategy
- Dev login/logout routes (`/dev/login/:id`, `/dev/logout`) — replaced by `/auth/developer` and `/logout`
- Manual `session[:user_id]` handling in `ApplicationController` — replaced by `Authentication` concern

#### What changes in `ApplicationController`

```ruby
class ApplicationController < ActionController::Base
  include Authentication

  set_current_tenant_through_filter
  before_action :set_kitchen_from_path

  private

  def set_kitchen_from_path
    return unless params[:kitchen_slug]
    set_current_tenant(Kitchen.find_by!(slug: params[:kitchen_slug]))
  end

  def current_kitchen = ActsAsTenant.current_tenant

  def current_user = Current.user

  def logged_in? = authenticated?

  def require_membership
    head :unauthorized unless logged_in? && current_kitchen&.member?(current_user)
  end

  def default_url_options
    { kitchen_slug: current_kitchen&.slug }.compact
  end
end
```

#### Test helper changes

```ruby
# test/test_helper.rb
def log_in(user)
  service = user.connected_services.first_or_create!(provider: 'developer', uid: user.email)
  session = user.sessions.create!(ip_address: '127.0.0.1', user_agent: 'Test')
  cookies.signed.permanent[:session_id] = session.id
end
```

---

## 4. URL Structure

### Change

Rename `/kitchens/:kitchen_slug/index` to `/kitchens/:kitchen_slug/ingredients`.

### Route plan for future features

```ruby
# Kitchen-scoped (inside scope block)
get 'ingredients', to: 'ingredients#index'        # renamed from 'index'
# Future: resources :comments (nested under recipes)
# Future: get 'settings', to: 'kitchen_settings#show'

# Tenant-agnostic (outside scope block)
# /auth/:provider/callback  (OmniAuth — handled by middleware)
# /logout                   (session destroy)
# Future: /profile           (user settings, multi-kitchen)
# Future: /up                (health check)
```

---

## 5. SiteDocument Consolidation

### Extract: `NutritionEntry` model

See section 1 for the schema. Replaces the `nutrition_data` SiteDocument. One row per ingredient, fully queryable. Kitchen-scoped via `acts_as_tenant`.

`bin/nutrition` is updated to read/write `NutritionEntry` rows instead of YAML. The USDA lookup and manual entry modes remain — only the storage backend changes.

Seed migration: `db/seeds.rb` reads `nutrition-data.yaml` and creates `NutritionEntry` rows (instead of storing the YAML blob as a SiteDocument).

### Keep as SiteDocuments

- `site_config` — 4 key-value pairs, read-only after seed, no benefit to a dedicated model
- `quick_bites` — user-editable text blob, parsed by `FamilyRecipes.parse_quick_bites_content`
- `grocery_aisles` — user-editable text blob, parsed by `FamilyRecipes.parse_grocery_aisles_markdown`

### Consolidate fallback pattern

Add a class method to `SiteDocument`:

```ruby
class SiteDocument < ApplicationRecord
  acts_as_tenant(:kitchen)

  def self.content_for(name, fallback_path: nil)
    find_by(name: name)&.content || (fallback_path && File.read(fallback_path))
  end
end
```

Replaces the four separate `load_X` methods across controllers.

---

## 6. ActiveJob Classes

### Design

Structure save-time work as job classes. Run synchronously with `perform_now` for now. Add Solid Queue later when synchronous execution becomes too slow.

**Decision to document:** When `perform_now` causes noticeably slow recipe saves (measured, not guessed), add `solid_queue` gem and switch to `perform_later`. Solid Queue runs inside Puma via `plugin :solid_queue` — no separate process needed.

#### Jobs

```ruby
# app/jobs/recipe_nutrition_job.rb
class RecipeNutritionJob < ApplicationJob
  def perform(recipe)
    # Calculate nutrition from NutritionEntry rows + AR ingredients/cross-references
    # Store result in recipe.nutrition_data (jsonb)
  end
end

# app/jobs/cascade_nutrition_job.rb
class CascadeNutritionJob < ApplicationJob
  def perform(recipe)
    # Find all recipes that reference this one (inbound dependencies)
    # Re-run RecipeNutritionJob for each
  end
end
```

Called from `MarkdownImporter` after a successful save:

```ruby
RecipeNutritionJob.perform_now(recipe)
CascadeNutritionJob.perform_now(recipe)
```

### PWA manifest stub

Add `public/manifest.json` with app name, icons, theme color, display mode. Add a minimal service worker at `public/service-worker.js` that caches the app shell. Makes the app installable on mobile. No offline recipe support yet — that comes later with Solid Cache + service worker cache strategies.

---

## 7. Docker Prep

### Changes now

- **Health check route:** `get '/up', to: 'rails/health#show'` (Rails 8 built-in)
- **`.env.example`:** Document all environment variables: `DATABASE_HOST`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`, `PORT`, `BINDING`, `RAILS_MAX_THREADS`, `WEB_CONCURRENCY`, `SECRET_KEY_BASE`, and reserved slots for `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
- **Remove filesystem dependencies:** `NutritionEntry` model eliminates `bin/nutrition` YAML file dependency. Seed data still reads from filesystem but only at `db:seed` time (baked into Docker image).
- **Comment `config/boot.rb` binding:** Explain the `0.0.0.0` default is intentional for LAN/container access.

### Deferred

- Dockerfile generation (use `dockerfile-rails` gem when ready to deploy)
- docker-compose.yml
- CI/CD pipeline updates

---

## Milestone Ordering

### Milestone 1: Data Foundation

Dependencies: none

- Add `acts_as_tenant` gem, configure initializer
- Create `CrossReference` model + migration
- Create `NutritionEntry` model + migration
- Add `kitchen_id` to `recipe_dependencies` + data migration
- Add `nutrition_data` (jsonb) to `recipes`
- Add `processed_instructions` to `steps`
- Apply `acts_as_tenant(:kitchen)` to all direct-kitchen models
- Update `MarkdownImporter` to store cross-references fully (multiplier, prep_note, position)
- Update `NutritionCalculator` to read from `NutritionEntry` rows
- Update `bin/nutrition` to write `NutritionEntry` rows
- Update `db/seeds.rb` to create `NutritionEntry` rows from YAML
- Compute and store nutrition on recipe save
- Consolidate `SiteDocument` fallback pattern
- Update all controller queries to work with `acts_as_tenant` (remove explicit `current_kitchen.` prefixes where the gem handles it)

### Milestone 2: Eliminate Parser at Render Time

Dependencies: Milestone 1

- Run `ScalableNumberPreprocessor` on save, store in `processed_instructions`
- Update `RecipesController#show` to load from AR only
- Update recipe views to render from AR models (steps with interleaved ingredients + cross-references via position ordering)
- Create `RecipeNutritionJob` and `CascadeNutritionJob` (`perform_now`)
- Delete render-time parser code paths from controllers
- Delete `recipe_map` rebuild
- Update tests for new render path

### Milestone 3: Authentication

Dependencies: none (can run in parallel with Milestones 1–2)

- Create `Session` model + migration
- Create `Current` model
- Create `Authentication` concern
- Create `ConnectedService` model + migration
- Add `omniauth` and `omniauth-rails_csrf_protection` gems
- Create OmniAuth initializer with `:developer` strategy
- Create `OmniauthCallbacksController`
- Make `email` required on User + migration
- Update `ApplicationController` to include `Authentication`
- Delete `DevSessionsController` and dev login/logout routes
- Update test helpers for new auth flow
- Update all controller tests

### Milestone 4: Polish and Prep

Dependencies: Milestones 1–3

- Rename `/index` route to `/ingredients`
- Add health check route (`/up`)
- Create `.env.example`
- Add PWA manifest stub
- Comment `config/boot.rb` binding
- Document Solid Queue upgrade path in CLAUDE.md
- Update CLAUDE.md for new architecture

### Future Milestones (Not In This Audit)

- **Solid Queue:** Add when `perform_now` becomes too slow
- **OmniAuth providers:** Add Google/Apple when deployment target exists
- **Pundit:** Add when `Membership#role` starts doing real work (admin/member/viewer)
- **Docker:** Generate Dockerfile when ready to deploy
- **PWA offline:** Service worker caching strategies for offline recipe access
- **API:** The parse-on-save architecture makes a JSON API straightforward — AR models are the complete source of truth
- **commonmarker:** Not recommended as a replacement for the custom parser. Could replace Redcarpet as the markdown-to-HTML renderer for instruction prose, but this is a lateral move, not a priority.
