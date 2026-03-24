# Settings Page Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace static `config/site.yml` with database-backed settings on the Kitchen model, add a settings page, and put a gear icon in the navbar.

**Architecture:** Add `site_title`, `homepage_heading`, `homepage_subtitle`, and `usda_api_key` columns to Kitchen. Encrypted API key via `encrypts`. Thin SettingsController with show/update. Gear icon outside the nav overflow system.

**Tech Stack:** Rails 8, SQLite, Turbo Drive, Stimulus (reveal toggle), Active Record Encryption

---

### Task 0: Active Record Encryption Setup

**Files:**
- Create: `config/initializers/active_record_encryption.rb`

Active Record Encryption needs keys but no `config/master.key` exists. Use environment-based deterministic keys so encryption works without credentials file.

**Step 1: Create the initializer**

```ruby
# frozen_string_literal: true

# Configures Active Record Encryption keys for encrypting sensitive columns
# (e.g., API keys on Kitchen). In production, set these environment variables;
# in dev/test, deterministic defaults are used so encryption works out of the box.
Rails.application.config.active_record.encryption.primary_key =
  ENV.fetch('ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY', 'dev-primary-key-min-12-bytes')
Rails.application.config.active_record.encryption.deterministic_key =
  ENV.fetch('ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY', 'dev-deterministic-key-12b')
Rails.application.config.active_record.encryption.key_derivation_salt =
  ENV.fetch('ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT', 'dev-key-derivation-salt')
```

**Step 2: Verify encryption works**

Run: `bin/rails runner "puts ActiveRecord::Encryption.config.primary_key.present?"`
Expected: `true`

**Step 3: Commit**

```bash
git add config/initializers/active_record_encryption.rb
git commit -m "feat: configure Active Record Encryption for API key storage"
```

---

### Task 1: Migration — Add Settings Columns to Kitchen

**Files:**
- Create: `db/migrate/002_add_settings_to_kitchen.rb`

**Step 1: Write the migration**

```ruby
class AddSettingsToKitchen < ActiveRecord::Migration[8.0]
  def change
    add_column :kitchens, :site_title, :string, default: 'Family Recipes'
    add_column :kitchens, :homepage_heading, :string, default: 'Our Recipes'
    add_column :kitchens, :homepage_subtitle, :string, default: "A collection of our family\u2019s favorite recipes."
    add_column :kitchens, :usda_api_key, :string
  end
end
```

**Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: migration succeeds, existing kitchens get default values

**Step 3: Verify columns exist**

Run: `bin/rails runner "puts Kitchen.column_names.sort.join(', ')"`
Expected: includes `homepage_heading`, `homepage_subtitle`, `site_title`, `usda_api_key`

**Step 4: Commit**

```bash
git add db/migrate/002_add_settings_to_kitchen.rb db/schema.rb
git commit -m "feat: add settings columns to Kitchen"
```

---

### Task 2: Kitchen Model — Encryption and multi_kitchen Refactor

**Files:**
- Modify: `app/models/kitchen.rb`

**Step 1: Write the failing test**

Add to `test/models/kitchen_test.rb`:

```ruby
test 'encrypts usda_api_key at rest' do
  setup_test_kitchen
  @kitchen.update!(usda_api_key: 'test-api-key-123')
  @kitchen.reload

  assert_equal 'test-api-key-123', @kitchen.usda_api_key

  # Verify it's not stored as plaintext in the database
  raw = ActiveRecord::Base.connection.select_value(
    "SELECT usda_api_key FROM kitchens WHERE id = #{@kitchen.id}"
  )
  assert_not_equal 'test-api-key-123', raw
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/kitchen_test.rb -n test_encrypts_usda_api_key_at_rest`
Expected: FAIL (no encryption yet)

**Step 3: Add encrypts and update enforce_single_kitchen_mode**

In `app/models/kitchen.rb`, add `encrypts :usda_api_key` after the associations. Also change `enforce_single_kitchen_mode` to read from `multi_kitchen` column... wait — `multi_kitchen` stays outside the database per design. But the current code reads `Rails.configuration.site.multi_kitchen`. We need to keep this working until Task 7 removes site.yml. For now, just add the encryption.

```ruby
encrypts :usda_api_key
```

Add after line 16 (`has_one :meal_plan`).

