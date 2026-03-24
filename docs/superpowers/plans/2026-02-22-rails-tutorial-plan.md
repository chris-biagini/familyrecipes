# Rails Tutorial Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Write `docs/how-your-rails-app-works.md` — a narrative Rails tutorial using this codebase as the example, targeted at the person who wrote the parser but doesn't understand the Rails plumbing.

**Architecture:** Two narrative "journeys" (a read request and a write request) that walk through the app end-to-end, introducing Rails concepts at the moment they become relevant. A glossary at the end serves as a quick-lookup reference. Real code from the app is shown at each stop with annotations.

**Approach:** Each task writes one section of the tutorial. Verify accuracy against actual source files. Commit after each major section.

---

### Task 0: Create the document with introduction

**Files:**
- Create: `docs/how-your-rails-app-works.md`

**Step 1: Write the document header and introduction**

Create `docs/how-your-rails-app-works.md` with:
- Title: "How Your Rails App Works"
- A short intro explaining what this document is, who it's for, and how to read it (the two-journey structure)
- Explain the premise: "You wrote the parser. You understand Recipe, Step, Ingredient as Ruby classes. This tutorial shows you what Rails does with them."
- Brief note on how to use this doc during conversations with Claude ("you don't need to memorize this — just know where to look")

**Step 2: Review and commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: add Rails tutorial — introduction"
```

---

### Task 1: Write Journey 1, Stop 1 — The Route

**Files:**
- Modify: `docs/how-your-rails-app-works.md`

**Step 1: Write the section**

Content to cover:
- Set the scene: "You click a link to `/kitchens/test-kitchen/recipes/focaccia`. What happens?"
- Show `config/routes.rb` (the kitchen-scoped block, lines 8-15)
- Explain: `scope 'kitchens/:kitchen_slug'` creates a URL prefix and extracts `:kitchen_slug` as a parameter
- Explain: `resources :recipes, only: %i[show create update destroy], param: :slug` — Rails shorthand that generates multiple routes from one line. `param: :slug` means use the recipe's slug in the URL instead of its database ID
- Show the route that matches: `GET /kitchens/:kitchen_slug/recipes/:slug` → `RecipesController#show`
- Explain route helpers: `recipe_path('focaccia')` generates `/kitchens/test-kitchen/recipes/focaccia`. You'll see these helpers in views and controllers — they're just URL generators so you never hardcode paths.
- Mention `default_url_options` (line 37-39 of ApplicationController): auto-fills `kitchen_slug` so most helpers work without passing it explicitly

**Key source files to reference:**
- `config/routes.rb:8-15`
- `app/controllers/application_controller.rb:37-39`

**Step 2: Review accuracy against source files and commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: Rails tutorial — Journey 1, Stop 1 (routes)"
```

---

### Task 2: Write Journey 1, Stop 2 — The Controller Pipeline

**Files:**
- Modify: `docs/how-your-rails-app-works.md`

**Step 1: Write the section**

Content to cover:
- "Before your controller action runs, Rails executes a chain of setup methods called before-actions."
- Show `ApplicationController` (lines 1-13) — the base class every controller inherits from
- Walk through the before-action chain in order:
  1. `resume_session` — looks for a session cookie, restores the login state. For now just know it runs; we'll explain the full auth flow in Journey 2.
  2. `set_kitchen_from_path` — extracts `kitchen_slug` from the URL, finds the Kitchen in the database, and sets it as the "current tenant." After this runs, every database query is automatically scoped to that kitchen's data. Show lines 17-21.
  3. `current_kitchen` (line 23) — a one-line method that returns the tenant set above. You'll see this everywhere.
- Then show `RecipesController#show` (lines 6-13): explain that `before_action :require_membership, only: %i[create update destroy]` means the membership check only applies to write actions — `show` doesn't require login.
- The action itself is just three lines: load the recipe, grab its nutrition data, done.

**Key source files to reference:**
- `app/controllers/application_controller.rb:1-25`
- `app/controllers/recipes_controller.rb:1-13`
- `app/controllers/concerns/authentication.rb:27-29` (just `resume_session`)

