# Rails 8 Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Rails 8 as a dynamic serving layer alongside the existing static site generator.

**Architecture:** Minimal Rails 8 shell coexisting with the static generator. Shares domain model (`lib/familyrecipes/`). Static build (`bin/generate`) and Rails (`bin/rails server`) are independent output paths. A Rack middleware serves pre-built static files; Rails routes progressively take over for dynamic pages.

**Tech Stack:** Rails 8 (minimal), Puma, Rack middleware, existing FamilyRecipes domain model

**Design doc:** `docs/plans/2026-02-21-rails-migration-design.md`

---

## Phase 2: Bootstrap Rails as Static File Server

### Task 1: Scaffold Rails into existing project

**Files:**
- Create: `app/`, `config/`, `bin/rails`, `bin/rake`, `bin/setup`, `config.ru`, and other Rails scaffolding
- Overwrite (will fix in Task 2): `Gemfile`, `Rakefile`, `.gitignore`

**Step 1: Install Rails gem**

```bash
gem install rails
```

**Step 2: Run the generator**

```bash
rails new . --minimal --skip-active-record --skip-test --skip-asset-pipeline --force
```

`--minimal` skips: Active Job, Action Mailer, Action Mailbox, Active Storage, Action Text, Action Cable, JavaScript, Hotwire, Jbuilder, system tests, bootsnap, dev gems, brakeman, rubocop, CI, Docker, Kamal, Solid, Thruster. We add `--skip-active-record` (no database), `--skip-test` (we have our own Minitest setup), and `--skip-asset-pipeline` (no Propshaft — we serve our own assets). `--force` overwrites conflicting files; we fix them in Task 2.

Expected: new directories (`app/`, `config/`, `log/`, `tmp/`, `vendor/`, `script/`, `storage/`) and files (`config.ru`, `bin/rails`, etc.) created. Existing directories (`lib/`, `recipes/`, `templates/`, `test/`, `docs/`) untouched. `Gemfile`, `Rakefile`, `.gitignore` overwritten (we fix these next).

**Step 3: Delete scaffolding we don't need**

```bash
rm -rf db/ storage/ script/ vendor/
rm -f config/credentials.yml.enc config/master.key
rm -f app/views/layouts/application.html.erb  # we'll write our own later
rm -f public/404.html public/406-unsupported-browser.html public/422.html public/500.html  # we have our own 404
```

We keep: `app/controllers/`, `app/models/`, `config/`, `public/` (for robots.txt, favicon if needed), `tmp/`, `log/`.

---

### Task 2: Merge project configuration files

**Files:**
- Modify: `Gemfile`, `Rakefile`, `.gitignore`, `.rubocop.yml`
- Create: `lib/tasks/familyrecipes.rake`

**Step 1: Write the merged Gemfile**

Combine Rails essentials with our existing gems:

```ruby
# frozen_string_literal: true

source 'https://rubygems.org'

gem 'puma', '>= 5'
gem 'rails', '~> 8.0'

gem 'minitest'
gem 'rake'
gem 'redcarpet'

group :development do
  gem 'rubocop', require: false
  gem 'rubocop-minitest', require: false
  gem 'webrick'
end
```

**Step 2: Write the Rails-compatible Rakefile**

```ruby
# frozen_string_literal: true

require_relative 'config/application'

Rails.application.load_tasks
```

**Step 3: Move our custom Rake tasks to `lib/tasks/familyrecipes.rake`**

```ruby
# frozen_string_literal: true

require 'rake/testtask'
require 'rubocop/rake_task'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test' << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
end

RuboCop::RakeTask.new(:lint)

desc 'Remove generated output'
task :clean do
  rm_rf 'output'
  puts 'Cleaned output/'
end

desc 'Build the static site'
task :build do
  ruby 'bin/generate'
end

task default: %i[lint test]
```

**Step 4: Merge `.gitignore`**

Keep our entries plus Rails entries:

```gitignore
# macOS / Windows
.DS_Store
Thumbs.db
desktop.ini

# Generated output
output/

# Editor directories
.nova/

# Claude Code local data
.claude/

# Bundler
.bundle/
vendor/bundle/

# Environment secrets
.env

# Rails
/log/*
/tmp/*
!/log/.keep
!/tmp/.keep
/config/master.key
/config/credentials/*.key
```

**Step 5: Update `.rubocop.yml` to exclude Rails-generated files**

Add to the `Exclude` list under `AllCops`:

