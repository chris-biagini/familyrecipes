# How Your Rails App Works

You built the recipe parser. You know `LineClassifier`, `RecipeBuilder`, `IngredientParser` inside and out. You wrote `FamilyRecipes::Recipe`, `FamilyRecipes::Step`, `FamilyRecipes::Ingredient` — the classes that turn a Markdown file into structured Ruby objects.

This tutorial shows you what Rails does with those objects.

It is not a Rails course. It won't teach you to write controllers or configure routes. It's a guided tour of *your* app — the one wrapped around your parser — so you can have informed conversations with Claude about how it works, why things are where they are, and what to ask for when you want something changed.

**You don't need to memorize any of this.** The point is to build a mental model: a sense of which pieces exist, what they're called, and roughly how they connect. When you're talking to Claude about a feature or a bug, knowing the right word — "controller," "migration," "concern" — gets you to the answer faster. If you forget the details, just point Claude at this document.

## How to read this

The tutorial follows two stories through the codebase. Each one traces a real HTTP request from the moment it hits the server to the moment the browser gets a response.

### Table of Contents

**[Journey 1: Someone reads your Focaccia recipe](#journey-1-someone-reads-your-focaccia-recipe)**
A visitor types in a URL and gets a recipe page. This is the *read path* — a GET request that flows through routing, a controller, the database, and a view template. By the end you'll understand how a URL becomes an HTML page, and where your parser's output lives in the database.

**[Journey 2: Someone edits and saves that recipe](#journey-2-someone-edits-and-saves-that-recipe)**
A logged-in family member opens the recipe editor, changes an ingredient, and hits save. This is the *write path* — a PATCH request that goes through authentication, validation, your parser (yes, it runs again here), and the database import pipeline. By the end you'll understand how the app protects data, when your code runs, and how edits flow back into the database.

**[Glossary](#glossary)**
A reference list of Rails terms used in this tutorial — routes, controllers, models, migrations, concerns, and the rest — defined in the context of your app, not in the abstract.

---

### A word about the app itself

This is a Rails 8 application backed by PostgreSQL. It runs on a single server (Puma) with no background job queue, no JavaScript framework, and no build step. Recipes are authored in Markdown, parsed by your code at save time, and stored as structured rows in the database. Every page renders live from those rows — there is no static site generator.

The app supports multiple "Kitchens" (think of them as separate family cookbooks that share the same server), and uses OmniAuth for login. All recipe data is scoped to a Kitchen, so one family's recipes never leak into another's.

If you run `bin/dev`, the server starts on port 3030 and you can see it at `http://localhost:3030`.

---

*Let's start with the read path.*

## Journey 1: Someone reads your Focaccia recipe

A visitor opens their browser and navigates to `http://localhost:3030/kitchens/test-kitchen/recipes/focaccia`. No login required — they just want to read the recipe. Here's everything that happens between that keystroke and the finished page.

### Stop 1: The Route

Every request starts in `config/routes.rb`. This file is a map: it tells Rails which code should handle which URL. Here's the part that matters:

```ruby
scope 'kitchens/:kitchen_slug' do
  get '/', to: 'homepage#show', as: :kitchen_root
  resources :recipes, only: %i[show create update destroy], param: :slug
  get 'index', to: 'ingredients#index', as: :ingredients
  get 'groceries', to: 'groceries#show', as: :groceries
  # ...
end
```

`scope 'kitchens/:kitchen_slug'` means every route inside this block starts with `/kitchens/something`. The `:kitchen_slug` part is a **parameter** — Rails extracts whatever value appears in that spot and makes it available as `params[:kitchen_slug]`. For our URL, that's `"test-kitchen"`.

`resources :recipes, only: %i[show create update destroy], param: :slug` is a single line that generates four separate routes — one for each action listed. It's Rails shorthand for mapping URLs to controller actions following REST conventions. The `param: :slug` option tells Rails to use `:slug` instead of the default `:id` in URLs, so you get `/recipes/focaccia` rather than `/recipes/47`.

The route that matches our GET request is: `GET /kitchens/:kitchen_slug/recipes/:slug` maps to `RecipesController#show`. That notation means "the `show` method inside `RecipesController`." Rails figured this out from `resources :recipes` — the `show` action responds to GET requests at the resource's path with a slug parameter.

This file also generates **route helpers** — Ruby methods that build URLs for you. `recipe_path('focaccia')` returns `"/kitchens/test-kitchen/recipes/focaccia"`. Views and controllers always use these helpers instead of hardcoding URL strings, so if you change the URL structure in the routes file, every link in the app updates automatically.

But wait — `recipe_path('focaccia')` only takes the recipe slug. How does it know the kitchen? That's `default_url_options` in `ApplicationController`:

```ruby
def default_url_options
  { kitchen_slug: current_kitchen&.slug }.compact
end
```

This method automatically fills in `kitchen_slug` for every route helper, so you almost never need to specify it yourself.

### Stop 2: The Controller Pipeline

Rails has matched the URL to `RecipesController#show`. Before it runs that method, though, it runs a chain of setup steps defined in `ApplicationController` — the parent class that every controller inherits from. Open `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern
  allow_unauthenticated_access

  set_current_tenant_through_filter
  before_action :resume_session
  before_action :set_kitchen_from_path

  helper_method :current_kitchen, :logged_in?

  # ...
end
```

Those `before_action` lines are the pipeline. They're **callbacks** — methods that Rails calls automatically before every controller action, in order. Think of them as a series of gates the request passes through before it reaches the action itself.

`resume_session` comes from the `Authentication` **concern** (a module mixed into the controller via `include Authentication`). It checks whether the visitor has a login cookie and restores their session if so. For our anonymous visitor, it finds nothing — and that's fine, because `allow_unauthenticated_access` at the top tells Rails not to require login. We'll dig into authentication in Journey 2.

`set_kitchen_from_path` is the important one for the read path:

```ruby
def set_kitchen_from_path
  return unless params[:kitchen_slug]

  set_current_tenant(Kitchen.find_by!(slug: params[:kitchen_slug]))
end
```

It takes the `kitchen_slug` extracted from the URL (`"test-kitchen"`), looks up the matching Kitchen in the database, and sets it as the **current tenant**. From this point forward, every database query is automatically scoped to this kitchen. The `find_by!` with the bang means "find it or raise an error" — if someone visits `/kitchens/nonexistent/recipes/focaccia`, this line blows up and Rails returns a 404.

`current_kitchen` is just a reader that returns whatever tenant was set:

```ruby
def current_kitchen = ActsAsTenant.current_tenant
```

Now the pipeline is done. Rails calls the actual action — `RecipesController#show`. Open `app/controllers/recipes_controller.rb`:

```ruby
class RecipesController < ApplicationController
  before_action :require_membership, only: %i[create update destroy]

  def show
    @recipe = current_kitchen.recipes
                             .includes(steps: %i[ingredients cross_references])
                             .find_by!(slug: params[:slug])
    @nutrition = @recipe.nutrition_data
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
```

Notice the `before_action :require_membership, only: %i[create update destroy]` at the top. The `only:` option means this callback runs *only* for create, update, and destroy — not for show. Our visitor doesn't need to be logged in to read a recipe. That one line is the entire access control for this controller.

The action itself is three lines: load the recipe, load nutrition data, and handle the case where it doesn't exist. The `@recipe` **instance variable** (the `@` prefix) is how the controller passes data to the view — any instance variable set in the action is automatically available in the template. That's a Rails convention you'll see everywhere.

### Stop 3: ActiveRecord — Loading the Data

Let's zoom into the query line, because there's a lot happening in one chain:

```ruby
@recipe = current_kitchen.recipes
                         .includes(steps: %i[ingredients cross_references])
                         .find_by!(slug: params[:slug])
```

**`current_kitchen.recipes`** — `Kitchen` has a `has_many :recipes` declaration, which means every Kitchen object gets a `.recipes` method that returns all recipes belonging to it. Under the hood, this adds `WHERE kitchen_id = 7` (or whatever the kitchen's ID is) to every query. You never write that WHERE clause yourself.

```ruby
# app/models/kitchen.rb
class Kitchen < ApplicationRecord
  has_many :recipes, dependent: :destroy
  # ...
end
```

**`.includes(steps: %i[ingredients cross_references])`** — this is **eager loading**. Without it, Rails would load the recipe, then when the view loops through steps it would run a separate query for each step's ingredients, then another for each step's cross-references. For a recipe with 6 steps, that's 13 queries instead of 3. The `includes` call tells Rails to load all of this data up front. It's a performance optimization you ask for when you know the view will need nested data.

**`.find_by!(slug: params[:slug])`** — find the recipe whose slug matches `"focaccia"`, or raise `ActiveRecord::RecordNotFound` (which the rescue block catches and turns into a 404 response).

The data that comes back is shaped by the **model** declarations — these are the classes in `app/models/` that map to database tables. Here's the relationship chain:

```ruby
# app/models/recipe.rb
class Recipe < ApplicationRecord
  acts_as_tenant :kitchen
  belongs_to :category
  has_many :steps, -> { order(:position) }, dependent: :destroy, inverse_of: :recipe
  has_many :ingredients, through: :steps
end
```

`acts_as_tenant :kitchen` is a plugin that automatically scopes all Recipe queries to the current kitchen — it's a second layer of protection beyond `current_kitchen.recipes`. Even if you accidentally wrote `Recipe.find_by(slug: 'focaccia')` somewhere, the tenant scoping would add the kitchen filter. Belt and suspenders.

`has_many :steps, -> { order(:position) }` means a recipe has multiple steps, and they always come back sorted by their position column. The `-> { order(:position) }` is a scope — a block that modifies the query.

Steps, in turn, own ingredients and cross-references:

```ruby
# app/models/step.rb
class Step < ApplicationRecord
  belongs_to :recipe, inverse_of: :steps
  has_many :ingredients, -> { order(:position) }, dependent: :destroy, inverse_of: :step
  has_many :cross_references, -> { order(:position) }, dependent: :destroy, inverse_of: :step

  def ingredient_list_items
    (ingredients + cross_references).sort_by(&:position)
  end
end
```

That `ingredient_list_items` method is worth noting — it merges ingredients and cross-references into one sorted list. The view calls this instead of iterating ingredients and cross-references separately, because in the original Markdown they're interleaved. They share a position column so they sort back into the original order.

`CrossReference` has an interesting trick — it delegates methods to its target recipe:

```ruby
# app/models/cross_reference.rb
class CrossReference < ApplicationRecord
  belongs_to :step, inverse_of: :cross_references
  belongs_to :target_recipe, class_name: 'Recipe'

  delegate :slug, to: :target_recipe, prefix: :target
  delegate :title, to: :target_recipe, prefix: :target
end
```

Those `delegate` lines mean you can call `cross_reference.target_slug` and `cross_reference.target_title` instead of `cross_reference.target_recipe.slug`. It's a convenience that also shows up in the view's duck typing, which we'll see in Stop 5.

### Stop 4: The View Layer — Layout and Template

The controller has set `@recipe` and `@nutrition`. Now Rails needs to render HTML. You might have noticed that `RecipesController#show` doesn't say *what* to render — there's no "render this template" line. That's **convention over configuration**, one of the most important ideas in Rails: `RecipesController#show` automatically renders `app/views/recipes/show.html.erb`. The controller name gives the directory (`recipes/`), the action name gives the file (`show`), and `.html.erb` means "HTML with Embedded Ruby."

But `show.html.erb` doesn't produce a complete HTML page. It's wrapped by a **layout** — `app/views/layouts/application.html.erb`:

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <title><%= content_for?(:title) ? content_for(:title) : 'Biagini Family Recipes' %></title>
  <%= csrf_meta_tags %>
  <%= stylesheet_link_tag 'style' %>
  <%= yield :head %>
</head>
<body <%= yield :body_attrs %>>
  <%= render 'shared/nav' %>
  <main>
    <%= yield %>
  </main>
  <%= yield :scripts %>
</body>
</html>
```

Two kinds of ERB tags here. **`<%= %>`** (with the equals sign) evaluates the Ruby inside and inserts the result into the HTML. **`<% %>`** (without the equals sign) runs the Ruby but outputs nothing — used for loops and conditionals.

**`<%= yield %>`** in the middle of `<main>` is where the template's content goes. Rails takes whatever `show.html.erb` produces and inserts it right there. The layout is the picture frame; the template is the picture.

**`<%= yield :scripts %>`**, **`<%= yield :head %>`**, and **`<%= yield :body_attrs %>`** are named **content slots**. Templates can fill them using `content_for`:

```erb
<% content_for(:title) { @recipe.title } %>

<% content_for(:scripts) do %>
  <%= javascript_include_tag 'notify', defer: true %>
  <%= javascript_include_tag 'recipe-state-manager', defer: true %>
  <%= javascript_include_tag 'recipe-editor', defer: true %>
<% end %>
```

This is how the recipe template sets the page title and includes recipe-specific JavaScript without modifying the layout. Every page shares the same layout, but each template can inject its own content into these slots.

The main body of the template reads like an HTML document with Ruby sprinkled in:

```erb
<article class="recipe">
  <header>
    <h1><%= @recipe.title %></h1>
    <p class="recipe-meta">
      <%= link_to @recipe.category.name, kitchen_root_path(anchor: @recipe.category.slug) %>
      <%- if @recipe.serves -%>&middot; Serves <%= format_yield_line(@recipe.serves.to_s) %><%- end -%>
    </p>
  </header>

  <% @recipe.steps.each do |step| %>
    <%= render 'step', step: step %>
  <% end %>
</article>
```

`@recipe` is the instance variable the controller set — it's just available here, no import needed. `link_to` is a Rails **helper** that generates an `<a>` tag. And `render 'step'` delegates each step to a separate file. That's our next stop.

### Stop 5: Partials and Helpers

**`<%= render 'step', step: step %>`** tells Rails to render the **partial** `app/views/recipes/_step.html.erb`. Partials always start with an underscore in the filename, but you leave the underscore off when calling `render`. The `step: step` part passes a local variable — inside the partial, `step` refers to the current step object.

Here's the core of the step partial:

```erb
<section>
  <h2><%= step.title %></h2>
  <%- unless step.ingredient_list_items.empty? -%>
  <div class="ingredients">
    <ul>
      <%- step.ingredient_list_items.each do |item| -%>
      <%- if item.respond_to?(:target_slug) -%>
      <li class="cross-reference">
        <b><%= link_to item.target_title, recipe_path(item.target_slug) %></b>
      </li>
      <%- else -%>
      <li>
        <b><%= item.name %></b><% if item.quantity_display %>, <span class="quantity"><%= item.quantity_display %></span><% end %>
      </li>
      <%- end -%>
      <%- end -%>
    </ul>
  </div>
  <%- end -%>

  <%- if step.processed_instructions.present? -%>
  <div class="instructions">
    <%= render_markdown(step.processed_instructions) %>
  </div>
  <%- end -%>
</section>
```

Remember `ingredient_list_items`? It returns a mixed list of `Ingredient` and `CrossReference` objects, sorted by position. The partial needs to render them differently — ingredients show a name and quantity, cross-references show a link to another recipe. But it doesn't check the class name. Instead, it uses **`respond_to?(:target_slug)`** — duck typing. If the item has a `target_slug` method, it's a cross-reference; if not, it's an ingredient. This is idiomatic Ruby: ask an object what it can do, not what it is.

`link_to item.target_title, recipe_path(item.target_slug)` generates something like `<a href="/kitchens/test-kitchen/recipes/pizza-dough">Pizza Dough</a>`. The route helper fills in the kitchen slug automatically, as we saw in Stop 1.

**`render_markdown`** is a **view helper** — a method defined in `app/helpers/recipes_helper.rb`:

```ruby
module RecipesHelper
  def render_markdown(text)
    return '' if text.blank?

    FamilyRecipes::Recipe::MARKDOWN.render(text).html_safe
  end
end
```

This is where your code re-enters the picture. `FamilyRecipes::Recipe::MARKDOWN` is the Redcarpet renderer you set up in the parser library. The helper wraps it in a nil-safe method that views can call cleanly. Helpers are available in all views automatically — Rails includes them based on the naming convention (`RecipesHelper` for `RecipesController` views, though in practice all helpers are available everywhere).

The nav partial (`app/views/shared/_nav.html.erb`) demonstrates another useful pattern — controller methods exposed to views:

```erb
<% if current_kitchen %>
  <%= link_to 'Home', kitchen_root_path %>
  <%= link_to 'Index', ingredients_path %>
  <%= link_to 'Groceries', groceries_path %>
<% end %>
<% if logged_in? %>
  <%= button_to 'Log out', logout_path, method: :delete %>
<% else %>
  <%= link_to 'Log in', login_path %>
<% end %>
```

`current_kitchen` and `logged_in?` are defined in `ApplicationController`, but the line `helper_method :current_kitchen, :logged_in?` back in Stop 2 made them callable from views too. Without that declaration, they'd only be available inside controllers.

### Stop 6: Assets — CSS and JavaScript

The layout includes stylesheets and scripts with helpers like `stylesheet_link_tag 'style'` and `javascript_include_tag 'recipe-editor', defer: true`. These turn into standard HTML tags:

```html
<link href="/assets/style-a1b2c3d4.css" rel="stylesheet">
<script src="/assets/recipe-editor-e5f6g7h8.js" defer></script>
```

Those hashes in the filenames are **fingerprints**, added by **Propshaft** — the Rails asset pipeline. It serves files directly from `app/assets/stylesheets/` and `app/assets/javascripts/` with no build step, no bundler, no Node.js. When a file changes, its fingerprint changes, which busts browser caches automatically. You edit `app/assets/stylesheets/style.css` directly, and Propshaft handles the rest.

The `defer` attribute on the script tags means the JavaScript loads without blocking the page render. This matters because the app follows **progressive enhancement** — the recipe page is a complete, readable HTML document before any JavaScript runs. The scripts add optional features (scaling quantities, editing, cross-off) but the page works without them. If JavaScript fails to load, you still have a perfectly good recipe.

This is also why the recipe template uses `content_for(:scripts)` to declare its JavaScript — only recipe pages load the recipe-specific scripts. The groceries page loads different ones. The layout provides the slots; each template fills only what it needs.

---

**That's the whole read path.** A URL hits the router, which picks a controller. The controller runs through a pipeline of callbacks (restore session, set kitchen), then executes a three-line action that loads a recipe from the database. Rails infers the template from the controller and action names, wraps it in a layout, and the view renders your parser's output — stored in the database as structured rows — back into HTML. Propshaft serves the CSS and JavaScript that make it look and feel like a cookbook page. The entire journey, from URL to finished HTML, touches about eight files and zero configuration.