**Step 2: Review and commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: Rails tutorial — Journey 1, Stop 2 (controller pipeline)"
```

---

### Task 3: Write Journey 1, Stop 3 — ActiveRecord (Loading the Data)

**Files:**
- Modify: `docs/how-your-rails-app-works.md`

**Step 1: Write the section**

Content to cover:
- Zoom in on line 7-9 of RecipesController: `current_kitchen.recipes.includes(steps: %i[ingredients cross_references]).find_by!(slug: params[:slug])`
- Unpack it piece by piece:
  - `current_kitchen.recipes` — "give me all recipes belonging to this kitchen." This is a **relationship** — `Kitchen has_many :recipes` (show kitchen.rb lines 8). Behind the scenes it adds `WHERE kitchen_id = 5` to the SQL.
  - `.includes(steps: %i[ingredients cross_references])` — "while you're at it, also load each recipe's steps, and each step's ingredients and cross-references, all in one query." Without this, rendering the page would fire a separate SQL query for every step and every ingredient (the "N+1 problem").
  - `.find_by!(slug: params[:slug])` — "find the one recipe whose slug matches the URL parameter, or raise a 404 if it doesn't exist."
- Show the model relationship chain with actual code:
  - `Recipe has_many :steps` (recipe.rb line 7) → `Step has_many :ingredients` (step.rb line 6)
  - `belongs_to` is the other side: `Step belongs_to :recipe` (step.rb line 4)
  - These declarations tell Rails how the database tables connect. A Step row has a `recipe_id` column pointing to its Recipe.
- Explain `acts_as_tenant :kitchen` (recipe.rb line 4): this is a gem that adds automatic kitchen scoping. It's why `current_kitchen.recipes` is safe — even if you forgot the scoping, the gem would add it.
- Show `Step#ingredient_list_items` (step.rb lines 12-14): merges ingredients and cross-references into one sorted list. This is what the view iterates over.

**Key source files to reference:**
- `app/controllers/recipes_controller.rb:7-9`
- `app/models/kitchen.rb:8`
- `app/models/recipe.rb:3-8`
- `app/models/step.rb:4-14`
- `app/models/ingredient.rb:3`
- `app/models/cross_reference.rb:3-7`

**Step 2: Review and commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: Rails tutorial — Journey 1, Stop 3 (ActiveRecord)"
```

---

### Task 4: Write Journey 1, Stop 4 — The View Layer (Layout and Template)

**Files:**
- Modify: `docs/how-your-rails-app-works.md`

**Step 1: Write the section**

Content to cover:
- "The controller loaded the data. Now Rails needs to turn it into HTML. It does this by combining a **layout** (the outer shell) with a **template** (the page-specific content)."
- Convention over configuration: `RecipesController#show` automatically renders `app/views/recipes/show.html.erb`. No explicit render call needed — Rails infers the template path from the controller name and action name.
- Show the layout (`application.html.erb`): explain that `<%= yield %>` is the hole where the template gets inserted. The layout handles the `<html>`, `<head>`, nav bar, and `<main>` wrapper.
- Show `content_for` — the recipe template uses `content_for(:title) { @recipe.title }` (show.html.erb line 1) to inject the recipe title into the layout's `<title>` tag (layout line 7). Similarly, `content_for(:scripts)` (show.html.erb lines 16-21) injects JavaScript tags into the layout's bottom-of-body slot (layout line 21). Think of `content_for` as named slots the template can fill.
- Explain `<%= %>` vs `<% %>`: the equals sign means "output this to the HTML." Without equals, the Ruby runs but produces no output (used for loops and conditionals).
- Show the recipe template's main structure: the `<article>` with header, step loop, footer, nutrition table, and editor dialog.
- Explain `@recipe` — the `@` means it's an instance variable set in the controller. Rails automatically makes controller instance variables available in the template. That's how data flows from controller to view.

**Key source files to reference:**
- `app/views/layouts/application.html.erb` (full file)
- `app/views/recipes/show.html.erb:1-6, 16-21, 23-40`

