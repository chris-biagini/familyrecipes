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

*Now let's see what happens when someone changes something.*

## Journey 2: Someone edits and saves that recipe

You just read the Focaccia recipe (Journey 1). You're logged in as a family member, and you notice the salt quantity is wrong. You click "Edit," fix the amount in the Markdown source, and hit "Save." Here's everything that happens between that click and the updated page.

### Stop 1: The Editor Dialog and JavaScript

At the end of Journey 1, the browser received the recipe page. If you're logged in and you belong to this kitchen, the page includes something extra that anonymous visitors don't see. Look at the bottom of `app/views/recipes/show.html.erb`:

```erb
<% if current_kitchen.member?(current_user) %>
<%= render 'editor_dialog',
           mode: :edit,
           content: @recipe.markdown_source,
           action_url: recipe_path(@recipe.slug),
           recipe: @recipe %>
<% end %>
```

The `member?` check means the editor dialog only appears in the HTML for logged-in kitchen members. Anonymous visitors get the same recipe page, minus the editing UI. The dialog is rendered from a **partial** (`app/views/recipes/_editor_dialog.html.erb`) that we can reuse for both editing and creating recipes, controlled by the `mode:` parameter.

Here's the dialog, trimmed to its structural bones:

```erb
<%# locals: (mode:, content:, action_url:, recipe: nil) %>
<dialog id="recipe-editor"
        class="editor-dialog"
        data-editor-open="<%= mode == :create ? '#new-recipe-button' : '#edit-button' %>"
        data-editor-url="<%= action_url %>"
        data-editor-method="<%= mode == :create ? 'POST' : 'PATCH' %>"
        data-editor-on-success="redirect"
        data-editor-body-key="markdown_source">
  <div class="editor-errors" hidden></div>
  <textarea class="editor-textarea"><%= content %></textarea>
  <div class="editor-footer">
    <button type="button" class="btn editor-cancel">Cancel</button>
    <button type="button" class="btn btn-primary editor-save">Save</button>
  </div>
</dialog>
```

This is a native HTML **`<dialog>`** element — no framework, no custom modal. The interesting part is the `data-` attributes on the dialog tag. These are the entire configuration for the JavaScript that drives it:

- **`data-editor-open`** — a CSS selector for the button that opens this dialog (`#edit-button`)
- **`data-editor-url`** — where to send the save request (`/kitchens/test-kitchen/recipes/focaccia`)
- **`data-editor-method`** — HTTP method: `PATCH` for editing, `POST` for creating
- **`data-editor-on-success`** — what to do after a successful save (`redirect` navigates to the recipe)
- **`data-editor-body-key`** — the JSON key to wrap the textarea content in (`markdown_source`)

The JavaScript (`app/assets/javascripts/recipe-editor.js`) is generic. On page load, it finds every `.editor-dialog` on the page and wires each one up by reading its data attributes. There's no per-dialog JavaScript — the same code handles the recipe editor, the Quick Bites editor on the groceries page, and the aisle editor. Want a new editor dialog? Add a `<dialog>` with the right data attributes. No JS changes needed.

When you click Save, the JavaScript does this:

```javascript
const response = await fetch(actionUrl, {
  method: method,
  headers: {
    'Content-Type': 'application/json',
    'X-CSRF-Token': csrfToken
  },
  body: JSON.stringify({ [bodyKey]: textarea.value })
});
```

That sends a `PATCH` request to `/kitchens/test-kitchen/recipes/focaccia` with a JSON body like `{ "markdown_source": "# Focaccia\n\nThe updated markdown..." }`. The **CSRF token** is a Rails security feature — it's a one-time token embedded in the page's `<meta>` tags that proves this request came from your page, not a malicious third-party site. Rails rejects requests without a valid token.

The request is now headed for `RecipesController#update`. But before Rails runs that method, it needs to verify that this user is allowed to make changes.

### Stop 2: Authentication and Authorization

In Journey 1, we breezed past `require_membership` because it didn't apply to the `show` action. Now it's front and center. Look at `app/controllers/recipes_controller.rb`:

```ruby
class RecipesController < ApplicationController
  before_action :require_membership, only: %i[create update destroy]
  # ...
end
```

Our PATCH request maps to the `update` action, so `require_membership` runs. Open `app/controllers/application_controller.rb`:

```ruby
def require_membership
  unless logged_in?
    return head(:unauthorized) if request.format.json?
    return request_authentication
  end
  return head(:unauthorized) unless current_kitchen&.member?(current_user)
end
```

This does two checks. First: **are you logged in at all?** If not, JSON requests get a 401 response (the editor JavaScript shows an error), and browser requests get redirected to the login page. Second: **are you a member of this kitchen?** Even a logged-in user can't edit recipes in someone else's kitchen.

`logged_in?` delegates to `authenticated?`, which calls `resume_session` from the `Authentication` concern. Here's the chain:

```ruby
# app/controllers/concerns/authentication.rb
def resume_session
  Current.session ||= find_session_by_cookie
end

def find_session_by_cookie
  Session.find_by(id: cookies.signed[:session_id])
end
```

When you logged in earlier, the app created a `Session` row in the database and stored its ID in a **signed cookie** — a cookie that Rails cryptographically signs so it can't be tampered with. `resume_session` reads that cookie, looks up the Session row, and stores it in **`Current`** — a thread-local container that holds data for just this one request:

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true
end
```

`Current.session` gives you the session. `Current.user` (which delegates through the session) gives you the user. These are available anywhere in the app for the duration of this request, then automatically reset. No global state leaks between requests.

`current_kitchen.member?(current_user)` is the final gate — it checks the `memberships` table for a row linking this user to this kitchen:

```ruby
# app/models/kitchen.rb
def member?(user)
  return false unless user
  memberships.exists?(user: user)
end
```

Our user passes both checks. The before-action finishes without halting, and Rails proceeds to `RecipesController#update`.

### Stop 3: Validation

The first thing `update` does is find the recipe and validate the incoming Markdown. Here's the top of the action:

```ruby
def update
  @recipe = current_kitchen.recipes.find_by!(slug: params[:slug])

  errors = MarkdownValidator.validate(params[:markdown_source])
  return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

  # ... import happens next
end
```

`find_by!` loads the existing recipe from the database — same pattern as `show` in Journey 1, but this time we need the record so we can track changes to the title later. If the slug doesn't match anything, the rescue at the bottom of the method catches the exception and returns a 404.

**`MarkdownValidator`** is a plain Ruby class in `app/services/markdown_validator.rb`. It runs your parser code in a read-only pass to check whether the Markdown is structurally valid:

```ruby
class MarkdownValidator
  def self.validate(markdown_source)
    new(markdown_source).validate
  end

  def validate
    return ['Recipe cannot be blank.'] if @markdown_source.blank?

    parsed = parse
    errors = []
    errors << 'Category is required in front matter.' unless parsed[:front_matter][:category]
    errors << 'Recipe must have at least one step.' if parsed[:steps].empty?
    errors
  rescue StandardError => error
    [error.message]
  end

  private

  def parse
    tokens = LineClassifier.classify(@markdown_source)
    RecipeBuilder.new(tokens).build
  end
end
```

This is **fail-fast validation**: check cheaply before doing anything expensive. The private `parse` method runs `LineClassifier` and `RecipeBuilder` — your code — to tokenize and parse the Markdown. If the parser raises an exception (missing title, malformed structure), the rescue catches it and surfaces the error message. If parsing succeeds, the validator checks for a category and at least one step.

The key design: the validator calls the same parser the importer will call momentarily. If validation passes, we know the import won't blow up on a parse error. And if validation fails, we haven't touched the database at all — the response goes back as a `422 Unprocessable Entity` with the error messages as JSON, and the editor JavaScript displays them in the `.editor-errors` div.

Our Focaccia edit passes validation. On to the import.

### Stop 4: The Import Pipeline

This is where your parser code meets the database. `MarkdownImporter` is the bridge between the two worlds: it takes raw Markdown, runs it through your parser, and writes the result into ActiveRecord models. Open `app/services/markdown_importer.rb`:

```ruby
class MarkdownImporter
  def self.import(markdown_source, kitchen:)
    new(markdown_source, kitchen: kitchen).import
  end

  def initialize(markdown_source, kitchen:)
    @markdown_source = markdown_source
    @kitchen = kitchen
    @parsed = parse_markdown
  end

  def import
    recipe = save_recipe
    compute_nutrition(recipe)
    recipe
  end
end
```

