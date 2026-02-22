# Auth & Kitchens Design

Date: 2026-02-22

## Goal

Introduce the concept of "being logged in" so the app can show/hide edit UI, protect write endpoints, and scope data to a kitchen (tenant). This is phase 1 of a multi-phase auth rollout — no passwords, no OAuth, no login form. Just the data model, helpers, and a dev-only session mechanism.

## Phased Rollout (Context)

1. **Now (this design):** Kitchen + User + Membership models, `current_user`/`current_kitchen` helpers, kitchen-scoped URLs, dev-only login route, conditional edit UI, protected write endpoints.
2. **Soon:** OmniAuth (Apple to start) with a separate Identity model. The only thing that changes is how `session[:user_id]` gets set — everything downstream stays the same.
3. **Later:** More OAuth providers, invitation flows, magic links for shared grocery lists, possibly kitchen privacy (members-only viewing).

## Data Model

### New Tables

**kitchens**

| Column     | Type    | Notes                |
|------------|---------|----------------------|
| id         | bigint  | PK                   |
| name       | string  | e.g., "Biagini Family" |
| slug       | string  | unique, e.g., "biagini-family" |
| created_at | datetime |                     |
| updated_at | datetime |                     |

**users**

| Column     | Type    | Notes                |
|------------|---------|----------------------|
| id         | bigint  | PK                   |
| name       | string  |                      |
| email      | string  | unique, nullable     |
| created_at | datetime |                     |
| updated_at | datetime |                     |

No password digest. Dev login sets `session[:user_id]` directly. OmniAuth will create an Identity model later.

**memberships**

| Column     | Type    | Notes                |
|------------|---------|----------------------|
| id         | bigint  | PK                   |
| kitchen_id | bigint  | FK → kitchens        |
| user_id    | bigint  | FK → users           |
| role       | string  | default: "member"    |
| created_at | datetime |                     |
| updated_at | datetime |                     |

Unique index on `[kitchen_id, user_id]`. The `role` column is a hedge — defaults to "member", nothing reads it yet. Available for future use without a migration.

### Altered Tables

Add `kitchen_id` (bigint, FK → kitchens, NOT NULL) to:

- **categories** — a kitchen's recipe categories
- **recipes** — direct FK avoids joins for scoping queries (categories already belong to a kitchen, but the direct FK is worth the redundancy)
- **site_documents** — quick bites and grocery aisles are per-kitchen

### What's NOT Here

- No `identities` table — deferred until OmniAuth.
- No `sessions` table — Rails cookie store is sufficient. Swap to `ActiveRecord::SessionStore` later if server-side revocation is needed.

## Routing

### URL Structure

```
/                                                → landing page
/kitchens/:kitchen_slug                          → kitchen homepage
/kitchens/:kitchen_slug/recipes/:slug            → recipe
/kitchens/:kitchen_slug/recipes (POST/PATCH/DELETE)
/kitchens/:kitchen_slug/index                    → ingredient index
/kitchens/:kitchen_slug/groceries                → grocery list
/kitchens/:kitchen_slug/groceries/quick_bites    → quick bites (PATCH)
/kitchens/:kitchen_slug/groceries/grocery_aisles → aisles (PATCH)

/dev/login/:id                                   → dev login (development only)
/dev/logout                                      → dev logout (development only)
```

### Route Definition

```ruby
root 'landing#show'

scope 'kitchens/:kitchen_slug' do
  get '/', to: 'homepage#show', as: :kitchen_root
  resources :recipes, only: %i[show create update destroy], param: :slug
  get 'index', to: 'ingredients#index', as: :ingredients
  get 'groceries', to: 'groceries#show', as: :groceries
  patch 'groceries/quick_bites', to: 'groceries#update_quick_bites', as: :groceries_quick_bites
  patch 'groceries/grocery_aisles', to: 'groceries#update_grocery_aisles', as: :groceries_grocery_aisles
end
```

### Design Decisions

- **`/kitchens/` prefix** (plural, not vanity root slug): self-documenting, zero route-collision risk, consistent with `/recipes/` plural. `/kitchens/` itself becomes a natural discovery/explore page later.
- **`default_url_options`** auto-fills `kitchen_slug` so existing view helpers need minimal changes.
- **`root_path`** now points to the landing page. Kitchen homepage links use `kitchen_root_path`.

## Authentication

### Session Management

Rails cookie store (the default). `session[:user_id]` is the only stored value. The cookie is signed and encrypted by Rails automatically.

### ApplicationController

```ruby
class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  helper_method :current_user, :current_kitchen, :logged_in?

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def current_kitchen
    @current_kitchen ||= Kitchen.find_by!(slug: params[:kitchen_slug])
  end

  def logged_in?
    current_user.present?
  end

  def require_authentication
    head :unauthorized unless logged_in?
  end

  def require_membership
    head :unauthorized unless logged_in? && current_kitchen.member?(current_user)
  end

  def default_url_options
    { kitchen_slug: current_kitchen&.slug }.compact
  end
end
```