```yaml
AllCops:
  TargetRubyVersion: 3.2
  NewCops: enable
  SuggestExtensions: false
  Exclude:
    - vendor/**/*
    - bin/rails
    - bin/rake
    - bin/setup
    - config/**/*
    - config.ru
    - app/controllers/application_controller.rb
```

**Step 6: Run `bundle install`**

```bash
bundle install
```

Expected: Gemfile.lock updated with Rails and its dependencies.

---

### Task 3: Configure Rails application

**Files:**
- Modify: `config/application.rb`
- Create: `config/initializers/familyrecipes.rb`

**Step 1: Fix `config/application.rb`**

The generated file will have individual framework requires. Verify it looks like this (adjust if the generator produced something different):

```ruby
require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

module Familyrecipes
  class Application < Rails::Application
    config.load_defaults 8.0

    # Don't autoload lib/familyrecipes — it uses its own require system
    # and the module name (FamilyRecipes) doesn't match Zeitwerk's expectation
    # (Familyrecipes) from the directory name.
    config.autoload_lib(ignore: %w[assets tasks familyrecipes])
  end
end
```

Key changes:
- Ensure `rails/test_unit/railtie` is required (we need `ActionDispatch::IntegrationTest` for Phase 3b controller tests)
- Add `familyrecipes` to the `autoload_lib` ignore list to prevent Zeitwerk conflicts (our `FamilyRecipes` module doesn't match Zeitwerk's expected `Familyrecipes` from the directory name)

**Step 2: Create initializer to load domain model**

Create `config/initializers/familyrecipes.rb`:

```ruby
# frozen_string_literal: true

require_relative '../../lib/familyrecipes'
```

This loads our domain model at Rails boot time so it's available to controllers and services.

**Step 3: Verify Rails boots**

```bash
bin/rails runner "puts Rails.env"
```

Expected output: `development`

If this fails, read the error and fix. Common issues: missing gems (run `bundle install`), syntax errors in config files.

---

### Task 4: Write StaticOutputMiddleware (TDD)

**Files:**
- Create: `test/middleware/static_output_middleware_test.rb`
- Create: `app/middleware/static_output_middleware.rb`

**Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'rack'
require 'fileutils'
require 'tmpdir'

require_relative '../../app/middleware/static_output_middleware'

class StaticOutputMiddlewareTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, 'style.css'), 'body { color: red; }')
    File.write(File.join(@dir, 'pizza-dough.html'), '<h1>Pizza Dough</h1>')
    File.write(File.join(@dir, '404.html'), '<h1>Not Found</h1>')
    FileUtils.mkdir_p(File.join(@dir, 'index'))
    File.write(File.join(@dir, 'index', 'index.html'), '<h1>Ingredient Index</h1>')

    @inner_app = ->(_env) { [404, { 'content-type' => 'text/plain' }, ['Not Found']] }
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_serves_exact_file
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir)
    status, headers, = middleware.call(env_for('/style.css'))

    assert_equal 200, status
    assert_match %r{text/css}, headers['content-type']
  end

  def test_serves_html_via_clean_url
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir)
    status, = middleware.call(env_for('/pizza-dough'))

    assert_equal 200, status
  end

  def test_serves_directory_index
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir)
    status, = middleware.call(env_for('/index/'))

    assert_equal 200, status
  end

  def test_falls_through_for_unknown_path
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir)
    status, = middleware.call(env_for('/nonexistent'))

    assert_equal 404, status
  end

  def test_html_fallback_disabled_skips_clean_urls
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir, html_fallback: false)
    status, = middleware.call(env_for('/pizza-dough'))

    assert_equal 404, status
  end

  def test_html_fallback_disabled_still_serves_exact_files
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir, html_fallback: false)
    status, = middleware.call(env_for('/style.css'))

    assert_equal 200, status
  end

  def test_html_fallback_disabled_still_serves_directory_index
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir, html_fallback: false)
    status, = middleware.call(env_for('/index/'))

    assert_equal 200, status
  end

  def test_gracefully_handles_missing_root_directory
    middleware = StaticOutputMiddleware.new(@inner_app, root: '/nonexistent/path')
    status, = middleware.call(env_for('/style.css'))

    assert_equal 404, status
  end

  def test_prevents_path_traversal
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir)
    status, = middleware.call(env_for('/../../../etc/passwd'))

    assert_equal 404, status
  end

  private

  def env_for(path)
    Rack::MockRequest.env_for(path)
  end
