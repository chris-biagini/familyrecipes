# Magic Link Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace join-code-as-password auth with email-verified magic link sign-in, delete the trusted-header path, and gate `/new` for an invite-only fly.io beta.

**Architecture:** A new `MagicLink` AR model carries a 6-character single-use code tied to a `User` and a `purpose` enum (`:sign_in` or `:join`). `SessionsController#create` accepts an email, finds the user, creates a magic link, and delivers it via `MagicLinkMailer` (SMTP when configured, Rails logger fallback otherwise). A `MagicLinksController` consumes the code atomically, cross-checks the consumed link's user email against a signed `:pending_auth` cookie, starts a session, and sets `email_verified_at`. `JoinsController#create` is rewritten to issue a `:join` magic link (membership is created on consume, not before). `KitchensController` gets a `before_action` gate backed by `Kitchen.accepting_signups?`. The trusted-header / Authelia code path and its supporting initializer, lib module, tests, and docs are deleted in one task.

**Tech Stack:** Rails 8, Minitest, ActiveSupport::MessageVerifier, Action Mailer (new to this project — no `app/mailers/` yet), ActiveRecord encryption (unchanged), Turbo + Stimulus (unchanged), Playwright (security specs).

**Spec:** `docs/superpowers/specs/2026-04-10-magic-link-auth-design.md`

**Branch:** `feature/magic-link-auth` (already created; spec is committed).

---

## File Structure

### New files

- `db/migrate/004_create_magic_links.rb` — schema migration
- `app/models/magic_link.rb` — the AR model
- `app/mailers/application_mailer.rb` — Rails mailer base class (first mailer in the project)
- `app/mailers/magic_link_mailer.rb` — one action, `sign_in_instructions(magic_link)`
- `app/views/layouts/mailer.html.erb` / `mailer.text.erb` — mailer layouts (required by Rails convention)
- `app/views/magic_link_mailer/sign_in_instructions.html.erb` / `.text.erb` — email templates
- `app/views/sessions/new.html.erb` — email entry form (replaces absence; current controller only has `destroy`)
- `app/views/magic_links/new.html.erb` — "check your email" + code entry form
- `app/controllers/magic_links_controller.rb` — `new` + `create`
- `app/controllers/concerns/pending_auth_token.rb` — helper mixin for the signed `:pending_auth` cookie (used by `SessionsController`, `MagicLinksController`, `JoinsController`)
- `test/models/magic_link_test.rb`
- `test/mailers/magic_link_mailer_test.rb`
- `test/mailers/previews/magic_link_mailer_preview.rb`
- `test/controllers/magic_links_controller_test.rb`
- `test/integration/auth_flow_test.rb` — full email→mailer→code→session path
- `test/security/magic_link_auth.spec.mjs` — Playwright

### Modified files

- `app/controllers/sessions_controller.rb` — rewritten: `new`, `create`, simplified `destroy`
- `app/controllers/joins_controller.rb` — `create` issues a magic link; no direct `start_new_session_for`
- `app/controllers/kitchens_controller.rb` — adds `enforce_accepting_signups` before_action
- `app/controllers/transfers_controller.rb` — deletes `create_for_member` + private helpers it uses
- `app/controllers/application_controller.rb` — deletes `authenticate_from_headers`, `trusted_header_identity`, `auto_join_sole_kitchen`, the `before_action :authenticate_from_headers`, class comment rewrite
- `app/models/kitchen.rb` — adds `self.accepting_signups?`
- `app/models/user.rb` — class comment rewrite (no "trusted-header" framing)
- `app/views/sessions/destroy.html.erb` — **deleted** (handled alongside controller rewrite)
- `app/views/kitchens/settings/_members.html.erb` and any Stimulus controller that wires the "Login link" button — delete that UI path
- `config/routes.rb` — new routes, deleted routes
- `config/environments/production.rb` — mailer SMTP/logger config + default URL options
- `config/environments/development.rb` — mailer logger config
- `config/environments/test.rb` — mailer `:test` delivery (may be default; verify)
- `config/initializers/trusted_proxy.rb` — **deleted**
- `config/initializers/trusted_proxy_warning.rb` — **deleted**
- `lib/familyrecipes/trusted_proxy_config.rb` — **deleted**
- `test/lib/familyrecipes/trusted_proxy_config_test.rb` — **deleted**
- `test/controllers/header_auth_test.rb` — **deleted**
- `test/controllers/welcome_controller_test.rb` — **deleted**
- `app/controllers/welcome_controller.rb` — **deleted**
- `app/views/welcome/` — **deleted**
- `test/controllers/sessions_controller_test.rb` — rewritten
- `test/controllers/joins_controller_test.rb` — updated (create issues magic link, not session)
- `test/controllers/kitchens_controller_test.rb` — adds gate tests
- `test/controllers/transfers_controller_test.rb` — deletes `create_for_member` cases
- `test/security/auth_bypass.spec.mjs` — updates routes referenced
- `lib/tasks/kitchen.rake` — gains `kitchen:create` task
- `.env.example` — new env vars
- `README.md` — deploy section rewrite
- `CLAUDE.md` — auth section rewrite

### Numbers

Expected net diff roughly `-400 / +1000` lines.

---

## Task 1: Create `MagicLink` migration and bare model

**Files:**
- Create: `db/migrate/004_create_magic_links.rb`
- Create: `app/models/magic_link.rb`
- Create: `test/models/magic_link_test.rb`

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/004_create_magic_links.rb
# frozen_string_literal: true

class CreateMagicLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :magic_links do |t|
      t.references :user, null: false, foreign_key: true
      t.references :kitchen, null: true, foreign_key: true
      t.string :code, null: false, limit: 6
      t.integer :purpose, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.string :request_ip
      t.string :request_user_agent
      t.timestamps
    end

    add_index :magic_links, :code, unique: true
    add_index :magic_links, :expires_at
  end
end
```

- [ ] **Step 2: Run the migration and verify schema**

```bash
bin/rails db:migrate
grep -A12 'create_table "magic_links"' db/schema.rb
```

Expected: schema.rb version bumps to `4` and shows the `magic_links` table with `code`, `purpose`, `expires_at`, `consumed_at`, `request_ip`, `request_user_agent`, and FKs to `user_id` + `kitchen_id`.

- [ ] **Step 3: Write a failing test that requires the model to exist**

```ruby
# test/models/magic_link_test.rb
# frozen_string_literal: true

require 'test_helper'

class MagicLinkTest < ActiveSupport::TestCase
  setup do
    @kitchen, @user = create_kitchen_and_user(email: 'chris@example.com', name: 'Chris')
  end

  test 'belongs to user and optional kitchen' do
    link = MagicLink.new(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now, code: 'ABCD23')
    assert link.valid?
    assert_equal @user, link.user
    assert_nil link.kitchen
  end
end
```

- [ ] **Step 4: Run the test — expected failure**

```bash
bundle exec ruby -Itest test/models/magic_link_test.rb
```

Expected: `NameError: uninitialized constant MagicLink`.

- [ ] **Step 5: Write the minimal model**

```ruby
# app/models/magic_link.rb
# frozen_string_literal: true

# Short-lived single-use authentication token tied to a User, delivered by
# email (or logged to stdout when SMTP is unconfigured). The code is the
# shared secret between the "check your email" page and the email itself;
# consuming it atomically starts a session. Join-purpose links also carry
# a kitchen_id so consumption can create the matching Membership.
#
# - User: the identity the link authenticates as
# - Kitchen: only set when purpose == :join
# - MagicLinkMailer: delivery
# - SessionsController / JoinsController: issue links
# - MagicLinksController: consume links
class MagicLink < ApplicationRecord
  belongs_to :user
  belongs_to :kitchen, optional: true

  enum :purpose, { sign_in: 0, join: 1 }, validate: true

  validates :code, presence: true, uniqueness: true, length: { is: 6 }
  validates :expires_at, presence: true
end
```

- [ ] **Step 6: Run the test — expected pass**

```bash
bundle exec ruby -Itest test/models/magic_link_test.rb
```

Expected: `1 runs, 2 assertions, 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add db/migrate/004_create_magic_links.rb db/schema.rb app/models/magic_link.rb test/models/magic_link_test.rb
git commit -m "Add MagicLink model and migration"
```

---

## Task 2: `MagicLink.generate_code` — 32-char alphabet, no ambiguous characters

**Files:**
- Modify: `app/models/magic_link.rb`
- Modify: `test/models/magic_link_test.rb`

- [ ] **Step 1: Write failing tests for the code generator**

Add to `test/models/magic_link_test.rb`:

```ruby
  test 'generate_code returns a 6-character string from the restricted alphabet' do
    100.times do
      code = MagicLink.generate_code
      assert_equal 6, code.length
      assert_match(/\A[A-HJ-NP-Z2-9]{6}\z/, code)
    end
  end

  test 'code is auto-assigned on create when blank' do
    link = MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now)
    assert_match(/\A[A-HJ-NP-Z2-9]{6}\z/, link.code)
  end

  test 'code is unique across creates' do
    codes = Array.new(50) do
      MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now).code
    end
    assert_equal codes.uniq.size, codes.size
  end
```

The alphabet `[A-HJ-NP-Z2-9]` excludes `I`, `O`, `0`, `1` — the visually ambiguous characters — yielding 32 glyphs.

- [ ] **Step 2: Run tests — expected failure**

```bash
bundle exec ruby -Itest test/models/magic_link_test.rb
```

Expected: `NoMethodError: undefined method 'generate_code'`.

- [ ] **Step 3: Implement code generation**

Edit `app/models/magic_link.rb`. Inside the class body, above the `belongs_to`:

```ruby
  ALPHABET = ('A'..'Z').to_a - %w[I O] + ('2'..'9').to_a
  CODE_LENGTH = 6
```

Add a class method:

```ruby
  class << self
    def generate_code
      Array.new(CODE_LENGTH) { ALPHABET.sample(random: SecureRandom) }.join
    end
  end
```

Add a `before_validation` hook:

```ruby
  before_validation :assign_code, on: :create

  private

  def assign_code
    return if code.present?

    self.code = loop do
      candidate = self.class.generate_code
      break candidate unless self.class.exists?(code: candidate)
    end
  end
