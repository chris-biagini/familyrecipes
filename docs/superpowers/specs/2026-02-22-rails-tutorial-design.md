# Rails Tutorial Design

**Date:** 2026-02-22
**Goal:** A skill-level-appropriate Rails tutorial using this codebase as the example, written for someone who authored the parser classes but doesn't understand the Rails plumbing around them.

## Audience Profile

- Wrote the original Recipe, Step, and Ingredient parser classes in Ruby
- Comfortable with basic Ruby: objects, methods, blocks
- Understands MVC at a conceptual level ("controller loads data, view renders it")
- Cannot trace the wiring: routes, before-actions, ActiveRecord relationships, view assembly
- **Goal:** Have informed conversations with Claude about the app — vocabulary, mental model, and the ability to point at the right part of the codebase when describing what they want

## Approach: "Follow the Request"

Structure the tutorial as two narrative journeys through the app, following HTTP requests from browser to response. Every Rails concept is introduced at the moment it becomes relevant, using real code from the app.

**Deliberately skips:** Testing, deployment, database migrations, gem internals. These can be separate docs later.

## Journey 1: "Someone wants to read your Focaccia recipe"

A GET request that introduces most Rails concepts in a low-stakes context.

### Stop 1: The Route
- `config/routes.rb` maps URL patterns to controller actions
- Named parameters (`:kitchen_slug`, `:slug`) extracted from the URL
- Route helpers like `recipe_path('focaccia')` generate URLs

### Stop 2: The Controller Pipeline
- Before-actions run in order before the controller action
- `resume_session` — restores login session from cookie
- `set_kitchen_from_path` — looks up Kitchen, sets current tenant
- `RecipesController#show` — the actual action (two lines)

### Stop 3: ActiveRecord — Loading the Data
- `current_kitchen.recipes.includes(...).find_by!(slug:)` unpacked piece by piece
- Model relationships: `has_many`, `belongs_to`, `through`
- Eager loading (`includes`) to avoid N+1 queries
- How `acts_as_tenant` scopes all queries to the current kitchen

### Stop 4: The View Layer — Layout and Template
- Convention: controller action name maps to template file
- Layout (`application.html.erb`) wraps template via `<%= yield %>`
- `content_for` lets templates inject content into layout slots (title, scripts)

### Stop 5: Partials and Helpers
- `render 'step', step: step` delegates to `_step.html.erb` (underscore convention)
- Local variables passed to partials
- Duck typing in views (`respond_to?(:target_slug)`)
- Helper methods like `scalable_instructions` in `RecipesHelper`

### Stop 6: Assets — CSS and JavaScript
- Propshaft serves fingerprinted assets from `app/assets/`
- No build step — files served directly with cache-busting hash
- `stylesheet_link_tag`, `javascript_include_tag`, `asset_path`
- Progressive enhancement: page works without JavaScript

## Journey 2: "Someone edits and saves that recipe"

A POST/PATCH request that builds on Journey 1 concepts and introduces the write path.

### Stop 1: The Editor Dialog and JavaScript
- HTML `<dialog>` element with `data-` attributes for configuration
- `recipe-editor.js` reads data attributes to know URL, method, success handler
- JavaScript POSTs markdown as JSON — the one place JS initiates a Rails request

### Stop 2: Authentication and Authorization
- `require_membership` before-action gates write endpoints
- Full check: logged in? (`Current.session` exists) → kitchen member? (`Membership` row exists)
- `allow_unauthenticated_access` makes reads open; membership check gates writes
- 401 response if either check fails

### Stop 3: Validation
- `MarkdownValidator` — plain Ruby class, not an ActiveRecord model
- Checks: content present, Category line exists, at least one step
- Fail fast: validate before importing

### Stop 4: The Import Pipeline
- `MarkdownImporter.import(markdown_source, kitchen:)` — the bridge
- Parse: `LineClassifier` → `RecipeBuilder` (the author's own code)
- Transaction: all DB writes succeed or all roll back
- Upsert recipe, replace steps/ingredients/cross-references, rebuild dependencies
- `RecipeNutritionJob.perform_now` computes nutrition, stores as jsonb
- After this, database is the source of truth — parser doesn't run again until next edit

### Stop 5: The Response and Redirect
- Controller renders JSON: `{ redirect_url: recipe_path(recipe.slug) }`
- JavaScript navigates to the URL → Journey 1 begins again (fresh GET)

## Glossary

~25-30 entries covering every Rails term used in both journeys. Each entry:
- Term name
- One or two sentence definition
- File path where it appears in this app

Organized alphabetically for quick lookup during conversations.

## Tone and Style

- Conversational, like a colleague walking through the codebase over coffee
- No Ruby pedagogy (reader already writes Ruby)
- No abstract MVC theory — just "here's what happens in your app"
- Real code from the app (trimmed to relevant lines) with annotations
- Goal is reading comprehension and vocabulary, not teaching the reader to write Rails code

## Output

Single Markdown file: `docs/how-your-rails-app-works.md`