end
```

**Step 2: Run test to verify it fails**

```bash
ruby test/middleware/static_output_middleware_test.rb
```

Expected: error — `cannot load such file -- app/middleware/static_output_middleware`

**Step 3: Write the middleware implementation**

```ruby
# frozen_string_literal: true

class StaticOutputMiddleware
  def initialize(app, root:, html_fallback: true)
    @app = app
    @root = root.to_s
    @html_fallback = html_fallback
    @file_server = File.directory?(@root) ? Rack::Files.new(@root) : nil
  end

  def call(env)
    return @app.call(env) unless @file_server

    path_info = Rack::Utils.clean_path_info(env[Rack::PATH_INFO])

    return serve(env, path_info) if servable?(path_info)

    if @html_fallback && !path_info.include?('.')
      html_path = "#{path_info}.html"
      return serve(env, html_path) if servable?(html_path)
    end

    index_path = File.join(path_info, 'index.html')
    return serve(env, index_path) if servable?(index_path)

    @app.call(env)
  end

  private

  def servable?(path)
    full = File.join(@root, path)
    File.file?(full) && full.start_with?(@root)
  end

  def serve(env, path)
    env = env.dup
    env[Rack::PATH_INFO] = path
    @file_server.call(env)
  end
end
```

**Step 4: Run tests to verify they pass**

```bash
ruby test/middleware/static_output_middleware_test.rb
```

Expected: all tests pass.

---

### Task 5: Wire middleware into Rails and verify Phase 2

**Files:**
- Modify: `config/environments/development.rb`
- Modify: `config/routes.rb` (ensure it exists and is empty)

**Step 1: Insert middleware in development config**

Add to `config/environments/development.rb`, inside the `configure` block:

```ruby
config.middleware.insert_after ActionDispatch::Static, StaticOutputMiddleware,
  root: Rails.root.join('output', 'web'),
  html_fallback: true
```

**Step 2: Ensure routes are empty**

`config/routes.rb` should be:

```ruby
Rails.application.routes.draw do
end
```

**Step 3: Generate the static site**

```bash
bin/generate
```

Expected: `output/web/` populated with HTML, CSS, JS files.

**Step 4: Start Rails and verify**

```bash
bin/rails server -p 3000
```

In another terminal (or via curl):

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/
# Expected: 200 (homepage served from output/web/index.html)

curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/style.css
# Expected: 200 (static asset)

curl -s http://localhost:3000/pizza-dough | head -5
# Expected: HTML content of pizza dough recipe (clean URL → pizza-dough.html)
```

Stop the server.

---

### Task 6: Run lint, tests, and commit Phase 2

**Step 1: Run RuboCop**

```bash
bundle exec rubocop
```

Fix any offenses in files we wrote. Exclude Rails-generated files as needed in `.rubocop.yml`.

**Step 2: Run tests**

```bash
bundle exec rake test
```

Expected: all existing tests pass, middleware tests pass.

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: bootstrap Rails 8 as static file server (Phase 2)

Adds minimal Rails 8 app alongside existing static site generator.
Rails serves pre-built output from output/web/ via StaticOutputMiddleware
with clean URL support. Existing bin/generate, templates, and domain
model are unchanged."
```

---

## Phase 3a: File Watching for Auto-Regeneration

### Task 7: Add file watcher for recipe changes

**Files:**
- Create: `config/initializers/recipe_watcher.rb`

**Step 1: Write the file watcher initializer**

```ruby
# frozen_string_literal: true

# Watch recipe markdown files and regenerate on changes.
# Only active in development — production uses pre-built static files.
return unless Rails.env.development?

recipes_glob = Rails.root.join('recipes', '**', '*.md').to_s

Rails.application.config.after_initialize do
  file_watcher = ActiveSupport::FileUpdateChecker.new([], { Rails.root.join('recipes').to_s => ['md'] }) do
    Rails.logger.info 'Recipe files changed — regenerating static site...'

    system('bin/generate', exception: true)

    Rails.logger.info 'Static site regenerated.'
  end

  ActiveSupport::Reloader.to_prepare do
    file_watcher.execute_if_updated
  end
end
```

This uses Rails' built-in `FileUpdateChecker` which polls for changes. Every time Rails reloads (i.e., on the next web request after a file changes), it checks if any `.md` files under `recipes/` have been modified and triggers `bin/generate`.

**Step 2: Verify it works**

1. Start Rails: `bin/rails server -p 3000`
2. Visit `http://localhost:3000/` to confirm it works
3. Edit a recipe file (e.g., add a blank line to any `.md` file)
4. Refresh the browser — check Rails log for "Recipe files changed" message
5. Confirm the page reflects the change