Two gates:
- **`require_authentication`** — any logged-in user (for routes outside a kitchen that still need login).
- **`require_membership`** — logged-in user is a member of the current kitchen. This protects write endpoints.

`Kitchen#member?(user)` is a simple `memberships.exists?(user: user)`.

### Controller Protection

```ruby
class RecipesController < ApplicationController
  before_action :require_membership, only: %i[create update destroy]
end

class GroceriesController < ApplicationController
  before_action :require_membership, only: %i[update_quick_bites update_grocery_aisles]
end
```

Read endpoints remain fully public. Write endpoints require kitchen membership.

### View Conditionals

```erb
<% if current_kitchen.member?(current_user) %>
  <button data-editor-open>Edit</button>
<% end %>
```

Edit buttons, "+ New" button, delete buttons — all wrapped in this check. Non-members see a clean read-only page.

### Dev Login

```ruby
class DevSessionsController < ApplicationController
  def create
    user = User.find(params[:id])
    session[:user_id] = user.id
    redirect_to kitchen_root_path(kitchen_slug: user.kitchens.first.slug)
  end

  def destroy
    reset_session
    redirect_to root_path
  end
end
```

Routes are only loaded in the development environment. `GET /dev/login/1` logs in, `GET /dev/logout` logs out.

### JavaScript — No Changes Needed

Fetch calls in `recipe-editor.js` and `groceries.js` already send the CSRF token. Session cookies travel automatically with same-origin requests. Auth is checked server-side. If a non-member somehow triggers a write request, the 401 response is handled by existing error display logic.

### Groceries Page State — No Auth Implications

Recipe selection, checked-off items, custom items are all client-side (localStorage + URL params). No server-side session interaction. A future shared grocery list via magic link works the same way — the share URL encodes the state, the viewer doesn't need to be logged in.

## Landing Page

A new `LandingController#show` at `/`. Same visual language (gingham background, content card). Minimal content for now:

- Site name/heading
- Link to the one existing kitchen

The landing page exists outside any kitchen scope — no `:kitchen_slug` in the route, so `current_kitchen` is not available. It has access to `current_user` only. Navigation is simpler than the kitchen-scoped nav (no Home/Index/Groceries links, which are kitchen-scoped).

Later: sign-in button, kitchen directory, "create your kitchen" CTA.

## Seed Data

```ruby
kitchen = Kitchen.find_or_create_by!(slug: 'biagini-family') do |k|
  k.name = 'Biagini Family'
end

user = User.find_or_create_by!(email: 'chris@example.com') do |u|
  u.name = 'Chris'
end

Membership.find_or_create_by!(kitchen: kitchen, user: user)

# Existing recipe/category/site_document seeding associates records with the kitchen
```

Idempotent, same pattern as the existing seeds.

## Test Strategy

### Existing Tests

Every URL gains a kitchen slug. Every write test needs a logged-in session. Mechanical updates:

- Create kitchen + user + membership in test setup
- Include kitchen slug in all path helpers
- Set `session[:user_id]` (or call `log_in_as(user)` helper) before write requests

### New Auth Tests

- Unauthorized write attempts return 401
- Edit buttons absent for non-members and logged-out visitors
- Dev login sets session and redirects to kitchen
- Dev logout clears session and redirects to landing page

### Test Helper

```ruby
def log_in_as(user)
  post dev_login_path(id: user.id)
end
```

## Full Change Inventory

| What                          | Change Type     |
|-------------------------------|-----------------|
| Kitchen model                 | New             |
| User model                    | New             |
| Membership model              | New             |
| LandingController             | New             |
| DevSessionsController         | New             |
| Landing page view             | New             |
| Migrations (3 new tables)     | New             |
| Migration (kitchen_id FKs)    | Alter           |
| config/routes.rb              | Rewrite         |
| ApplicationController         | Add auth helpers |
| RecipesController             | Add before_action |
| GroceriesController           | Add before_action |
| HomepageController            | Scoped queries  |
| IngredientsController         | Scoped queries  |
| Layout/nav                    | Kitchen-scoped helpers |
| Views (edit buttons)          | Membership check wrapping |
| db/seeds.rb                   | Kitchen/user creation |
| All tests                     | Kitchen slug + session setup |
| JavaScript                    | **No changes**  |

## Explicitly Deferred

- Identity model / OmniAuth
- Multi-kitchen management UI (create kitchen, invite members)
- Kitchen privacy (public vs. members-only)
- Magic links for shared grocery lists
- Role-based authorization (column exists, nothing reads it)
- `/kitchens/` directory/explore page
- Database-backed sessions
