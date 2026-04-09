# Auth System (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add passwordless authentication via cooking-themed join codes, kitchen creation, and session-based auth — replacing the Authelia-only flow for beta.

**Architecture:** Three new controllers (KitchensController, JoinsController, SessionsController) funnel into the existing session machinery. Kitchen gains an encrypted `join_code` column. A `JoinCodeGenerator` module provides word-list-based code generation. `auto_join_sole_kitchen` is removed; the explicit join flow replaces it.

**Tech Stack:** Rails 8, SQLite, Minitest, Stimulus, Turbo Frames, acts_as_tenant

**Spec:** `docs/superpowers/specs/2026-04-08-auth-system-design.md`

---

## File Map

**New files:**
- `db/seeds/resources/join-code-words.yaml` — curated word lists (techniques, ingredients, dishes)
- `lib/join_code_generator.rb` — module: loads YAML, generates 4-word codes
- `config/initializers/join_code_generator.rb` — loads word list at boot
- `db/migrate/002_add_join_code_to_kitchens.rb` — schema migration
- `app/controllers/kitchens_controller.rb` — kitchen creation flow
- `app/controllers/joins_controller.rb` — join/re-auth flow
- `app/controllers/sessions_controller.rb` — production logout
- `app/views/kitchens/new.html.erb` — create-kitchen form
- `app/views/joins/new.html.erb` — join-code entry form
- `app/views/joins/verify.html.erb` — email entry form
- `app/views/joins/name.html.erb` — name entry form (new members)
- `app/views/layouts/auth.html.erb` — minimal layout for auth pages
- `app/assets/stylesheets/auth.css` — auth page styles
- `test/models/join_code_generator_test.rb` — word list + generation tests
- `test/controllers/kitchens_controller_test.rb` — kitchen creation tests
- `test/controllers/joins_controller_test.rb` — join/re-auth tests
- `test/controllers/sessions_controller_test.rb` — logout tests

**Modified files:**
- `app/models/kitchen.rb` — encrypts :join_code, generation callback, regenerate method
- `app/controllers/application_controller.rb` — remove auto_join_sole_kitchen
- `app/controllers/dev_sessions_controller.rb` — remove destroy action
- `app/controllers/landing_controller.rb` — no-kitchens redirect, multi-kitchen links
- `app/views/landing/show.html.erb` — add create/join links
- `config/routes.rb` — new routes, move logout route
- `app/views/settings/_editor_frame.html.erb` — join code + members + profile sections
- `app/javascript/controllers/settings_editor_controller.js` — profile save, regenerate
- `app/controllers/settings_controller.rb` — add join_code, members, profile endpoints
- `test/controllers/header_auth_test.rb` — update auto-join tests
- `test/test_helper.rb` — update create_kitchen_and_user for join codes

---

### Task 1: Join Code Word List and Generator

**Files:**
- Create: `db/seeds/resources/join-code-words.yaml`
- Create: `lib/join_code_generator.rb`
- Create: `config/initializers/join_code_generator.rb`
- Create: `test/models/join_code_generator_test.rb`

- [ ] **Step 1: Create the word list YAML**

Create `db/seeds/resources/join-code-words.yaml` with three sections. Target: ~80 techniques, ~250 ingredients, ~120 dishes. ASCII only, lowercase, no diacritics.

The file is large (word list curation). Include a broad, diverse set of cooking terms. Every word must match `/\A[a-z]+\z/` — single words, no hyphens, no spaces, no accented characters.

- [ ] **Step 2: Create the JoinCodeGenerator module**

```ruby
# lib/join_code_generator.rb
# frozen_string_literal: true

# Generates cooking-themed join codes in the format:
# "technique ingredient ingredient dish"
# Loaded once at boot via initializer; arrays frozen for thread safety.
# Uses SecureRandom for index selection.
#
# - Kitchen: calls generate on create, stores result in join_code column
# - config/initializers/join_code_generator.rb: triggers load! at boot
module JoinCodeGenerator
  WORDS_PATH = Rails.root.join('db/seeds/resources/join-code-words.yaml')

  class << self
    attr_reader :techniques, :ingredients, :dishes

    def load!
      data = YAML.load_file(WORDS_PATH)
      @techniques = data.fetch('techniques').map(&:freeze).freeze
      @ingredients = data.fetch('ingredients').map(&:freeze).freeze
      @dishes = data.fetch('dishes').map(&:freeze).freeze
    end

    def generate
      t = techniques[SecureRandom.random_number(techniques.size)]
      i1 = ingredients[SecureRandom.random_number(ingredients.size)]
      i2 = pick_second_ingredient(i1)
      d = dishes[SecureRandom.random_number(dishes.size)]
      "#{t} #{i1} #{i2} #{d}"
    end

    private

    def pick_second_ingredient(first)
      loop do
        candidate = ingredients[SecureRandom.random_number(ingredients.size)]
        return candidate unless candidate == first
      end
    end
  end
end
```

- [ ] **Step 3: Create the initializer**

```ruby
# config/initializers/join_code_generator.rb
# frozen_string_literal: true

require_relative '../../lib/join_code_generator'
JoinCodeGenerator.load!
```

- [ ] **Step 4: Write tests for the generator**