The class method `import` is the public interface — the controller calls `MarkdownImporter.import(params[:markdown_source], kitchen: current_kitchen)` and gets a Recipe back. Let's walk through each phase.

**Phase 1: Parse.** The constructor calls `parse_markdown` immediately:

```ruby
def parse_markdown
  tokens = LineClassifier.classify(markdown_source)
  RecipeBuilder.new(tokens).build
end
```

This is your code. `LineClassifier` tokenizes the Markdown into typed lines, `RecipeBuilder` assembles them into a structured hash with `:title`, `:description`, `:front_matter`, `:steps`, `:footer`. The result is a plain Ruby hash — no ActiveRecord, no database. Just data.

**Phase 2: Transaction.** `save_recipe` wraps the entire database write in a **transaction**:

```ruby
def save_recipe
  ActiveRecord::Base.transaction do
    recipe = find_or_initialize_recipe
    update_recipe_attributes(recipe)
    recipe.save!
    replace_steps(recipe)
    rebuild_dependencies(recipe)
    recipe
  end
end
```

A transaction means all of these database operations either succeed together or fail together. If `replace_steps` blows up halfway through, the recipe attributes get rolled back too. You never end up with a half-updated recipe.

**Phase 3: Find or create.** `find_or_initialize_recipe` derives a slug from the parsed title and looks for an existing recipe:

```ruby
def find_or_initialize_recipe
  slug = FamilyRecipes.slugify(parsed[:title])
  kitchen.recipes.find_or_initialize_by(slug: slug)
end
```

`find_or_initialize_by` either finds the existing Focaccia record or builds a new (unsaved) one in memory. For our edit, it finds the existing record. For a brand-new recipe, it initializes a blank one.

**Phase 4: Set attributes.** `update_recipe_attributes` takes the parsed data and maps it onto the Recipe model's columns:

```ruby
def update_recipe_attributes(recipe)
  category = find_or_create_category(parsed[:front_matter][:category])
  makes_qty, makes_unit = parse_makes(parsed[:front_matter][:makes])

  recipe.assign_attributes(
    title: parsed[:title],
    description: parsed[:description],
    category: category,
    kitchen: kitchen,
    makes_quantity: makes_qty,
    makes_unit_noun: makes_unit,
    serves: parsed[:front_matter][:serves]&.to_i,
    footer: parsed[:footer],
    markdown_source: markdown_source
  )
end
```

`assign_attributes` sets the values in memory without saving. The `save!` on the next line writes them to the database (the bang means it raises an exception if validation fails, which the transaction would then roll back).

**Phase 5: Replace steps.** This is the most destructive part — and the simplest:

```ruby
def replace_steps(recipe)
  recipe.steps.destroy_all
  parsed[:steps].each_with_index do |step_data, index|
    step = recipe.steps.create!(
      title: step_data[:tldr],
      instructions: step_data[:instructions],
      processed_instructions: process_instructions(step_data[:instructions]),
      position: index
    )
    import_step_items(step, step_data[:ingredients])
  end
end
```

`destroy_all` deletes every existing step (and their ingredients and cross-references, thanks to `dependent: :destroy` on the model). Then it creates fresh ones from the parsed data. This is a full replacement, not a diff — simpler to reason about and impossible to leave stale data behind. Each step's instructions get run through `ScalableNumberPreprocessor`, which wraps numbers in `<span class="scalable">` tags so the client-side scaling JavaScript can find them later.

`import_step_items` iterates through each step's ingredient list and creates either an `Ingredient` or a `CrossReference` row depending on whether the parsed data has a `:cross_reference` flag — the distinction your `IngredientParser` makes when it sees the `@[Recipe Name]` syntax.

**Phase 6: Rebuild dependencies.** `rebuild_dependencies` updates the `RecipeDependency` table, which tracks which recipes reference which other recipes. Same pattern: destroy all existing dependencies, create new ones from the parsed cross-references. This table powers things like warning you when deleting a recipe that other recipes link to.

**Phase 7: Compute nutrition.** After the transaction commits, `compute_nutrition` runs two jobs synchronously:

```ruby
def compute_nutrition(recipe)
  RecipeNutritionJob.perform_now(recipe)
  CascadeNutritionJob.perform_now(recipe)
end
```

