# Trusted-Header Auth Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace OAuth with trusted-header authentication, fix orphan user onboarding (#93), and secure ActionCable (#94).

**Architecture:** Authelia sets `Remote-User`/`Remote-Email` headers on proxied requests. A before_action reads these headers to find-or-create users and auto-join the sole kitchen. OmniAuth is removed entirely. The session cookie layer is unchanged — headers only matter when establishing a new session.

**Tech Stack:** Rails 8, ActionCable, Solid Cable, SQLite, Minitest

---

### Task 0: Remove OmniAuth and ConnectedService

**Files:**
- Remove: `app/controllers/omniauth_callbacks_controller.rb`
- Remove: `app/controllers/sessions_controller.rb`
- Remove: `app/views/sessions/new.html.erb`
- Remove: `app/models/connected_service.rb`
- Remove: `config/initializers/omniauth.rb`
- Remove: `test/controllers/omniauth_callbacks_controller_test.rb`
- Remove: `test/controllers/sessions_controller_test.rb`
- Remove: `test/models/connected_service_test.rb`
- Modify: `Gemfile` — remove `omniauth` and `omniauth-rails_csrf_protection`
- Modify: `config/routes.rb:25-28` — remove OmniAuth and login routes
- Modify: `app/models/user.rb:7` — remove `has_many :connected_services`
- Modify: `test/test_helper.rb:13` — remove `OmniAuth.config.test_mode = true`
- Modify: `app/controllers/concerns/authentication.rb:33-36` — remove `request_authentication` redirect to `/login` and `after_authentication_url`
- Create new migration: `db/migrate/003_drop_connected_services.rb`

**Step 1: Remove gems**

Edit `Gemfile`, remove these two lines:
```ruby
gem 'omniauth'
gem 'omniauth-rails_csrf_protection'
```

Run:
```bash
bundle install
```

**Step 2: Create migration to drop connected_services**

Create `db/migrate/003_drop_connected_services.rb`:
```ruby
# frozen_string_literal: true

class DropConnectedServices < ActiveRecord::Migration[8.1]
  def change
    drop_table :connected_services do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.timestamps
      t.index %i[provider uid], unique: true
    end
  end
end
```

Run:
```bash
rails db:migrate
```

**Step 3: Delete OmniAuth files**

Delete these files:
- `app/controllers/omniauth_callbacks_controller.rb`
- `app/controllers/sessions_controller.rb`
- `app/views/sessions/new.html.erb`
- `app/models/connected_service.rb`
- `config/initializers/omniauth.rb`
- `test/controllers/omniauth_callbacks_controller_test.rb`
- `test/controllers/sessions_controller_test.rb`
- `test/models/connected_service_test.rb`

**Step 4: Clean up references**

Edit `app/models/user.rb` — remove the `has_many :connected_services, dependent: :destroy` line.

Edit `config/routes.rb` — remove these lines:
```ruby
match 'auth/:provider/callback', to: 'omniauth_callbacks#create', as: :omniauth_callback, via: %i[get post]
get 'auth/failure', to: 'omniauth_callbacks#failure'
delete 'logout', to: 'omniauth_callbacks#destroy', as: :logout
get 'login', to: 'sessions#new', as: :login
```

Edit `test/test_helper.rb` — remove the `OmniAuth.config.test_mode = true` line.

Edit `app/controllers/concerns/authentication.rb`:
- Remove the `request_authentication` method (redirected to `/login` which no longer exists).
- Remove the `after_authentication_url` method (only used by OmniAuth callback).
- The `require_authentication` method still calls `request_authentication` — replace its fallback behavior. Since there's no login page, unauthenticated requests to protected resources should return 403 (same pattern as the JSON branch in `require_membership`). Update `require_authentication` to:
```ruby
def require_authentication
  resume_session || head(:forbidden)
end
```

**Step 5: Run tests, expect failures**

Run:
```bash
rake test 2>&1 | grep -E 'failures|errors|NameError|NoMethod'
```