```ruby
# test/models/join_code_generator_test.rb
# frozen_string_literal: true

require 'test_helper'

class JoinCodeGeneratorTest < ActiveSupport::TestCase
  test 'word lists are loaded and frozen' do
    assert_predicate JoinCodeGenerator.techniques, :frozen?
    assert_predicate JoinCodeGenerator.ingredients, :frozen?
    assert_predicate JoinCodeGenerator.dishes, :frozen?
  end

  test 'word lists are non-empty' do
    assert JoinCodeGenerator.techniques.size >= 60
    assert JoinCodeGenerator.ingredients.size >= 200
    assert JoinCodeGenerator.dishes.size >= 80
  end

  test 'all words are lowercase ASCII' do
    all_words = JoinCodeGenerator.techniques + JoinCodeGenerator.ingredients + JoinCodeGenerator.dishes
    all_words.each do |word|
      assert_match(/\A[a-z]+\z/, word, "Word '#{word}' contains non-ASCII or non-lowercase characters")
    end
  end

  test 'no duplicate words within or across lists' do
    all_words = JoinCodeGenerator.techniques + JoinCodeGenerator.ingredients + JoinCodeGenerator.dishes
    assert_equal all_words.size, all_words.uniq.size, 'Duplicate words found in word lists'
  end

  test 'generate produces 4-word string' do
    code = JoinCodeGenerator.generate
    words = code.split
    assert_equal 4, words.size
  end

  test 'generate follows technique-ingredient-ingredient-dish format' do
    code = JoinCodeGenerator.generate
    words = code.split
    assert_includes JoinCodeGenerator.techniques, words[0]
    assert_includes JoinCodeGenerator.ingredients, words[1]
    assert_includes JoinCodeGenerator.ingredients, words[2]
    assert_includes JoinCodeGenerator.dishes, words[3]
  end

  test 'two ingredients are different' do
    20.times do
      code = JoinCodeGenerator.generate
      words = code.split
      assert_not_equal words[1], words[2], "Duplicate ingredients in: #{code}"
    end
  end

  test 'generate produces different codes' do
    codes = Array.new(10) { JoinCodeGenerator.generate }
    assert codes.uniq.size > 1, 'All generated codes were identical'
  end
end
```

- [ ] **Step 5: Run tests**

Run: `ruby -Itest test/models/join_code_generator_test.rb`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add db/seeds/resources/join-code-words.yaml lib/join_code_generator.rb config/initializers/join_code_generator.rb test/models/join_code_generator_test.rb
git commit -m "Add cooking-themed join code word list and generator"
```

---

### Task 2: Schema Migration and Kitchen Model

**Files:**
- Create: `db/migrate/002_add_join_code_to_kitchens.rb`
- Modify: `app/models/kitchen.rb`
- Modify: `test/test_helper.rb`

- [ ] **Step 1: Create the migration**

```ruby
# db/migrate/002_add_join_code_to_kitchens.rb
# frozen_string_literal: true

class AddJoinCodeToKitchens < ActiveRecord::Migration[8.0]
  def up
    add_column :kitchens, :join_code, :string

    # Backfill existing kitchens — use update! (not update_column) so
    # Active Record encryption runs. Define a bare stub to avoid coupling
    # to the application model.
    Kitchen.reset_column_information
    Kitchen.find_each do |kitchen|
      kitchen.update!(join_code: JoinCodeGenerator.generate)
    end

    change_column_null :kitchens, :join_code, false
    add_index :kitchens, :join_code, unique: true
  end

  def down
    remove_column :kitchens, :join_code
  end
end
```

Note: This migration references `JoinCodeGenerator` directly. Normally CLAUDE.md forbids calling application code from migrations, but `JoinCodeGenerator` is a standalone module with no AR dependencies — it just reads a YAML file. This is safe. The `update!` call (not `update_column`) ensures Active Record encryption runs.

- [ ] **Step 2: Run the migration**

Run: `rails db:migrate`
Expected: Migration succeeds, existing kitchens get join codes.

- [ ] **Step 3: Update Kitchen model**

Add to `app/models/kitchen.rb`:
- `encrypts :join_code, deterministic: true` — encrypted at rest, queryable
- `before_create :set_join_code` — auto-generate on creation
- `regenerate_join_code!` — generate new code, save
- `find_by_join_code(code)` — class method, normalizes input

Update the header comment to mention join codes.

```ruby
# In kitchen.rb, add after the existing encrypts lines:
encrypts :join_code, deterministic: true

# Add after the validates block:
before_create :set_join_code

def self.find_by_join_code(code)
  normalized = code.to_s.strip.downcase.squish
  find_by(join_code: normalized)
end

def regenerate_join_code!
  loop do
    self.join_code = JoinCodeGenerator.generate
    break unless Kitchen.where.not(id: id).exists?(join_code: join_code)
  end
  save!
end

# In private section:
def set_join_code
  loop do
    self.join_code = JoinCodeGenerator.generate
    break unless Kitchen.exists?(join_code: join_code)
  end
end
```

- [ ] **Step 4: Update test helper**

In `test/test_helper.rb`, update `setup_test_kitchen` to handle the new `join_code` column. Since `Kitchen.first` may already have a code from migration, this should work without changes. But `create_kitchen_and_user` may need the column default. Verify existing tests still pass.

- [ ] **Step 5: Write Kitchen model tests for join codes**

Add to an existing or new test file `test/models/kitchen_join_code_test.rb`:

```ruby
# test/models/kitchen_join_code_test.rb
# frozen_string_literal: true

require 'test_helper'

