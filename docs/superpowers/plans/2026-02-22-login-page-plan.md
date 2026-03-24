# Login Page Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add a permanent login page at `/login` with nav login/logout links, fixing the OmniAuth 2.x POST requirement.

**Architecture:** New `SessionsController#new` renders a login form that POSTs to `/auth/developer` (dev/test). The `Authentication` concern redirects to `login_path` instead of the broken `/auth/developer` GET. Nav gets login/logout links.

**Tech Stack:** Rails 8, OmniAuth 2.x, Minitest

---

### Task 1: Route and Controller

**Files:**
- Modify: `config/routes.rb:17` (callback already fixed to `post`, add `get 'login'`)
- Create: `app/controllers/sessions_controller.rb`
- Create: `test/controllers/sessions_controller_test.rb`

**Step 1: Write the failing test**

Create `test/controllers/sessions_controller_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test 'login page renders successfully' do
    get login_path

    assert_response :success
    assert_select 'h1', 'Log In'
  end

  test 'login page has form that posts to omniauth developer' do
    get login_path

    assert_select 'form[action="/auth/developer"][method="post"]'
    assert_select 'input[name="name"]'
    assert_select 'input[name="email"]'
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/sessions_controller_test.rb`
Expected: FAIL — no route matches `login_path`

**Step 3: Add route and controller**

Add to `config/routes.rb`, after the `delete 'logout'` line and before the `if Rails.env.development?` block:

```ruby
get 'login', to: 'sessions#new', as: :login
```

Create `app/controllers/sessions_controller.rb`:

```ruby
# frozen_string_literal: true

class SessionsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :set_kitchen_from_path

  def new
  end
end
```

**Step 4: Create the view (minimal, enough to pass)**

Create `app/views/sessions/new.html.erb`:

```erb
<% content_for(:title) { 'Log In' } %>

<article class="login">
  <header>
    <h1>Log In</h1>
  </header>

  <% if Rails.env.development? || Rails.env.test? %>
    <%= form_tag '/auth/developer', method: :post, class: 'login-form' do %>
      <%= hidden_field_tag :authenticity_token, form_authenticity_token %>
      <div class="login-field">
        <%= label_tag :name, 'Name' %>
        <%= text_field_tag :name, nil, required: true, autofocus: true %>
      </div>
      <div class="login-field">
        <%= label_tag :email, 'Email' %>
        <%= email_field_tag :email, nil, required: true %>
      </div>
      <div class="login-actions">
        <%= submit_tag 'Log In', class: 'btn btn-primary' %>
      </div>
    <% end %>
  <% else %>
    <p class="login-placeholder">OAuth providers coming soon.</p>
  <% end %>
</article>
```

**Step 5: Run test to verify it passes**