Expected: Several test failures from tests that reference `login_path`, `logout_path`, `omniauth_callback_path`, etc. These will be fixed in subsequent tasks. The removed test files should eliminate most failures. Remaining failures will be in `test/controllers/auth_test.rb`, `test/integration/nav_login_test.rb`, and `test/integration/end_to_end_test.rb`.

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor: remove OmniAuth and ConnectedService

Strip OAuth infrastructure: gems, controller, model, initializer,
routes, login page. The session cookie layer remains unchanged.
Trusted-header auth will replace this in the next commit.

Closes #93 (partial)"
```

---

### Task 1: Add trusted-header authentication

**Files:**
- Modify: `app/controllers/application_controller.rb` — add `authenticate_from_headers` before_action
- Test: `test/controllers/header_auth_test.rb` (new)

**Step 1: Write the failing tests**

Create `test/controllers/header_auth_test.rb`:
```ruby
# frozen_string_literal: true

require 'test_helper'

class HeaderAuthTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
  end

  test 'creates user and session from trusted headers' do
    assert_difference 'User.count', 1 do
      assert_difference 'Session.count', 1 do
        get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
          'Remote-User' => 'alice',
          'Remote-Name' => 'Alice Smith',
          'Remote-Email' => 'alice@example.com'
        }
      end
    end

    assert_response :success
    user = User.find_by(email: 'alice@example.com')

    assert_equal 'Alice Smith', user.name
    assert_predicate cookies[:session_id], :present?
  end

  test 'reuses existing user matched by email' do
    User.create!(name: 'Alice', email: 'alice@example.com')

    assert_no_difference 'User.count' do
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
        'Remote-User' => 'alice',
        'Remote-Name' => 'Alice Updated',
        'Remote-Email' => 'alice@example.com'
      }
    end

    assert_response :success
  end

  test 'does nothing without Remote-User header' do
    assert_no_difference 'User.count' do
      assert_no_difference 'Session.count' do
        get kitchen_root_path(kitchen_slug: @kitchen.slug)
      end
    end

    assert_response :success
  end

  test 'does not create duplicate session when cookie already valid' do
    get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
      'Remote-User' => 'alice',
      'Remote-Name' => 'Alice',
      'Remote-Email' => 'alice@example.com'
    }

    assert_difference 'Session.count', 0 do
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
        'Remote-User' => 'alice',
        'Remote-Name' => 'Alice',
        'Remote-Email' => 'alice@example.com'
      }
    end
  end

  test 'uses Remote-User as name fallback when Remote-Name is absent' do
    get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
      'Remote-User' => 'bob',
      'Remote-Email' => 'bob@example.com'
    }

    assert_equal 'bob', User.find_by(email: 'bob@example.com').name
  end
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
ruby -Itest test/controllers/header_auth_test.rb -v 2>&1
```

Expected: All 5 tests fail (no `authenticate_from_headers` method yet).

**Step 3: Implement trusted-header auth**

Edit `app/controllers/application_controller.rb`. Add a new before_action after `resume_session`:

```ruby
before_action :authenticate_from_headers
```

Add the private method:

```ruby
def authenticate_from_headers
  return if authenticated?

  remote_user = request.headers['Remote-User']
  return unless remote_user

  email = request.headers['Remote-Email'] || "#{remote_user}@header.local"
  name = request.headers['Remote-Name'] || remote_user

  user = User.find_or_create_by!(email: email) do |u|
    u.name = name
  end

  start_new_session_for(user)
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
ruby -Itest test/controllers/header_auth_test.rb -v 2>&1
```

Expected: All 5 pass.

**Step 5: Commit**

```bash
git add app/controllers/application_controller.rb test/controllers/header_auth_test.rb
git commit -m "feat: add trusted-header authentication