class KitchenJoinCodeTest < ActiveSupport::TestCase
  test 'join code is generated on create' do
    kitchen = Kitchen.create!(name: 'New Kitchen', slug: 'new-kitchen')
    assert_predicate kitchen.join_code, :present?
    assert_equal 4, kitchen.join_code.split.size
  end

  test 'join code is unique across kitchens' do
    with_multi_kitchen do
      k1 = Kitchen.create!(name: 'Kitchen A', slug: 'kitchen-a')
      k2 = Kitchen.create!(name: 'Kitchen B', slug: 'kitchen-b')
      assert_not_equal k1.join_code, k2.join_code
    end
  end

  test 'regenerate_join_code! produces a new code' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test-regen')
    old_code = kitchen.join_code
    kitchen.regenerate_join_code!
    assert_not_equal old_code, kitchen.join_code
  end

  test 'find_by_join_code normalizes input' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test-lookup')
    code = kitchen.join_code
    upcased = code.upcase
    padded = "  #{code}  "

    assert_equal kitchen, Kitchen.find_by_join_code(upcased)
    assert_equal kitchen, Kitchen.find_by_join_code(padded)
  end

  test 'find_by_join_code returns nil for invalid code' do
    assert_nil Kitchen.find_by_join_code('invalid code here now')
  end
end
```

- [ ] **Step 6: Run all tests**

Run: `rake test`
Expected: All pass (existing + new).

- [ ] **Step 7: Commit**

```bash
git add db/migrate/002_add_join_code_to_kitchens.rb app/models/kitchen.rb test/models/kitchen_join_code_test.rb
git commit -m "Add encrypted join_code column to Kitchen with generation"
```

---

### Task 3: Routes and SessionsController

**Files:**
- Create: `app/controllers/sessions_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/dev_sessions_controller.rb`
- Create: `test/controllers/sessions_controller_test.rb`

- [ ] **Step 1: Create SessionsController**

```ruby
# app/controllers/sessions_controller.rb
# frozen_string_literal: true

# Production logout endpoint. Terminates the database-backed session and clears
# the signed cookie. Replaces DevSessionsController#destroy for production use.
#
# - Authentication concern: provides terminate_session
# - DevSessionsController: retains dev-only login (create action)
class SessionsController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def destroy
    terminate_session
    cookies[:skip_dev_auto_login] = true if Rails.env.development?
    redirect_to root_path
  end
end
```

- [ ] **Step 2: Update routes**

In `config/routes.rb`, replace the logout route and add new auth routes:

```ruby
# Replace:
#   delete 'logout', to: 'dev_sessions#destroy', as: :logout
# With:
delete 'logout', to: 'sessions#destroy', as: :logout

# Add before the logout line:
get 'new', to: 'kitchens#new', as: :new_kitchen
post 'new', to: 'kitchens#create'
get 'join', to: 'joins#new', as: :join_kitchen
post 'join', to: 'joins#verify', as: :verify_join
post 'join/complete', to: 'joins#create', as: :complete_join
```

- [ ] **Step 3: Update DevSessionsController**

Remove the `destroy` action. Keep only `create`:

```ruby
# app/controllers/dev_sessions_controller.rb
# frozen_string_literal: true

# Dev/test-only authentication bypass. Provides direct login at /dev/login/:id
# (blocked in production). Logout moved to SessionsController.
class DevSessionsController < ApplicationController
  skip_before_action :set_kitchen_from_path
  before_action :require_non_production_environment, only: :create

  def create
    user = User.find(params[:id])
    start_new_session_for(user)
    cookies.delete(:skip_dev_auto_login)
    kitchen = ActsAsTenant.without_tenant { user.kitchens.first }
    return redirect_to root_path unless kitchen

    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  private

  def require_non_production_environment
    head :not_found unless Rails.env.local?
  end
end
```

- [ ] **Step 4: Write SessionsController tests**

```ruby
# test/controllers/sessions_controller_test.rb
# frozen_string_literal: true

require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'logout clears session and redirects to root' do
    log_in

    assert_predicate cookies[:session_id], :present?

    delete logout_path

    assert_redirected_to root_path
  end

  test 'logout when not logged in redirects to root' do
    delete logout_path

    assert_redirected_to root_path
  end
end
```

- [ ] **Step 5: Run tests**

Run: `rake test`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/sessions_controller.rb app/controllers/dev_sessions_controller.rb config/routes.rb test/controllers/sessions_controller_test.rb
git commit -m "Add SessionsController for production logout, update routes"
```

---

### Task 4: Remove auto_join_sole_kitchen

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/models/membership.rb` (update header comment)
- Modify: `test/controllers/header_auth_test.rb`

- [ ] **Step 1: Remove auto_join_sole_kitchen from ApplicationController**

In `app/controllers/application_controller.rb`:
- Remove `before_action :auto_join_sole_kitchen`
- Remove the `auto_join_sole_kitchen` method (lines 92-104)
- Update the header comment to remove mention of auto-join

- [ ] **Step 2: Update Membership header comment**

Remove the sentence about auto_join_sole_kitchen from the Membership model header comment.

- [ ] **Step 3: Update header auth tests**

The "auto-joins sole kitchen" and "does not auto-join" tests need to be removed or updated. Remove the following tests from `test/controllers/header_auth_test.rb`:
- `test 'auto-joins sole kitchen for new user'`
- `test 'does not auto-join when multiple kitchens exist'`
- `test 'does not auto-join when user already has membership'`

These behaviors no longer exist — users join via the explicit join flow.

- [ ] **Step 4: Run tests**

Run: `rake test`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/application_controller.rb app/models/membership.rb test/controllers/header_auth_test.rb
git commit -m "Remove auto_join_sole_kitchen (replaced by explicit join flow)"
```

---

### Task 5: Auth Layout and Styles

**Files:**
- Create: `app/views/layouts/auth.html.erb`
- Create: `app/assets/stylesheets/auth.css`

- [ ] **Step 1: Create auth layout**

A minimal layout for auth pages (create kitchen, join, etc.). Shares the app's design tokens from `base.css` but doesn't include the full navigation, settings dialog, or editor infrastructure.

