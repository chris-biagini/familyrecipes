# Re-Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Separate invitation (magic phrase) from re-authentication by adding session transfer, login links, and polished join-code fallback UX.

**Architecture:** Three re-auth mechanisms layered on Rails' built-in `signed_id`. A new `TransfersController` handles token generation and consumption. QR codes via `rqrcode` gem. Sign-out interstitial and welcome screen surface the join code at key moments. One migration adds `email_verified_at` for future use.

**Tech Stack:** Rails 8, `signed_id`, `rqrcode` gem, Stimulus, Turbo Frames, Minitest

**Spec:** `docs/superpowers/specs/2026-04-09-auth-reauth-design.md`

**Branch:** `feature/auth` (existing long-lived branch)

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `db/migrate/003_add_email_verified_at_to_users.rb` | Add nullable `email_verified_at` column |
| Create | `app/controllers/transfers_controller.rb` | Token generation (self + member) and consumption |
| Create | `app/controllers/welcome_controller.rb` | Post-join welcome screen with join code |
| Create | `app/views/transfers/create.html.erb` | QR code + copyable link (Turbo Frame response) |
| Create | `app/views/transfers/create_for_member.html.erb` | Copyable login link (Turbo Frame response) |
| Create | `app/views/transfers/show_error.html.erb` | Invalid/expired token error page |
| Create | `app/views/sessions/destroy.html.erb` | Sign-out interstitial with join code(s) |
| Create | `app/views/welcome/show.html.erb` | Welcome screen with join code |
| Create | `test/controllers/transfers_controller_test.rb` | Transfer + login link tests |
| Create | `test/controllers/welcome_controller_test.rb` | Welcome screen tests |
| Create | `lib/tasks/kitchen.rake` | `kitchen:show_join_code` escape hatch |
| Modify | `Gemfile` | Add `rqrcode` gem |
| Modify | `config/routes.rb` | Add transfer, login link, and welcome routes |
| Modify | `app/controllers/sessions_controller.rb` | Sign-out interstitial (render instead of redirect) |
| Modify | `app/controllers/joins_controller.rb` | Redirect new members to welcome page |
| Modify | `app/controllers/settings_controller.rb` | Add `id` to member list data |
| Modify | `app/views/settings/_editor_frame.html.erb` | Add transfer button + login link buttons |
| Modify | `app/javascript/controllers/settings_editor_controller.js` | Copy-to-clipboard actions |
| Modify | `app/assets/stylesheets/auth.css` | Styles for new auth pages and settings transfer UI |
| Modify | `test/controllers/sessions_controller_test.rb` | Update sign-out test expectations |
| Modify | `test/controllers/joins_controller_test.rb` | Update new-member redirect test |

---

### Task 1: Migration — add email_verified_at to users

**Files:**
- Create: `db/migrate/003_add_email_verified_at_to_users.rb`

- [ ] **Step 1: Write the migration**

```ruby
# frozen_string_literal: true

class AddEmailVerifiedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_verified_at, :datetime
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: Migration runs successfully, no errors.

- [ ] **Step 3: Verify the column exists**

Run: `bin/rails runner "puts User.column_names.include?('email_verified_at')"`
Expected: `true`

- [ ] **Step 4: Commit**

```bash
git add db/migrate/003_add_email_verified_at_to_users.rb db/schema.rb
git commit -m "Add email_verified_at column to users for future verification"
```

---

### Task 2: Add rqrcode gem

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add the gem to the Gemfile**

Add `gem 'rqrcode'` to the top-level (non-grouped) gems, after the `solid_cable` line:

```ruby
gem 'rqrcode'
```

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: `rqrcode` and its dependency `chunky_png` are installed.

- [ ] **Step 3: Verify it works**

Run: `bin/rails runner "require 'rqrcode'; puts RQRCode::QRCode.new('test').as_svg(module_size: 4).size > 0"`
Expected: `true`

- [ ] **Step 4: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "Add rqrcode gem for QR code generation"
```

---

### Task 3: Routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add the new routes**