Read Remote-User/Remote-Name/Remote-Email headers from the reverse
proxy (Authelia). Find-or-create user and establish a session cookie.
No-op when headers are absent (dev/test use DevSessionsController)."
```

---

### Task 2: Auto-join sole kitchen

**Files:**
- Modify: `app/controllers/application_controller.rb` — add auto-join logic after header auth
- Modify: `test/controllers/header_auth_test.rb` — add auto-join tests

**Step 1: Write the failing tests**

Add to `test/controllers/header_auth_test.rb`:

```ruby
test 'auto-joins sole kitchen for new user' do
  get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
    'Remote-User' => 'alice',
    'Remote-Name' => 'Alice',
    'Remote-Email' => 'alice@example.com'
  }

  user = User.find_by(email: 'alice@example.com')

  assert_predicate user.memberships, :any?
  assert @kitchen.member?(user)
end

test 'does not auto-join when multiple kitchens exist' do
  Kitchen.create!(name: 'Second Kitchen', slug: 'second')

  get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
    'Remote-User' => 'alice',
    'Remote-Name' => 'Alice',
    'Remote-Email' => 'alice@example.com'
  }

  user = User.find_by(email: 'alice@example.com')

  assert_predicate user.memberships, :empty?
end

test 'does not auto-join when user already has membership' do
  user = User.create!(name: 'Alice', email: 'alice@example.com')
  ActsAsTenant.with_tenant(@kitchen) { Membership.create!(kitchen: @kitchen, user: user) }

  assert_no_difference 'Membership.count' do
    get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
      'Remote-User' => 'alice',
      'Remote-Name' => 'Alice',
      'Remote-Email' => 'alice@example.com'
    }
  end
end
```

**Step 2: Run tests to verify new tests fail**

Run:
```bash
ruby -Itest test/controllers/header_auth_test.rb -v 2>&1
```

Expected: The 3 new auto-join tests fail; the original 5 still pass.

**Step 3: Add auto-join logic**

Edit `app/controllers/application_controller.rb`. Add a new before_action after `authenticate_from_headers`:

```ruby
before_action :auto_join_sole_kitchen
```

Add the private method:

```ruby
def auto_join_sole_kitchen
  return unless authenticated?

  user = current_user
  return if user.memberships.exists?

  kitchens = ActsAsTenant.without_tenant { Kitchen.all }
  return unless kitchens.size == 1

  ActsAsTenant.with_tenant(kitchens.first) do
    Membership.create!(kitchen: kitchens.first, user: user)
  end
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
ruby -Itest test/controllers/header_auth_test.rb -v 2>&1
```

Expected: All 8 tests pass.

**Step 5: Commit**

```bash
git add app/controllers/application_controller.rb test/controllers/header_auth_test.rb
git commit -m "feat: auto-join sole kitchen for new users

When a user is authenticated and has no memberships, and exactly one
kitchen exists, auto-create the membership. This eliminates the
dead-end landing page for homelab deployments.

Closes #93"
```

---

### Task 3: Landing page redirect for sole kitchen

**Files:**
- Modify: `app/controllers/landing_controller.rb:6-8`
- Modify: `test/controllers/landing_controller_test.rb`

**Step 1: Write the failing tests**

Replace the contents of `test/controllers/landing_controller_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class LandingControllerTest < ActionDispatch::IntegrationTest
  test 'redirects to sole kitchen when exactly one exists' do
    kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')

    get root_path

    assert_redirected_to kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  test 'renders landing page when no kitchens exist' do
    get root_path

    assert_response :success
    assert_select 'h1', 'Family Recipes'
  end

  test 'renders landing page with kitchen list when multiple exist' do
    Kitchen.create!(name: 'Kitchen A', slug: 'kitchen-a')
    Kitchen.create!(name: 'Kitchen B', slug: 'kitchen-b')

    get root_path

    assert_response :success
    assert_select 'a', 'Kitchen A'
    assert_select 'a', 'Kitchen B'
  end
end
```

**Step 2: Run tests to verify the redirect test fails**

Run:
```bash
ruby -Itest test/controllers/landing_controller_test.rb -v 2>&1
```

Expected: "redirects to sole kitchen" fails (currently renders 200). The other two should pass.

**Step 3: Implement the redirect**

Edit `app/controllers/landing_controller.rb`:

```ruby
# frozen_string_literal: true