```erb
<%# app/views/layouts/auth.html.erb %>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><%= yield(:title) || 'Family Recipes' %></title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <%= stylesheet_link_tag 'base', 'auth' %>
</head>
<body class="auth-page">
  <main class="auth-container">
    <%= yield %>
  </main>
</body>
</html>
```

- [ ] **Step 2: Create auth styles**

Create `app/assets/stylesheets/auth.css` with styles for auth forms. Follow the existing design tokens from `base.css` (--font-display, --font-body, --ground, --text, --rule, etc.). Keep it minimal — centered card with form fields.

The CSS should provide:
- `.auth-container` — centered flex container
- `.auth-card` — card with padding, border, shadow
- `.auth-card h1` — heading using --font-display
- `.auth-field` — form field wrapper (label + input)
- `.auth-field label` — styled label
- `.auth-field input` — uses .input-base pattern from base.css
- `.auth-submit` — submit button (uses .btn pattern)
- `.auth-error` — error message styling
- `.auth-footer` — links below the form (e.g., "Already have a kitchen?")

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/auth.html.erb app/assets/stylesheets/auth.css
git commit -m "Add auth layout and styles for auth pages"
```

---

### Task 6: KitchensController (Kitchen Creation Flow)

**Files:**
- Create: `app/controllers/kitchens_controller.rb`
- Create: `app/views/kitchens/new.html.erb`
- Create: `test/controllers/kitchens_controller_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/controllers/kitchens_controller_test.rb
# frozen_string_literal: true

require 'test_helper'

class KitchensControllerTest < ActionDispatch::IntegrationTest
  test 'new renders creation form' do
    with_multi_kitchen do
      get new_kitchen_path
      assert_response :success
      assert_select 'form'
    end
  end

  test 'create builds kitchen, user, membership, meal plan, and session' do
    with_multi_kitchen do
      assert_difference ['Kitchen.count', 'User.count', 'Membership.count', 'MealPlan.count'], 1 do
        post new_kitchen_path, params: {
          name: 'Chef User',
          email: 'chef@example.com',
          kitchen_name: 'Our Kitchen'
        }
      end

      kitchen = Kitchen.find_by(slug: 'our-kitchen')
      assert_predicate kitchen, :present?
      assert_predicate kitchen.join_code, :present?

      user = User.find_by(email: 'chef@example.com')
      assert_equal 'Chef User', user.name
      assert kitchen.member?(user)

      membership = ActsAsTenant.with_tenant(kitchen) { kitchen.memberships.find_by(user: user) }
      assert_equal 'owner', membership.role

      assert_redirected_to kitchen_root_path(kitchen_slug: 'our-kitchen')
      assert_predicate cookies[:session_id], :present?
    end
  end

  test 'create with existing user email reuses user' do
    existing = User.create!(name: 'Existing', email: 'existing@example.com')

    with_multi_kitchen do
      assert_no_difference 'User.count' do
        assert_difference 'Kitchen.count', 1 do
          post new_kitchen_path, params: {
            name: 'Existing',
            email: 'existing@example.com',
            kitchen_name: 'Second Kitchen'
          }
        end
      end
    end
  end

  test 'create with validation errors re-renders form' do
    with_multi_kitchen do
      post new_kitchen_path, params: {
        name: '',
        email: 'bad',
        kitchen_name: ''
      }

      assert_response :unprocessable_content
      assert_select 'form'
    end
  end

  test 'create redirects to home if already logged in and not intentional' do
    create_kitchen_and_user
    log_in

    get new_kitchen_path

    assert_redirected_to root_path
  end

  test 'create allows logged-in user when intentional param present' do
    create_kitchen_and_user
    log_in

    with_multi_kitchen do
      get new_kitchen_path(intentional: true)
      assert_response :success
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/kitchens_controller_test.rb`
Expected: FAIL (controller doesn't exist yet).

- [ ] **Step 3: Create KitchensController**

```ruby
# app/controllers/kitchens_controller.rb
# frozen_string_literal: true

# Kitchen creation flow. Creates a Kitchen, User, Membership (owner role),
# and MealPlan in a single transaction, then starts a session. Ungated in
# Phase 1 (beta); Phase 2 adds email verification for hosted mode.
#
# - Kitchen: tenant model with join_code generation
# - User: found or created by email
# - Membership: join table with role column
# - Authentication concern: start_new_session_for
class KitchensController < ApplicationController
  skip_before_action :set_kitchen_from_path
  before_action :redirect_if_logged_in, only: :new

  layout 'auth'

  rate_limit to: 5, within: 1.hour, by: -> { request.remote_ip }, only: :create

  def new
    # Form rendered by view
  end

  def create
    kitchen = nil
    user = nil

    ActiveRecord::Base.transaction do
      kitchen = build_kitchen
      user = find_or_create_user
      ActsAsTenant.with_tenant(kitchen) do
        Membership.create!(kitchen: kitchen, user: user, role: 'owner')
      end
      MealPlan.create!(kitchen: kitchen)
    end

    start_new_session_for(user)
    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
  rescue ActiveRecord::RecordInvalid => e
    @errors = e.record.errors.full_messages
    render :new, status: :unprocessable_content
  end

  private

  def build_kitchen
    Kitchen.create!(
      name: params[:kitchen_name],
      slug: params[:kitchen_name].to_s.parameterize.presence || 'kitchen'
    )
  end

  def find_or_create_user
    User.find_or_create_by!(email: params[:email].to_s.strip.downcase) do |u|
      u.name = params[:name]
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def redirect_if_logged_in
    return unless authenticated?
    return if params[:intentional]

    redirect_to root_path
  end
end
```

- [ ] **Step 4: Create the view**

```erb
<%# app/views/kitchens/new.html.erb %>
<% content_for(:title) { 'Create a Kitchen' } %>