Also update the header comment to mention settings columns.

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/models/kitchen_test.rb -n test_encrypts_usda_api_key_at_rest`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/kitchen.rb test/models/kitchen_test.rb
git commit -m "feat: encrypt usda_api_key on Kitchen model"
```

---

### Task 3: Routes and SettingsController

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/settings_controller.rb`

**Step 1: Write failing controller tests**

Create `test/controllers/settings_controller_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'requires membership to view settings' do
    get settings_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'renders settings page for logged-in member' do
    log_in
    get settings_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'h1', 'Settings'
  end

  test 'requires membership to update settings' do
    patch settings_path(kitchen_slug: kitchen_slug), params: { kitchen: { site_title: 'New' } }

    assert_response :forbidden
  end

  test 'updates site settings' do
    log_in
    patch settings_path(kitchen_slug: kitchen_slug), params: {
      kitchen: { site_title: 'New Title', homepage_heading: 'New Heading', homepage_subtitle: 'New Sub' }
    }

    assert_redirected_to settings_path(kitchen_slug: kitchen_slug)
    follow_redirect!
    @kitchen.reload
    assert_equal 'New Title', @kitchen.site_title
    assert_equal 'New Heading', @kitchen.homepage_heading
    assert_equal 'New Sub', @kitchen.homepage_subtitle
  end

  test 'updates usda api key' do
    log_in
    patch settings_path(kitchen_slug: kitchen_slug), params: {
      kitchen: { usda_api_key: 'my-secret-key' }
    }

    assert_redirected_to settings_path(kitchen_slug: kitchen_slug)
    @kitchen.reload
    assert_equal 'my-secret-key', @kitchen.usda_api_key
  end

  test 'rejects unpermitted params' do
    log_in
    patch settings_path(kitchen_slug: kitchen_slug), params: {
      kitchen: { site_title: 'OK', slug: 'hacked' }
    }

    assert_redirected_to settings_path(kitchen_slug: kitchen_slug)
    @kitchen.reload
    assert_equal 'OK', @kitchen.site_title
    assert_equal 'test-kitchen', @kitchen.slug
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/settings_controller_test.rb`
Expected: FAIL (no route, no controller)

**Step 3: Add routes**

In `config/routes.rb`, inside the `scope '(/kitchens/:kitchen_slug)'` block, add after the `post 'import'` line:

```ruby
get 'settings', to: 'settings#show', as: :settings
patch 'settings', to: 'settings#update'
```

**Step 4: Create the controller**

```ruby
# frozen_string_literal: true

# Manages kitchen-scoped settings: site branding (title, heading, subtitle)
# and API keys (USDA). Thin controller — validates and saves directly to
# current_kitchen with no side effects.
#
# - Kitchen: settings live as columns on the tenant model
# - ApplicationController: provides current_kitchen and require_membership
class SettingsController < ApplicationController
  before_action :require_membership

  def show; end

  def update
    if current_kitchen.update(settings_params)
      redirect_to settings_path, notice: 'Settings saved.'
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def settings_params
    params.expect(kitchen: [:site_title, :homepage_heading, :homepage_subtitle, :usda_api_key])
  end
end
```

**Step 5: Create a minimal view**

Create `app/views/settings/show.html.erb` with a placeholder so tests pass:

```erb
<h1>Settings</h1>
```

(The full view comes in Task 4.)

**Step 6: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/settings_controller_test.rb`
Expected: PASS

**Step 7: Commit**

```bash
git add config/routes.rb app/controllers/settings_controller.rb \
  app/views/settings/show.html.erb test/controllers/settings_controller_test.rb
git commit -m "feat: add SettingsController with routes and tests"
```

---

### Task 4: Settings View

**Files:**
- Modify: `app/views/settings/show.html.erb`
- Create: `app/javascript/controllers/reveal_controller.js`

**Step 1: Build the settings form view**

Replace `app/views/settings/show.html.erb`:

```erb
<% content_for(:title) { "Settings — #{current_kitchen.site_title}" } %>

<article class="settings-page">
  <h1>Settings</h1>

  <% if notice %>
    <p class="flash-notice"><%= notice %></p>
  <% end %>

  <%= form_with model: current_kitchen, url: settings_path, method: :patch, class: 'settings-form' do |f| %>
    <section class="settings-section">
      <h2>Site</h2>
      <div class="settings-field">
        <%= f.label :site_title, 'Site title' %>
        <%= f.text_field :site_title, class: 'settings-input' %>
      </div>
      <div class="settings-field">
        <%= f.label :homepage_heading, 'Homepage heading' %>
        <%= f.text_field :homepage_heading, class: 'settings-input' %>
      </div>
      <div class="settings-field">
        <%= f.label :homepage_subtitle, 'Homepage subtitle' %>
        <%= f.text_field :homepage_subtitle, class: 'settings-input' %>
      </div>
    </section>

    <section class="settings-section">
      <h2>API Keys</h2>
      <div class="settings-field" data-controller="reveal">
        <%= f.label :usda_api_key, 'USDA API key' %>
        <div class="settings-api-key-row">
          <%= f.password_field :usda_api_key,
                value: current_kitchen.usda_api_key,
                class: 'settings-input',
                data: { reveal_target: 'input' },
                autocomplete: 'off' %>
          <button type="button" class="btn settings-reveal-btn"
                  data-action="reveal#toggle"
                  data-reveal-target="button">Show</button>
        </div>
      </div>
    </section>

    <div class="settings-actions">
      <%= f.submit 'Save', class: 'btn btn-primary' %>
    </div>
  <% end %>
</article>
```

**Step 2: Create the reveal Stimulus controller**

Create `app/javascript/controllers/reveal_controller.js`:

```javascript
/**
 * Toggles a password field between masked and visible. Used on the settings
 * page for API key fields.
 *
 * - Targets: input (the password field), button (the toggle button)
 */
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]

  toggle() {
    const isPassword = this.inputTarget.type === "password"
    this.inputTarget.type = isPassword ? "text" : "password"
    this.buttonTarget.textContent = isPassword ? "Hide" : "Show"
  }
}
```

**Step 3: Add settings page CSS**

Add to `app/assets/stylesheets/style.css` (near the end, before media queries):

```css
/* Settings page */
.settings-page {
  max-width: 36rem;
}

.settings-page h1 {
  margin-bottom: 1.5rem;
}

.settings-section {
  margin-bottom: 2rem;
}

.settings-section h2 {
  font-size: 1rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  border-bottom: 1px solid var(--border-muted);
  padding-bottom: 0.4rem;
  margin-bottom: 1rem;
}

.settings-field {
  margin-bottom: 1rem;
}

.settings-field label {
  display: block;
  font-size: 0.85rem;
  font-weight: 600;
  margin-bottom: 0.25rem;
}

.settings-input {
  width: 100%;
  font-family: inherit;
  font-size: 0.95rem;
  padding: 0.4rem 0.6rem;
  border: 1px solid var(--border-muted);
  border-radius: 3px;
  background: var(--content-background-color);
  color: var(--text-color);
  box-sizing: border-box;
}

.settings-input:focus {
  outline: 2px solid var(--accent-color);
  outline-offset: 1px;
  border-color: var(--accent-color);
}

.settings-api-key-row {
  display: flex;
  gap: 0.5rem;
  align-items: stretch;
}

.settings-api-key-row .settings-input {
  flex: 1;
}

.settings-reveal-btn {
  white-space: nowrap;
  min-width: 3.5rem;
}

.settings-actions {
  margin-top: 2rem;
}

.flash-notice {
  padding: 0.5rem 0.75rem;
  background: var(--flash-success-bg, #e8f5e9);
  border: 1px solid var(--flash-success-border, #a5d6a7);
  border-radius: 3px;
  margin-bottom: 1.5rem;
  font-size: 0.9rem;
}
```

**Step 4: Verify in browser**

Run: `bin/dev` and navigate to `/settings`
Expected: Settings page renders with Site and API Keys sections, form submits and redirects with flash

**Step 5: Run existing tests**

Run: `ruby -Itest test/controllers/settings_controller_test.rb`
Expected: PASS

**Step 6: Commit**

```bash
git add app/views/settings/show.html.erb app/javascript/controllers/reveal_controller.js \
  app/assets/stylesheets/style.css
git commit -m "feat: settings page view with reveal toggle for API keys"
```

---

### Task 5: Gear Icon in Navbar

**Files:**
- Modify: `app/views/shared/_nav.html.erb`
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Write a nav integration test**

Add to `test/controllers/settings_controller_test.rb`:

```ruby
test 'gear icon visible in navbar for members' do
  log_in
  get home_path(kitchen_slug: kitchen_slug)

  assert_select 'nav a.nav-settings-link'
end

test 'gear icon hidden when not logged in' do
  get home_path(kitchen_slug: kitchen_slug)

  assert_select 'nav a.nav-settings-link', count: 0
end
```

Note: `home_path` is defined in ApplicationController — use it the same way other tests reference pages. The homepage requires a kitchen, so the helper `kitchen_slug` provides it.

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/settings_controller_test.rb -n /gear_icon/`
Expected: FAIL

**Step 3: Add gear icon to nav**

In `app/views/shared/_nav.html.erb`, add between the nav-drawer div and the `yield :extra_nav` line (between lines 22 and 23):

```erb
<% if logged_in? %>
  <%= link_to settings_path, class: 'nav-settings-link', title: 'Settings', aria: { label: 'Settings' } do %>
    <svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <circle cx="12" cy="12" r="3"/>
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>
    </svg>
  <% end %>
<% end %>
```

**Step 4: Add CSS for the gear icon**

Add to `style.css` in the nav section (after the `.nav-auth-btn:hover` rule, around line 354):

```css
.nav-settings-link {
  padding: 0.5rem 0.6rem !important;
  flex-shrink: 0;
}

.nav-settings-link .nav-icon {
  width: 1.1rem;
  height: 1.1rem;
}

.nav-settings-link span {
  display: none;
}

.nav-settings-link::after {
  display: none !important;
}
```

The `!important` on `::after` prevents the underline animation that other nav links get. The gear is icon-only — no label, no underline.

**Step 5: Run tests**

Run: `ruby -Itest test/controllers/settings_controller_test.rb -n /gear_icon/`
Expected: PASS

**Step 6: Commit**

```bash
git add app/views/shared/_nav.html.erb app/assets/stylesheets/style.css
git commit -m "feat: add gear icon to navbar linking to settings"
```

---

### Task 6: Replace site.yml References

**Files:**
- Modify: `app/views/layouts/application.html.erb:10`
- Modify: `app/controllers/homepage_controller.rb`
- Modify: `app/controllers/landing_controller.rb`
- Modify: `app/controllers/pwa_controller.rb`
- Modify: `app/views/homepage/show.html.erb`
- Modify: `app/models/kitchen.rb` (enforce_single_kitchen_mode)
- Modify: `test/test_helper.rb` (with_multi_kitchen)

This task replaces all `Rails.configuration.site` reads with `current_kitchen` attribute reads. The `multi_kitchen` flag is a deployment concern — move it to an environment variable.

**Step 1: Write failing tests for the new behavior**

Add to `test/controllers/homepage_controller_test.rb` (or update existing):

```ruby
test 'homepage uses kitchen site_title in page title' do
  log_in
  @kitchen.update!(site_title: 'Our Family Kitchen')
  get home_path(kitchen_slug: kitchen_slug)

  assert_select 'title', 'Our Family Kitchen'
end

test 'homepage uses kitchen heading and subtitle' do
  log_in
  @kitchen.update!(homepage_heading: 'Custom Heading', homepage_subtitle: 'Custom Sub')
  get home_path(kitchen_slug: kitchen_slug)

  assert_select 'h1', 'Custom Heading'
  assert_select 'header p', 'Custom Sub'
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb -n /kitchen.*title/`
Expected: FAIL (still reading from site.yml)

**Step 3: Update the layout**

In `app/views/layouts/application.html.erb` line 10, change:
```erb
<title><%= content_for?(:title) ? content_for(:title) : Rails.configuration.site.site_title %></title>
```
to:
```erb
<title><%= content_for?(:title) ? content_for(:title) : current_kitchen&.site_title || 'Family Recipes' %></title>
```

The `&.` handles the landing page where no kitchen is set yet. The fallback string covers that case.

**Step 4: Update HomepageController**

Remove `@site_config = Rails.configuration.site` from `show`. The view will read directly from `current_kitchen`.

**Step 5: Update homepage view**

In `app/views/homepage/show.html.erb`:
- Line 1: `<% content_for(:title) { current_kitchen.site_title } %>`
- Line 18: `<h1><%= current_kitchen.homepage_heading %></h1>`
- Line 19: `<p><%= current_kitchen.homepage_subtitle %></p>`

**Step 6: Update LandingController**

Remove `@site_config = Rails.configuration.site` from `render_sole_kitchen_homepage`. The view now reads from `current_kitchen` which is set on the line above.

**Step 7: Update PwaController**

In `app/controllers/pwa_controller.rb`, the manifest needs a kitchen for the title. Since PwaController skips `set_kitchen_from_path`, resolve the sole kitchen:

Change line 28 from:
```ruby
name: Rails.configuration.site.site_title,
```
to:
```ruby
name: sole_kitchen_title,
```

Add a private method:
```ruby
def sole_kitchen_title
  kitchen = ActsAsTenant.without_tenant { Kitchen.first }
  kitchen&.site_title || 'Family Recipes'