class LandingController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def show
    @kitchens = ActsAsTenant.without_tenant { Kitchen.all.to_a }
    return redirect_to kitchen_root_path(kitchen_slug: @kitchens.first.slug) if @kitchens.size == 1
  end
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
ruby -Itest test/controllers/landing_controller_test.rb -v 2>&1
```

Expected: All 3 pass.

**Step 5: Commit**

```bash
git add app/controllers/landing_controller.rb test/controllers/landing_controller_test.rb
git commit -m "feat: auto-redirect to sole kitchen from landing page

When exactly one kitchen exists, skip the landing page and redirect
directly to the kitchen homepage. Multi-kitchen deploys still see
the kitchen picker."
```

---

### Task 4: Fix groceries auth gates (read paths public)

**Files:**
- Modify: `app/controllers/groceries_controller.rb:4` — split `require_membership`
- Modify: `app/views/shared/_nav.html.erb:6-8` — show groceries link for all users
- Modify: `test/controllers/groceries_controller_test.rb:12-15` — update access tests
- Modify: `test/controllers/auth_test.rb:98-101` — update grocery access test
- Modify: `test/integration/end_to_end_test.rb:86-92` — groceries link visibility

**Step 1: Write failing tests for public grocery reads**

Edit `test/controllers/groceries_controller_test.rb`. Replace the first two access control tests:

```ruby
# --- Access control ---

test 'show is publicly accessible without login' do
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_response :success
end

test 'state is publicly accessible without login' do
  get groceries_state_path(kitchen_slug: kitchen_slug), as: :json

  assert_response :success
end

test 'aisle_order_content is publicly accessible without login' do
  get groceries_aisle_order_content_path(kitchen_slug: kitchen_slug), as: :json

  assert_response :success
end
```

Keep the existing tests that assert `select`, `check`, `custom_items`, `clear`, `update_quick_bites`, and `update_aisle_order` require membership (lines 24-60) — those should still pass.

**Step 2: Run tests to verify the new public-access tests fail**

Run:
```bash
ruby -Itest test/controllers/groceries_controller_test.rb -v 2>&1
```

Expected: The 3 new public-access tests fail (currently returns redirect/403).

**Step 3: Split the auth gate**

Edit `app/controllers/groceries_controller.rb`. Replace:
```ruby
before_action :require_membership
```

With:
```ruby
before_action :require_membership, only: %i[select check update_custom_items clear
                                            update_quick_bites update_aisle_order]
```

**Step 4: Update nav to show groceries link for everyone**

Edit `app/views/shared/_nav.html.erb`. Replace lines 6-8:
```erb
        <% if logged_in? %>
          <%= link_to 'Groceries', groceries_path, class: 'groceries', title: 'Printable grocery list' %>
        <% end %>
```

With:
```erb
        <%= link_to 'Groceries', groceries_path, class: 'groceries', title: 'Printable grocery list' %>
```

**Step 5: Update affected tests**

Edit `test/controllers/auth_test.rb`. Replace the "groceries page redirects non-members to login" test (lines 98-101):
```ruby
test 'groceries page is publicly accessible' do
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_response :success
end
```

Edit `test/integration/end_to_end_test.rb`. Replace the "layout hides groceries link when not logged in" test (lines 86-92):
```ruby
test 'layout shows groceries link when not logged in' do
  get kitchen_root_path(kitchen_slug: kitchen_slug)

  assert_select 'nav a.home', 'Home'
  assert_select 'nav a.ingredients', 'Ingredients'
  assert_select 'nav a.groceries', 'Groceries'
end
```

**Step 6: Run tests to verify they pass**

Run:
```bash
ruby -Itest test/controllers/groceries_controller_test.rb test/controllers/auth_test.rb test/integration/end_to_end_test.rb -v 2>&1
```

Expected: All pass.

**Step 7: Commit**

```bash
git add app/controllers/groceries_controller.rb app/views/shared/_nav.html.erb test/controllers/groceries_controller_test.rb test/controllers/auth_test.rb test/integration/end_to_end_test.rb
git commit -m "fix: make grocery read paths publicly accessible