**Step 3: Commit**

```bash
git add config/initializers/recipe_watcher.rb
git commit -m "feat: auto-regenerate static site on recipe file changes (Phase 3a)

Uses ActiveSupport::FileUpdateChecker to watch recipes/**/*.md and
trigger bin/generate when files change. Development only."
```

---

## Phase 3b: Dynamic Recipe Serving

### Task 8: Create RecipeFinder service (TDD)

**Files:**
- Create: `test/services/recipe_finder_test.rb`
- Create: `app/services/recipe_finder.rb`

**Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../config/environment'
require_relative '../../app/services/recipe_finder'

class RecipeFinderTest < Minitest::Test
  def test_finds_recipe_by_slug
    recipe = RecipeFinder.find_by_slug('pizza-dough')

    assert recipe
    assert_equal 'pizza-dough', recipe.id
    assert_equal 'Pizza Dough', recipe.title
  end

  def test_returns_nil_for_unknown_slug
    assert_nil RecipeFinder.find_by_slug('nonexistent-recipe')
  end

  def test_extracts_category_from_front_matter
    recipe = RecipeFinder.find_by_slug('pizza-dough')

    assert recipe.category
    refute_empty recipe.category
  end

  def test_ignores_quick_bites_file
    assert_nil RecipeFinder.find_by_slug('quick-bites')
  end
end
```

Note: this test depends on a recipe called "Pizza Dough" existing in the repo. Check `recipes/` for an actual recipe slug to use and adjust the test if needed.

**Step 2: Run test to verify it fails**

```bash
ruby test/services/recipe_finder_test.rb
```

Expected: error — `cannot load such file -- app/services/recipe_finder`

**Step 3: Implement RecipeFinder**

```ruby
# frozen_string_literal: true

class RecipeFinder
  RECIPES_DIR = Rails.root.join('recipes')
  QUICK_BITES_FILENAME = 'Quick Bites.md'

  def self.find_by_slug(slug)
    path = find_recipe_path(slug)
    return unless path

    source = File.read(path)
    category = extract_category(source)
    FamilyRecipes::Recipe.new(markdown_source: source, id: slug, category: category)
  end

  def self.find_recipe_path(slug)
    Dir.glob(RECIPES_DIR.join('**', '*.md')).find do |path|
      next if File.basename(path) == QUICK_BITES_FILENAME

      FamilyRecipes.slugify(File.basename(path, '.*')) == slug
    end
  end
  private_class_method :find_recipe_path

  def self.extract_category(source)
    source[/^Category:\s*(.+)/, 1]&.strip
  end
  private_class_method :extract_category
end
```

**Step 4: Run tests to verify they pass**

```bash
ruby test/services/recipe_finder_test.rb
```

Expected: all tests pass.

---

### Task 9: Create RecipesController and routes (TDD)

**Files:**
- Create: `test/controllers/recipes_controller_test.rb`
- Create: `app/controllers/recipes_controller.rb`
- Modify: `config/routes.rb`
- Modify: `config/environments/development.rb` (change `html_fallback` to `false`)

**Step 1: Write the failing controller test**

```ruby
# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

require_relative '../../config/environment'
require 'rails/test_help'

class RecipesControllerTest < ActionDispatch::IntegrationTest
  test 'shows a recipe by slug' do
    get '/pizza-dough'

    assert_response :success
    assert_includes response.body, 'Pizza Dough'
  end

  test 'returns 404 for unknown recipe' do
    get '/nonexistent-recipe'

    assert_response :not_found
  end
end
```

Adjust the slug if "pizza-dough" doesn't exist — use any recipe slug from the repo.

**Step 2: Run test to verify it fails**

```bash
ruby test/controllers/recipes_controller_test.rb
```

Expected: routing error (no route matches).

**Step 3: Add routes**

Update `config/routes.rb`:

```ruby
# frozen_string_literal: true

Rails.application.routes.draw do
  get ':id', to: 'recipes#show', constraints: { id: /[a-z0-9-]+/ }
end
```

The constraint ensures only lowercase slug-like URLs match, preventing the catch-all from swallowing asset requests or Rails internal paths.

**Step 4: Switch middleware to `html_fallback: false`**

In `config/environments/development.rb`, change:

```ruby
config.middleware.insert_after ActionDispatch::Static, StaticOutputMiddleware,
  root: Rails.root.join('output', 'web'),
  html_fallback: false
```

This stops the middleware from serving `.html` files for clean URLs — Rails routes handle those now. The middleware still serves CSS, JS, images, and directory indexes (homepage, groceries, index).

**Step 5: Create the controller**

```ruby
# frozen_string_literal: true