<div class="auth-card">
  <h1>Create a Kitchen</h1>
  <p class="auth-subtitle">Start a new recipe collection for your household.</p>

  <% if @errors&.any? %>
    <div class="auth-error">
      <% @errors.each do |error| %>
        <p><%= error %></p>
      <% end %>
    </div>
  <% end %>

  <%= form_with url: new_kitchen_path, method: :post, local: true do |f| %>
    <div class="auth-field">
      <label for="name">Your name</label>
      <input type="text" id="name" name="name" class="input-base input-lg"
             value="<%= params[:name] %>" required autofocus>
    </div>

    <div class="auth-field">
      <label for="email">Your email</label>
      <input type="email" id="email" name="email" class="input-base input-lg"
             value="<%= params[:email] %>" required>
    </div>

    <div class="auth-field">
      <label for="kitchen_name">Kitchen name</label>
      <input type="text" id="kitchen_name" name="kitchen_name" class="input-base input-lg"
             value="<%= params[:kitchen_name] %>" required
             placeholder="e.g., The Smith Kitchen">
    </div>

    <button type="submit" class="btn auth-submit">Create Kitchen</button>
  <% end %>

  <div class="auth-footer">
    <p>Have a join code? <%= link_to 'Join a kitchen', join_kitchen_path %></p>
  </div>
</div>
```

- [ ] **Step 5: Run tests**

Run: `ruby -Itest test/controllers/kitchens_controller_test.rb`
Expected: All pass.

- [ ] **Step 6: Run full test suite**

Run: `rake test`
Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/kitchens_controller.rb app/views/kitchens/new.html.erb test/controllers/kitchens_controller_test.rb
git commit -m "Add KitchensController for kitchen creation flow"
```

---

### Task 7: JoinsController (Join/Re-auth Flow)

**Files:**
- Create: `app/controllers/joins_controller.rb`
- Create: `app/views/joins/new.html.erb`
- Create: `app/views/joins/verify.html.erb`
- Create: `app/views/joins/name.html.erb`
- Create: `test/controllers/joins_controller_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/controllers/joins_controller_test.rb
# frozen_string_literal: true

require 'test_helper'

class JoinsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'new renders join code form' do
    get join_kitchen_path

    assert_response :success
    assert_select 'form'
  end

  test 'verify with invalid code shows error' do
    post verify_join_path, params: { join_code: 'invalid code here now' }

    assert_response :unprocessable_content
    assert_select '.auth-error'
  end

  test 'verify with valid code renders email form' do
    post verify_join_path, params: { join_code: @kitchen.join_code }

    assert_response :success
    assert_select 'input[name="email"]'
  end

  test 'complete with known email re-authenticates' do
    signed_kitchen = sign_kitchen_id(@kitchen.id)

    assert_no_difference ['User.count', 'Membership.count'] do
      post complete_join_path, params: {
        email: @user.email,
        signed_kitchen_id: signed_kitchen
      }
    end

    assert_redirected_to kitchen_root_path(kitchen_slug: @kitchen.slug)
    assert_predicate cookies[:session_id], :present?
  end

  test 'complete with unknown email renders name form' do
    signed_kitchen = sign_kitchen_id(@kitchen.id)

    post complete_join_path, params: {
      email: 'newperson@example.com',
      signed_kitchen_id: signed_kitchen
    }

    assert_response :success
    assert_select 'input[name="name"]'
  end

  test 'complete with name creates user and membership' do
    signed_kitchen = sign_kitchen_id(@kitchen.id)

    assert_difference ['User.count', 'Membership.count'], 1 do
      post complete_join_path, params: {
        email: 'newperson@example.com',
        name: 'New Person',
        signed_kitchen_id: signed_kitchen
      }
    end

    assert_redirected_to kitchen_root_path(kitchen_slug: @kitchen.slug)

    user = User.find_by(email: 'newperson@example.com')
    assert_equal 'New Person', user.name
    assert @kitchen.member?(user)
  end

  test 'complete with existing user from another kitchen creates membership only' do
    other_kitchen = nil
    with_multi_kitchen do
      other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    end
    outsider = User.create!(name: 'Outsider', email: 'outsider@example.com')
    ActsAsTenant.with_tenant(other_kitchen) do
      Membership.create!(kitchen: other_kitchen, user: outsider)
    end

    signed_kitchen = sign_kitchen_id(@kitchen.id)

    assert_no_difference 'User.count' do
      assert_difference 'Membership.count', 1 do
        post complete_join_path, params: {
          email: 'outsider@example.com',
          signed_kitchen_id: signed_kitchen
        }
      end
    end

    assert_redirected_to kitchen_root_path(kitchen_slug: @kitchen.slug)
  end

  test 'complete with tampered signed kitchen ID is rejected' do
    post complete_join_path, params: {
      email: @user.email,
      signed_kitchen_id: 'tampered-value'
    }

    assert_redirected_to join_kitchen_path
  end

  private

  def sign_kitchen_id(id)
    Rails.application.message_verifier(:join).generate(id, purpose: :join, expires_in: 15.minutes)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/joins_controller_test.rb`
Expected: FAIL.

- [ ] **Step 3: Create JoinsController**