Add after the existing `delete 'logout'` line and before the `dev/login` line:

```ruby
  post 'transfer', to: 'transfers#create', as: :create_transfer
  get 'transfer/:token', to: 'transfers#show', as: :show_transfer
  post 'members/:id/login_link', to: 'transfers#create_for_member', as: :member_login_link
  get 'welcome', to: 'welcome#show', as: :welcome
```

- [ ] **Step 2: Verify routes**

Run: `bin/rails routes | grep -E 'transfer|login_link|welcome'`
Expected: Four routes listed matching the new paths.

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "Add routes for session transfer, login links, and welcome page"
```

---

### Task 4: TransfersController — token consumption (show action)

Build the consumption side first so we can write end-to-end tests for generation actions immediately.

**Files:**
- Create: `app/controllers/transfers_controller.rb`
- Create: `app/views/transfers/show_error.html.erb`
- Create: `test/controllers/transfers_controller_test.rb`

- [ ] **Step 1: Write the failing tests for show action**

```ruby
# frozen_string_literal: true

require 'test_helper'

class TransfersControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'show with valid transfer token creates session and redirects' do
    token = @user.signed_id(purpose: :transfer, expires_in: 5.minutes)

    get show_transfer_path(token:, k: kitchen_slug)

    assert_redirected_to kitchen_root_path(kitchen_slug: kitchen_slug)
    assert_predicate cookies[:session_id], :present?
  end

  test 'show with valid login token creates session and redirects' do
    token = @user.signed_id(purpose: :login, expires_in: 24.hours)

    get show_transfer_path(token:, k: kitchen_slug)

    assert_redirected_to kitchen_root_path(kitchen_slug: kitchen_slug)
    assert_predicate cookies[:session_id], :present?
  end

  test 'show with expired token renders error' do
    token = @user.signed_id(purpose: :transfer, expires_in: 0.seconds)
    travel 1.minute

    get show_transfer_path(token:, k: kitchen_slug)

    assert_response :unprocessable_content
    assert_select '.auth-error'
  end

  test 'show with tampered token renders error' do
    get show_transfer_path(token: 'tampered-garbage', k: kitchen_slug)

    assert_response :unprocessable_content
    assert_select '.auth-error'
  end

  test 'show with wrong kitchen slug renders error' do
    other_kitchen = nil
    with_multi_kitchen do
      other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    end
    token = @user.signed_id(purpose: :transfer, expires_in: 5.minutes)

    get show_transfer_path(token:, k: other_kitchen.slug)

    assert_response :unprocessable_content
    assert_select '.auth-error'
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/transfers_controller_test.rb`
Expected: All 5 tests FAIL (controller doesn't exist yet).

- [ ] **Step 3: Write the controller**

```ruby
# frozen_string_literal: true

# Generates and consumes signed, time-limited tokens for re-authentication.
# Two token types: :transfer (self, 5 min, QR code) and :login (member-to-member,
# 24 hours, copyable link). Both are consumed via the same show action using
# User#find_signed. Kitchen context is passed as a query param (?k=slug) and
# verified against the user's memberships before creating a session.
#
# - Authentication concern: start_new_session_for, require_authentication
# - User: signed_id / find_signed (Rails built-in)
# - Kitchen: membership verification
# - Settings dialog: triggers create/create_for_member via Turbo Frame forms
class TransfersController < ApplicationController
  skip_before_action :set_kitchen_from_path

  allow_unauthenticated_access only: :show

  layout 'auth', only: :show

  def show
    user = resolve_token
    kitchen = resolve_kitchen(user)

    unless user && kitchen
      @error = 'This link is invalid or has expired.'
      return render :show_error, status: :unprocessable_content
    end

    start_new_session_for(user)
    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  private

  def resolve_token
    User.find_signed(params[:token], purpose: :transfer) ||
      User.find_signed(params[:token], purpose: :login)
  end

  def resolve_kitchen(user)
    return nil unless user

    slug = params[:k]
    return nil unless slug

    kitchen = ActsAsTenant.without_tenant { Kitchen.find_by(slug:) }
    return nil unless kitchen

    member = ActsAsTenant.with_tenant(kitchen) { kitchen.member?(user) }
    member ? kitchen : nil
  end