Run: `ruby -Itest test/controllers/sessions_controller_test.rb`
Expected: PASS (2 tests, all green)

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/sessions_controller.rb app/views/sessions/new.html.erb test/controllers/sessions_controller_test.rb
git commit -m "feat: add login page with OmniAuth developer form"
```

---

### Task 2: Fix Authentication Redirect

**Files:**
- Modify: `app/controllers/concerns/authentication.rb:37`

**Step 1: Write the failing test**

Add to `test/controllers/sessions_controller_test.rb`:

```ruby
test 'unauthenticated access to protected action redirects to login' do
  create_kitchen_and_user

  post recipes_path(kitchen_slug: kitchen_slug), params: { recipe: { markdown: '# Test' } }

  assert_redirected_to login_path
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/sessions_controller_test.rb -n test_unauthenticated_access_to_protected_action_redirects_to_login`
Expected: FAIL — redirects to `/auth/developer` instead of `/login`

**Step 3: Fix the redirect**

In `app/controllers/concerns/authentication.rb`, change line 37 from:

```ruby
redirect_to '/auth/developer'
```

to:

```ruby
redirect_to login_path
```

**Step 4: Run tests to verify**

Run: `ruby -Itest test/controllers/sessions_controller_test.rb`
Expected: PASS (3 tests)

Also run full suite to check nothing broke:

Run: `rake test`
Expected: All green

**Step 5: Commit**

```bash
git add app/controllers/concerns/authentication.rb test/controllers/sessions_controller_test.rb
git commit -m "fix: redirect unauthenticated users to login page instead of /auth/developer"
```

---

### Task 3: Nav Login/Logout Links

**Files:**
- Modify: `app/views/shared/_nav.html.erb`
- Modify: `app/assets/stylesheets/style.css`
- Create: `test/integration/nav_login_test.rb`

**Step 1: Write the failing test**

Create `test/integration/nav_login_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class NavLoginTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'anonymous user sees log in link' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav a[href=?]', login_path, text: 'Log in'
  end

  test 'logged-in user sees log out button' do
    log_in

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav form[action=?] button', logout_path, text: 'Log out'
  end

  test 'anonymous user does not see log out button' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav form[action=?]', logout_path, count: 0
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/integration/nav_login_test.rb`
Expected: FAIL — no log in link in nav

**Step 3: Update the nav partial**

Replace `app/views/shared/_nav.html.erb` with:

```erb
  <nav>
    <div>
      <% if current_kitchen %>
        <%= link_to 'Home', kitchen_root_path, class: 'home', title: 'Home (Table of Contents)' %>
        <%= link_to 'Index', ingredients_path, class: 'index', title: 'Index of ingredients' %>
        <%= link_to 'Groceries', groceries_path, class: 'groceries', title: 'Printable grocery list' %>
      <% else %>
        <%= link_to 'Home', root_path, class: 'home', title: 'Home' %>
      <% end %>
    </div>
    <div>
      <% if logged_in? %>
        <%= button_to 'Log out', logout_path, method: :delete, class: 'nav-auth-btn' %>
      <% else %>
        <%= link_to 'Log in', login_path, class: 'login' %>
      <% end %>
    </div>
    <%= yield :extra_nav if content_for?(:extra_nav) %>
  </nav>
```

**Step 4: Add nav auth button styling**

Add to `app/assets/stylesheets/style.css`, after the `nav > div:last-child:not(:first-child)` rule (around line 201):

```css
.nav-auth-btn {
  appearance: none;
  -webkit-appearance: none;
  font-family: "Futura", sans-serif;
  font-size: 0.8rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  background: none;
  border: none;
  color: var(--text-color);
  cursor: pointer;
  padding: 0.5rem 0.9rem;
  line-height: 1.5;
  transition: color 0.2s ease;
}

.nav-auth-btn:hover {
  color: var(--accent-color);
}
```

**Step 5: Run tests to verify**

Run: `ruby -Itest test/integration/nav_login_test.rb`
Expected: PASS (3 tests)

**Step 6: Commit**

```bash
git add app/views/shared/_nav.html.erb app/assets/stylesheets/style.css test/integration/nav_login_test.rb
git commit -m "feat: add login/logout links to nav"
```

---

### Task 4: Login Page Styling

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Add login form styles**

Add to `app/assets/stylesheets/style.css`, before the print media query section:

```css
/************************/
/* Login page           */
/************************/

.login header {
  margin-bottom: 1.5rem;
}

.login-form {
  max-width: 20rem;
  margin: 0 auto;
}

.login-field {
  margin-bottom: 1rem;
}

.login-field label {
  display: block;
  font-family: "Futura", sans-serif;
  font-size: 0.8rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  margin-bottom: 0.35rem;
}

.login-field input {
  width: 100%;
  padding: 0.5rem 0.6rem;
  font-family: inherit;
  font-size: 1rem;
  border: 1px solid var(--border-light);
  border-radius: 3px;
  background: white;
  color: var(--text-color);
  box-sizing: border-box;
}

.login-field input:focus {
  outline: 2px solid var(--accent-color);
  outline-offset: 1px;
  border-color: var(--accent-color);
}

.login-actions {
  margin-top: 1.5rem;
  text-align: center;
}

.login-actions .btn {
  width: 100%;
  padding: 0.6rem;
  font-size: 0.9rem;
}

.login-placeholder {
  text-align: center;
  font-style: italic;
  color: var(--muted-text);
}
```

**Step 2: Visually verify**

Run: `bin/dev`
Navigate to: `http://localhost:3030/login`
Confirm: centered form card, Futura labels, accent-colored submit button, looks at home in the cookbook aesthetic.

**Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "style: add login page form styles"
```

---

### Task 5: Full Test Suite Verification

**Step 1: Run lint**

Run: `rake lint`
Expected: No offenses

**Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass, no regressions

**Step 3: Final commit if any fixes needed**

If lint or tests required changes, commit them here.