**Step 2: Review and commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: Rails tutorial — Journey 1, Stop 4 (views and layout)"
```

---

### Task 5: Write Journey 1, Stop 5 — Partials and Helpers

**Files:**
- Modify: `docs/how-your-rails-app-works.md`

**Step 1: Write the section**

Content to cover:
- "Inside the template, `<%= render 'step', step: step %>` hands off to another file. This is a **partial** — a reusable template fragment."
- Convention: partials are named with an underscore prefix (`_step.html.erb`), but you reference them without the underscore (`render 'step'`). The `step: step` part passes the local variable.
- Walk through `_step.html.erb` (lines 7-22): the duck typing pattern. `item.respond_to?(:target_slug)` — instead of checking the class (`is_a? CrossReference`), we ask "does this object know how to give me a target slug?" If yes, render it as a recipe link. If no, render it as a plain ingredient. This is idiomatic Ruby and matches the project's conventions.
- Show `link_to item.target_title, recipe_path(item.target_slug)` — a helper that generates an `<a>` tag. `recipe_path` is the route helper from Stop 1.
- Explain helpers: `RecipesHelper` (show the file) provides methods like `render_markdown` and `scalable_instructions` that process text before rendering. These are available in all recipe views. They call into your parser classes (`FamilyRecipes::Recipe::MARKDOWN`, `ScalableNumberPreprocessor`) — this is one of the places where your code meets Rails.
- Mention the nav partial (`_nav.html.erb`) — show how `logged_in?` and `current_kitchen` are used to conditionally show links. These are **helper methods** declared in the controller (`helper_method :current_kitchen, :logged_in?`) and made available in views.

**Key source files to reference:**
- `app/views/recipes/show.html.erb:38-40`
- `app/views/recipes/_step.html.erb` (full file)
- `app/helpers/recipes_helper.rb` (full file)
- `app/views/shared/_nav.html.erb` (full file)
- `app/controllers/application_controller.rb:13`

**Step 2: Review and commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: Rails tutorial — Journey 1, Stop 5 (partials and helpers)"
```

---

### Task 6: Write Journey 1, Stop 6 — Assets

**Files:**
- Modify: `docs/how-your-rails-app-works.md`

**Step 1: Write the section**

Content to cover:
- "The HTML is assembled. The browser also needs CSS and JavaScript files."
- Propshaft: no build step, no Node, no Webpack. Files in `app/assets/` are served directly. Propshaft adds a fingerprint hash to the filename (`style-abc123.css`) so browsers can cache aggressively — when the file changes, the hash changes, and browsers fetch the new version.
- `stylesheet_link_tag 'style'` (layout line 9) → generates `<link href="/assets/style-HASH.css">`. There's one main stylesheet for the whole site.
- `javascript_include_tag 'recipe-editor', defer: true` (show.html.erb line 20) → generates `<script src="/assets/recipe-editor-HASH.js" defer>`. The `defer` attribute means the browser loads it without blocking page rendering.
- Progressive enhancement: every page works without JavaScript. The scale button, cross-off state, and editor are enhancements. This matters because the app treats recipes as documents first.
- Wrap up Journey 1: "That's the full read path. The browser requested a URL, Rails matched it to a controller, loaded data from the database, assembled HTML from a layout + template + partials, and served it with fingerprinted CSS and JS. The whole thing is about 15 lines of Ruby across 3 files (route, controller action, model query) plus the ERB templates."

**Key source files to reference:**
- `app/views/layouts/application.html.erb:9`
- `app/views/recipes/show.html.erb:16-21`

**Step 2: Review and commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: Rails tutorial — Journey 1, Stop 6 (assets) and Journey 1 wrap-up"
```

---

### Task 7: Write Journey 2, Stop 1 — The Editor Dialog and JavaScript

**Files:**
- Modify: `docs/how-your-rails-app-works.md`

**Step 1: Write the section**

Content to cover:
- "Journey 2 starts in the browser, not on the server."
- Transition: "You just read a recipe (Journey 1). Now you want to edit it. You click the Edit button."
- Show the editor dialog partial (`_editor_dialog.html.erb`): it's an HTML `<dialog>` element with data attributes that configure `recipe-editor.js`. No custom JS per dialog — the JS reads the `data-` attributes to know where to send the request, what HTTP method to use, and what to do on success.
- Walk through the data attributes:
  - `data-editor-open="#edit-button"` — which button opens this dialog
  - `data-editor-url="<%= action_url %>"` — where to send the request (e.g., `/kitchens/test-kitchen/recipes/focaccia`)
  - `data-editor-method="PATCH"` — HTTP method (PATCH for updates, POST for creates)
  - `data-editor-on-success="redirect"` — after a successful save, navigate to the URL in the response
  - `data-editor-body-key="markdown_source"` — the JSON key to wrap the textarea content in
- "When you click Save, the JavaScript sends a PATCH request with `{ markdown_source: '# Focaccia\n...' }` as JSON. This is where we leave the browser and enter Rails again — same controller pipeline as Journey 1, but hitting a different action."

**Key source files to reference:**
- `app/views/recipes/_editor_dialog.html.erb` (full file)
- `app/views/recipes/show.html.erb:53-59` (where the dialog is rendered)

**Step 2: Review and commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: Rails tutorial — Journey 2, Stop 1 (editor dialog)"
```