```

Add `require 'securerandom'` at the top of the file.

- [ ] **Step 4: Run tests — expected pass**

```bash
bundle exec ruby -Itest test/models/magic_link_test.rb
```

Expected: `4 runs, all assertions pass`.

- [ ] **Step 5: Commit**

```bash
git add app/models/magic_link.rb test/models/magic_link_test.rb
git commit -m "MagicLink: generate unique 6-char codes from a restricted alphabet"
```

---

## Task 3: Atomic `MagicLink.consume` with expiry + single-use enforcement

**Files:**
- Modify: `app/models/magic_link.rb`
- Modify: `test/models/magic_link_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/models/magic_link_test.rb`:

```ruby
  test 'consume returns the link and marks it consumed' do
    link = MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now)
    result = MagicLink.consume(link.code)

    assert_equal link.id, result.id
    assert_not_nil result.consumed_at
  end

  test 'consume returns nil for unknown code' do
    assert_nil MagicLink.consume('ZZZZZZ')
  end

  test 'consume returns nil for expired code' do
    link = MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 1.minute.ago)

    assert_nil MagicLink.consume(link.code)
  end

  test 'consume returns nil when code is already consumed' do
    link = MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now)
    MagicLink.consume(link.code)

    assert_nil MagicLink.consume(link.code)
  end

  test 'consume normalizes the input code (whitespace and case)' do
    link = MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now)
    result = MagicLink.consume("  #{link.code.downcase}  ")

    assert_equal link.id, result.id
  end

  test 'consume is atomic under concurrent attempts' do
    link = MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now)

    results = Array.new(5) do
      Thread.new { MagicLink.consume(link.code) }
    end.map(&:value)

    successes = results.compact
    assert_equal 1, successes.size
  end