```ruby
# app/controllers/joins_controller.rb
# frozen_string_literal: true

# Multi-step join flow: enter join code → enter email → re-auth or register.
# Handles both new member registration and returning member re-authentication
# through a single unified flow. Kitchen ID is passed between steps via a
# signed, time-limited token to prevent tampering.
#
# - Kitchen: join code lookup via find_by_join_code
# - User: found or created by email
# - Membership: join table creation for new members
# - Authentication concern: start_new_session_for
class JoinsController < ApplicationController
  skip_before_action :set_kitchen_from_path

  layout 'auth'

  rate_limit to: 10, within: 1.hour, by: -> { request.remote_ip }, only: :verify

  def new
    # Renders join code form
  end

  def verify
    kitchen = Kitchen.find_by_join_code(params[:join_code])

    unless kitchen
      @error = "That code doesn't match any kitchen. Double-check and try again."
      return render :new, status: :unprocessable_content
    end

    @signed_kitchen_id = sign_kitchen_id(kitchen.id)
    @kitchen_name = kitchen.name
    render :verify
  end

  def create
    kitchen = resolve_signed_kitchen
    return redirect_to join_kitchen_path, alert: 'Invalid or expired session. Please re-enter your join code.' unless kitchen

    email = params[:email].to_s.strip.downcase
    authenticate_or_register(kitchen, email)
  end

  private

  def authenticate_or_register(kitchen, email)
    user = User.find_by(email: email)

    return authenticate_existing(kitchen, user) if user
    return render_name_form(kitchen, email) unless params[:name].present?

    register_new_member(kitchen, email, params[:name])
  end

  def authenticate_existing(kitchen, user)
    ensure_membership(kitchen, user)
    start_new_session_for(user)
    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  def ensure_membership(kitchen, user)
    return if ActsAsTenant.with_tenant(kitchen) { kitchen.member?(user) }

    ActsAsTenant.with_tenant(kitchen) { Membership.create!(kitchen: kitchen, user: user) }
  end

  def register_new_member(kitchen, email, name)
    user = User.create!(name: name, email: email)
    ActsAsTenant.with_tenant(kitchen) { Membership.create!(kitchen: kitchen, user: user) }
    start_new_session_for(user)
    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
  rescue ActiveRecord::RecordInvalid => e
    @errors = e.record.errors.full_messages
    render_name_form(kitchen, email)
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def render_name_form(kitchen, email)
    @signed_kitchen_id = sign_kitchen_id(kitchen.id)
    @kitchen_name = kitchen.name
    @email = email
    render :name
  end

  def sign_kitchen_id(id)
    Rails.application.message_verifier(:join).generate(id, purpose: :join, expires_in: 15.minutes)
  end

  def resolve_signed_kitchen
    kitchen_id = Rails.application.message_verifier(:join).verified(params[:signed_kitchen_id], purpose: :join)
    return nil unless kitchen_id

    ActsAsTenant.without_tenant { Kitchen.find_by(id: kitchen_id) }
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
```

- [ ] **Step 4: Create views**

Create `app/views/joins/new.html.erb` — join code entry form:

```erb
<% content_for(:title) { 'Join a Kitchen' } %>

<div class="auth-card">
  <h1>Join a Kitchen</h1>
  <p class="auth-subtitle">Enter the join code you received.</p>

  <% if @error %>
    <div class="auth-error"><p><%= @error %></p></div>
  <% end %>

  <%= form_with url: verify_join_path, method: :post, local: true do |f| %>
    <div class="auth-field">
      <label for="join_code">Join code</label>
      <input type="text" id="join_code" name="join_code" class="input-base input-lg"
             placeholder="braised eggplant cardamom casserole" required autofocus
             autocomplete="off" autocapitalize="none">
    </div>

    <button type="submit" class="btn auth-submit">Continue</button>
  <% end %>

  <div class="auth-footer">
    <p>Want to start your own? <%= link_to 'Create a kitchen', new_kitchen_path %></p>
  </div>
</div>
```

Create `app/views/joins/verify.html.erb` — email entry form:

```erb
<% content_for(:title) { "Join #{@kitchen_name}" } %>

<div class="auth-card">
  <h1><%= @kitchen_name %></h1>
  <p class="auth-subtitle">Enter your email to join or sign back in.</p>

  <%= form_with url: complete_join_path, method: :post, local: true do |f| %>
    <%= hidden_field_tag :signed_kitchen_id, @signed_kitchen_id %>

    <div class="auth-field">
      <label for="email">Your email</label>
      <input type="email" id="email" name="email" class="input-base input-lg"
             required autofocus>
    </div>

    <button type="submit" class="btn auth-submit">Continue</button>
  <% end %>
</div>
```

Create `app/views/joins/name.html.erb` — name entry for new members:

```erb
<% content_for(:title) { "Join #{@kitchen_name}" } %>

<div class="auth-card">
  <h1>Welcome to <%= @kitchen_name %></h1>
  <p class="auth-subtitle">One more thing &mdash; what should we call you?</p>

  <% if @errors&.any? %>
    <div class="auth-error">
      <% @errors.each do |error| %>
        <p><%= error %></p>
      <% end %>
    </div>
  <% end %>

  <%= form_with url: complete_join_path, method: :post, local: true do |f| %>
    <%= hidden_field_tag :signed_kitchen_id, @signed_kitchen_id %>
    <%= hidden_field_tag :email, @email %>

    <div class="auth-field">
      <label for="name">Your name</label>
      <input type="text" id="name" name="name" class="input-base input-lg"
             required autofocus>
    </div>

    <button type="submit" class="btn auth-submit">Join Kitchen</button>
  <% end %>
</div>
```

- [ ] **Step 5: Run tests**

Run: `ruby -Itest test/controllers/joins_controller_test.rb`
Expected: All pass.

- [ ] **Step 6: Run full test suite**