end
```

- [ ] **Step 4: Write the error view**

```erb
<% content_for(:title) { 'Link Expired' } %>

<div class="auth-card">
  <h1>Can't sign in</h1>

  <div class="auth-error"><p><%= @error %></p></div>

  <p class="auth-subtitle">This login link may have expired or already been used. Ask a kitchen member to send you a new one, or sign in with your kitchen's join code.</p>

  <div class="auth-footer">
    <p><%= link_to 'Sign in with join code', join_kitchen_path %></p>
  </div>
</div>
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/transfers_controller_test.rb`
Expected: All 5 tests PASS.

- [ ] **Step 6: Run full test suite**

Run: `rake test`
Expected: All existing tests still pass.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/transfers_controller.rb app/views/transfers/show_error.html.erb test/controllers/transfers_controller_test.rb
git commit -m "Add TransfersController show action: consume signed transfer/login tokens"
```

---

### Task 5: TransfersController — self-transfer (create action)

**Files:**
- Modify: `app/controllers/transfers_controller.rb`
- Create: `app/views/transfers/create.html.erb`
- Modify: `test/controllers/transfers_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `transfers_controller_test.rb`:

```ruby
  test 'create requires authentication' do
    post create_transfer_path

    assert_response :forbidden
  end

  test 'create returns QR code and link' do
    log_in

    post create_transfer_path, params: { kitchen_slug: kitchen_slug }

    assert_response :success
    assert_select 'svg'
    assert_select 'input[readonly]'
  end

  test 'create token is consumable' do
    log_in

    post create_transfer_path, params: { kitchen_slug: kitchen_slug }

    # Extract the transfer URL from the readonly input's value attribute
    link_input = css_select('input[readonly]').first
    url = link_input['value']
    reset!

    get url

    assert_response :redirect
    assert_predicate cookies[:session_id], :present?
  end
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `ruby -Itest test/controllers/transfers_controller_test.rb`
Expected: 3 new tests FAIL (create action not defined), 5 existing tests PASS.

- [ ] **Step 3: Add the create action to the controller**

Add to `TransfersController`, after `show` and before `private`:

```ruby
  def create
    token = current_user.signed_id(purpose: :transfer, expires_in: 5.minutes)
    kitchen_slug = params[:kitchen_slug]
    @transfer_url = show_transfer_url(token:, k: kitchen_slug)
    @qr_svg = generate_qr_svg(@transfer_url)
    render layout: false
  end
```

Add `generate_qr_svg` to the private section:

```ruby
  def generate_qr_svg(url)
    RQRCode::QRCode.new(url).as_svg(
      shape_rendering: 'crispEdges',
      module_size: 4,
      standalone: true,
      use_path: true
    )
  end
```

- [ ] **Step 4: Write the create view**

This is rendered without layout inside a Turbo Frame in the settings dialog.

```erb
<turbo-frame id="transfer-frame">
  <div class="transfer-result">
    <div class="transfer-qr">
      <%= @qr_svg.html_safe %>
    </div>
    <div class="transfer-link-row">
      <input type="text" class="input-base" readonly value="<%= @transfer_url %>">
      <button type="button" class="btn"
              data-action="settings-editor#copyToClipboard"
              data-settings-editor-copy-text-param="<%= @transfer_url %>">Copy</button>
    </div>
    <p class="transfer-hint">Scan this QR code or copy the link. Expires in 5 minutes.</p>
  </div>
</turbo-frame>
```

**Note on `html_safe`:** The SVG is generated by `rqrcode` from a URL we constructed — no user content is interpolated into the SVG itself. The URL is passed as data to the QR encoder, which outputs geometric SVG paths. This is safe. Add this call to `config/html_safe_allowlist.yml` with the correct file and line number after the view is created.