```

- [ ] **Step 2: Run tests — expected failure**

```bash
bundle exec ruby -Itest test/models/magic_link_test.rb
```

Expected: `NoMethodError: undefined method 'consume'`.

- [ ] **Step 3: Implement `consume`**

In `app/models/magic_link.rb`, inside `class << self`:

```ruby
    def consume(raw_code)
      sanitized = normalize(raw_code)
      return nil if sanitized.blank?

      updated = where(code: sanitized, consumed_at: nil)
                .where('expires_at > ?', Time.current)
                .update_all(consumed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- intentional: atomic single-use claim
      return nil unless updated == 1

      find_by(code: sanitized)
    end

    def normalize(raw_code)
      raw_code.to_s.strip.upcase
    end
```

- [ ] **Step 4: Run tests — expected pass**

```bash
bundle exec ruby -Itest test/models/magic_link_test.rb
```

Expected: `10 runs, all pass`. SQLite's write concurrency may require enabling `PRAGMA journal_mode = WAL` for the concurrent test; if the concurrent test is flaky in isolation, wrap it in `ActiveRecord::Base.connection_pool.with_connection` inside each thread (the threads need their own connection from the pool).

If the concurrency test is still flaky under SQLite, replace the thread-based test with a direct two-step proof that `consume` returns nil on a second call — the atomicity is already proven by the single `update_all` call, and the race test documents intent more than it verifies the DB. Use your judgment; leave either version in with a comment explaining the choice.

- [ ] **Step 5: Commit**

```bash
git add app/models/magic_link.rb test/models/magic_link_test.rb
git commit -m "MagicLink.consume: atomic single-use with expiry"
```

---

## Task 4: `User#verify_email!` + `email_verified?` — make the existing column meaningful

The column already exists from migration `003_add_email_verified_at_to_users.rb`. This task adds behavior, not schema.

**Files:**
- Modify: `app/models/user.rb`
- Create: `test/models/user_email_verification_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/models/user_email_verification_test.rb
# frozen_string_literal: true

require 'test_helper'

class UserEmailVerificationTest < ActiveSupport::TestCase
  setup do
    @kitchen, @user = create_kitchen_and_user(email: 'chris@example.com', name: 'Chris')
    @user.update_column(:email_verified_at, nil)
  end

  test 'email_verified? is false when the column is nil' do
    assert_not @user.email_verified?
  end

  test 'verify_email! sets email_verified_at to the current time' do
    freeze_time do
      @user.verify_email!
      assert_equal Time.current, @user.email_verified_at
    end
  end

  test 'verify_email! is a no-op when already verified' do
    @user.update!(email_verified_at: 3.days.ago)
    previous = @user.email_verified_at

    @user.verify_email!
    assert_equal previous, @user.reload.email_verified_at
  end

  test 'email_verified? is true when the column is set' do
    @user.update!(email_verified_at: Time.current)
    assert @user.email_verified?
  end
end
```

- [ ] **Step 2: Run test — expected failure**

```bash
bundle exec ruby -Itest test/models/user_email_verification_test.rb
```

Expected: `NoMethodError: undefined method 'verify_email!' ... undefined method 'email_verified?'`.

- [ ] **Step 3: Implement**

Edit `app/models/user.rb`. Replace the whole class comment and add the methods. The new file:

```ruby
# frozen_string_literal: true

# A person who can sign in and be a member of one or more Kitchens. Created
# via the join flow (JoinsController) or the kitchen creation flow
# (KitchensController). Authentication is email-verified: a User is
# considered authenticated once they've consumed a valid MagicLink proving
# control of their email address. The session layer (Session model +
# Authentication concern) is auth-agnostic so new "front doors" (passkeys,
# OAuth) can be added without touching this model.
class User < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :kitchens, through: :memberships
  has_many :sessions, dependent: :destroy
  has_many :magic_links, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  def email_verified? = email_verified_at.present?

  def verify_email!
    return if email_verified?

    update!(email_verified_at: Time.current)
  end
end
```

- [ ] **Step 4: Run test — expected pass**

```bash
bundle exec ruby -Itest test/models/user_email_verification_test.rb
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/user.rb test/models/user_email_verification_test.rb
git commit -m "User: verify_email! and email_verified?"
```

---

## Task 5: `ApplicationMailer` + `MagicLinkMailer` scaffolding with layouts

Rails convention requires both the HTML and text versions for multipart delivery. The project has no `app/mailers/` directory yet — this is the first mailer.

**Files:**
- Create: `app/mailers/application_mailer.rb`
- Create: `app/mailers/magic_link_mailer.rb`
- Create: `app/views/layouts/mailer.html.erb`
- Create: `app/views/layouts/mailer.text.erb`
- Create: `app/views/magic_link_mailer/sign_in_instructions.html.erb`
- Create: `app/views/magic_link_mailer/sign_in_instructions.text.erb`
- Create: `test/mailers/magic_link_mailer_test.rb`

- [ ] **Step 1: Write the failing mailer test**

```ruby
# test/mailers/magic_link_mailer_test.rb
# frozen_string_literal: true

require 'test_helper'

class MagicLinkMailerTest < ActionMailer::TestCase
  setup do
    @kitchen, @user = create_kitchen_and_user(email: 'chris@example.com', name: 'Chris')
    @magic_link = MagicLink.create!(
      user: @user,
      purpose: :sign_in,
      expires_at: 15.minutes.from_now,
      request_ip: '10.0.0.5',
      request_user_agent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14)'
    )
  end

  test 'sign_in_instructions sets headers' do
    mail = MagicLinkMailer.sign_in_instructions(@magic_link)

    assert_equal ['chris@example.com'], mail.to
    assert_equal 'Sign in to Family Recipes', mail.subject
    assert_equal ['no-reply@localhost'], mail.from
  end

  test 'sign_in_instructions renders the code in both parts' do
    mail = MagicLinkMailer.sign_in_instructions(@magic_link)

    assert_includes mail.html_part.body.to_s, @magic_link.code
    assert_includes mail.text_part.body.to_s, @magic_link.code
  end

  test 'sign_in_instructions renders the request metadata' do
    mail = MagicLinkMailer.sign_in_instructions(@magic_link)
    body = mail.text_part.body.to_s

    assert_includes body, '10.0.0.5'
    assert_includes body, 'Macintosh'
  end

  test 'sign_in_instructions renders a code-bearing URL' do
    mail = MagicLinkMailer.sign_in_instructions(@magic_link)
    body = mail.html_part.body.to_s

    assert_includes body, "code=#{@magic_link.code}"
  end
end
```

- [ ] **Step 2: Run test — expected failure**

```bash
bundle exec ruby -Itest test/mailers/magic_link_mailer_test.rb
```

Expected: `NameError: uninitialized constant MagicLinkMailer`.

- [ ] **Step 3: Create `ApplicationMailer`**

```ruby
# app/mailers/application_mailer.rb
# frozen_string_literal: true

# Base class for all mailers in the app. Currently the only mailer is
# MagicLinkMailer; other transactional mail can subclass this. Delivery
# transport is configured per-environment (see config/environments/*).
class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch('MAILER_FROM_ADDRESS', 'no-reply@localhost') }
  layout 'mailer'
end
```

- [ ] **Step 4: Create `MagicLinkMailer`**

```ruby
# app/mailers/magic_link_mailer.rb
# frozen_string_literal: true

# Delivers short-lived sign-in codes to users. One action,
# sign_in_instructions, takes a MagicLink record and renders both HTML
# and text parts containing the 6-character code, a one-click link, the
# expiry, and the IP / user-agent of the request that issued it. Operators
# without SMTP get the full email in the Rails log (see
# config/environments/production.rb).
#
# - MagicLink: the record being delivered
# - MagicLinksController: receives the code for consumption
class MagicLinkMailer < ApplicationMailer
  def sign_in_instructions(magic_link)
    @magic_link = magic_link
    @code = magic_link.code
    @login_url = sessions_magic_link_url(code: magic_link.code)
    @expires_in_minutes = 15
    @request_ip = magic_link.request_ip
    @request_user_agent = magic_link.request_user_agent

    mail to: magic_link.user.email, subject: 'Sign in to Family Recipes'
  end
end
```

- [ ] **Step 5: Create mailer layouts**

```erb
<%# app/views/layouts/mailer.html.erb %>
<!DOCTYPE html>
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  </head>
  <body>
    <%= yield %>
  </body>
</html>
```

```erb
<%# app/views/layouts/mailer.text.erb %>
<%= yield %>
```

- [ ] **Step 6: Create the email templates**

```erb
<%# app/views/magic_link_mailer/sign_in_instructions.html.erb %>
<h1>Sign in to Family Recipes</h1>

<p>Enter this code on the sign-in page:</p>

<p style="font-size:28px; letter-spacing:4px; font-family:monospace;">
  <strong><%= @code %></strong>
</p>

<p>Or just click this link:</p>

<p><%= link_to 'Sign me in', @login_url %></p>

<p>This code expires in <%= @expires_in_minutes %> minutes.</p>

<hr>

<p><small>Requested from <%= @request_ip %> (<%= @request_user_agent %>).<br>
If you didn't request this, ignore this email — nothing will happen without the code.</small></p>
```

```erb
<%# app/views/magic_link_mailer/sign_in_instructions.text.erb %>
Sign in to Family Recipes

Enter this code on the sign-in page:

    <%= @code %>

Or open this link:

<%= @login_url %>

This code expires in <%= @expires_in_minutes %> minutes.

---

Requested from <%= @request_ip %> (<%= @request_user_agent %>).
If you didn't request this, ignore this email — nothing will happen
without the code.
```

- [ ] **Step 7: Run the mailer test**

The test references `sessions_magic_link_url`, which doesn't exist yet — Task 8 adds the route. Until then, stub the URL helper in the mailer test setup:

```ruby
  setup do
    Rails.application.routes.default_url_options[:host] = 'example.test'
    # ... existing setup
  end
```

And pre-define a placeholder `sessions_magic_link_url` by adding a temporary no-op route at the top of `config/routes.rb` that this task owns:

```ruby
  # Temporarily added in Task 5; finalized in Task 8.
  get 'sessions/magic_link', to: 'magic_links#new', as: :sessions_magic_link
```

Run:

```bash
bundle exec ruby -Itest test/mailers/magic_link_mailer_test.rb
```

Expected: all 4 tests pass. If the `sessions_magic_link_url` helper generates `http://example.test/sessions/magic_link?code=ABC123`, the test assertions should match.

- [ ] **Step 8: Commit**

```bash
git add app/mailers/ app/views/layouts/mailer.html.erb app/views/layouts/mailer.text.erb app/views/magic_link_mailer/ config/routes.rb test/mailers/magic_link_mailer_test.rb
git commit -m "MagicLinkMailer: sign_in_instructions with HTML+text templates"
```

---

## Task 6: Mailer delivery configuration (SMTP + log fallback)

**Files:**
- Modify: `config/environments/production.rb`
- Modify: `config/environments/development.rb`
- Modify: `config/environments/test.rb`
- Modify: `.env.example`

- [ ] **Step 1: Add mailer config to `production.rb`**

Append before the `end` of the configure block:

```ruby
  # Action Mailer — SMTP when configured, Rails logger delivery otherwise.
  # The logger fallback writes the full email to stdout so a homelab
  # operator without SMTP can retrieve the sign-in code from container logs.
  config.action_mailer.delivery_method = ENV['SMTP_ADDRESS'].present? ? :smtp : :logger
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.smtp_settings = {
    address:              ENV['SMTP_ADDRESS'],
    port:                 ENV.fetch('SMTP_PORT', 587).to_i,
    user_name:            ENV['SMTP_USERNAME'],
    password:             ENV['SMTP_PASSWORD'],
    authentication:       ENV.fetch('SMTP_AUTHENTICATION', 'plain').to_sym,
    enable_starttls_auto: true
  }
  config.action_mailer.default_url_options = {
    host:     URI.parse(ENV.fetch('BASE_URL', 'http://localhost:3030')).host,
    protocol: ENV.fetch('BASE_URL', 'http://localhost:3030').start_with?('https') ? 'https' : 'http'
  }
```

- [ ] **Step 2: Add minimal dev config to `development.rb`**

Append before the `end` of the configure block:

```ruby
  config.action_mailer.delivery_method = :logger
  config.action_mailer.perform_deliveries = true
  config.action_mailer.default_url_options = { host: 'localhost', port: 3030 }
```

- [ ] **Step 3: Set test delivery in `test.rb`**

Verify `test.rb` has or add:

```ruby
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: 'example.test' }
```

- [ ] **Step 4: Update `.env.example`**

Append to the existing file:

```bash
# --- Magic link auth (Phase 2) ---

# Public URL of this deployment. Used to render magic link URLs in emails.
BASE_URL=https://familyrecipes.example.com

# From: header for outbound mail.
MAILER_FROM_ADDRESS=no-reply@familyrecipes.example.com

# SMTP settings — leave SMTP_ADDRESS unset to fall back to Rails logger delivery.
# SMTP_ADDRESS=smtp.postmarkapp.com
# SMTP_PORT=587
# SMTP_USERNAME=
# SMTP_PASSWORD=
# SMTP_AUTHENTICATION=plain

# Kitchen creation gating. Set DISABLE_SIGNUPS=true on hosted (fly.io). On
# homelab, leave unset — the /new page will work on a fresh install
# (Kitchen.count == 0) and be closed after the first kitchen exists. Set
# ALLOW_SIGNUPS=true on homelab to allow creating additional kitchens.
# DISABLE_SIGNUPS=true
# ALLOW_SIGNUPS=true
```

- [ ] **Step 5: Run the existing mailer test to confirm nothing broke**

```bash
bundle exec ruby -Itest test/mailers/magic_link_mailer_test.rb
```

Expected: still passes (test environment uses `:test` delivery which keeps deliveries in `ActionMailer::Base.deliveries`).

- [ ] **Step 6: Commit**

```bash
git add config/environments/production.rb config/environments/development.rb config/environments/test.rb .env.example
git commit -m "Configure Action Mailer: SMTP with logger fallback"
```

---

## Task 7: Mailer preview for manual inspection

**Files:**
- Create: `test/mailers/previews/magic_link_mailer_preview.rb`

- [ ] **Step 1: Write the preview**

```ruby
# test/mailers/previews/magic_link_mailer_preview.rb
# frozen_string_literal: true

# Preview magic link email templates at /rails/mailers in development.
class MagicLinkMailerPreview < ActionMailer::Preview
  def sign_in_instructions
    kitchen, user = Kitchen.first, User.first
    raise 'Seed a kitchen/user first: bin/rails db:seed' unless kitchen && user

    link = MagicLink.new(
      user: user,
      kitchen: kitchen,
      purpose: :sign_in,
      code: 'ABCD23',
      expires_at: 15.minutes.from_now,
      request_ip: '10.0.0.5',
      request_user_agent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0)'
    )

    MagicLinkMailer.sign_in_instructions(link)
  end
end
```

- [ ] **Step 2: Run tests to confirm nothing regressed**

```bash
bundle exec rake test TEST=test/mailers
```

Expected: all mailer tests pass.

- [ ] **Step 3: Commit**

```bash
git add test/mailers/previews/magic_link_mailer_preview.rb
git commit -m "MagicLinkMailer preview"
```

---

## Task 8: `PendingAuthToken` concern — signed cookie helpers

The signed cookie that carries the typed email between `/sessions/new`, `/sessions/magic_link`, and `/join` is used in three controllers. Extracting a tiny concern keeps the verifier logic in one place and makes it testable in isolation.

**Files:**
- Create: `app/controllers/concerns/pending_auth_token.rb`
- Create: `test/controllers/concerns/pending_auth_token_test.rb`

- [ ] **Step 1: Write the concern test**

```ruby
# test/controllers/concerns/pending_auth_token_test.rb
# frozen_string_literal: true

require 'test_helper'

class PendingAuthTokenTest < ActiveSupport::TestCase
  # Test the concern by including it into a PORO with stubbed cookies.
  class Harness
    include PendingAuthToken

    def initialize
      @cookies = {}
    end

    attr_reader :cookies

    def cookies
      @cookies_proxy ||= CookieProxy.new(@cookies)
    end

    class CookieProxy
      def initialize(store) = @store = store
      def signed = self
      def [](key) = @store[key]
      def []=(key, value) = (@store[key] = value.is_a?(Hash) ? value[:value] : value)
      def delete(key) = @store.delete(key)
    end
  end

  test 'set_pending_auth_email round-trips the email' do
    h = Harness.new
    h.set_pending_auth_email('chris@example.com')

    assert_equal 'chris@example.com', h.pending_auth_email
  end

  test 'pending_auth_email returns nil when unset' do
    assert_nil Harness.new.pending_auth_email
  end

  test 'pending_auth_email returns nil when tampered' do
    h = Harness.new
    h.cookies.signed[:pending_auth] = 'garbage'

    assert_nil h.pending_auth_email
  end

  test 'clear_pending_auth removes the cookie' do
    h = Harness.new
    h.set_pending_auth_email('chris@example.com')
    h.clear_pending_auth

    assert_nil h.pending_auth_email
  end
end
```

- [ ] **Step 2: Run test — expected failure**

```bash
bundle exec ruby -Itest test/controllers/concerns/pending_auth_token_test.rb
```

Expected: `NameError: uninitialized constant PendingAuthToken`.

- [ ] **Step 3: Implement the concern**

```ruby
# app/controllers/concerns/pending_auth_token.rb
# frozen_string_literal: true

# Encapsulates the signed `:pending_auth` cookie carrying the normalized
# email between /sessions/new -> /sessions/magic_link and between
# /join -> /sessions/magic_link. The cookie is signed with
# MessageVerifier, purpose :pending_auth, 15-minute expiry, so it cannot
# be forged without secret_key_base. The email is what
# MagicLinksController#create cross-checks against the consumed magic
# link's user email to prevent a passerby hijacking a half-finished
# sign-in with a code obtained elsewhere.
#
# - SessionsController: sets the cookie after issuing a magic link
# - JoinsController: sets the cookie after issuing a :join magic link
# - MagicLinksController: reads it in the before_action and clears it on consume
module PendingAuthToken
  extend ActiveSupport::Concern

  PENDING_AUTH_EXPIRY = 15.minutes
  PENDING_AUTH_PURPOSE = :pending_auth

  def set_pending_auth_email(email)
    token = Rails.application.message_verifier(:pending_auth).generate(
      email, purpose: PENDING_AUTH_PURPOSE, expires_in: PENDING_AUTH_EXPIRY
    )
    cookies.signed[:pending_auth] = { value: token, httponly: true, same_site: :lax }
  end

  def pending_auth_email
    raw = cookies.signed[:pending_auth]
    return nil if raw.blank?

    Rails.application.message_verifier(:pending_auth).verified(raw, purpose: PENDING_AUTH_PURPOSE)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def clear_pending_auth
    cookies.delete(:pending_auth)
  end
end
```

- [ ] **Step 4: Run test — expected pass**

```bash
bundle exec ruby -Itest test/controllers/concerns/pending_auth_token_test.rb
```

Expected: 4 pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/concerns/pending_auth_token.rb test/controllers/concerns/pending_auth_token_test.rb
git commit -m "PendingAuthToken concern: signed cookie for email between auth steps"
```

---

## Task 9: Routes update — sessions, magic_links, remove member login link and welcome

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Edit `config/routes.rb`**

Replace the block:

```ruby
  get 'new', to: 'kitchens#new', as: :new_kitchen
  post 'new', to: 'kitchens#create'
  get 'join', to: 'joins#new', as: :join_kitchen
  post 'join', to: 'joins#verify', as: :verify_join
  post 'join/complete', to: 'joins#create', as: :complete_join

  delete 'logout', to: 'sessions#destroy', as: :logout

  post 'transfer', to: 'transfers#create', as: :create_transfer
  get 'transfer/:token', to: 'transfers#show', as: :show_transfer
  post 'members/:id/login_link', to: 'transfers#create_for_member', as: :member_login_link
  get 'welcome', to: 'welcome#show', as: :welcome

  get 'dev/login/:id', to: 'dev_sessions#create', as: :dev_login if Rails.env.local?
```

with:

```ruby
  get 'new', to: 'kitchens#new', as: :new_kitchen
  post 'new', to: 'kitchens#create'
  get 'join', to: 'joins#new', as: :join_kitchen
  post 'join', to: 'joins#verify', as: :verify_join
  post 'join/complete', to: 'joins#create', as: :complete_join

  get 'sessions/new', to: 'sessions#new', as: :new_session
  post 'sessions', to: 'sessions#create', as: :sessions
  get 'sessions/magic_link', to: 'magic_links#new', as: :sessions_magic_link
  post 'sessions/magic_link', to: 'magic_links#create', as: :consume_magic_link
  delete 'logout', to: 'sessions#destroy', as: :logout

  post 'transfer', to: 'transfers#create', as: :create_transfer
  get 'transfer/:token', to: 'transfers#show', as: :show_transfer

  get 'dev/login/:id', to: 'dev_sessions#create', as: :dev_login if Rails.env.local?
```

The routes deleted:
- `post 'members/:id/login_link' ...` (member-to-member login link — Task 15)
- `get 'welcome' ...` (welcome screen — Task 14)

The temporary `sessions/magic_link` route added in Task 5 is replaced with the complete four-route block above.

- [ ] **Step 2: Run `bin/rails routes` to verify**

```bash
bin/rails routes | grep -E 'session|magic_link|welcome|member_login|transfer'
```

Expected: `welcome` and `member_login_link` no longer appear; four session routes present; `transfer` and `show_transfer` still present.

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "Routes: add /sessions/new /sessions/magic_link; drop /welcome and member login link"
```

---

## Task 10: `SessionsController#new` + view

**Files:**
- Modify: `app/controllers/sessions_controller.rb`
- Create: `app/views/sessions/new.html.erb`
- Modify: `test/controllers/sessions_controller_test.rb`

- [ ] **Step 1: Write failing test**

Open `test/controllers/sessions_controller_test.rb`. Delete its current contents (they test the old logout interstitial which we're removing). Replace with:

```ruby
# frozen_string_literal: true

require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen, @user = create_kitchen_and_user(email: 'chris@example.com', name: 'Chris')
  end

  test 'GET /sessions/new renders the email form' do
    get new_session_path
    assert_response :success
    assert_select 'form[action=?]', sessions_path
    assert_select 'input[type=email][name=email]'
  end

  test 'GET /sessions/new redirects to root when already signed in' do
    log_in(@user)
    get new_session_path
    assert_redirected_to root_path
  end
end
```

- [ ] **Step 2: Run test — expected failure**

```bash
bundle exec ruby -Itest test/controllers/sessions_controller_test.rb
```

Expected: routing error (no `new_session_path` wiring in controller yet) or template missing.

- [ ] **Step 3: Rewrite `SessionsController`**

Replace `app/controllers/sessions_controller.rb` with:

```ruby
# frozen_string_literal: true

# Email-first authentication front door. `new` renders a single-field form;
# `create` accepts an email, issues a MagicLink (or renders the same
# "check your email" response for unknown emails for anti-enumeration),
# and stores the pending email in a signed cookie. Code consumption is
# handled by MagicLinksController. `destroy` ends the session and
# redirects to root — no interstitial.
#
# - User: looked up by email
# - MagicLink: created on the sign-in code path
# - MagicLinkMailer: delivers the code
# - PendingAuthToken concern: signed cookie carrying the typed email
# - Authentication concern: terminate_session
class SessionsController < ApplicationController
  include PendingAuthToken

  skip_before_action :set_kitchen_from_path

  layout 'auth'

  rate_limit to: 10, within: 15.minutes, by: -> { request.remote_ip }, only: :create

  def new
    return redirect_to root_path if authenticated?
    # Form rendered by the view
  end

  def destroy
    terminate_session
    cookies[:skip_dev_auto_login] = true if Rails.env.development?
    redirect_to root_path, notice: "You've been signed out."
  end
end
```

(`create` is added in Task 11.)

- [ ] **Step 4: Create the view**

```erb
<%# app/views/sessions/new.html.erb %>
<% content_for :page_title, 'Sign in' %>

<h1>Sign in</h1>

<% if flash[:alert].present? %>
  <p class="flash flash-alert"><%= flash[:alert] %></p>
<% end %>

<%= form_with url: sessions_path, method: :post, local: true do |f| %>
  <label>
    Email address
    <%= f.email_field :email, required: true, autofocus: true, autocomplete: 'email' %>
  </label>
  <%= f.submit 'Send me a sign-in code' %>
<% end %>

<p>New here? <%= link_to 'Use a join code', join_kitchen_path %>.</p>
```

- [ ] **Step 5: Run test — expected pass**

```bash
bundle exec ruby -Itest test/controllers/sessions_controller_test.rb
```

Expected: 2 pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/sessions_controller.rb app/views/sessions/new.html.erb test/controllers/sessions_controller_test.rb
git commit -m "SessionsController#new: email entry form"
```

---

## Task 11: `SessionsController#create` — issue magic link (known) or fake flow (unknown)

**Files:**
- Modify: `app/controllers/sessions_controller.rb`
- Modify: `test/controllers/sessions_controller_test.rb`

- [ ] **Step 1: Add failing tests**

Append to `test/controllers/sessions_controller_test.rb` inside the class:

```ruby
  test 'POST /sessions with known email creates a magic link and delivers mail' do
    assert_difference -> { MagicLink.count } => 1, -> { ActionMailer::Base.deliveries.size } => 1 do
      post sessions_path, params: { email: 'chris@example.com' }
    end

    assert_redirected_to sessions_magic_link_path

    link = MagicLink.order(:created_at).last
    assert_equal @user, link.user
    assert_equal 'sign_in', link.purpose
  end

  test 'POST /sessions with unknown email sends no mail but still redirects (anti-enumeration)' do
    assert_no_difference -> { MagicLink.count } do
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        post sessions_path, params: { email: 'stranger@example.com' }
      end
    end

    assert_redirected_to sessions_magic_link_path
  end

  test 'POST /sessions with an email that matches a user with no memberships is treated as unknown' do
    orphan = User.create!(name: 'Orphan', email: 'orphan@example.com')
    orphan.memberships.destroy_all

    assert_no_difference -> { MagicLink.count } do
      post sessions_path, params: { email: orphan.email }
    end

    assert_redirected_to sessions_magic_link_path
  end

  test 'POST /sessions is rate-limited' do
    11.times { post sessions_path, params: { email: 'chris@example.com' } }
    assert_response :too_many_requests
  end

  test 'POST /sessions sets the pending_auth cookie' do
    post sessions_path, params: { email: 'chris@example.com' }
    assert_not_empty cookies[:pending_auth]
  end
```

Ensure the test file clears deliveries between runs by adding to setup:

```ruby
    ActionMailer::Base.deliveries.clear
```

- [ ] **Step 2: Run tests — expected failure**

```bash
bundle exec ruby -Itest test/controllers/sessions_controller_test.rb
```

Expected: `create` action missing → `AbstractController::ActionNotFound` or routing error.

- [ ] **Step 3: Implement `create`**

Add to `SessionsController` (above the private section if you add one; below `destroy` is fine):

```ruby
  def create
    email = normalize_email(params[:email])
    return redirect_to new_session_path, alert: 'Please enter an email address.' if email.blank?

    user = User.find_by(email:)
    issue_magic_link(user) if user && user.memberships.any?

    set_pending_auth_email(email)
    redirect_to sessions_magic_link_path
  end

  private

  def normalize_email(raw)
    raw.to_s.strip.downcase.presence
  end

  def issue_magic_link(user)
    link = MagicLink.create!(
      user: user,
      purpose: :sign_in,
      expires_at: 15.minutes.from_now,
      request_ip: request.remote_ip,
      request_user_agent: request.user_agent
    )
    MagicLinkMailer.sign_in_instructions(link).deliver_now
  end
```

- [ ] **Step 4: Run tests — expected pass**

```bash
bundle exec ruby -Itest test/controllers/sessions_controller_test.rb
```

Expected: all 7 pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/sessions_controller.rb test/controllers/sessions_controller_test.rb
git commit -m "SessionsController#create: issue magic link, anti-enumeration"
```

---

## Task 12: `MagicLinksController#new` + view

**Files:**
- Create: `app/controllers/magic_links_controller.rb`
- Create: `app/views/magic_links/new.html.erb`
- Create: `test/controllers/magic_links_controller_test.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/controllers/magic_links_controller_test.rb
# frozen_string_literal: true

require 'test_helper'

class MagicLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen, @user = create_kitchen_and_user(email: 'chris@example.com', name: 'Chris')
    ActionMailer::Base.deliveries.clear
  end

  test 'GET /sessions/magic_link without pending_auth cookie redirects to new_session_path' do
    get sessions_magic_link_path
    assert_redirected_to new_session_path
  end

  test 'GET /sessions/magic_link with pending_auth cookie renders the code form' do
    post sessions_path, params: { email: @user.email }
    get sessions_magic_link_path

    assert_response :success
    assert_select 'form[action=?]', sessions_magic_link_path
    assert_select 'input[name=code]'
  end

  test 'GET /sessions/magic_link masks the pending email' do
    post sessions_path, params: { email: @user.email }
    get sessions_magic_link_path

    assert_select 'body', /example\.com/
    assert_select 'body' do |body|
      full = body.text
      assert_no_match(/chris@/, full, 'full email should not appear in the body')
    end
  end
end
```

- [ ] **Step 2: Run test — expected failure**

```bash
bundle exec ruby -Itest test/controllers/magic_links_controller_test.rb
```

Expected: `NameError: uninitialized constant MagicLinksController`.

- [ ] **Step 3: Implement the controller (new action only)**

```ruby
# app/controllers/magic_links_controller.rb
# frozen_string_literal: true

# Consumes short-lived magic link codes issued by SessionsController or
# JoinsController. `new` renders the code-entry form (after the user has
# hit /sessions/new with an email). `create` consumes the code atomically,
# verifies the consumed link's user email against the signed pending_auth
# cookie, starts a session, and redirects to the user's kitchen.
# `:join` purpose links also create a Membership on consume.
#
# - MagicLink: the consumed record
# - User: the authenticated identity (verify_email! on first consume)
# - PendingAuthToken concern: reads and clears the pending_auth cookie
# - Authentication concern: start_new_session_for
class MagicLinksController < ApplicationController
  include PendingAuthToken

  skip_before_action :set_kitchen_from_path
  before_action :require_pending_auth

  layout 'auth'

  rate_limit to: 10, within: 15.minutes, by: -> { request.remote_ip }, only: :create

  def new
    @masked_email = mask_email(pending_auth_email)
  end

  private

  def require_pending_auth
    return if pending_auth_email.present?

    redirect_to new_session_path, alert: 'Please start by entering your email.'
  end

  def mask_email(email)
    return '' if email.blank?

    _, domain = email.split('@', 2)
    "…@#{domain}"
  end
end
```

- [ ] **Step 4: Create the view**

```erb
<%# app/views/magic_links/new.html.erb %>
<% content_for :page_title, 'Check your email' %>

<h1>Check your email</h1>

<p>
  If <strong><%= @masked_email %></strong> is a member of a kitchen, we've
  sent them a 6-character sign-in code.
</p>

<% if flash[:alert].present? %>
  <p class="flash flash-alert"><%= flash[:alert] %></p>
<% end %>

<%= form_with url: sessions_magic_link_path, method: :post, local: true do |f| %>
  <label>
    Sign-in code
    <%= f.text_field :code, required: true, autofocus: true, autocomplete: 'one-time-code',
                     inputmode: 'latin', maxlength: 6 %>
  </label>
  <%= f.submit 'Sign in' %>
<% end %>

<p><%= link_to 'Start over', new_session_path %></p>
```

- [ ] **Step 5: Run tests — expected pass**

```bash
bundle exec ruby -Itest test/controllers/magic_links_controller_test.rb
```

Expected: 3 pass. The "masks the pending email" assertion may need tweaking depending on how your full page renders — the intent is "the part before `@` does not appear in the page text."

- [ ] **Step 6: Commit**

```bash
git add app/controllers/magic_links_controller.rb app/views/magic_links/ test/controllers/magic_links_controller_test.rb
git commit -m "MagicLinksController#new: code entry form"
```

---

## Task 13: `MagicLinksController#create` — consume, verify, session, membership

**Files:**
- Modify: `app/controllers/magic_links_controller.rb`
- Modify: `test/controllers/magic_links_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Append to `test/controllers/magic_links_controller_test.rb`:

```ruby
  test 'POST /sessions/magic_link with valid code starts a session and sets email_verified_at' do
    post sessions_path, params: { email: @user.email }
    @user.update_column(:email_verified_at, nil)
    link = MagicLink.last

    freeze_time do
      post sessions_magic_link_path, params: { code: link.code }

      assert_redirected_to kitchen_root_path(kitchen_slug: @kitchen.slug)
      assert_not_nil cookies[:session_id]
      assert_equal Time.current, @user.reload.email_verified_at
    end
  end

  test 'POST /sessions/magic_link consumes the link (single-use)' do
    post sessions_path, params: { email: @user.email }
    link = MagicLink.last

    post sessions_magic_link_path, params: { code: link.code }
    delete logout_path
    cookies.delete(:pending_auth)

    post sessions_path, params: { email: @user.email }
    post sessions_magic_link_path, params: { code: link.code }

    assert_response :unprocessable_content
    assert_select 'body', /invalid or expired/i
  end

  test 'POST /sessions/magic_link fails closed on code/email mismatch' do
    other_kitchen, other_user = create_kitchen_and_user(email: 'other@example.com', name: 'Other')
    post sessions_path, params: { email: other_user.email }
    other_link = MagicLink.last

    cookies.delete(:pending_auth)
    post sessions_path, params: { email: @user.email }

    post sessions_magic_link_path, params: { code: other_link.code }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test 'POST /sessions/magic_link with :join purpose creates the membership idempotently' do
    kitchen, = create_kitchen_and_user(email: 'owner@example.com', name: 'Owner')
    new_user = User.create!(name: 'Joiner', email: 'joiner@example.com')
    link = MagicLink.create!(
      user: new_user,
      kitchen: kitchen,
      purpose: :join,
      expires_at: 15.minutes.from_now
    )

    set_pending_auth_for(new_user.email)

    assert_difference -> { Membership.count } => 1 do
      post sessions_magic_link_path, params: { code: link.code }
    end

    assert_redirected_to kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  test 'POST /sessions/magic_link with invalid code re-renders with error' do
    post sessions_path, params: { email: @user.email }

    post sessions_magic_link_path, params: { code: 'ZZZZZZ' }
    assert_response :unprocessable_content
  end

  test 'POST /sessions/magic_link is rate-limited' do
    post sessions_path, params: { email: @user.email }

    11.times { post sessions_magic_link_path, params: { code: 'ZZZZZZ' } }
    assert_response :too_many_requests
  end

  private

  def set_pending_auth_for(email)
    verifier = Rails.application.message_verifier(:pending_auth)
    token = verifier.generate(email, purpose: :pending_auth, expires_in: 15.minutes)
    cookies.signed[:pending_auth] = token
  end
```

- [ ] **Step 2: Run tests — expected failure**

```bash
bundle exec ruby -Itest test/controllers/magic_links_controller_test.rb
```

Expected: `create` missing.

- [ ] **Step 3: Implement `create`**

Add inside `MagicLinksController`, before the private section:

```ruby
  def create
    link = MagicLink.consume(params[:code])
    return render_invalid unless link
    return fail_mismatch unless pending_auth_email == link.user.email

    link.user.verify_email!
    ensure_join_membership(link) if link.join?
    start_new_session_for(link.user)
    clear_pending_auth

    redirect_to after_sign_in_path_for(link)
  end
```

Add private helpers inside the same class:

```ruby
  def render_invalid
    flash.now[:alert] = 'Invalid or expired code. Try again or start over.'
    @masked_email = mask_email(pending_auth_email)
    render :new, status: :unprocessable_content
  end

  def fail_mismatch
    clear_pending_auth
    redirect_to new_session_path, alert: 'That code didn\'t match. Please start over.'
  end

  def ensure_join_membership(link)
    ActsAsTenant.with_tenant(link.kitchen) do
      Membership.find_or_create_by!(kitchen: link.kitchen, user: link.user) do |m|
        m.role = 'member'
      end
    end
  end

  def after_sign_in_path_for(link)
    kitchen = link.kitchen || ActsAsTenant.without_tenant { link.user.kitchens.first }
    return root_path unless kitchen

    kitchen_root_path(kitchen_slug: kitchen.slug)
  end
```

- [ ] **Step 4: Run tests — expected pass**

```bash
bundle exec ruby -Itest test/controllers/magic_links_controller_test.rb
```

Expected: all 10 pass (3 from Task 12 + 7 new).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/magic_links_controller.rb test/controllers/magic_links_controller_test.rb
git commit -m "MagicLinksController#create: consume code, verify email, start session"
```

---

## Task 14: Simplify `SessionsController#destroy`; delete logout interstitial view; delete `WelcomeController`

**Files:**
- Modify: `app/controllers/sessions_controller.rb` (already simplified in Task 10 — confirm)
- Delete: `app/views/sessions/destroy.html.erb`
- Delete: `app/controllers/welcome_controller.rb`
- Delete: `app/views/welcome/` (entire directory)
- Delete: `test/controllers/welcome_controller_test.rb`

- [ ] **Step 1: Write failing test for logout behavior**

In `test/controllers/sessions_controller_test.rb`, add:

```ruby
  test 'DELETE /logout terminates session and redirects to root with flash' do
    log_in(@user)
    delete logout_path

    assert_redirected_to root_path
    assert_equal "You've been signed out.", flash[:notice]
    assert_nil cookies[:session_id].presence
  end

  test 'DELETE /logout when not logged in still redirects to root' do
    delete logout_path
    assert_redirected_to root_path
  end
```

- [ ] **Step 2: Run tests — expected pass (the Task 10 rewrite already handles this) or fail**

```bash
bundle exec ruby -Itest test/controllers/sessions_controller_test.rb
```

If the tests fail because the response tries to render the deleted view, that's expected — continue.

- [ ] **Step 3: Delete the logout interstitial view and the welcome feature**

```bash
git rm app/views/sessions/destroy.html.erb
git rm app/controllers/welcome_controller.rb
git rm -r app/views/welcome
git rm test/controllers/welcome_controller_test.rb
```

- [ ] **Step 4: Grep for stragglers and fix any references**

```bash
grep -rn 'welcome_path\|welcome_controller\|WelcomeController\|views/welcome' app config test lib
```

Expected: likely hits in `app/controllers/joins_controller.rb` (`redirect_to_welcome`), which will be fixed in Task 16. No other references.

- [ ] **Step 5: Run sessions test again**

```bash
bundle exec ruby -Itest test/controllers/sessions_controller_test.rb
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Remove logout interstitial and WelcomeController"
```

---

## Task 15: Drop `TransfersController#create_for_member` + UI button

**Files:**
- Modify: `app/controllers/transfers_controller.rb`
- Modify: `test/controllers/transfers_controller_test.rb`
- Modify: `app/views/kitchens/settings/_members.html.erb` (path may differ — grep first)

- [ ] **Step 1: Locate the "Login link" UI**

```bash
grep -rn 'member_login_link\|Login link\|create_for_member' app config test
```

Note the exact file paths that reference `member_login_link_path`, `create_for_member`, or a "Login link" button in the settings dialog. Typical locations: `app/views/settings/*.html.erb` and a Stimulus controller under `app/javascript/controllers/`.

- [ ] **Step 2: Delete the controller action and its helpers**

Edit `app/controllers/transfers_controller.rb`:

1. Remove `create_for_member` (method + its private helpers `resolve_current_kitchen` and `find_kitchen_member` if they are not used by any other action — grep within the file to confirm; if both are only used by `create_for_member`, delete them).
2. Update the class header comment: change `"Two token types: :transfer (self, 5 min, QR code) and :login (member-to-member, 24 hours, copyable link)"` to `"One token type: :transfer (self, 5 min, QR code)."` Remove `:login`-related wording.
3. Remove the `:login` purpose fallback in `resolve_token` — it becomes:

```ruby
  def resolve_token
    User.find_signed(params[:token], purpose: :transfer)
  end
```

- [ ] **Step 3: Delete the UI button**

Open each view file found in Step 1. Remove the "Login link" button/form element, keeping the rest of the member row intact. Delete any Stimulus controller code that only wires this button.

- [ ] **Step 4: Update `test/controllers/transfers_controller_test.rb`**

Delete all tests whose name mentions `create_for_member`, `login_link`, or the `:login` purpose. The self-transfer tests (`create`, `show` with `:transfer` purpose) stay.

- [ ] **Step 5: Run transfers tests**

```bash
bundle exec ruby -Itest test/controllers/transfers_controller_test.rb
```

Expected: all remaining tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Drop member-to-member login links; keep self-transfer QR"
```

---

## Task 16: Rewrite `JoinsController#create` — issue a `:join` magic link instead of a session

**Files:**
- Modify: `app/controllers/joins_controller.rb`
- Modify: `test/controllers/joins_controller_test.rb`

- [ ] **Step 1: Rewrite failing tests in `joins_controller_test.rb`**

Existing tests assert that `create` starts a session and redirects to `welcome_path`. Replace the relevant test group with:

```ruby
  test 'POST /join/complete with known email creates a :join magic link and delivers mail' do
    kitchen, owner = create_kitchen_and_user(email: 'owner@example.com', name: 'Owner')
    signed = sign_kitchen_id(kitchen.id)
    User.create!(name: 'Joiner', email: 'joiner@example.com')

    ActionMailer::Base.deliveries.clear

    assert_difference -> { MagicLink.where(purpose: :join).count } => 1,
                      -> { ActionMailer::Base.deliveries.size } => 1 do
      post complete_join_path, params: { signed_kitchen_id: signed, email: 'joiner@example.com' }
    end

    assert_redirected_to sessions_magic_link_path

    link = MagicLink.order(:created_at).last
    assert_equal kitchen, link.kitchen
    assert_equal 'join', link.purpose
    assert_nil link.user.memberships.find_by(kitchen: kitchen), 'membership should not exist yet'
  end

  test 'POST /join/complete with new email creates User, magic link, and mail' do
    kitchen, = create_kitchen_and_user(email: 'owner@example.com', name: 'Owner')
    signed = sign_kitchen_id(kitchen.id)

    ActionMailer::Base.deliveries.clear

    assert_difference -> { User.count } => 1, -> { MagicLink.count } => 1 do
      post complete_join_path, params: {
        signed_kitchen_id: signed, email: 'new@example.com', name: 'New Person'
      }
    end

    assert_redirected_to sessions_magic_link_path
    user = User.find_by(email: 'new@example.com')
    assert_equal 'New Person', user.name
  end

  test 'POST /join/complete with missing name re-renders the name form' do
    kitchen, = create_kitchen_and_user(email: 'owner@example.com', name: 'Owner')
    signed = sign_kitchen_id(kitchen.id)

    assert_no_difference -> { MagicLink.count } do
      post complete_join_path, params: { signed_kitchen_id: signed, email: 'new@example.com' }
    end

    assert_response :success
    assert_select 'input[name=name]'
  end

  private

  def sign_kitchen_id(id)
    Rails.application.message_verifier(:join).generate(id, purpose: :join, expires_in: 15.minutes)
  end
```

Delete any existing tests that assert `start_new_session_for` or `redirect_to welcome_path`.

- [ ] **Step 2: Run tests — expected failures**

```bash
bundle exec ruby -Itest test/controllers/joins_controller_test.rb
```

Expected: new behavior not yet implemented.

- [ ] **Step 3: Rewrite `JoinsController#create`**

Replace the body of `create` and the `authenticate_or_register`, `authenticate_existing`, `register_new_member`, `ensure_membership`, and `redirect_to_welcome` methods. Final shape of the controller:

```ruby
# frozen_string_literal: true

# Step 1 of the invitation flow: visitor enters a join code, which we
# validate and use to issue a :join magic link. Membership creation is
# deferred to MagicLinksController#create so the "no membership without
# verified email" invariant lives in one place.
#
# - Kitchen: join code lookup
# - MagicLink: created with purpose: :join and the target kitchen
# - MagicLinkMailer: delivers the 6-character code
# - PendingAuthToken concern: signed cookie carrying the typed email
class JoinsController < ApplicationController
  include PendingAuthToken

  skip_before_action :set_kitchen_from_path

  layout 'auth'

  rate_limit to: 10, within: 1.hour, by: -> { request.remote_ip }, only: :verify

  def new; end

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

    email = normalize_email(params[:email])
    return redirect_to join_kitchen_path, alert: 'Please enter your email.' if email.blank?

    return render_name_form(kitchen, email) if new_user_missing_name?(email)

    issue_join_link(kitchen, email)
  rescue ActiveRecord::RecordInvalid => error
    @errors = error.record.errors.full_messages
    render_name_form(kitchen, email)
  end

  private

  def normalize_email(raw)
    raw.to_s.strip.downcase.presence
  end

  def new_user_missing_name?(email)
    params[:name].blank? && User.find_by(email:).nil?
  end

  def issue_join_link(kitchen, email)
    user = User.find_or_create_by!(email:) do |u|
      u.name = params[:name].to_s.presence || email.split('@').first
    end
    link = MagicLink.create!(
      user:,
      kitchen:,
      purpose: :join,
      expires_at: 15.minutes.from_now,
      request_ip: request.remote_ip,
      request_user_agent: request.user_agent
    )
    MagicLinkMailer.sign_in_instructions(link).deliver_now
    set_pending_auth_email(email)
    redirect_to sessions_magic_link_path
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

- [ ] **Step 4: Run tests — expected pass**

```bash
bundle exec ruby -Itest test/controllers/joins_controller_test.rb
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/joins_controller.rb test/controllers/joins_controller_test.rb
git commit -m "JoinsController#create: issue :join magic link instead of starting session"
```

---

## Task 17: `Kitchen.accepting_signups?` + `KitchensController` gate

**Files:**
- Modify: `app/models/kitchen.rb`
- Modify: `app/controllers/kitchens_controller.rb`
- Modify: `test/controllers/kitchens_controller_test.rb`
- Create: `test/models/kitchen_accepting_signups_test.rb`

- [ ] **Step 1: Write failing model tests**

```ruby
# test/models/kitchen_accepting_signups_test.rb
# frozen_string_literal: true

require 'test_helper'

class KitchenAcceptingSignupsTest < ActiveSupport::TestCase
  setup do
    ActsAsTenant.without_tenant { Kitchen.delete_all }
    @original_disable = ENV['DISABLE_SIGNUPS']
    @original_allow = ENV['ALLOW_SIGNUPS']
    ENV.delete('DISABLE_SIGNUPS')
    ENV.delete('ALLOW_SIGNUPS')
  end

  teardown do
    ENV['DISABLE_SIGNUPS'] = @original_disable
    ENV['ALLOW_SIGNUPS']   = @original_allow
  end

  test 'accepts signups on a fresh install with no env vars' do
    assert Kitchen.accepting_signups?
  end

  test 'rejects signups after the first kitchen when no env vars are set' do
    create_kitchen_and_user(email: 'owner@example.com', name: 'Owner')

    assert_not Kitchen.accepting_signups?
  end

  test 'DISABLE_SIGNUPS=true wins even on a fresh install' do
    ENV['DISABLE_SIGNUPS'] = 'true'

    assert_not Kitchen.accepting_signups?
  end

  test 'ALLOW_SIGNUPS=true re-enables after the first kitchen' do
    create_kitchen_and_user(email: 'owner@example.com', name: 'Owner')
    ENV['ALLOW_SIGNUPS'] = 'true'

    assert Kitchen.accepting_signups?
  end

  test 'DISABLE_SIGNUPS beats ALLOW_SIGNUPS' do
    create_kitchen_and_user(email: 'owner@example.com', name: 'Owner')
    ENV['ALLOW_SIGNUPS']   = 'true'
    ENV['DISABLE_SIGNUPS'] = 'true'

    assert_not Kitchen.accepting_signups?
  end
end
```

- [ ] **Step 2: Run tests — expected failure**

```bash
bundle exec ruby -Itest test/models/kitchen_accepting_signups_test.rb
```

- [ ] **Step 3: Add the method to `Kitchen`**

In `app/models/kitchen.rb`, add inside the class body:

```ruby
  def self.accepting_signups?
    return false if ENV['DISABLE_SIGNUPS'] == 'true'

    ActsAsTenant.without_tenant do
      return true if Kitchen.none?
    end

    ENV['ALLOW_SIGNUPS'] == 'true'
  end
```

- [ ] **Step 4: Run model tests — expected pass**

```bash
bundle exec ruby -Itest test/models/kitchen_accepting_signups_test.rb
```

- [ ] **Step 5: Write failing controller tests**

Append to `test/controllers/kitchens_controller_test.rb`:

```ruby
  test 'GET /new returns 404 when signups are disabled' do
    ENV['DISABLE_SIGNUPS'] = 'true'
    create_kitchen_and_user(email: 'owner@example.com', name: 'Owner')

    get new_kitchen_path
    assert_response :not_found
  ensure
    ENV.delete('DISABLE_SIGNUPS')
  end

  test 'POST /new returns 404 when signups are disabled' do
    ENV['DISABLE_SIGNUPS'] = 'true'
    create_kitchen_and_user(email: 'owner@example.com', name: 'Owner')

    post new_kitchen_path, params: { name: 'A', email: 'a@example.com', kitchen_name: 'Test' }
    assert_response :not_found
  ensure
    ENV.delete('DISABLE_SIGNUPS')
  end

  test 'GET /new returns 404 on a populated homelab without ALLOW_SIGNUPS' do
    create_kitchen_and_user(email: 'owner@example.com', name: 'Owner')

    get new_kitchen_path
    assert_response :not_found
  end

  test 'GET /new returns 200 on a fresh install' do
    ActsAsTenant.without_tenant { Kitchen.delete_all }

    get new_kitchen_path
    assert_response :success
  end
```

- [ ] **Step 6: Add the before_action in `KitchensController`**

```ruby
  before_action :enforce_accepting_signups
```

(Place above the existing `before_action :redirect_if_logged_in`.)

Add the private method:

```ruby
  def enforce_accepting_signups
    head :not_found unless Kitchen.accepting_signups?
  end
```

- [ ] **Step 7: Run all tests — expected pass**

```bash
bundle exec ruby -Itest test/controllers/kitchens_controller_test.rb
bundle exec ruby -Itest test/models/kitchen_accepting_signups_test.rb
```

- [ ] **Step 8: Commit**

```bash
git add app/models/kitchen.rb app/controllers/kitchens_controller.rb test/models/kitchen_accepting_signups_test.rb test/controllers/kitchens_controller_test.rb
git commit -m "Kitchen.accepting_signups?: env-var gate for /new"
```

---

## Task 18: `rake kitchen:create` task for seeding hosted kitchens from a shell

**Files:**
- Modify: `lib/tasks/kitchen.rake`

- [ ] **Step 1: Write the task**

Append to `lib/tasks/kitchen.rake` inside the `namespace :kitchen do` block:

```ruby
  desc 'Create a kitchen + owner user (args: name, email, owner_name)'
  task :create, %i[name email owner_name] => :environment do |_t, args|
    abort 'Usage: rake "kitchen:create[Kitchen Name,owner@example.com,Owner Name]"' if args.to_a.any?(&:blank?)

    ActsAsTenant.without_tenant do
      ActiveRecord::Base.transaction do
        kitchen = Kitchen.create!(
          name: args[:name],
          slug: args[:name].to_s.parameterize.presence || 'kitchen'
        )
        user = User.find_or_create_by!(email: args[:email]) { |u| u.name = args[:owner_name] }
        Membership.create!(kitchen: kitchen, user: user, role: 'owner')
        MealPlan.create!(kitchen: kitchen)

        puts "Created kitchen: #{kitchen.name} (#{kitchen.slug})"
        puts "Owner: #{user.name} <#{user.email}>"
        puts "Join code: #{kitchen.join_code}"
      end
    end
  end
```

- [ ] **Step 2: Verify from a Rails runner**

```bash
bin/rails runner "puts Rake::Task['kitchen:create'].present? ? 'loaded' : 'missing'"
bin/rails runner "ActiveRecord::Base.transaction { Rake::Task['kitchen:create'].invoke('Test','t@example.com','Tester'); raise ActiveRecord::Rollback }"
```

Expected: prints "Created kitchen: Test (test)", owner line, and a join code. The rollback keeps the DB clean.

- [ ] **Step 3: Commit**

```bash
git add lib/tasks/kitchen.rake
git commit -m "rake kitchen:create: seed a kitchen + owner from the shell"
```

---

## Task 19: Delete trusted-header auth path entirely

This is the biggest single deletion. It touches ApplicationController, an initializer, a lib module, and tests.

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/models/user.rb` (class comment)
- Delete: `config/initializers/trusted_proxy.rb`
- Delete: `config/initializers/trusted_proxy_warning.rb`
- Delete: `lib/familyrecipes/trusted_proxy_config.rb`
- Delete: `test/lib/familyrecipes/trusted_proxy_config_test.rb`
- Delete: `test/controllers/header_auth_test.rb`
- Modify: `test/security/auth_bypass.spec.mjs` (remove any header-spoof cases; unchanged if none)
- Modify: `README.md` (remove Authelia / trusted-header sections)
- Modify: `docs/help/` (remove any Authelia setup page — grep first)
- Modify: `config/debride_allowlist.txt` (remove trusted-header entries)

- [ ] **Step 1: Write failing test proving trusted-header auth is gone**

Add to `test/controllers/auth_test.rb` (which already exists):

```ruby
  test 'trusted-header environment variables are ignored' do
    get root_path, env: {
      'REMOTE_ADDR'  => '127.0.0.1',
      'HTTP_REMOTE_USER' => 'alice',
      'HTTP_REMOTE_EMAIL' => 'alice@example.com',
      'HTTP_REMOTE_NAME' => 'Alice'
    }

    assert_nil cookies[:session_id].presence
  end
```

- [ ] **Step 2: Run test — expected failure**

```bash
bundle exec ruby -Itest test/controllers/auth_test.rb -n test_trusted-header_environment_variables_are_ignored
```

Expected: the session cookie is set because the header-auth path is still wired. Test fails.

- [ ] **Step 3: Gut `ApplicationController`**

Open `app/controllers/application_controller.rb`. Replace:

1. The entire class comment block at the top (lines 1-31) with:

```ruby
# frozen_string_literal: true

# Central before_action pipeline: resume session -> auto-login in dev ->
# set tenant from path. Public reads are allowed
# (allow_unauthenticated_access); write paths and member-only pages call
# require_membership. Also manages the optional kitchen_slug URL scope and
# cache headers for member-only pages.
#
# Collaborators:
# - Authentication concern: session lifecycle (resume, start, terminate)
# - Kitchen / acts_as_tenant: multi-tenant scoping via set_current_tenant
# - User / Membership: session-bound identity
```

2. Remove `before_action :authenticate_from_headers` (keep `resume_session`, `auto_login_in_development`, `set_kitchen_from_path`).

3. Delete the methods: `authenticate_from_headers`, `trusted_header_identity`, `auto_join_sole_kitchen`. Leave everything else untouched.

- [ ] **Step 4: Delete the supporting files**

```bash
git rm config/initializers/trusted_proxy.rb
git rm config/initializers/trusted_proxy_warning.rb
git rm lib/familyrecipes/trusted_proxy_config.rb
git rm test/lib/familyrecipes/trusted_proxy_config_test.rb
git rm test/controllers/header_auth_test.rb
```

- [ ] **Step 5: Grep for any remaining references**

```bash
grep -rn 'trusted_proxy\|TrustedProxyConfig\|authenticate_from_headers\|HTTP_REMOTE_USER\|HTTP_REMOTE_EMAIL\|TRUSTED_PROXY_IPS\|TRUSTED_HEADER_' app lib config test docs
```

Expected hits to fix:
- `README.md` — delete any "Authelia" / "trusted header" sections
- `docs/help/*.md` — any Authelia setup page (delete or rewrite)
- `config/debride_allowlist.txt` — remove entries pointing at trusted-proxy code
- `CLAUDE.md` — this is rewritten in Task 22; leave for now

Remove each remaining reference.

- [ ] **Step 6: Update `app/models/user.rb` class comment**

(Already done in Task 4 — verify.)

- [ ] **Step 7: Run the failing test from Step 1**

```bash
bundle exec ruby -Itest test/controllers/auth_test.rb
```

Expected: the trusted-header ignore test passes; other tests in the file still pass.

- [ ] **Step 8: Run the full test suite to catch fallout**

```bash
bundle exec rake test
```

Expected: all pass. If anything in the `auth_test.rb`, `tenant_isolation_test.rb`, or controller tests fails because it relied on trusted-header shortcuts, fix the individual test by using `log_in(user)` instead.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Delete trusted-header auth: ApplicationController, initializer, lib, tests, docs"
```

---

## Task 20: End-to-end integration test (Minitest)

**Files:**
- Create: `test/integration/auth_flow_test.rb`

- [ ] **Step 1: Write the full-flow test**

```ruby
# test/integration/auth_flow_test.rb
# frozen_string_literal: true

require 'test_helper'

class AuthFlowTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen, @user = create_kitchen_and_user(email: 'chris@example.com', name: 'Chris')
    ActionMailer::Base.deliveries.clear
    @user.update_column(:email_verified_at, nil)
  end

  test 'full magic link sign-in flow: email -> mailer -> code -> session' do
    get new_session_path
    assert_response :success

    assert_difference -> { ActionMailer::Base.deliveries.size } => 1 do
      post sessions_path, params: { email: @user.email }
    end
    assert_redirected_to sessions_magic_link_path

    delivered = ActionMailer::Base.deliveries.last
    assert_equal [@user.email], delivered.to

    code = MagicLink.order(:created_at).last.code
    assert_match(/\A[A-HJ-NP-Z2-9]{6}\z/, code)

    get sessions_magic_link_path
    assert_response :success

    post sessions_magic_link_path, params: { code: code }
    assert_redirected_to kitchen_root_path(kitchen_slug: @kitchen.slug)

    follow_redirect!
    assert_response :success

    assert_not_nil @user.reload.email_verified_at
  end
end
```

- [ ] **Step 2: Run it**

```bash
bundle exec ruby -Itest test/integration/auth_flow_test.rb
```

Expected: passes.

- [ ] **Step 3: Commit**

```bash
git add test/integration/auth_flow_test.rb
git commit -m "Integration test: full magic link auth flow"
```

---

## Task 21: Playwright security spec — `magic_link_auth.spec.mjs`

**Files:**
- Create: `test/security/magic_link_auth.spec.mjs`
- Modify: `test/security/auth_bypass.spec.mjs` (refer to new routes where applicable)
- Verify: `test/security/seed_security_kitchens.rb` still works (it may reference trusted-header paths)

- [ ] **Step 1: Seed the security fixtures and start the dev server**

```bash
bin/rails runner test/security/seed_security_kitchens.rb
bin/dev
```

(Run `bin/dev` in a separate terminal; subsequent commands assume the server is listening on `http://rika:3030`. Use `rika` hostname per user preference.)

- [ ] **Step 2: Read `test/security/helpers.mjs`** to understand available helpers (`fetchAnonymousWithCsrf`, `logIn`, etc.)

- [ ] **Step 3: Write the spec**

```javascript
// test/security/magic_link_auth.spec.mjs
// Runs against a live dev server on port 3030.

import { test, expect } from '@playwright/test';

const BASE = process.env.BASE_URL || 'http://rika:3030';

test.describe('magic link auth', () => {
  test('known email → magic link issued; returns check-your-email screen', async ({ page }) => {
    await page.goto(`${BASE}/sessions/new`);
    await page.fill('input[type=email]', 'chris@example.com');
    await page.click('button[type=submit], input[type=submit]');
    await expect(page).toHaveURL(/\/sessions\/magic_link/);
    await expect(page.locator('body')).toContainText(/check your email/i);
  });

  test('unknown email → identical screen (anti-enumeration)', async ({ page }) => {
    await page.goto(`${BASE}/sessions/new`);
    await page.fill('input[type=email]', 'nobody-' + Date.now() + '@example.com');
    await page.click('button[type=submit], input[type=submit]');
    await expect(page).toHaveURL(/\/sessions\/magic_link/);
    await expect(page.locator('body')).toContainText(/check your email/i);
  });

  test('invalid code is rejected with an error and does not sign in', async ({ page }) => {
    await page.goto(`${BASE}/sessions/new`);
    await page.fill('input[type=email]', 'chris@example.com');
    await page.click('button[type=submit], input[type=submit]');

    await page.fill('input[name=code]', 'ZZZZZZ');
    await page.click('button[type=submit], input[type=submit]');

    await expect(page.locator('body')).toContainText(/invalid or expired/i);
    const cookies = await page.context().cookies();
    expect(cookies.find(c => c.name === 'session_id')).toBeUndefined();
  });

  test('brute force attempts are rate-limited', async ({ page, request }) => {
    await page.goto(`${BASE}/sessions/new`);
    await page.fill('input[type=email]', 'chris@example.com');
    await page.click('button[type=submit], input[type=submit]');

    const csrf = await page.getAttribute('meta[name=csrf-token]', 'content');
    let lastStatus = 0;
    for (let i = 0; i < 15; i++) {
      const r = await request.post(`${BASE}/sessions/magic_link`, {
        form: { code: 'ZZZZZZ', authenticity_token: csrf },
        headers: { 'x-csrf-token': csrf }
      });
      lastStatus = r.status();
      if (lastStatus === 429) break;
    }
    expect(lastStatus).toBe(429);
  });
});
```

Adjust the form selectors (`button[type=submit]` etc.) to match the actual rendered markup from Task 10 and Task 12.

- [ ] **Step 4: Run the spec**

```bash
npx playwright test test/security/magic_link_auth.spec.mjs
```

Expected: all 4 tests pass.

- [ ] **Step 5: Update `auth_bypass.spec.mjs` if it references removed routes**

```bash
grep -n 'welcome\|member_login\|HTTP_REMOTE' test/security/auth_bypass.spec.mjs
```

Remove or rewrite any test referencing `welcome_path`, `member_login_link`, or trusted-header headers. Self-transfer (`/transfer`) cases stay.

- [ ] **Step 6: Run the full security suite**

```bash
npx playwright test test/security/
```

Expected: all specs pass. If `auth_security.spec.mjs` or `tenant_isolation.spec.mjs` break, fix their references — no behavioral changes needed.

- [ ] **Step 7: Commit**

```bash
git add test/security/magic_link_auth.spec.mjs test/security/auth_bypass.spec.mjs
git commit -m "Playwright: magic link auth security spec"
```

---

## Task 22: Documentation — README, CLAUDE.md, .env.example already done

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Rewrite the README's auth/deploy section**

Open `README.md`. Locate the sections that mention:
- Authelia
- Trusted-header auth
- `HTTP_REMOTE_USER`
- `TRUSTED_PROXY_IPS`

Delete those sections entirely. In their place, add:

```markdown
## Authentication

Family Recipes uses email-verified magic link sign-in. To sign in:

1. Visit `/sessions/new`
2. Type your email address
3. Check your inbox for a 6-character code
4. Enter the code — you're signed in

If your deployment does not have SMTP configured, the magic link email is
written to the Rails log (stdout). Homelab operators can retrieve the code
with `docker logs familyrecipes | grep -A20 "Sign in to Family Recipes"`.

### Configuring SMTP

Set these environment variables for outbound email:

- `BASE_URL` — the public URL of your deployment (e.g., `https://recipes.example.com`)
- `MAILER_FROM_ADDRESS` — the `From:` address
- `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` — SMTP credentials
- `SMTP_AUTHENTICATION` (default: `plain`)

Any SMTP provider works — Postmark, Resend, SendGrid, AWS SES, Mailgun, or a
self-hosted relay.

### Kitchen creation

On a fresh install with no kitchens, visit `/new` to create the first
kitchen. After the first kitchen exists, `/new` is closed unless the operator
opts in by setting `ALLOW_SIGNUPS=true`.

For hosted deployments (fly.io, etc.), set `DISABLE_SIGNUPS=true` to close
`/new` entirely and seed kitchens from a shell:

```bash
bin/rake "kitchen:create[Kitchen Name,owner@example.com,Owner Name]"
```

This prints the join code for the operator to share with the first member.
```

- [ ] **Step 2: Rewrite the CLAUDE.md auth section**

In `CLAUDE.md`, locate the **Auth flow** paragraph under **Architecture** and replace it with:

```markdown
**Auth flow.** Email-verified magic link sign-in: `/sessions/new` accepts an
email, `MagicLink` issues a 6-character single-use code via
`MagicLinkMailer`, and `MagicLinksController` consumes it — verifying the
consumed link's user email against a signed `:pending_auth` cookie — to
start a session. `JoinsController` reuses the same mechanism with
`purpose: :join` so membership is only created after email verification.
Kitchen creation (`/new`) is gated by `Kitchen.accepting_signups?`
(`DISABLE_SIGNUPS` / `ALLOW_SIGNUPS` env vars); hosted deployments seed
kitchens via `rake kitchen:create`. SMTP is optional — logger delivery is
the homelab fallback. `WelcomeController` and member-to-member login links
were removed; self-transfer QR (`/transfer`) remains.
```

Delete the **Trusted-header auto-join** paragraph entirely. In the env vars
/ secrets section (if present), remove `TRUSTED_PROXY_IPS` and
`TRUSTED_HEADER_USER/EMAIL/NAME`, and add `BASE_URL`, `MAILER_FROM_ADDRESS`,
`SMTP_*`, `DISABLE_SIGNUPS`, `ALLOW_SIGNUPS`.

- [ ] **Step 3: Scan for stale references**

```bash
grep -rn 'Authelia\|trusted.header\|HTTP_REMOTE_USER' README.md CLAUDE.md docs/help/
```

Expected: zero results. Fix any remaining hits.

- [ ] **Step 4: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "Docs: rewrite auth sections for magic link flow"
```

---

## Task 23: Final validation

**Files:** (none — validation only)

- [ ] **Step 1: Run the full Ruby test suite**

```bash
bundle exec rake test
```

Expected: all pass. Fix any stragglers — likely Bullet N+1 warnings on magic link consume (add `.includes(:user, :kitchen)` if flagged).

- [ ] **Step 2: Run RuboCop**

```bash
bundle exec rubocop
```

Expected: 0 offenses.

- [ ] **Step 3: Run Brakeman**

```bash
bundle exec rake security
```

Expected: 0 medium+ warnings. Add entries to `config/brakeman.ignore` only if a false positive appears and is documented.

- [ ] **Step 4: Run `rake lint:html_safe`**

```bash
bundle exec rake lint:html_safe
```

Expected: 0 unauditeds. If any added view uses `.html_safe` or `raw()`, add it to `config/html_safe_allowlist.yml` with a comment.

- [ ] **Step 5: Run the full Playwright security suite**

```bash
bin/rails runner test/security/seed_security_kitchens.rb
npx playwright test test/security/
```

Expected: all specs pass.

- [ ] **Step 6: Manual smoke test**

Start `bin/dev`. Visit `http://rika:3030/sessions/new`. Sign in with a seeded email. Confirm:

- The email form renders
- Submitting produces a redirect to `/sessions/magic_link`
- The Rails log prints the magic link email (logger delivery in development)
- Pasting the code signs you in
- `/logout` redirects to `/` with a flash and no interstitial
- `/new` on a populated install shows a 404 (or 200 if `Kitchen.count == 0`)
- Visiting `/welcome` returns 404 (route deleted)
- Visiting `/members/:id/login_link` returns 404 (route deleted)

- [ ] **Step 7: Push the branch and open a draft PR**

```bash
git push -u origin feature/magic-link-auth
gh pr create --draft --title "Magic link auth (Phase 2): fly.io beta readiness" \
  --body "$(cat <<'EOF'
## Summary
- Replace join-code-as-password with email-verified magic link sign-in
- Drop the trusted-header / Authelia auth path entirely
- Gate `/new` for invite-only fly.io beta via `DISABLE_SIGNUPS`
- Demote `WelcomeController` and member-to-member login links

## Test plan
- [x] `rake test`
- [x] `rubocop`
- [x] `rake security` (Brakeman)
- [x] `rake lint:html_safe`
- [x] Playwright `test/security/` suite
- [x] Manual smoke test of full flow on `bin/dev`

## Deploy steps (fly.io)
1. Merge PR, let CI build image
2. `fly secrets set DISABLE_SIGNUPS=true BASE_URL=... MAILER_FROM_ADDRESS=... SMTP_*`
3. `fly deploy`
4. `fly ssh console -C "bin/rake db:migrate"`
5. `fly ssh console -C "bin/rake 'kitchen:create[Name,email@example.com,Owner]'"`
6. Share the printed join code with first member

Spec: `docs/superpowers/specs/2026-04-10-magic-link-auth-design.md`
EOF
)"
```

(Open as draft first so reviewers can see CI results before being asked for sign-off.)

---