class RecipesController < ApplicationController
  def show
    @recipe = RecipeFinder.find_by_slug(params[:id])

    if @recipe
      render :show
    else
      head :not_found
    end
  end
end
```

**Step 6: Create a minimal recipe view**

Create `app/views/recipes/show.html.erb`:

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
  <meta name="theme-color" content="rgb(205, 71, 84)">
  <title><%= @recipe.title %></title>
  <link rel="stylesheet" href="/style.css">
  <link rel="icon" type="image/svg+xml" href="/favicon.svg">
</head>
<body data-recipe-id="<%= @recipe.id %>" data-version-hash="<%= @recipe.version_hash %>">
  <nav>
    <a href="/">Home</a>
    <a href="/index/">Index</a>
    <a href="/groceries/">Groceries</a>
  </nav>
  <main>
    <article>
      <h1><%= @recipe.title %></h1>
      <%- if @recipe.description %>
        <p class="recipe-description"><%= @recipe.description %></p>
      <%- end %>

      <%- @recipe.steps.each do |step| %>
        <section class="recipe-step">
          <h2><%= step.name %></h2>

          <%- unless step.ingredients.empty? %>
            <table class="ingredients-table">
              <tbody>
                <%- step.ingredients.each do |ing| %>
                  <tr>
                    <td class="ingredient-name"><%= ing.name %></td>
                    <td class="ingredient-quantity"><%= ing.quantity %></td>
                    <td class="ingredient-prep"><%= ing.prep_note %></td>
                  </tr>
                <%- end %>
              </tbody>
            </table>
          <%- end %>

          <div class="instructions">
            <%= step.instructions %>
          </div>
        </section>
      <%- end %>
    </article>
  </main>
  <script src="/recipe-state-manager.js" defer></script>
</body>
</html>
```

This is a minimal view that proves the pipeline works. It uses the same CSS (served by middleware from `output/web/style.css`) and includes the recipe state manager JS. It does NOT yet have full feature parity with the static template (no nutrition table, no scaling UI, no cross-off). Those can be added incrementally.

Note: this view does NOT use a Rails layout — it's a self-contained HTML document, matching the static template pattern. We can extract a layout later when we have multiple dynamic pages.

**Step 7: Run controller test**

```bash
ruby test/controllers/recipes_controller_test.rb
```

Expected: tests pass.

**Step 8: Run all tests**

```bash
bundle exec rake test
```

Expected: all tests pass (existing + new middleware + service + controller tests).

---

### Task 10: End-to-end verification and commit Phase 3b

**Step 1: Generate static site (needed for CSS/JS assets)**

```bash
bin/generate
```

**Step 2: Start Rails and verify dynamic serving**

```bash
bin/rails server -p 3000
```

Verify:
- `http://localhost:3000/` — homepage (served by middleware from static output)
- `http://localhost:3000/style.css` — CSS (served by middleware)
- `http://localhost:3000/pizza-dough` — recipe (served dynamically by RecipesController)
- `http://localhost:3000/index/` — ingredient index (served by middleware)
- `http://localhost:3000/groceries/` — grocery list (served by middleware)
- `http://localhost:3000/nonexistent` — 404

The dynamically-served recipe page should be readable and styled (same CSS). It won't be pixel-identical to the static version yet — that's expected.

**Step 3: Run lint**

```bash
bundle exec rubocop
```

Fix any offenses.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: dynamic recipe serving via Rails controller (Phase 3b)

Adds RecipeFinder service to locate and parse recipes by slug,
RecipesController to serve them dynamically, and a minimal recipe
view. Middleware switches to html_fallback:false so Rails routes
handle clean URLs for recipes while middleware continues serving
static assets, homepage, index, and groceries pages."
```

---

## Post-Phase 3b: Known follow-ups (not in scope)

These are natural next steps but outside this plan:

- **View parity:** Bring the Rails recipe view to feature parity with the static template (nutrition table, scaling, cross-off, footer, cross-references)
- **Rails layout extraction:** Extract shared head/nav into `app/views/layouts/application.html.erb`
- **Homepage controller:** Dynamic homepage rendering
- **Caching:** `Rails.cache` for parsed Recipe objects, keyed on file mtime
- **Error pages:** Custom 404 page in Rails (currently falls through to middleware or bare 404)
- **Test environment middleware:** Configure middleware for test environment
- **CI updates:** Add Rails boot check to GitHub Actions