- [ ] **Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/transfers_controller_test.rb`
Expected: All 8 tests PASS.

- [ ] **Step 6: Update html_safe allowlist**

Check the line number of the `.html_safe` call in `app/views/transfers/create.html.erb` and add it to `config/html_safe_allowlist.yml`. Run `rake lint:html_safe` to verify.

- [ ] **Step 7: Run lint**

Run: `bundle exec rubocop app/controllers/transfers_controller.rb`
Expected: No offenses.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/transfers_controller.rb app/views/transfers/create.html.erb test/controllers/transfers_controller_test.rb config/html_safe_allowlist.yml
git commit -m "Add session transfer: generate signed token with QR code"
```

---

### Task 6: TransfersController — login link for member (create_for_member action)

**Files:**
- Modify: `app/controllers/transfers_controller.rb`
- Create: `app/views/transfers/create_for_member.html.erb`
- Modify: `app/controllers/settings_controller.rb`
- Modify: `test/controllers/transfers_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `transfers_controller_test.rb`:

```ruby
  test 'create_for_member requires authentication' do
    post member_login_link_path(id: @user.id)

    assert_response :forbidden
  end

  test 'create_for_member returns copyable link' do
    log_in
    other_user = User.create!(name: 'Other', email: 'other@example.com')
    ActsAsTenant.with_tenant(@kitchen) { Membership.create!(kitchen: @kitchen, user: other_user) }

    post member_login_link_path(id: other_user.id), params: { kitchen_slug: kitchen_slug }

    assert_response :success
    assert_select 'input[readonly]'
  end

  test 'create_for_member rejects non-member target' do
    log_in
    outsider = User.create!(name: 'Outsider', email: 'outsider@example.com')

    post member_login_link_path(id: outsider.id), params: { kitchen_slug: kitchen_slug }

    assert_response :not_found
  end

  test 'create_for_member token logs in target user' do
    log_in
    other_user = User.create!(name: 'Other', email: 'other@example.com')
    ActsAsTenant.with_tenant(@kitchen) { Membership.create!(kitchen: @kitchen, user: other_user) }

    post member_login_link_path(id: other_user.id), params: { kitchen_slug: kitchen_slug }

    link_input = css_select('input[readonly]').first
    url = link_input['value']
    reset!

    get url

    assert_response :redirect
    follow_redirect!
    assert_equal other_user.id, Session.last.user_id
  end
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `ruby -Itest test/controllers/transfers_controller_test.rb`
Expected: 4 new tests FAIL, 8 existing tests PASS.

- [ ] **Step 3: Add the create_for_member action**

Add to `TransfersController`, after the `create` method:

```ruby
  def create_for_member
    kitchen = resolve_current_kitchen
    target = find_kitchen_member(kitchen)
    return head(:not_found) unless target

    token = target.signed_id(purpose: :login, expires_in: 24.hours)
    @login_link_url = show_transfer_url(token:, k: kitchen.slug)
    render layout: false
  end
```

Add to the private section:

```ruby
  def resolve_current_kitchen
    slug = params[:kitchen_slug]
    ActsAsTenant.without_tenant { Kitchen.find_by!(slug:) }
  end

  def find_kitchen_member(kitchen)
    ActsAsTenant.with_tenant(kitchen) do
      user = User.find_by(id: params[:id])
      return nil unless user && kitchen.member?(user)

      user
    end
  end
```

- [ ] **Step 4: Write the create_for_member view**

```erb
<turbo-frame id="login-link-frame-<%= params[:id] %>">
  <div class="login-link-result">
    <div class="transfer-link-row">
      <input type="text" class="input-base" readonly value="<%= @login_link_url %>">
      <button type="button" class="btn"
              data-action="settings-editor#copyToClipboard"
              data-settings-editor-copy-text-param="<%= @login_link_url %>">Copy</button>
    </div>
    <p class="transfer-hint">Share this link. Expires in 24 hours.</p>
  </div>
</turbo-frame>
```