---

### Task 8: Write Journey 2, Stop 2 — Authentication and Authorization

**Files:**
- Modify: `docs/how-your-rails-app-works.md`

**Step 1: Write the section**

Content to cover:
- "The PATCH request hits the controller pipeline. The before-actions run again — `resume_session`, `set_kitchen_from_path` — same as Journey 1. But this time there's an extra gate."
- Show `RecipesController` line 4: `before_action :require_membership, only: %i[create update destroy]`. This means `update` requires membership, but `show` doesn't.
- Walk through `require_membership` (ApplicationController lines 27-35):
  1. `logged_in?` — are you logged in? This calls `authenticated?` from the Authentication concern, which checks if `Current.session` exists.
  2. If not logged in: return 401 (for JSON requests) or redirect to login page (for browser requests).
  3. `current_kitchen.member?(current_user)` — are you a member of *this* kitchen? Show `Kitchen#member?` (kitchen.rb lines 16-19): it checks the `memberships` table for a row linking this user to this kitchen.
- Explain the session system briefly (we're not doing a deep dive on login/logout, just enough to understand the check):
  - When you log in, a `Session` row is created in the database and its ID is stored in a signed cookie.
  - `resume_session` reads that cookie, finds the Session row, and sets `Current.session`.
  - `Current` (show current.rb) is a thread-local container — it holds the session for the duration of this request, then resets.
  - `current_user` (Authentication concern line 62) delegates through the session to get the user.
- "If both checks pass, the controller action runs. If either fails, you get a 401 and the editor shows an error."

**Key source files to reference:**
- `app/controllers/recipes_controller.rb:4`
- `app/controllers/application_controller.rb:27-35`
- `app/controllers/concerns/authentication.rb:19-33, 44-53, 62`
- `app/models/current.rb` (full file)
- `app/models/kitchen.rb:16-19`

**Step 2: Review and commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: Rails tutorial — Journey 2, Stop 2 (authentication)"
```

---

### Task 9: Write Journey 2, Stop 3 — Validation

**Files:**
- Modify: `docs/how-your-rails-app-works.md`

**Step 1: Write the section**

Content to cover:
- "You're authenticated and authorized. The `update` action runs."
- Show RecipesController#update (lines 25-51), focusing on the first three lines: find the recipe, validate the markdown, bail if errors.
- Show `MarkdownValidator` (full file): it's a plain Ruby class, not an ActiveRecord model. It parses the markdown using your parser classes (`LineClassifier`, `RecipeBuilder`) and checks for structural problems: blank content, missing Category, no steps.
- "This is the fail-fast pattern: validate before doing anything expensive. If the markdown is malformed, the controller returns a JSON error response immediately. The editor JavaScript displays these as toast notifications."
- Note: `MarkdownValidator` calls your parser code. If parsing raises an error (e.g., `RecipeBuilder` can't find a title), the rescue on line 20 catches it and turns it into a validation error message. Your parser's exceptions become user-facing error messages.

**Key source files to reference:**
- `app/controllers/recipes_controller.rb:26-29`
- `app/services/markdown_validator.rb` (full file)

**Step 2: Review and commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: Rails tutorial — Journey 2, Stop 3 (validation)"
```

---

### Task 10: Write Journey 2, Stop 4 — The Import Pipeline

**Files:**
- Modify: `docs/how-your-rails-app-works.md`

**Step 1: Write the section**

This is the longest section — it's the heart of the app. Content to cover:

- "Validation passed. Now the controller calls `MarkdownImporter.import(params[:markdown_source], kitchen: current_kitchen)`. This is where your parser meets the database."
- Show `MarkdownImporter` and walk through the pipeline:
  1. **Parse** (line 40-43): `LineClassifier.classify` → `RecipeBuilder.new(tokens).build`. "This is your code. It returns a hash with `:title`, `:description`, `:front_matter`, `:steps` (each with `:tldr`, `:instructions`, `:ingredients`), and `:footer`."
  2. **Transaction** (line 25-33): `ActiveRecord::Base.transaction do ... end`. "Everything inside this block either all succeeds or all fails. If creating a step raises an error, the recipe changes are also rolled back. The database never ends up in a half-updated state."
  3. **Find or create the recipe** (lines 45-48): `kitchen.recipes.find_or_initialize_by(slug: slug)`. "If a recipe with this slug already exists, update it. If not, create a new one."
  4. **Set attributes** (lines 50-65): The parsed data gets mapped onto the Recipe model's columns. Category is found or created. Makes/serves are extracted from front matter.
  5. **Replace steps** (lines 84-97): "Destroy all old steps and create new ones from the parsed data. Each step gets a title, instructions, processed_instructions (with scalable number markup baked in), and a position."
  6. **Import ingredients and cross-references** (lines 105-138): "Each ingredient from the parser becomes an Ingredient row. Cross-references become CrossReference rows that point at the target Recipe."
  7. **Rebuild dependencies** (lines 147-159): "The RecipeDependency table tracks which recipes reference which. This is rebuilt from scratch on every save."
  8. **Compute nutrition** (lines 35-38): "`RecipeNutritionJob.perform_now(recipe)` re-parses the markdown, runs your `NutritionCalculator`, and stores the result as JSON in `recipe.nutrition_data`. This runs synchronously (blocking) for now."
- "After this, the database is the source of truth. The parser doesn't run again until the next edit. Views render from the AR models — the pre-computed Step rows, Ingredient rows, and nutrition JSON."

**Key source files to reference:**
- `app/controllers/recipes_controller.rb:32`
- `app/services/markdown_importer.rb` (full file, with focus on the pipeline)

**Step 2: Review and commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: Rails tutorial — Journey 2, Stop 4 (import pipeline)"
```

---

### Task 11: Write Journey 2, Stop 5 — The Response and Redirect

**Files:**
- Modify: `docs/how-your-rails-app-works.md`

**Step 1: Write the section**

Content to cover:
- "The recipe is saved. The controller renders a JSON response."
- Show RecipesController#update lines 46-48: `render json: { redirect_url: recipe_path(recipe.slug) }`
- "The JavaScript editor reads `redirect_url` from the response and navigates the browser to it. This triggers a fresh GET request — Journey 1 starts again, loading the just-saved recipe from the database."
- Wrap up Journey 2: "That's the full write path. JavaScript sends markdown as JSON, Rails authenticates you, validates the markdown, parses it into database rows, computes nutrition, and responds with a redirect URL. Your parser runs once on the write path; after that, the database serves the reads."
- Add a brief "where the parser lives" summary: your parser classes are called from three places:
  1. `MarkdownImporter` — the write path (decompose markdown into DB rows)
  2. `RecipeNutritionJob` — right after import (compute nutrition from parsed structure)
  3. `GroceriesController` — at view time (aggregate ingredients across multiple recipes)

**Key source files to reference:**
- `app/controllers/recipes_controller.rb:46-48`

**Step 2: Review and commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: Rails tutorial — Journey 2, Stop 5 (response) and Journey 2 wrap-up"
```

---

### Task 12: Write the Glossary

**Files:**
- Modify: `docs/how-your-rails-app-works.md`

**Step 1: Write the glossary**

~25-30 entries, alphabetically. Each entry: term, 1-2 sentence definition, file path in this app. Cover every Rails term used in both journeys:

`acts_as_tenant`, `ActiveRecord`, `ApplicationController`, `asset_path`, `before_action`, `belongs_to`, `concern`, `content_for`, `Current`, `default_url_options`, `delegate`, `destroy`/`dependent: :destroy`, `ERB`, `find_by!`/`find_or_initialize_by`, `has_many`/`has_many through`, `helper_method`, `includes` (eager loading), `instance variable (@)`, `javascript_include_tag`, `layout`, `link_to`, `membership`, `params`, `partial`, `perform_now`, `Propshaft`, `render`, `rescue (method-level)`, `resources` (routes), `route helper`, `scope` (routes), `session (database-backed)`, `stylesheet_link_tag`, `transaction`, `yield`/`yield :name`

**Step 2: Review and commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: Rails tutorial — glossary"
```

---

### Task 13: Final review and cleanup

**Files:**
- Modify: `docs/how-your-rails-app-works.md`

**Step 1: Read the complete document end-to-end**

Check for:
- Narrative flow — does each section build on the previous one?
- Accuracy — do code references match the actual source files?
- Tone — conversational but precise, no Ruby pedagogy, no "what is MVC"
- Completeness — are all Rails concepts from the design doc covered?
- Length — trim anything that repeats or belabors a point

**Step 2: Make any needed edits and final commit**

```bash
git add docs/how-your-rails-app-works.md
git commit -m "docs: Rails tutorial — final review and polish"
```