Split require_membership on GroceriesController: show, state, and
aisle_order_content are now public reads. Write actions still require
membership. Groceries nav link visible to all users."
```

---

### Task 5: Secure ActionCable (#94)

**Files:**
- Modify: `app/channels/application_cable/connection.rb`
- Modify: `app/channels/grocery_list_channel.rb:4-8`
- Modify: `test/channels/grocery_list_channel_test.rb`

**Step 1: Write the failing tests**

Replace `test/channels/grocery_list_channel_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class GroceryListChannelTest < ActionCable::Channel::TestCase
  setup do
    @kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    @user = User.create!(name: 'Member', email: 'member@example.com')
    ActsAsTenant.with_tenant(@kitchen) do
      Membership.create!(kitchen: @kitchen, user: @user)
    end
  end

  test 'subscribes when user is kitchen member' do
    stub_connection current_user: @user
    subscribe kitchen_slug: @kitchen.slug

    assert_predicate subscription, :confirmed?
  end

  test 'rejects subscription for unknown kitchen' do
    stub_connection current_user: @user
    subscribe kitchen_slug: 'nonexistent'

    assert_predicate subscription, :rejected?
  end

  test 'rejects subscription when user is not a member' do
    outsider = User.create!(name: 'Outsider', email: 'outsider@example.com')

    stub_connection current_user: outsider
    subscribe kitchen_slug: @kitchen.slug

    assert_predicate subscription, :rejected?
  end

  test 'rejects subscription when no user' do
    stub_connection current_user: nil
    subscribe kitchen_slug: @kitchen.slug

    assert_predicate subscription, :rejected?
  end

  test 'broadcasts version to kitchen' do
    assert_broadcast_on(
      GroceryListChannel.broadcasting_for(@kitchen),
      version: 42
    ) do
      GroceryListChannel.broadcast_version(@kitchen, 42)
    end
  end
end
```

**Step 2: Run tests to verify new tests fail**

Run:
```bash
ruby -Itest test/channels/grocery_list_channel_test.rb -v 2>&1
```

Expected: Tests expecting `current_user` to be available fail.

**Step 3: Implement Connection authentication**

Edit `app/channels/application_cable/connection.rb`:

```ruby
# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      session = Session.find_by(id: cookies.signed[:session_id])
      session&.user || reject_unauthorized_connection
    end
  end
end
```

**Step 4: Add membership check to channel**

Edit `app/channels/grocery_list_channel.rb`:

```ruby
# frozen_string_literal: true

class GroceryListChannel < ApplicationCable::Channel
  def subscribed
    kitchen = Kitchen.find_by(slug: params[:kitchen_slug])
    reject unless kitchen&.member?(current_user)

    stream_for kitchen
  end

  def self.broadcast_version(kitchen, version)
    broadcast_to(kitchen, version: version)
  end

  def self.broadcast_content_changed(kitchen)
    broadcast_to(kitchen, type: 'content_changed')
  end
end
```

**Step 5: Run tests to verify they pass**

Run:
```bash
ruby -Itest test/channels/grocery_list_channel_test.rb -v 2>&1
```

Expected: All 5 pass.

**Step 6: Commit**

```bash
git add app/channels/application_cable/connection.rb app/channels/grocery_list_channel.rb test/channels/grocery_list_channel_test.rb
git commit -m "fix: authenticate ActionCable connections and check membership

Connection identifies users from the session cookie. Channel rejects
subscriptions from non-members. Unauthenticated WebSocket connections
are rejected.

Closes #94"
```

---

### Task 6: Update nav login/logout UI and routes

**Files:**
- Modify: `app/views/shared/_nav.html.erb:13-18` — update logout route
- Modify: `config/routes.rb` — add standalone logout route to `dev_sessions#destroy`
- Modify: `test/integration/nav_login_test.rb` — update expectations
- Modify: `app/controllers/concerns/authentication.rb` — clean up unused methods