- [ ] **Step 5: Update SettingsController member_list to include user IDs**

In `app/controllers/settings_controller.rb`, update the `member_list` method to include the user ID:

Change:
```ruby
        { name: m.user.name, email: m.user.email, role: m.role }
```
to:
```ruby
        { id: m.user_id, name: m.user.name, email: m.user.email, role: m.role }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/transfers_controller_test.rb`
Expected: All 12 tests PASS.

- [ ] **Step 7: Run lint**

Run: `bundle exec rubocop app/controllers/transfers_controller.rb app/controllers/settings_controller.rb`
Expected: No offenses.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/transfers_controller.rb app/views/transfers/create_for_member.html.erb app/controllers/settings_controller.rb test/controllers/transfers_controller_test.rb
git commit -m "Add login link generation for kitchen members"
```

---

### Task 7: Sign-out interstitial

**Files:**
- Modify: `app/controllers/sessions_controller.rb`
- Create: `app/views/sessions/destroy.html.erb`
- Modify: `test/controllers/sessions_controller_test.rb`

- [ ] **Step 1: Update the tests**

Replace the contents of `sessions_controller_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'logout renders interstitial with join code' do
    log_in

    delete logout_path

    assert_response :success
    assert_select 'h1', text: /signed out/i
    assert_match @kitchen.join_code, response.body
  end

  test 'logout clears session' do
    log_in

    assert_predicate cookies[:session_id], :present?

    delete logout_path

    assert_equal 0, @user.sessions.count
  end

  test 'logout when not logged in redirects to root' do
    delete logout_path

    assert_redirected_to root_path
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/sessions_controller_test.rb`
Expected: First two tests FAIL (controller still redirects), third PASS.

- [ ] **Step 3: Update the controller**

Replace `SessionsController`:

```ruby
# frozen_string_literal: true

# Production logout endpoint. Renders a sign-out interstitial showing the
# kitchen's join code(s) so the user can get back in. Loads kitchen data
# while still authenticated, then terminates the session before rendering.
#
# - Authentication concern: provides terminate_session, current_user
# - Kitchen: join_code for re-entry fallback
# - JoinsController: the "sign back in" link targets the join flow
class SessionsController < ApplicationController
  skip_before_action :set_kitchen_from_path

  layout 'auth'

  def destroy
    unless authenticated?
      cookies[:skip_dev_auto_login] = true if Rails.env.development?
      return redirect_to root_path
    end

    @kitchen_codes = current_user.kitchens.map { |k| { name: k.name, join_code: k.join_code } }
    terminate_session
    cookies[:skip_dev_auto_login] = true if Rails.env.development?
  end
end
```

- [ ] **Step 4: Write the sign-out view**

```erb
<% content_for(:title) { 'Signed Out' } %>

<div class="auth-card">
  <h1>You've been signed out</h1>

  <% @kitchen_codes.each do |kitchen| %>
    <div class="signout-kitchen">
      <p class="signout-kitchen-name"><%= kitchen[:name] %></p>
      <p class="auth-subtitle">Join code:</p>
      <p class="signout-join-code"><%= kitchen[:join_code] %></p>
    </div>
  <% end %>

  <p class="signout-hint">Save this — you'll need it to sign back in if you don't have another device handy.</p>

  <div class="auth-footer">
    <p><%= link_to 'Sign back in', join_kitchen_path %> · <%= link_to 'Go to homepage', root_path %></p>
  </div>
</div>
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/sessions_controller_test.rb`
Expected: All 3 tests PASS.

- [ ] **Step 6: Run full test suite**

Run: `rake test`
Expected: All tests pass. Check that no other tests depend on the old redirect behavior from `DELETE /logout`.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/sessions_controller.rb app/views/sessions/destroy.html.erb test/controllers/sessions_controller_test.rb
git commit -m "Sign-out interstitial: show join code(s) on logout"
```

---

### Task 8: Welcome screen after first join