end
```

**Step 8: Update enforce_single_kitchen_mode**

In `app/models/kitchen.rb`, change `enforce_single_kitchen_mode` to read from an environment variable instead of `Rails.configuration.site`:

```ruby
def enforce_single_kitchen_mode
  return if ENV['MULTI_KITCHEN'] == 'true'

  errors.add(:base, 'Only one kitchen is allowed in single-kitchen mode') if Kitchen.exists?
end
```

**Step 9: Update test helper**

In `test/test_helper.rb`, update `with_multi_kitchen` to use the env var:

```ruby
def with_multi_kitchen
  original = ENV['MULTI_KITCHEN']
  ENV['MULTI_KITCHEN'] = 'true'
  yield
ensure
  ENV['MULTI_KITCHEN'] = original
end
```

**Step 10: Run all tests**

Run: `rake test`
Expected: All tests pass

**Step 11: Commit**

```bash
git add app/views/layouts/application.html.erb app/controllers/homepage_controller.rb \
  app/controllers/landing_controller.rb app/controllers/pwa_controller.rb \
  app/views/homepage/show.html.erb app/models/kitchen.rb test/test_helper.rb
git commit -m "feat: replace Rails.configuration.site with Kitchen columns"
```

---

### Task 7: Remove site.yml and Initializer

**Files:**
- Delete: `config/site.yml`
- Delete: `config/initializers/site_config.rb`

**Step 1: Verify no remaining references**

Run: `grep -r 'Rails\.configuration\.site' app/ config/ test/ lib/`
Expected: No matches (only docs/plans may still reference it)

**Step 2: Delete the files**

```bash
rm config/site.yml config/initializers/site_config.rb
```

**Step 3: Run full test suite**

Run: `rake test`
Expected: All tests pass

**Step 4: Run lint**

Run: `rake lint`
Expected: No offenses

**Step 5: Commit**

```bash
git rm config/site.yml config/initializers/site_config.rb
git commit -m "chore: remove site.yml — settings now live in Kitchen model"
```

---

### Task 8: Update Architectural Comments and CLAUDE.md

**Files:**
- Modify: `app/models/kitchen.rb` (header comment)
- Modify: `app/controllers/homepage_controller.rb` (header comment)
- Modify: `app/controllers/pwa_controller.rb` (header comment)
- Modify: `CLAUDE.md`

**Step 1: Update Kitchen header comment**

Add mention of site settings columns (`site_title`, `homepage_heading`, `homepage_subtitle`) and encrypted `usda_api_key` to the header.

**Step 2: Update HomepageController header comment**

Remove reference to `Rails.configuration.site`. Mention `current_kitchen` provides branding.

**Step 3: Update PwaController header comment**

Replace `Rails.configuration.site` reference with `Kitchen#site_title`.

**Step 4: Update CLAUDE.md**

In the Architecture section, add a brief note about settings:

> **Settings.** Site branding and API keys live as columns on Kitchen (no
> separate settings table). `usda_api_key` is encrypted via Active Record
> Encryption. `SettingsController` is a thin show/update — no write service.
> The `multi_kitchen` flag is an env var (`MULTI_KITCHEN=true`), not a database
> setting.

Remove any references to `config/site.yml` or `Rails.configuration.site`.

**Step 5: Run lint and tests**

Run: `rake`
Expected: All pass

**Step 6: Commit**

```bash
git add app/models/kitchen.rb app/controllers/homepage_controller.rb \
  app/controllers/pwa_controller.rb CLAUDE.md
git commit -m "docs: update architectural comments and CLAUDE.md for settings"
```