`RecipeNutritionJob` calculates this recipe's nutrition facts from its ingredients. `CascadeNutritionJob` recalculates any recipe that references *this* recipe (via cross-references), since their nutrition totals may have changed. Both run inline (`perform_now`) — no background queue.

After the importer returns, the database is the source of truth. The Markdown has been decomposed into rows across five tables (recipes, steps, ingredients, cross_references, recipe_dependencies), the raw source has been stored in `markdown_source`, and nutrition data has been computed and stored as jsonb. The parser won't run again until the next edit.

### Stop 5: The Response and Redirect

Back in the controller, the import is done. The rest of `update` handles a few housekeeping tasks and sends the response:

```ruby
def update
  @recipe = current_kitchen.recipes.find_by!(slug: params[:slug])
  # validation and import happened above...

  old_title = @recipe.title
  recipe = MarkdownImporter.import(params[:markdown_source], kitchen: current_kitchen)

  updated_references = if title_changed?(old_title, recipe.title)
                         CrossReferenceUpdater.rename_references(
                           old_title: old_title, new_title: recipe.title, kitchen: current_kitchen
                         )
                       else
                         []
                       end

  @recipe.destroy! if recipe.slug != @recipe.slug
  recipe.update!(edited_at: Time.current)

  response_json = { redirect_url: recipe_path(recipe.slug) }
  response_json[:updated_references] = updated_references if updated_references.any?
  render json: response_json
end
```

If the title changed, `CrossReferenceUpdater` finds every other recipe that references this one by its old title and updates those references. If the slug changed (because the title changed), the old recipe record gets destroyed — the importer already created a new one with the new slug. Either way, the `edited_at` timestamp is set.

The response is JSON: `{ "redirect_url": "/kitchens/test-kitchen/recipes/focaccia" }`. Back in the browser, the JavaScript reads `redirect_url` and navigates there:

```javascript
if (response.ok) {
  const data = await response.json();
  window.location = data.redirect_url;
}
```

The browser navigates to the recipe URL, and Journey 1 starts all over again — router, controller pipeline, database query, view render. The page loads with the updated salt quantity. The cycle is complete.

---

**That's the whole write path.** A click opens a native `<dialog>` configured entirely through data attributes. JavaScript sends a JSON PATCH request with the Markdown source. The controller verifies you're logged in and belong to this kitchen, validates the Markdown with a fast parser pass, then hands it to the import pipeline. The importer runs your parser code one more time, decomposes the result into database rows inside a transaction, and computes nutrition. The controller sends back a redirect URL, and the JavaScript navigates there — handing off to the read path from Journey 1.

Your parser code appears in exactly three places in the running app:

1. **`MarkdownValidator`** — a quick parse to check structure before committing to the import.
2. **`MarkdownImporter`** — the full parse that decomposes Markdown into database rows. This is where `LineClassifier`, `RecipeBuilder`, and `IngredientParser` do their real work.
3. **`RecipeNutritionJob`** — after import, it uses the structured data to calculate nutrition facts.

Everything else — routing, authentication, rendering, scaling, cross-references — works from the database rows your parser helped create.

## Glossary

Quick reference for the Rails terms used in the two journeys above. Each definition is grounded in this app, not abstract Rails documentation. The file path tells you where to look.

**`acts_as_tenant`** — A plugin that automatically scopes database queries to the current kitchen. In this app it appears on `Recipe`, `Category`, and `CrossReference`, so even an unscoped query like `Recipe.all` silently adds `WHERE kitchen_id = ?`. See `app/models/recipe.rb`.

**ActiveRecord** — The Rails layer that maps Ruby classes to database tables. Each model in `app/models/` (Recipe, Step, Ingredient, Kitchen, etc.) is an ActiveRecord class — you call methods like `.find_by!`, `.create!`, and `.save!` on them, and ActiveRecord translates those into SQL.

**`ApplicationController`** — The base class every controller inherits from. It sets up the `before_action` pipeline (session restoration, kitchen lookup), defines shared helper methods, and includes the `Authentication` concern. See `app/controllers/application_controller.rb`.

**`assign_attributes`** — Sets column values on an ActiveRecord object in memory without saving to the database. `MarkdownImporter` uses it to stage all of a recipe's attributes before calling `save!` inside the transaction. See `app/services/markdown_importer.rb`.