**Files:**
- Create: `app/controllers/welcome_controller.rb`
- Create: `app/views/welcome/show.html.erb`
- Modify: `app/controllers/joins_controller.rb`
- Create: `test/controllers/welcome_controller_test.rb`
- Modify: `test/controllers/joins_controller_test.rb`

- [ ] **Step 1: Write the welcome controller tests**

```ruby
# frozen_string_literal: true

require 'test_helper'

class WelcomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'show with valid signed kitchen ID renders join code' do
    signed_id = sign_welcome_kitchen(@kitchen.id)

    get welcome_path(k: signed_id)

    assert_response :success
    assert_match @kitchen.join_code, response.body
    assert_select 'h1', text: /welcome/i
  end

  test 'show with invalid signed ID redirects to root' do
    get welcome_path(k: 'tampered-value')

    assert_redirected_to root_path
  end

  test 'show with expired signed ID redirects to root' do
    signed_id = sign_welcome_kitchen(@kitchen.id)
    travel 20.minutes

    get welcome_path(k: signed_id)

    assert_redirected_to root_path
  end

  private

  def sign_welcome_kitchen(id)
    Rails.application.message_verifier(:welcome).generate(id, purpose: :welcome, expires_in: 15.minutes)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/welcome_controller_test.rb`
Expected: All 3 tests FAIL (controller doesn't exist).

- [ ] **Step 3: Write the welcome controller**

```ruby
# frozen_string_literal: true

# One-time welcome screen shown after a new member joins a kitchen. Displays
# the kitchen name and join code with a prompt to save it. The kitchen ID is
# passed as a signed, time-limited parameter to prevent bookmarking as a
# way to peek at join codes.
#
# - JoinsController: redirects here after new member registration
# - Kitchen: join_code display
class WelcomeController < ApplicationController
  skip_before_action :set_kitchen_from_path

  allow_unauthenticated_access

  layout 'auth'

  def show
    kitchen = resolve_signed_kitchen
    return redirect_to root_path unless kitchen

    @kitchen_name = kitchen.name
    @join_code = kitchen.join_code
    @kitchen_slug = kitchen.slug
  end

  private

  def resolve_signed_kitchen
    kitchen_id = Rails.application.message_verifier(:welcome).verified(params[:k], purpose: :welcome)
    return nil unless kitchen_id

    ActsAsTenant.without_tenant { Kitchen.find_by(id: kitchen_id) }
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
```

- [ ] **Step 4: Write the welcome view**

```erb
<% content_for(:title) { "Welcome to #{@kitchen_name}" } %>

<div class="auth-card">
  <h1>Welcome to <%= @kitchen_name %>!</h1>

  <p class="auth-subtitle">Your kitchen's join code:</p>
  <p class="signout-join-code"><%= @join_code %></p>

  <p class="signout-hint">Screenshot this or write it down — it's how you get back in on a new device.</p>

  <div class="auth-footer">
    <p><%= link_to 'Got it, take me to the kitchen', kitchen_root_path(kitchen_slug: @kitchen_slug) %></p>
  </div>
</div>
```

- [ ] **Step 5: Run welcome tests to verify they pass**

Run: `ruby -Itest test/controllers/welcome_controller_test.rb`
Expected: All 3 tests PASS.

- [ ] **Step 6: Update JoinsController to redirect new members to welcome**

In `app/controllers/joins_controller.rb`, modify `register_new_member`. Change the redirect line from:

```ruby
    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
```

to:

```ruby
    signed_k = Rails.application.message_verifier(:welcome).generate(kitchen.id, purpose: :welcome, expires_in: 15.minutes)
    redirect_to welcome_path(k: signed_k)
```

- [ ] **Step 7: Update the joins controller test**

In `test/controllers/joins_controller_test.rb`, update the test `'complete with name creates user and membership'`. Change the redirect assertion from:

```ruby
    assert_redirected_to kitchen_root_path(kitchen_slug: @kitchen.slug)
```

to:

```ruby
    assert_response :redirect
    assert_match %r{/welcome\?k=}, response.location
```

- [ ] **Step 8: Run all affected tests**

Run: `ruby -Itest test/controllers/joins_controller_test.rb test/controllers/welcome_controller_test.rb`
Expected: All tests PASS.

- [ ] **Step 9: Commit**

```bash
git add app/controllers/welcome_controller.rb app/views/welcome/show.html.erb test/controllers/welcome_controller_test.rb app/controllers/joins_controller.rb test/controllers/joins_controller_test.rb
git commit -m "Add welcome screen after first join, showing join code to save"
```

---

### Task 9: Rake task escape hatch

**Files:**
- Create: `lib/tasks/kitchen.rake`

- [ ] **Step 1: Write the rake task**

```ruby
# frozen_string_literal: true

namespace :kitchen do
  desc 'Print the join code for a kitchen (KITCHEN=slug)'
  task show_join_code: :environment do
    slug = ENV.fetch('KITCHEN', nil)
    abort 'Usage: rake kitchen:show_join_code KITCHEN=slug-here' unless slug

    kitchen = ActsAsTenant.without_tenant { Kitchen.find_by(slug:) }
    abort "No kitchen found with slug '#{slug}'" unless kitchen

    puts "Kitchen: #{kitchen.name}"
    puts "Join code: #{kitchen.join_code}"
  end
end
```

- [ ] **Step 2: Test it manually**

Run: `rake kitchen:show_join_code KITCHEN=test-kitchen`
Expected: Prints the kitchen name and join code (or "No kitchen found" if slug doesn't exist).

Run: `rake kitchen:show_join_code`
Expected: Aborts with usage message.

- [ ] **Step 3: Run lint**

Run: `bundle exec rubocop lib/tasks/kitchen.rake`
Expected: No offenses.

- [ ] **Step 4: Commit**

```bash
git add lib/tasks/kitchen.rake
git commit -m "Add rake kitchen:show_join_code escape hatch for locked-out owners"
```

---

### Task 10: Settings dialog — transfer and login link UI

**Files:**
- Modify: `app/views/settings/_editor_frame.html.erb`
- Modify: `app/javascript/controllers/settings_editor_controller.js`
- Modify: `app/assets/stylesheets/auth.css`

- [ ] **Step 1: Add transfer button and login link buttons to settings view**

In `app/views/settings/_editor_frame.html.erb`, add a "Log in on another device" section. Insert after the join code field hint (line 92, `<span class="settings-field-hint">Share this code...`):

```erb
        <div class="settings-field">
          <form action="<%= create_transfer_path %>" method="post" data-turbo-frame="transfer-frame">
            <input type="hidden" name="authenticity_token" value="<%= form_authenticity_token %>">
            <input type="hidden" name="kitchen_slug" value="<%= kitchen.slug %>">
            <button type="submit" class="btn settings-transfer-btn">Log in on another device</button>
          </form>
          <turbo-frame id="transfer-frame"></turbo-frame>
        </div>
```

Replace the members list loop. Change:

```erb
            <% members.each do |member| %>
              <li>
                <span class="member-name"><%= member[:name] %></span>
                <span class="member-email"><%= member[:email] %></span>
                <% if member[:role] == 'owner' %>
                  <span class="member-role">owner</span>
                <% end %>
              </li>
            <% end %>
```

to:

```erb
            <% members.each do |member| %>
              <li class="settings-member-row">
                <span class="member-info">
                  <span class="member-name"><%= member[:name] %></span>
                  <span class="member-email"><%= member[:email] %></span>
                  <% if member[:role] == 'owner' %>
                    <span class="member-role">owner</span>
                  <% end %>
                </span>
                <form action="<%= member_login_link_path(id: member[:id]) %>" method="post"
                      data-turbo-frame="login-link-frame-<%= member[:id] %>">
                  <input type="hidden" name="authenticity_token" value="<%= form_authenticity_token %>">
                  <input type="hidden" name="kitchen_slug" value="<%= kitchen.slug %>">
                  <button type="submit" class="btn btn-sm settings-login-link-btn">Login link</button>
                </form>
                <turbo-frame id="login-link-frame-<%= member[:id] %>"></turbo-frame>
              </li>
            <% end %>
```

- [ ] **Step 2: Add copy-to-clipboard action to Stimulus controller**

In `app/javascript/controllers/settings_editor_controller.js`, add a `copyToClipboard` method. This is called from the copy buttons in the transfer and login link Turbo Frame responses:

```javascript
  copyToClipboard(event) {
    const text = event.params.copyText
    navigator.clipboard.writeText(text)
  }
```

- [ ] **Step 3: Add CSS for the new elements**

Add to `app/assets/stylesheets/auth.css`:

```css
/* Sign-out interstitial & welcome screen */
.signout-kitchen {
  margin-bottom: 1.25rem;
}

.signout-kitchen-name {
  font-weight: 500;
  margin: 0 0 0.25rem;
}

.signout-join-code {
  font-family: var(--font-display);
  font-size: 1.3rem;
  color: var(--text);
  margin: 0.25rem 0;
  line-height: 1.3;
}

.signout-hint {
  color: var(--text-soft);
  font-size: 0.85rem;
  line-height: 1.4;
  margin: 1.25rem 0 0;
}
```

The transfer and login link UI renders inside the settings dialog, which uses the main layout (with `base.css`). Add these styles to `auth.css` as well (they apply to both the auth pages and the Turbo Frame responses):

```css
/* Transfer & login link UI */
.settings-transfer-btn {
  margin-top: 0.5rem;
}

.transfer-result,
.login-link-result {
  margin-top: 0.5rem;
}

.transfer-qr svg {
  display: block;
  max-width: 200px;
  margin: 0 auto 0.75rem;
}

.transfer-link-row {
  display: flex;
  gap: 0.5rem;
  align-items: center;
}

.transfer-link-row input {
  flex: 1;
  font-size: 0.8rem;
}

.transfer-hint {
  color: var(--text-soft);
  font-size: 0.8rem;
  margin: 0.5rem 0 0;
}

.settings-login-link-btn {
  font-size: 0.75rem;
  padding: 0.2rem 0.5rem;
}

.settings-member-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-wrap: wrap;
}

.member-info {
  flex: 1;
}
```

- [ ] **Step 4: Build JS**

Run: `npm run build`
Expected: Build succeeds with no errors.

- [ ] **Step 5: Run lint on all modified files**

Run: `bundle exec rubocop app/controllers/settings_controller.rb app/controllers/transfers_controller.rb`
Run: `rake lint:html_safe`
Expected: No offenses.

- [ ] **Step 6: Run full test suite**

Run: `rake test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/views/settings/_editor_frame.html.erb app/javascript/controllers/settings_editor_controller.js app/assets/stylesheets/auth.css
git commit -m "Add session transfer and login link UI to settings dialog"
```

---

### Task 11: Final integration check

- [ ] **Step 1: Run full test suite and lint**

Run: `rake`
Expected: All tests pass, no lint offenses.

- [ ] **Step 2: Run Brakeman**

Run: `rake security`
Expected: No new warnings. The `TransfersController` uses `find_signed` (no SQL injection risk) and `html_safe` on `rqrcode` output (allowlisted).

- [ ] **Step 3: Manual smoke test**

Start the dev server: `MULTI_KITCHEN=true bin/dev`

Test each flow:
1. Create a kitchen, verify join code is shown
2. Sign out — verify interstitial shows join code
3. Join the kitchen via join code — verify welcome screen for new members
4. Open settings → click "Log in on another device" → verify QR code appears in Turbo Frame
5. Open settings → members list → click "Login link" → verify link appears in Turbo Frame
6. Copy a transfer link, open in incognito → verify it logs you in
7. Copy a login link, open in incognito → verify it logs in the target user
8. Wait for a transfer link to expire, then visit → verify error page with "Sign in with join code" link

- [ ] **Step 4: Commit any fixes from smoke testing**

If any issues were found during smoke testing, fix and commit them individually.