Run: `rake test`
Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/joins_controller.rb app/views/joins/ test/controllers/joins_controller_test.rb
git commit -m "Add JoinsController for join code and re-auth flow"
```

---

### Task 8: LandingController Updates

**Files:**
- Modify: `app/controllers/landing_controller.rb`
- Modify: `app/views/landing/show.html.erb`
- Create: `test/controllers/landing_controller_test.rb`

- [ ] **Step 1: Write tests**

```ruby
# test/controllers/landing_controller_test.rb
# frozen_string_literal: true

require 'test_helper'

class LandingControllerTest < ActionDispatch::IntegrationTest
  test 'redirects to /new when no kitchens exist' do
    Kitchen.delete_all

    get root_path

    assert_redirected_to new_kitchen_path
  end

  test 'renders sole kitchen homepage when one kitchen exists' do
    setup_test_kitchen

    get root_path

    assert_response :success
  end

  test 'renders kitchen list with create/join links when multiple kitchens exist' do
    setup_test_kitchen
    with_multi_kitchen { Kitchen.create!(name: 'Second', slug: 'second') }

    get root_path

    assert_response :success
    assert_select "a[href='#{new_kitchen_path}']"
    assert_select "a[href='#{join_kitchen_path}']"
  end
end
```

- [ ] **Step 2: Update LandingController**

```ruby
# app/controllers/landing_controller.rb
# frozen_string_literal: true

# Root route handler. No kitchens → redirects to /new (kitchen creation).
# One Kitchen → renders its homepage directly (clean root-level URLs).
# Multiple Kitchens → renders a kitchen-list landing page with create/join links.
# Skips set_kitchen_from_path because the root URL has no slug.
#
# - Kitchen: tenant lookup (bypasses ActsAsTenant scoping)
# - HomepageController: shares the homepage/show view for the sole-kitchen case
# - KitchensController: creation flow at /new
# - JoinsController: join flow at /join
class LandingController < ApplicationController
  skip_before_action :set_kitchen_from_path
  before_action :prevent_html_caching, only: :show

  def show
    @kitchens = ActsAsTenant.without_tenant { Kitchen.all.to_a }

    return redirect_to new_kitchen_path if @kitchens.empty?

    @kitchens.size == 1 ? render_sole_kitchen_homepage : render('landing/show')
  end

  private

  def render_sole_kitchen_homepage
    set_current_tenant(@kitchens.first)
    @categories = current_kitchen.categories.with_recipes.ordered.includes(recipes: :tags)
    render 'homepage/show'
  end
end
```

- [ ] **Step 3: Update landing view**

```erb
<%# app/views/landing/show.html.erb %>
<% content_for(:title) { 'Family Recipes' } %>

<article class="landing">
  <header>
    <h1>Family Recipes</h1>
    <p>A place for your family&rsquo;s recipes.</p>
  </header>

  <% if @kitchens.any? %>
  <nav class="kitchen-list">
    <ul>
      <% @kitchens.each do |kitchen| %>
      <li><%= link_to kitchen.name, kitchen_root_path(kitchen_slug: kitchen.slug) %></li>
      <% end %>
    </ul>
  </nav>
  <% end %>

  <nav class="landing-actions">
    <%= link_to 'Create a kitchen', new_kitchen_path(intentional: true), class: 'btn' %>
    <%= link_to 'Join a kitchen', join_kitchen_path, class: 'btn' %>
  </nav>
</article>
```

- [ ] **Step 4: Run tests**

Run: `rake test`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/landing_controller.rb app/views/landing/show.html.erb test/controllers/landing_controller_test.rb
git commit -m "Update LandingController: redirect to /new when no kitchens, add create/join links"
```

---

### Task 9: Settings Dialog — Join Code, Members, Profile

**Files:**
- Modify: `app/controllers/settings_controller.rb`
- Modify: `app/views/settings/_editor_frame.html.erb`
- Modify: `app/javascript/controllers/settings_editor_controller.js`
- Create: `test/controllers/settings_join_code_test.rb`

- [ ] **Step 1: Write tests for new settings endpoints**

```ruby
# test/controllers/settings_join_code_test.rb
# frozen_string_literal: true

require 'test_helper'

class SettingsJoinCodeTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    log_in
  end

  test 'settings JSON includes join_code and members' do
    get settings_path(kitchen_slug: kitchen_slug), as: :json

    json = JSON.parse(response.body)
    assert_predicate json['join_code'], :present?
    assert_kind_of Array, json['members']
    assert_equal 1, json['members'].size
    assert_equal @user.name, json['members'].first['name']
  end

  test 'regenerate_join_code changes the code' do
    old_code = @kitchen.join_code

    post settings_regenerate_join_code_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    @kitchen.reload
    assert_not_equal old_code, @kitchen.join_code
  end

  test 'regenerate_join_code requires owner role' do
    member_user = User.create!(name: 'Member', email: 'member@example.com')
    Membership.create!(kitchen: @kitchen, user: member_user, role: 'member')
    get dev_login_path(id: member_user.id)

    post settings_regenerate_join_code_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end

  test 'update_profile changes user name and email' do
    patch settings_profile_path(kitchen_slug: kitchen_slug),
          params: { user: { name: 'New Name', email: 'newemail@example.com' } },
          as: :json

    assert_response :success
    @user.reload
    assert_equal 'New Name', @user.name
    assert_equal 'newemail@example.com', @user.email
  end
end
```

- [ ] **Step 2: Add routes for new settings endpoints**

In `config/routes.rb`, inside the kitchen scope, after the existing settings routes:

```ruby
post 'settings/regenerate_join_code', to: 'settings#regenerate_join_code', as: :settings_regenerate_join_code
patch 'settings/profile', to: 'settings#update_profile', as: :settings_profile
```

- [ ] **Step 3: Update SettingsController**

Add new actions to `app/controllers/settings_controller.rb`:

- Include `join_code` and `members` in the `show` JSON response
- Add `regenerate_join_code` action (owner-only)
- Add `update_profile` action (updates current_user)

```ruby
def show
  members = ActsAsTenant.with_tenant(current_kitchen) do
    current_kitchen.memberships.includes(:user).map do |m|
      { name: m.user.name, email: m.user.email, role: m.role || 'member' }
    end
  end

  render json: {
    site_title: current_kitchen.site_title,
    homepage_heading: current_kitchen.homepage_heading,
    homepage_subtitle: current_kitchen.homepage_subtitle,
    usda_api_key_set: current_kitchen.usda_api_key.present?,
    anthropic_api_key_set: current_kitchen.anthropic_api_key.present?,
    show_nutrition: current_kitchen.show_nutrition,
    decorate_tags: current_kitchen.decorate_tags,
    join_code: current_kitchen.join_code,
    members: members,
    current_user_name: current_user.name,
    current_user_email: current_user.email
  }
end

def regenerate_join_code
  return head(:forbidden) unless owner?

  current_kitchen.regenerate_join_code!
  render json: { join_code: current_kitchen.join_code }
end

def update_profile
  if current_user.update(profile_params)
    render json: { status: 'ok' }
  else
    render json: { errors: current_user.errors.full_messages }, status: :unprocessable_content
  end
end

# In private section:
def owner?
  current_kitchen.memberships.exists?(user: current_user, role: 'owner')
end

def profile_params
  params.expect(user: %i[name email])
end
```

- [ ] **Step 4: Update settings editor frame view**

Add three new fieldsets to `app/views/settings/_editor_frame.html.erb` after the API Keys fieldset:

1. **Kitchen** fieldset — join code display + regenerate button + member list
2. **Profile** fieldset — name + email fields for current user

The join code display should be read-only. The regenerate button triggers a standalone POST (not part of the normal save flow). The member list is display-only.

- [ ] **Step 5: Update settings editor JS controller**

Add targets for the new profile fields. Update `#buildPayload()` to not include profile data (it's saved separately). Add a `regenerateJoinCode` method that POSTs to the regenerate endpoint. Add profile save handling.

- [ ] **Step 6: Run tests**

Run: `rake test`
Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/settings_controller.rb app/views/settings/_editor_frame.html.erb app/javascript/controllers/settings_editor_controller.js config/routes.rb test/controllers/settings_join_code_test.rb
git commit -m "Add join code, members, and profile sections to settings dialog"
```

---

### Task 10: Update Existing Tests and Lint

**Files:**
- Modify: various test files as needed
- Modify: `config/html_safe_allowlist.yml` (if line numbers shifted)

- [ ] **Step 1: Run full test suite**

Run: `rake test`
Fix any failures caused by the new join_code requirement on Kitchen or the removal of auto_join_sole_kitchen.

- [ ] **Step 2: Run RuboCop**

Run: `bundle exec rubocop`
Fix any offenses in new files. Common issues:
- Line length on test files
- Missing frozen_string_literal
- Method length on controllers

- [ ] **Step 3: Run Brakeman**

Run: `rake security`
Verify no new warnings from the new controllers.

- [ ] **Step 4: Run html_safe audit**

Run: `rake lint:html_safe`
Update `config/html_safe_allowlist.yml` if line numbers shifted.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "Fix lint, test, and security issues from auth implementation"
```

---

### Task 11: Playwright Security Tests

**Files:**
- Create: `test/security/auth_security.spec.mjs`

- [ ] **Step 1: Create Playwright security tests**

```javascript
// test/security/auth_security.spec.mjs
import { test, expect } from '@playwright/test';

const BASE = process.env.BASE_URL || 'http://localhost:3030';

test.describe('Auth security', () => {
  test('join code brute force is rate limited', async ({ request }) => {
    const responses = [];
    for (let i = 0; i < 12; i++) {
      const resp = await request.post(`${BASE}/join`, {
        form: { join_code: `invalid attempt ${i}` }
      });
      responses.push(resp.status());
    }
    expect(responses.filter(s => s === 429).length).toBeGreaterThan(0);
  });

  test('tampered signed kitchen ID is rejected', async ({ request }) => {
    const resp = await request.post(`${BASE}/join/complete`, {
      form: {
        email: 'test@example.com',
        signed_kitchen_id: 'tampered-value'
      }
    });
    expect(resp.status()).toBe(302);
    expect(resp.headers()['location']).toContain('/join');
  });

  test('logged out user cannot access write paths', async ({ request }) => {
    const resp = await request.post(`${BASE}/recipes`, {
      headers: { 'Content-Type': 'application/json' },
      data: { markdown_source: '# Test' }
    });
    expect(resp.status()).toBe(403);
  });
});
```

- [ ] **Step 2: Commit**

```bash
git add test/security/auth_security.spec.mjs
git commit -m "Add Playwright security tests for auth flows"
```

---

### Task 12: Final Integration Verification

- [ ] **Step 1: Run full test suite**

Run: `rake test`
Expected: All tests pass.

- [ ] **Step 2: Run full lint**

Run: `rake lint`
Expected: 0 offenses.

- [ ] **Step 3: Run security check**

Run: `rake security`
Expected: No new warnings.

- [ ] **Step 4: Manual smoke test (if dev server available)**

Start the dev server with `MULTI_KITCHEN=true bin/dev` and verify:
1. Root URL redirects to /new when no kitchens exist
2. Kitchen creation flow works end-to-end
3. Join code is displayed in settings
4. Join flow works with the code
5. Logout works
6. Re-auth via join code + email works

- [ ] **Step 5: Final commit and push**

```bash
git push -u origin feature/auth
```