With OmniAuth removed, there's no `/login` page or `/logout` route. In dev/test, `DevSessionsController` handles sessions. In production behind Authelia, there's no login page (headers handle it). The nav needs to:
- Show "Log out" pointing to `dev_logout_path` in dev/test.
- In production, logout doesn't make much sense (Authelia controls the session), but we still need to clear the Rails session cookie. Add a lightweight logout route.

**Step 1: Update routes**

Edit `config/routes.rb`. The dev login/logout routes already exist but are gated to dev/test. Add a production-safe logout route. The final routes should look like:

```ruby
# frozen_string_literal: true

Rails.application.routes.draw do
  get 'up', to: 'rails/health#show', as: :rails_health_check

  root 'landing#show'

  scope 'kitchens/:kitchen_slug' do
    get '/', to: 'homepage#show', as: :kitchen_root
    resources :recipes, only: %i[show create update destroy], param: :slug
    get 'ingredients', to: 'ingredients#index', as: :ingredients
    get 'groceries', to: 'groceries#show', as: :groceries
    get 'groceries/state', to: 'groceries#state', as: :groceries_state
    patch 'groceries/select', to: 'groceries#select', as: :groceries_select
    patch 'groceries/check', to: 'groceries#check', as: :groceries_check
    patch 'groceries/custom_items', to: 'groceries#update_custom_items', as: :groceries_custom_items
    delete 'groceries/clear', to: 'groceries#clear', as: :groceries_clear
    patch 'groceries/quick_bites', to: 'groceries#update_quick_bites', as: :groceries_quick_bites
    patch 'groceries/aisle_order', to: 'groceries#update_aisle_order', as: :groceries_aisle_order
    get 'groceries/aisle_order_content', to: 'groceries#aisle_order_content', as: :groceries_aisle_order_content
    post 'nutrition/:ingredient_name', to: 'nutrition_entries#upsert', as: :nutrition_entry_upsert
    delete 'nutrition/:ingredient_name', to: 'nutrition_entries#destroy', as: :nutrition_entry_destroy
  end

  delete 'logout', to: 'dev_sessions#destroy', as: :logout

  if Rails.env.development? || Rails.env.test?
    get 'dev/login/:id', to: 'dev_sessions#create', as: :dev_login
  end
end
```

Note: `logout` route now points to `dev_sessions#destroy` for all environments. Remove the environment gate on `DevSessionsController#destroy` so it works in production too (it just calls `terminate_session` + redirect — safe for any environment). Keep the `require_non_production_environment` gate only on `#create` (the login action).

**Step 2: Update DevSessionsController**

Edit `app/controllers/dev_sessions_controller.rb` — move the environment gate to only apply to `create`:

```ruby
# frozen_string_literal: true

class DevSessionsController < ApplicationController
  skip_before_action :set_kitchen_from_path
  before_action :require_non_production_environment, only: :create

  def create
    user = User.find(params[:id])
    start_new_session_for(user)
    kitchen = ActsAsTenant.without_tenant { user.kitchens.first }
    return redirect_to root_path unless kitchen

    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  def destroy
    terminate_session
    redirect_to root_path
  end

  private

  def require_non_production_environment
    head :not_found unless Rails.env.development? || Rails.env.test?
  end
end
```

**Step 3: Update nav partial**

Edit `app/views/shared/_nav.html.erb`. The login/logout section becomes:

```erb
    <div>
      <% if logged_in? %>
        <%= button_to 'Log out', logout_path, method: :delete, class: 'nav-auth-btn' %>
      <% end %>
    </div>
```

Remove the "Log in" link entirely — there's no login page. In production, Authelia handles login. In dev, use `/dev/login/:id` directly.

**Step 4: Update nav tests**

Replace `test/integration/nav_login_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class NavLoginTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'anonymous user does not see log in or log out' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav form[action*="logout"]', count: 0
  end

  test 'logged-in user sees log out button' do
    log_in

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav form[action*="logout"] button', text: 'Log out'
  end
end
```

**Step 5: Clean up Authentication concern**

Edit `app/controllers/concerns/authentication.rb`. Remove the methods that reference the now-gone login page:

```ruby
# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def authenticated? = Current.session.present?

  def require_authentication
    resume_session || head(:forbidden)
  end

  def resume_session
    Current.session ||= find_session_by_cookie
  end

  def find_session_by_cookie
    Session.find_by(id: cookies.signed[:session_id])
  end

  def start_new_session_for(user)
    user.sessions.create!(
      user_agent: request.user_agent,
      ip_address: request.remote_ip
    ).tap do |new_session|
      Current.session = new_session
      cookies.signed.permanent[:session_id] = {
        value: new_session.id, httponly: true, same_site: :lax, secure: Rails.env.production?
      }
    end
  end

  def terminate_session
    Current.session&.destroy
    cookies.delete(:session_id)
    Current.reset
  end

  def current_user = Current.user
end
```

**Step 6: Update auth_test.rb for missing login redirect**

Edit `test/controllers/auth_test.rb`. The test "unauthenticated PATCH to quick_bites returns 403" is still valid. But the `require_membership` method in `ApplicationController` still calls `request_authentication` for non-JSON requests, which now returns 403. Update the `require_membership` method in `ApplicationController` — HTML requests from unauthenticated users should also get 403 (there's no login page to redirect to):

Edit `app/controllers/application_controller.rb`, update `require_membership`:

```ruby
def require_membership
  return head(:forbidden) unless logged_in?

  head(:forbidden) unless current_kitchen&.member?(current_user)
end
```

Update `test/controllers/auth_test.rb`:
- The "unauthenticated POST to recipes returns 403" test already expects 403 with `as: :json` — it should still pass.
- Update any tests that expected redirect to `/login` to expect 403 instead.

**Step 7: Run the full test suite**

Run:
```bash
rake test 2>&1 | tail -20
```

Expected: All tests pass (some tests were removed, some updated).

**Step 8: Commit**

```bash
git add -A
git commit -m "refactor: update nav, routes, and auth for header-only flow

Remove login link from nav (no login page exists). Logout route
available in all environments. Authentication concern returns 403
instead of redirecting to a login page. Dev login still works for
dev/test."
```

---

### Task 7: Full test suite green + update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` — update auth documentation, routes, affected files
- Run: `rake test` and `rake lint`

**Step 1: Run the full test suite**

Run:
```bash
rake test 2>&1
```

Fix any remaining failures. Common issues:
- Tests referencing `login_path` route helper — these routes no longer exist.
- Tests referencing `omniauth_callback_path` — these routes no longer exist.
- The `groceries_controller_test.rb` "show redirects to login" test — already fixed in Task 4.

**Step 2: Run lint**

Run:
```bash
rake lint 2>&1
```

Fix any RuboCop offenses in new/modified files.

**Step 3: Update CLAUDE.md**

Update the relevant sections:
- **Routes** section: Remove `/auth/:provider/callback`, `/auth/failure`, `/login`. Add note about `/logout` available in all environments. Note `/dev/login/:id` is dev/test only.
- **Architecture** section: Replace OmniAuth auth description with trusted-header auth description.
- **Test Command** section: Remove OmniAuth test mode reference if present.
- **Database Setup** section: Note that `ConnectedService` table no longer exists (migration 003 drops it).

**Step 4: Run full suite one more time**

Run:
```bash
rake 2>&1
```

Expected: Lint + all tests pass.

**Step 5: Commit**

```bash
git add -A
git commit -m "docs: update CLAUDE.md for trusted-header auth

Remove OmniAuth references, document header auth strategy,
update route listing, note ConnectedService removal."
```

---

### Task 8: Close GitHub issues

**Step 1: Verify both issues are addressed**

- Issue #93: Orphan users now get auto-joined to the sole kitchen via header auth.
- Issue #94: ActionCable Connection authenticates from session cookie, channel checks membership.

**Step 2: Close issues**

Run:
```bash
gh issue close 93 -c "Fixed: trusted-header auth + auto-join sole kitchen replaces OAuth. No more orphan users."
gh issue close 94 -c "Fixed: ActionCable Connection authenticates from session cookie, GroceryListChannel checks kitchen membership."
```