**`before_action`** — A controller callback that runs automatically before the action method. In this app, `resume_session` and `set_kitchen_from_path` run before every action; `require_membership` runs only before `create`, `update`, and `destroy`. See `app/controllers/application_controller.rb` and `app/controllers/recipes_controller.rb`.

**`belongs_to`** — Declares that a model holds a foreign key pointing to another model's row. `Recipe` belongs to `Category`, `Step` belongs to `Recipe`, `Ingredient` belongs to `Step`. It means "this record cannot exist without that parent." See `app/models/step.rb`.

**concern** — A Ruby module mixed into a controller (or model) with `include`. The `Authentication` concern adds session management methods (`resume_session`, `start_new_session_for`, `current_user`) to `ApplicationController` without cluttering its file. See `app/controllers/concerns/authentication.rb`.

**`content_for` / `yield :name`** — A two-part system for injecting content from a template into specific slots in the layout. The template calls `content_for(:scripts) { ... }` to fill a named slot; the layout calls `yield :scripts` where that content should appear. The recipe template uses this to include page-specific JavaScript. See `app/views/layouts/application.html.erb` and `app/views/recipes/show.html.erb`.

**CSRF token** — A cryptographic token Rails embeds in the page's `<meta>` tags to prevent cross-site request forgery. The editor JavaScript includes it in the `X-CSRF-Token` header of every save request; Rails rejects requests without a valid token. Generated by `csrf_meta_tags` in `app/views/layouts/application.html.erb`.

**`Current` (ActiveSupport::CurrentAttributes)** — A thread-local container that holds per-request state. In this app it stores the `Session` object and delegates `user` through it. Available anywhere during a single request, automatically reset afterward. See `app/models/current.rb`.

**`default_url_options`** — A controller method that provides default parameter values for all route helpers. In this app it auto-fills `kitchen_slug` from the current kitchen, so `recipe_path('focaccia')` works without explicitly passing the kitchen. See `app/controllers/application_controller.rb`.

**`delegate`** — Forwards method calls from one object to an associated object. `CrossReference` delegates `:slug` and `:title` to its `target_recipe` with a `target` prefix, so you can call `cross_reference.target_slug` instead of `cross_reference.target_recipe.slug`. See `app/models/cross_reference.rb`.

**`dependent: :destroy`** — An option on `has_many` that automatically deletes child records when the parent is destroyed. When a Recipe is deleted, its Steps are destroyed, which in turn destroys their Ingredients and CrossReferences. See `app/models/recipe.rb`.

**eager loading (`includes`)** — Tells ActiveRecord to load associated records in bulk instead of one query per parent. `RecipesController#show` uses `.includes(steps: %i[ingredients cross_references])` to load a recipe and all its nested data in three queries instead of dozens. See `app/controllers/recipes_controller.rb`.

**ERB (Embedded Ruby)** — The templating format Rails uses for HTML views. `<%= expression %>` outputs the result; `<% code %>` runs code without output. Files end in `.html.erb`. See any file in `app/views/`.

**`find_by!` / `find_or_initialize_by`** — ActiveRecord lookup methods. `find_by!` returns a record or raises `ActiveRecord::RecordNotFound` (which becomes a 404). `find_or_initialize_by` returns an existing record or builds an unsaved one in memory — used by the importer to handle both new and existing recipes. See `app/services/markdown_importer.rb`.

**`has_many` / `has_many :through`** — Declares that a model owns multiple child records. `Kitchen` has many `recipes`; `Recipe` has many `steps`. The `:through` variant creates a shortcut across a join: `Recipe` has many `ingredients` through `steps`, so you can call `recipe.ingredients` even though ingredients belong to steps. See `app/models/kitchen.rb` and `app/models/recipe.rb`.

**`helper_method`** — Makes a controller method available in view templates. `ApplicationController` declares `helper_method :current_kitchen, :logged_in?` so the nav partial can check `logged_in?` and recipe templates can check `current_kitchen.member?(current_user)`. See `app/controllers/application_controller.rb`.

**instance variable (`@`)** — A variable prefixed with `@` that Rails automatically passes from a controller action to its view template. `RecipesController#show` sets `@recipe`, and the template reads `@recipe.title` — no import or parameter passing required.

