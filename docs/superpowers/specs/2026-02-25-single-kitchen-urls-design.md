# Single-Kitchen URL Simplification

## Context

All routes currently live under `/kitchens/:kitchen_slug/`. For a homelab deployment with
exactly one kitchen, this prefix is visual noise — `/kitchens/biagini-family/recipes/bagels`
should just be `/recipes/bagels`. When a second kitchen is added, the prefix should
reappear automatically.

## Decisions

- **Dynamic mode switching.** One kitchen = root-level URLs. Two+ kitchens = scoped URLs.
  No configuration flag — the route behavior adapts to the kitchen count.
- **No backwards-compatibility redirects.** Old-style `/kitchens/:slug/...` URLs naturally
  continue to work (the route still matches), but we add no redirect code.
- **Root path serves homepage in single-kitchen mode.** No redirect from `/` to
  `/kitchens/:slug` — the homepage renders directly at `/`.

## 1. Routes: Optional Scope

Wrap kitchen-scoped routes in an optional segment so both URL shapes resolve to the same
controller actions:

```ruby
root 'landing#show'

get 'kitchens/:kitchen_slug', to: 'homepage#show', as: :kitchen_root

scope '(/kitchens/:kitchen_slug)' do
  resources :recipes, only: %i[show create update destroy], param: :slug
  get 'ingredients', to: 'ingredients#index', as: :ingredients
  get 'groceries', to: 'groceries#show', as: :groceries
  # ... all other grocery/nutrition routes
end
```

The optional `(/kitchens/:kitchen_slug)` segment means:
- `recipe_path('bagels')` generates `/recipes/bagels` when no `kitchen_slug` is supplied.
- `recipe_path('bagels', kitchen_slug: 'biagini-family')` generates
  `/kitchens/biagini-family/recipes/bagels`.
- `default_url_options` controls which shape path helpers produce.

The `root` route takes priority over the optional scope for `GET /`, so the landing
page controller handles the root path.

The `kitchen_root` route stays outside the optional scope — it always requires a slug
and is only used in multi-kitchen contexts.

## 2. Kitchen Resolution

`ApplicationController#set_kitchen_from_path` gets two resolution paths:

```ruby
def set_kitchen_from_path
  if params[:kitchen_slug]
    set_current_tenant(Kitchen.find_by!(slug: params[:kitchen_slug]))
    return
  end

  kitchen = resolve_sole_kitchen
  if kitchen
    set_current_tenant(kitchen)
  else
    redirect_to root_path
  end
end

def resolve_sole_kitchen
  kitchens = ActsAsTenant.without_tenant { Kitchen.limit(2).to_a }
  kitchens.first if kitchens.size == 1
end
```

When `kitchen_slug` is absent and multiple kitchens exist, the request hit a root-level
route that can't resolve a kitchen — redirect to the landing page.

**Performance:** `LIMIT 2` means at most two rows are loaded, making the sole-kitchen
check negligible. No caching needed for a table with 1-2 rows.

## 3. `default_url_options`

```ruby
def default_url_options
  if params[:kitchen_slug]
    { kitchen_slug: params[:kitchen_slug] }
  else
    {}
  end
end
```

When `kitchen_slug` is in the request params (multi-kitchen mode), path helpers produce
scoped URLs. When absent (single-kitchen mode), they produce root-level URLs. This
requires zero changes to existing view code — `recipe_path(slug)`,
`groceries_state_path`, etc. all produce the right shape automatically.

## 4. Landing Page as Homepage

`LandingController#show` currently redirects to the sole kitchen. Instead, it renders
the homepage template directly:

```ruby
def show
  @kitchens = ActsAsTenant.without_tenant { Kitchen.all.to_a }
  return render_sole_kitchen_homepage if @kitchens.size == 1
  # Multi-kitchen: falls through to render landing/show
end
```

`render_sole_kitchen_homepage` sets the tenant, loads `@site_config` and `@categories`,
and renders `homepage/show`. This eliminates the redirect — the URL stays at `/`.

## 5. `home_path` Helper

`kitchen_root_path` requires a `kitchen_slug` parameter and always generates
`/kitchens/:slug`. In single-kitchen mode, the "home" link should point to `/`.

Add a `home_path` helper method to `ApplicationController` (exposed via `helper_method`):

```ruby
def home_path(**opts)
  params[:kitchen_slug] ? kitchen_root_path(**opts) : root_path(**opts)
end
```

Replace `kitchen_root_path` with `home_path` in:
- `app/views/shared/_nav.html.erb` (Home link)
- `app/views/recipes/show.html.erb` (category link)
- `RecipesController#destroy` (redirect URL in JSON response)

The multi-kitchen landing page (`landing/show.html.erb`) keeps its explicit
`kitchen_root_path(kitchen_slug: kitchen.slug)` calls — those are always kitchen-scoped.

## 6. ActionCable — No Changes

The groceries page passes `data-kitchen-slug` to JavaScript for ActionCable subscription
identity and localStorage keys. This is independent of URL structure — the kitchen slug
is still needed for channel subscription regardless of URL mode. No changes needed.

## 7. Edge Cases

**Second kitchen added while user browses root-level URLs.** The root-level routes still
match, but `set_kitchen_from_path` can no longer resolve a sole kitchen. It redirects to
the landing page, which now shows the kitchen list. The user picks a kitchen and continues
with kitchen-scoped URLs.

**Kitchen-scoped URLs in single-kitchen mode.** These naturally work because the optional
scope matches both shapes. A user who bookmarked `/kitchens/biagini-family/recipes/bagels`
can still use it. All links on that page will be kitchen-scoped (because `kitchen_slug`
is in params), but everything functions correctly.

**Kitchen deleted leaving zero.** `set_kitchen_from_path` finds no sole kitchen, redirects
to the landing page, which renders an empty kitchen list. Same as today.

**Tests.** Existing tests pass `kitchen_slug:` explicitly to path helpers. These continue
to work — they generate kitchen-scoped URLs, which the optional scope matches. No test
changes required for existing behavior.