**`javascript_include_tag`** — A Rails helper that generates a `<script>` tag with a Propshaft-fingerprinted URL. `javascript_include_tag 'recipe-editor', defer: true` becomes `<script src="/assets/recipe-editor-abc123.js" defer>`. See `app/views/recipes/show.html.erb`.

**layout** — The HTML wrapper around every page. `app/views/layouts/application.html.erb` provides the `<html>`, `<head>`, nav bar, and `<main>` tag. Each template's content is inserted at the `<%= yield %>` point in the layout. Templates share the layout but inject page-specific content via `content_for`.

**`link_to`** — A Rails view helper that generates an `<a>` tag. `link_to @recipe.category.name, kitchen_root_path(anchor: @recipe.category.slug)` produces a link with the category name as text and the kitchen homepage as the destination. See `app/views/recipes/show.html.erb`.

**partial** — A reusable template fragment whose filename starts with an underscore. `render 'step', step: step` renders `app/views/recipes/_step.html.erb` with a local variable. Partials let you extract repeated markup — the step partial is rendered once per step in a loop. See `app/views/recipes/_step.html.erb`.

**`perform_now`** — Runs an ActiveJob job inline, in the current request, without a background queue. `MarkdownImporter` calls `RecipeNutritionJob.perform_now(recipe)` to calculate nutrition synchronously at save time. See `app/services/markdown_importer.rb`.

**Propshaft** — The Rails asset pipeline used by this app. It serves files from `app/assets/` with fingerprinted URLs (e.g., `style-a1b2c3d4.css`) for cache busting. No build step, no bundler, no Node.js. See `app/assets/stylesheets/` and `app/assets/javascripts/`.

**`render`** — Produces a response. In views, `render 'step'` inserts a partial. In controllers, `render json: { ... }` sends a JSON response. When a controller action doesn't call `render`, Rails automatically renders the conventional template (e.g., `RecipesController#show` renders `app/views/recipes/show.html.erb`).

**`rescue` (method-level)** — A `rescue` clause attached directly to a method body, without a wrapping `begin`/`end`. `RecipesController#show` uses `rescue ActiveRecord::RecordNotFound` at the method level to catch missing recipes and return a 404. See `app/controllers/recipes_controller.rb`.

**`resources` (routes)** — A single line in `config/routes.rb` that generates RESTful routes for a controller. `resources :recipes, only: %i[show create update destroy], param: :slug` creates four routes mapping HTTP verbs and URLs to controller actions. See `config/routes.rb`.

**route helper** — A Ruby method generated from your route definitions that builds URL paths. `recipe_path('focaccia')` returns `"/kitchens/test-kitchen/recipes/focaccia"`. Always use these instead of hardcoding URL strings — if the route changes, the helper updates automatically. Defined by `config/routes.rb`, used everywhere.

**`scope` (routes)** — Groups routes under a shared URL prefix without creating a new controller namespace. `scope 'kitchens/:kitchen_slug'` means every route inside the block starts with `/kitchens/something` and extracts `kitchen_slug` as a parameter. See `config/routes.rb`.

**session (database-backed)** — A `Session` row in the database that represents a logged-in user. Created at login, looked up on each request via a signed cookie. Destroyed at logout. This replaces Rails' default cookie-based session with a server-side record. See `app/models/session.rb` and `app/controllers/concerns/authentication.rb`.

**signed cookie** — A cookie whose value Rails cryptographically signs to prevent tampering. The app stores `session_id` as a signed cookie — the browser sends it back on every request, and `Authentication#find_session_by_cookie` reads it with `cookies.signed[:session_id]`. See `app/controllers/concerns/authentication.rb`.

**`stylesheet_link_tag`** — A Rails helper that generates a `<link>` tag with a Propshaft-fingerprinted URL. `stylesheet_link_tag 'style'` becomes `<link href="/assets/style-abc123.css" rel="stylesheet">`. See `app/views/layouts/application.html.erb`.

**transaction** — A database guarantee that a group of operations either all succeed or all roll back. `MarkdownImporter#save_recipe` wraps recipe creation, step replacement, and dependency rebuilding in `ActiveRecord::Base.transaction { ... }` so a failure partway through never leaves a half-updated recipe. See `app/services/markdown_importer.rb`.
