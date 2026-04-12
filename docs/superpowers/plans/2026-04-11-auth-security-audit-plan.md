# Auth Security Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close seven verified auth vulnerabilities and add cohesive hardening (audit logging, session-drift detection, removing the `auto_login_in_development` footgun) in a single PR against `feature/security-audit`.

**Architecture:** Bundle all fixes on one branch. Each task is TDD: failing test → implementation → green → commit. Tasks are ordered so that high-risk changes (session cookie cutover) land last with a warm, tested codebase. Cross-cutting observability via a narrow `SecurityEventLogger` service object is introduced early so later tasks can instrument against it.

**Tech Stack:** Rails 8, SQLite (primary + cable), Minitest, `ActsAsTenant`, `cookies.encrypted`, Rails 8 `rate_limit`, Bullet (N+1 detection in tests), Brakeman, Playwright (pen tests in `test/security/`).

**Spec:** `docs/superpowers/specs/2026-04-11-auth-security-audit-design.md` — read before starting.

---

## File Structure

**Created:**
- `app/services/security_event_logger.rb` — tagged JSON audit log emitter (~15 lines)
- `test/services/security_event_logger_test.rb` — unit tests
- `test/integration/session_drift_test.rb` — drift-logging integration test
- `test/security/timing_invariance.spec.mjs` — Playwright timing-variance test

**Modified:**
- `app/controllers/application_controller.rb` — remove `auto_login_in_development`
- `app/controllers/sessions_controller.rb` — `deliver_later`, log events
- `app/controllers/magic_links_controller.rb` — unify error responses, log events
- `app/controllers/joins_controller.rb` — rate limit `:create`, `deliver_later`, log events
- `app/controllers/dev_sessions_controller.rb` — drop `skip_dev_auto_login` plumbing
- `app/controllers/transfers_controller.rb` — log transfer-token consume
- `app/controllers/concerns/authentication.rb` — `signed_id` session cookie, drift detection, log session lifecycle
- `app/controllers/concerns/pending_auth_token.rb` — simplify to encrypted cookie
- `app/channels/application_cable/connection.rb` — `find_signed` session lookup
- `app/models/magic_link.rb` — opportunistic `cleanup_expired` call inside `consume`
- `test/test_helper.rb` — include `ActiveJob::TestHelper` for `assert_enqueued_emails`
- `test/controllers/sessions_controller_test.rb` — update mailer assertions, add event assertions
- `test/controllers/magic_links_controller_test.rb` — unified error path, event assertions
- `test/controllers/joins_controller_test.rb` — rate limit, event assertions
- `test/controllers/dev_sessions_controller_test.rb` — verify no skip cookie path
- `test/security/helpers.mjs` — remove `skip_dev_auto_login` plumbing
- `test/security/auth_security.spec.mjs` — add `/join/complete` rate-limit case

**Deleted:**
- `docs/superpowers/plans/2026-04-10-harden-trusted-header-auth-plan.md` — obsoleted cleanup

---

## Task 1: Remove `auto_login_in_development`

Goal: Delete the dev-only auto-login and everything propping it up. Catches the footgun where a production deploy misconfigured to run in `development` mode would silently hand out sessions.

**Files:**
- Modify: `app/controllers/application_controller.rb` (delete `before_action` on line 23 and method at lines 61-70)
- Modify: `app/controllers/sessions_controller.rb` (line 39)
- Modify: `app/controllers/dev_sessions_controller.rb` (line 19)
- Modify: `test/security/helpers.mjs` (remove `skip_dev_auto_login=1` plumbing)
- Modify: Any test helpers or tests that relied on implicit auto-login

- [ ] **Step 1.1: Write a failing "method is gone" regression test**

Create or append to `test/controllers/application_controller_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class ApplicationControllerTest < ActiveSupport::TestCase
  test 'ApplicationController does not define auto_login_in_development' do
    refute ApplicationController.private_instance_methods(false).include?(:auto_login_in_development),
           'auto_login_in_development must not exist — deleted in the auth security audit as a production footgun'
  end

  test 'ApplicationController before_action chain does not reference auto_login_in_development' do
    callback_names = ApplicationController._process_action_callbacks.map(&:filter)

    refute_includes callback_names, :auto_login_in_development
  end
end
```

- [ ] **Step 1.2: Run test to verify it fails**

```bash
ruby -Itest test/controllers/application_controller_test.rb
```

Expected: both assertions FAIL (`auto_login_in_development` is currently in both the methods list and the callback chain).

- [ ] **Step 1.3: Delete the method and its `before_action` from `ApplicationController`**

Edit `app/controllers/application_controller.rb`:

Remove line 23:
```ruby
  before_action :auto_login_in_development
```

Remove the method at lines 61-70:
```ruby
  def auto_login_in_development
    return unless Rails.env.development?
    return if authenticated?
    return if cookies[:skip_dev_auto_login]

    user = User.first
    return unless user

    start_new_session_for(user)
  end
```

- [ ] **Step 1.4: Delete `skip_dev_auto_login` cookie writes**

Edit `app/controllers/sessions_controller.rb` — delete line 39:
```ruby
    cookies[:skip_dev_auto_login] = true if Rails.env.development?
```

Edit `app/controllers/dev_sessions_controller.rb` — delete line 19:
```ruby
    cookies.delete(:skip_dev_auto_login)
```

- [ ] **Step 1.5: Run the regression test, verify green**

```bash
ruby -Itest test/controllers/application_controller_test.rb
```

Expected: both tests PASS.

- [ ] **Step 1.6: Run the full Rails test suite to find any breakages**

```bash
bundle exec rake test
```

Expected: some failures are likely — any test that implicitly relied on auto-login (e.g., `get root_path` without calling `log_in` first, then asserting a member-only page rendered) will now return 403.

Strategy: for each failing test, add an explicit `log_in` call in the setup or inline. Do NOT add a workaround that restores implicit auto-login.

Sample fix pattern:
```ruby
# Before (relied on auto-login):
test 'something needing auth' do
  get some_member_only_path
  assert_response :success
end

# After:
test 'something needing auth' do
  log_in
  get some_member_only_path
  assert_response :success
end
```

- [ ] **Step 1.7: Re-run the suite, verify fully green**

```bash
bundle exec rake test
```

Expected: all tests PASS.

- [ ] **Step 1.8: Update `test/security/helpers.mjs`**

The Playwright helpers currently send `skip_dev_auto_login=1` on anonymous requests so the dev server doesn't silently authenticate them. With auto-login gone, this is dead code.

Read `test/security/helpers.mjs`. Find every reference to `skip_dev_auto_login` (likely in functions like `fetchAnonymous`, `fetchAnonymousWithCsrf`, or a `buildAnonymousHeaders` helper). Delete:
- The query-param appending
- Any cookie setup that sets `skip_dev_auto_login`
- Documentation comments that explain why it was needed

Keep the anonymous-fetch functions themselves — they're still useful for pen tests.

- [ ] **Step 1.9: Quick sanity-check with a Playwright spec**

Without running the full suite, spot-check that the helpers still compile:

```bash
cd /home/claude/mirepoix && node -e "import('./test/security/helpers.mjs').then(m => console.log('ok'))"
```

Expected: prints `ok`. If it errors, fix syntax issues in helpers.mjs.

- [ ] **Step 1.10: Grep the codebase for any remaining references**

Use the Grep tool with pattern `auto_login_in_development|skip_dev_auto_login` and glob `{app,config}/**/*.{rb,mjs}`. Expected: zero hits. Then re-run with glob `test/**/*.{rb,mjs}` — `test/` may still have references in test names or comments (those are fine).

- [ ] **Step 1.11: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Remove auto_login_in_development

The dev-only auto-login as User.first was a production-critical gate —
a single misconfigured deploy running in development mode would hand
out sessions silently. Saving one click per bin/dev restart isn't worth
that footgun. Deleting it also removes the skip_dev_auto_login cookie
and the Playwright helper plumbing that existed only to work around it.

Dev workflow: bin/dev, then visit /dev/login/1 once per session.

Part of the auth security audit bundle — finding H2.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create `SecurityEventLogger` service

Goal: Narrow service object for emitting tagged JSON audit log lines. Later tasks instrument against it.

**Files:**
- Create: `app/services/security_event_logger.rb`
- Create: `test/services/security_event_logger_test.rb`

- [ ] **Step 2.1: Write the failing unit test**

Create `test/services/security_event_logger_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class SecurityEventLoggerTest < ActiveSupport::TestCase
  setup do
    @io = StringIO.new
    @original_logger = Rails.logger
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(@io))
  end

  teardown do
    Rails.logger = @original_logger
  end

  test 'log emits a tagged JSON line containing the event name' do
    SecurityEventLogger.log(:magic_link_issued, user_id: 42, purpose: :sign_in)

    output = @io.string

    assert_includes output, '[security]'
    assert_match(/"event":"magic_link_issued"/, output)
    assert_match(/"user_id":42/, output)
    assert_match(/"purpose":"sign_in"/, output)
  end

  test 'log includes an ISO8601 timestamp' do
    SecurityEventLogger.log(:session_created)

    output = @io.string

    assert_match(/"at":"\d{4}-\d{2}-\d{2}T/, output)
  end

  test 'log handles events with no attributes' do
    assert_nothing_raised do
      SecurityEventLogger.log(:session_destroyed)
    end

    assert_match(/"event":"session_destroyed"/, @io.string)
  end
end
```

- [ ] **Step 2.2: Run test, confirm it fails**

```bash
ruby -Itest test/services/security_event_logger_test.rb
```

Expected: FAIL with `NameError: uninitialized constant SecurityEventLogger`.

- [ ] **Step 2.3: Implement `SecurityEventLogger`**

Create `app/services/security_event_logger.rb`:

```ruby
# frozen_string_literal: true

# Narrow audit-log emitter for auth and security events. Every call produces
# a single Rails.logger.info line tagged `[security]` with a JSON payload
# containing the event name, a timestamp, and whatever attributes the caller
# passes. No AR model, no subscribers, no async — just structured lines in
# the same log stream as everything else.
#
# - Called from: SessionsController, MagicLinksController, JoinsController,
#   TransfersController, Authentication concern
# - Read by: whoever greps the production log for `[security]`
class SecurityEventLogger
  def self.log(event, **attrs)
    payload = { event: event, at: Time.current.iso8601, **attrs }
    Rails.logger.tagged('security') { Rails.logger.info(payload.to_json) }
  end
end
```

- [ ] **Step 2.4: Run test, confirm it passes**

```bash
ruby -Itest test/services/security_event_logger_test.rb
```

Expected: all three tests PASS.

- [ ] **Step 2.5: Commit**

```bash
git add app/services/security_event_logger.rb test/services/security_event_logger_test.rb
git commit -m "$(cat <<'EOF'
Add SecurityEventLogger service

Narrow audit-log emitter that writes a single Rails.logger.info line
tagged [security] with a JSON payload. Called from auth controllers and
the Authentication concern to record login attempts, session lifecycle,
token consume events, rate-limit hits, and session-drift observations.

No AR model and no ActiveSupport::Notifications subscriber — homelab
scale doesn't need async. A future hosted-deployment phase can swap in
a subscriber without changing call sites.

Part of the auth security audit bundle — finding H1.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Opportunistic `MagicLink` cleanup

Goal: Prevent unbounded growth of the `magic_links` table by deleting expired and old-consumed rows on every successful `consume`. Bridge until Solid Queue lands (tracked in #384).

**Files:**
- Modify: `app/models/magic_link.rb`
- Modify: `test/models/magic_link_test.rb` (create if absent)

- [ ] **Step 3.1: Write failing tests for `cleanup_expired`**

Create or append to `test/models/magic_link_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class MagicLinkTest < ActiveSupport::TestCase
  setup do
    create_kitchen_and_user
  end

  test 'cleanup_expired deletes rows past expires_at' do
    expired = MagicLink.create!(
      user: @user, purpose: :sign_in, expires_at: 20.minutes.ago, code: 'EXPRD1'
    )
    fresh = MagicLink.create!(
      user: @user, purpose: :sign_in, expires_at: 10.minutes.from_now, code: 'FRESH1'
    )

    MagicLink.cleanup_expired

    assert_not MagicLink.exists?(expired.id)
    assert MagicLink.exists?(fresh.id)
  end

  test 'cleanup_expired deletes consumed rows older than 1 hour' do
    old_consumed = MagicLink.create!(
      user: @user, purpose: :sign_in, expires_at: 10.minutes.from_now,
      code: 'OLDCNS', consumed_at: 2.hours.ago
    )
    recent_consumed = MagicLink.create!(
      user: @user, purpose: :sign_in, expires_at: 10.minutes.from_now,
      code: 'NEWCNS', consumed_at: 5.minutes.ago
    )

    MagicLink.cleanup_expired

    assert_not MagicLink.exists?(old_consumed.id)
    assert MagicLink.exists?(recent_consumed.id)
  end

  test 'consume triggers cleanup_expired on success' do
    stale = MagicLink.create!(
      user: @user, purpose: :sign_in, expires_at: 2.hours.ago, code: 'STALE1'
    )
    link = MagicLink.create!(
      user: @user, purpose: :sign_in, expires_at: 10.minutes.from_now, code: 'FRSHX1'
    )

    MagicLink.consume(link.code)

    assert_not MagicLink.exists?(stale.id)
  end

  test 'consume does not trigger cleanup on failure' do
    stale = MagicLink.create!(
      user: @user, purpose: :sign_in, expires_at: 2.hours.ago, code: 'STALE2'
    )

    MagicLink.consume('NOTACD')

    assert MagicLink.exists?(stale.id)
  end
end
```

- [ ] **Step 3.2: Run tests, confirm they fail**

```bash
ruby -Itest test/models/magic_link_test.rb
```

Expected: FAIL with `NoMethodError: undefined method 'cleanup_expired'` on the first two tests; the third fails because `consume` doesn't call it yet; the fourth will pass accidentally but is load-bearing once the third is fixed.

- [ ] **Step 3.3: Implement `cleanup_expired` and wire it into `consume`**

Edit `app/models/magic_link.rb`. Replace the `consume` method and add `cleanup_expired`:

```ruby
def self.consume(raw_code)
  sanitized = normalize(raw_code)
  return nil if sanitized.blank?

  updated = where(code: sanitized, consumed_at: nil)
            .where('expires_at > ?', Time.current)
            .update_all(consumed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- intentional: atomic single-use claim
  return nil unless updated == 1

  cleanup_expired
  find_by(code: sanitized)
end

def self.cleanup_expired
  where('expires_at < ? OR (consumed_at IS NOT NULL AND consumed_at < ?)',
        Time.current, 1.hour.ago).delete_all
end
```

Also update the header comment on the class to mention the opportunistic cleanup:

```ruby
# Short-lived single-use authentication token tied to a User, delivered by
# email (or logged to stdout when SMTP is unconfigured). The code is the
# shared secret between the "check your email" page and the email itself;
# consuming it atomically starts a session. Join-purpose links also carry
# a kitchen_id so consumption can create the matching Membership. Every
# successful consume also opportunistically prunes expired rows — a bridge
# until Solid Queue + a recurring job land (tracked in #384).
#
# - User: the identity the link authenticates as
# - Kitchen: only set when purpose == :join
# - MagicLinkMailer: delivery
# - SessionsController / JoinsController: issue links
# - MagicLinksController: consume links
```

- [ ] **Step 3.4: Run tests, confirm all four pass**

```bash
ruby -Itest test/models/magic_link_test.rb
```

Expected: all four tests PASS.

- [ ] **Step 3.5: Run the full model test suite to check for regressions**

```bash
bundle exec rails test test/models/
```

Expected: all tests PASS.

- [ ] **Step 3.6: Commit**

```bash
git add app/models/magic_link.rb test/models/magic_link_test.rb
git commit -m "$(cat <<'EOF'
Opportunistic MagicLink cleanup inside consume

Every successful MagicLink.consume now also deletes expired rows and
consumed rows older than 1 hour, preventing unbounded growth of an
attacker-touched table. Opportunistic rather than scheduled because
Solid Queue isn't installed yet (tracked in #384) — promote to a real
recurring job when it lands.

The 1-hour grace on consumed_at keeps recent consumes around long
enough to avoid confusing races between update_all and find_by.

Part of the auth security audit bundle — finding F4.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Simplify `PendingAuthToken` to encrypted cookie

Goal: Replace the signed-cookie-plus-MessageVerifier double-wrap with `cookies.encrypted`, collapsing the 42-line concern to ~15 lines while also encrypting the email payload.

**Files:**
- Modify: `app/controllers/concerns/pending_auth_token.rb`

- [ ] **Step 4.1: Run the existing session/join/magic_links tests to establish green baseline**

```bash
bundle exec rails test test/controllers/sessions_controller_test.rb test/controllers/magic_links_controller_test.rb test/controllers/joins_controller_test.rb
```

Expected: all PASS. If not, Task 1's removal of `auto_login_in_development` introduced regressions that need fixing before proceeding.

- [ ] **Step 4.2: Rewrite `PendingAuthToken`**

Replace the entire contents of `app/controllers/concerns/pending_auth_token.rb`:

```ruby
# frozen_string_literal: true

# Encapsulates the encrypted `:pending_auth` cookie carrying the normalized
# email between /sessions/new -> /sessions/magic_link and between
# /join -> /sessions/magic_link. Encrypted (AES-GCM via cookies.encrypted)
# so the email payload isn't readable even with a cookie dump; 15-minute
# expiry enforced by the cookie jar. The email is what
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

  # rubocop:disable Naming/AccessorMethodName -- not a writer; encrypts+expires, paired with `pending_auth_email` reader
  def set_pending_auth_email(email)
    cookies.encrypted[:pending_auth] = {
      value: email,
      expires: PENDING_AUTH_EXPIRY.from_now,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }
  end
  # rubocop:enable Naming/AccessorMethodName

  def pending_auth_email
    cookies.encrypted[:pending_auth].presence
  end

  def clear_pending_auth
    cookies.delete(:pending_auth)
  end
end
```

- [ ] **Step 4.3: Run the three controller test files**

```bash
bundle exec rails test test/controllers/sessions_controller_test.rb test/controllers/magic_links_controller_test.rb test/controllers/joins_controller_test.rb
```

Expected: all PASS. The existing tests already use `post sessions_path` etc., which go through the concern — if they pass, the encrypted-cookie rewrite is transparent to callers.

If any test asserts `cookies[:pending_auth]` directly (non-empty check is fine, but equality to a specific signed-value would fail), leave the assertion as `assert_not_empty cookies[:pending_auth].to_s` — the encrypted value is still a non-empty string, just unreadable.

- [ ] **Step 4.4: Commit**

```bash
git add app/controllers/concerns/pending_auth_token.rb
git commit -m "$(cat <<'EOF'
Simplify PendingAuthToken to encrypted cookie

Drops the signed-cookie-plus-inner-MessageVerifier double-wrap in favor
of cookies.encrypted, which handles expiry natively and adds AES-GCM
confidentiality for the email payload. Concern shrinks from 42 lines
to 15. Externally identical — callers still see
set_pending_auth_email / pending_auth_email / clear_pending_auth.

Part of the auth security audit bundle — finding F6.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Unify `MagicLinksController` error responses

Goal: Stop leaking code validity via differential responses (200 + form for invalid code vs 302 + redirect for email mismatch). Both failure paths return the same 200 + form.

**Files:**
- Modify: `app/controllers/magic_links_controller.rb`
- Modify: `test/controllers/magic_links_controller_test.rb`

- [ ] **Step 5.1: Write the failing test**

Append to `test/controllers/magic_links_controller_test.rb`:

```ruby
test 'POST /sessions/magic_link with code/email mismatch re-renders the form (no redirect)' do
  other_user = ActsAsTenant.without_tenant do
    User.create!(name: 'Other', email: 'other@example.com')
  end
  ActsAsTenant.with_tenant(@kitchen) do
    Membership.create!(kitchen: @kitchen, user: other_user)
  end

  post sessions_path, params: { email: other_user.email }
  other_link = MagicLink.order(:created_at).last

  cookies.delete(:pending_auth)
  post sessions_path, params: { email: @user.email }

  post sessions_magic_link_path, params: { code: other_link.code }

  assert_response :unprocessable_content
  assert_select 'input[name=code]'
end

test 'POST /sessions/magic_link preserves pending_auth cookie on failed consume' do
  post sessions_path, params: { email: @user.email }

  post sessions_magic_link_path, params: { code: 'ZZZZZZ' }

  assert_not_empty cookies[:pending_auth].to_s
end
```

Note: there's an existing test `'fails closed on code/email mismatch'` that asserts `assert_redirected_to new_session_path`. That test becomes wrong with this change — update it in-place to match the new behavior:

Find the existing test:
```ruby
test 'POST /sessions/magic_link fails closed on code/email mismatch' do
  # ... setup ...
  post sessions_magic_link_path, params: { code: other_link.code }

  assert_redirected_to new_session_path
end
```

Change the final assertion to:
```ruby
  assert_response :unprocessable_content
```

- [ ] **Step 5.2: Run the tests, confirm the new ones fail and the updated one fails**

```bash
ruby -Itest test/controllers/magic_links_controller_test.rb
```

Expected: the two new tests FAIL, the updated test FAILS (currently redirects, expected 422).

- [ ] **Step 5.3: Rewrite the `create` action to unify error responses**

Edit `app/controllers/magic_links_controller.rb`. Replace the `create` method and remove `fail_mismatch`:

```ruby
def create
  link = MagicLink.consume(params[:code])
  return render_invalid unless link && pending_auth_email == link.user.email

  link.user.verify_email!
  ensure_join_membership(link) if link.join?
  start_new_session_for(link.user)
  clear_pending_auth

  redirect_to after_sign_in_path_for(link)
end
```

Delete the `fail_mismatch` method entirely (currently lines 62-65).

The `render_invalid` method stays as-is.

- [ ] **Step 5.4: Run the tests, confirm all pass**

```bash
ruby -Itest test/controllers/magic_links_controller_test.rb
```

Expected: all tests PASS, including the new mismatch behavior and the cookie-preservation check.

- [ ] **Step 5.5: Commit**

```bash
git add app/controllers/magic_links_controller.rb test/controllers/magic_links_controller_test.rb
git commit -m "$(cat <<'EOF'
Unify MagicLinksController error responses

Both failure modes — invalid/expired code and code/email mismatch —
now return the same 200 + form response, closing a code-validity leak
where an attacker without the pending_auth cookie could distinguish a
valid-but-wrong-email code (302 redirect) from an invalid code (200
render). Also stops clearing pending_auth on mismatch, letting the
user retry without starting over; the cookie still expires in 15 min
on its own.

Part of the auth security audit bundle — finding F7.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Rate limit `/join/complete`

Goal: Close the email enumeration vector on `POST /join/complete`, which currently has no rate limit.

**Files:**
- Modify: `app/controllers/joins_controller.rb`
- Modify: `test/controllers/joins_controller_test.rb`

- [ ] **Step 6.1: Write the failing test**

Append to `test/controllers/joins_controller_test.rb`:

```ruby
test 'POST /join/complete is rate-limited' do
  kitchen_being_joined = Kitchen.create!(name: 'Another Kitchen', slug: 'another-kitchen')
  signed = sign_kitchen_id(kitchen_being_joined.id)

  11.times do |i|
    post complete_join_path,
         params: { signed_kitchen_id: signed, email: "person#{i}@example.com", name: 'Person' }
  end

  assert_response :too_many_requests
end
```

- [ ] **Step 6.2: Run test, confirm it fails**

```bash
ruby -Itest test/controllers/joins_controller_test.rb -n test_POST__join_complete_is_rate_limited
```

Expected: FAIL (no rate limit, so all 11 requests succeed with 302).

- [ ] **Step 6.3: Add the rate limit**

Edit `app/controllers/joins_controller.rb`. Change line 19 from:

```ruby
rate_limit to: 10, within: 1.hour, by: -> { request.remote_ip }, only: :verify
```

to:

```ruby
rate_limit to: 10, within: 1.hour, by: -> { request.remote_ip }, only: :verify
rate_limit to: 10, within: 15.minutes, by: -> { request.remote_ip }, only: :create
```

- [ ] **Step 6.4: Run the test, confirm it passes**

```bash
ruby -Itest test/controllers/joins_controller_test.rb -n test_POST__join_complete_is_rate_limited
```

Expected: PASS.

- [ ] **Step 6.5: Run all joins controller tests**

```bash
ruby -Itest test/controllers/joins_controller_test.rb
```

Expected: all tests PASS.

- [ ] **Step 6.6: Commit**

```bash
git add app/controllers/joins_controller.rb test/controllers/joins_controller_test.rb
git commit -m "$(cat <<'EOF'
Rate limit JoinsController#create

Closes the email enumeration vector on POST /join/complete. An
attacker with a valid signed_kitchen_id could previously hammer the
endpoint with different emails and observe whether the controller
renders the name form (new user) or issues a link (existing user).
10 requests per 15 minutes per IP matches SessionsController#create.

Part of the auth security audit bundle — finding F1.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `deliver_later` + timing branch convergence

Goal: Close the timing-based email enumeration side channel by moving mailer delivery to a job queue and making both "known" and "unknown" email paths do comparable work.

**Files:**
- Modify: `test/test_helper.rb` (include `ActiveJob::TestHelper`)
- Modify: `app/controllers/sessions_controller.rb`
- Modify: `app/controllers/joins_controller.rb`
- Modify: `test/controllers/sessions_controller_test.rb`
- Modify: `test/controllers/joins_controller_test.rb`

- [ ] **Step 7.1: Include `ActiveJob::TestHelper` in `ActiveSupport::TestCase`**

Edit `test/test_helper.rb`. After the `require 'action_cable/channel/test_case'` line, add:

```ruby
require 'action_mailer/test_helper'
```

Then find the `ActiveSupport::TestCase` module reopening (there are a couple; use the one with `private` method definitions around line 58) and add to it:

```ruby
module ActiveSupport
  class TestCase
    include ActionMailer::TestHelper
```

Note: `ActionMailer::TestHelper` transitively includes `ActiveJob::TestHelper`, which enables `assert_enqueued_emails`. Do NOT separately include `ActiveJob::TestHelper` — that would cause method redefinition warnings.

- [ ] **Step 7.2: Update existing mailer delivery assertions to use `assert_enqueued_emails`**

Edit `test/controllers/sessions_controller_test.rb`. Find the test at lines 27-38 (`'POST /sessions with known email creates a magic link and delivers mail'`).

Replace its body:

```ruby
test 'POST /sessions with known email creates a magic link and enqueues mail' do
  assert_enqueued_emails 1 do
    assert_difference -> { MagicLink.count } => 1 do
      post sessions_path, params: { email: @user.email }
    end
  end

  assert_redirected_to sessions_magic_link_path

  link = MagicLink.order(:created_at).last

  assert_equal @user, link.user
  assert_equal 'sign_in', link.purpose
end
```

Also update the "unknown email" test at lines 40-49 to use `assert_no_enqueued_emails`:

```ruby
test 'POST /sessions with unknown email enqueues no mail but still redirects (anti-enumeration)' do
  assert_no_difference -> { MagicLink.count } do
    assert_no_enqueued_emails do
      post sessions_path, params: { email: 'stranger@example.com' }
    end
  end

  assert_redirected_to sessions_magic_link_path
  assert_not_empty cookies[:pending_auth].to_s
end
```

And the orphan test at lines 51-63:

```ruby
test 'POST /sessions with an email matching a user with no memberships is treated as unknown' do
  orphan = ActsAsTenant.without_tenant do
    User.create!(name: 'Orphan', email: 'orphan@example.com')
  end
  orphan.memberships.destroy_all

  assert_no_enqueued_emails do
    post sessions_path, params: { email: orphan.email }
  end

  assert_redirected_to sessions_magic_link_path
  assert_not_empty cookies[:pending_auth].to_s
end
```

Edit `test/controllers/joins_controller_test.rb`. Find the test at lines 31-50 (`'POST /join/complete with known email creates a :join magic link and delivers mail'`). Replace the `ActionMailer::Base.deliveries.clear` + `assert_difference` block:

```ruby
test 'POST /join/complete with known email creates a :join magic link and enqueues mail' do
  kitchen_being_joined = Kitchen.create!(name: 'Another Kitchen', slug: 'another-kitchen')
  signed = sign_kitchen_id(kitchen_being_joined.id)
  joiner = User.create!(name: 'Joiner', email: 'joiner@example.com')

  assert_enqueued_emails 1 do
    assert_difference -> { MagicLink.where(purpose: :join).count } => 1 do
      post complete_join_path, params: { signed_kitchen_id: signed, email: joiner.email }
    end
  end

  assert_redirected_to sessions_magic_link_path

  link = MagicLink.order(:created_at).last

  assert_equal kitchen_being_joined, link.kitchen
  assert_equal 'join', link.purpose
  assert_equal joiner, link.user
  assert_nil ActsAsTenant.with_tenant(kitchen_being_joined) { Membership.find_by(user: joiner) }
end
```

- [ ] **Step 7.3: Run the updated tests, confirm they currently fail**

```bash
ruby -Itest test/controllers/sessions_controller_test.rb test/controllers/joins_controller_test.rb
```

Expected: the updated tests FAIL because the controllers still use `deliver_now`, which doesn't enqueue jobs — the `assert_enqueued_emails` assertion expects 1 enqueued, gets 0.

- [ ] **Step 7.4: Switch `SessionsController` to `deliver_later` + branch convergence**

Edit `app/controllers/sessions_controller.rb`. Replace `issue_magic_link_for` and `deliver_sign_in_link`:

```ruby
def issue_magic_link_for(email)
  user = User.find_by(email:)
  has_membership = user && ActsAsTenant.without_tenant { user.memberships.any? }
  return SecurityEventLogger.log(:unknown_email_auth_attempt, email: email) unless has_membership

  deliver_sign_in_link(user)
end

def deliver_sign_in_link(user)
  link = MagicLink.create!(
    user: user, purpose: :sign_in, expires_at: 15.minutes.from_now,
    request_ip: request.remote_ip, request_user_agent: request.user_agent
  )
  SecurityEventLogger.log(:magic_link_issued, user_id: user.id, purpose: :sign_in)
  MagicLinkMailer.sign_in_instructions(link).deliver_later
end
```

- [ ] **Step 7.5: Switch `JoinsController` to `deliver_later`**

Edit `app/controllers/joins_controller.rb`. Replace the body of `issue_join_link`:

```ruby
def issue_join_link(kitchen, email)
  user = find_or_create_user(email)
  link = create_join_link(user, kitchen)
  SecurityEventLogger.log(:magic_link_issued, user_id: user.id, purpose: :join, kitchen_id: kitchen.id)
  MagicLinkMailer.sign_in_instructions(link).deliver_later
  set_pending_auth_email(email)
  redirect_to sessions_magic_link_path
rescue ActiveRecord::RecordNotUnique
  retry
end
```

- [ ] **Step 7.6: Run the controller tests, confirm they pass**

```bash
ruby -Itest test/controllers/sessions_controller_test.rb test/controllers/joins_controller_test.rb
```

Expected: all tests PASS.

- [ ] **Step 7.7: Run the full Rails test suite to check for regressions**

```bash
bundle exec rake test
```

Expected: all tests PASS. If any test asserts `ActionMailer::Base.deliveries.size` on an auth path, update it to use `assert_enqueued_emails`.

- [ ] **Step 7.8: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Switch auth mailer delivery to deliver_later + converge timing branches

Closes the timing-based email enumeration side channel on
SessionsController#create and JoinsController#create. deliver_now made
known-email paths 50-500ms slower than unknown-email paths; deliver_later
returns immediately after enqueue, and the unknown-email branch now also
does non-trivial work (a SecurityEventLogger.log call), collapsing the
gap from hundreds of ms to noise.

A stopwatch-wielding attacker can theoretically still distinguish the
branches; we accept that over adding artificial sleep().

Also starts emitting :magic_link_issued and :unknown_email_auth_attempt
events via SecurityEventLogger.

Part of the auth security audit bundle — finding F2 + H1 instrumentation.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Log magic link consume outcomes

Goal: Add `SecurityEventLogger` instrumentation to `MagicLinksController#create` and log `:rate_limited` events across all auth endpoints.

**Files:**
- Modify: `app/controllers/magic_links_controller.rb`
- Modify: `app/controllers/sessions_controller.rb`
- Modify: `app/controllers/joins_controller.rb`
- Modify: `app/controllers/transfers_controller.rb`
- Modify: `test/controllers/magic_links_controller_test.rb`

- [ ] **Step 8.1: Write a failing test for consume-success logging**

Append to `test/controllers/magic_links_controller_test.rb`:

```ruby
test 'POST /sessions/magic_link logs :magic_link_consumed on success' do
  post sessions_path, params: { email: @user.email }
  link = MagicLink.order(:created_at).last

  io = StringIO.new
  Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
  begin
    post sessions_magic_link_path, params: { code: link.code }
  ensure
    Rails.logger = Rails.application.config.logger || Rails.logger
  end

  assert_match(/\[security\].*"event":"magic_link_consumed"/, io.string)
end

test 'POST /sessions/magic_link logs :magic_link_consume_failed on invalid code' do
  post sessions_path, params: { email: @user.email }

  io = StringIO.new
  Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
  begin
    post sessions_magic_link_path, params: { code: 'ZZZZZZ' }
  ensure
    Rails.logger = Rails.application.config.logger || Rails.logger
  end

  assert_match(/\[security\].*"event":"magic_link_consume_failed"/, io.string)
end
```

- [ ] **Step 8.2: Run tests, confirm they fail**

```bash
ruby -Itest test/controllers/magic_links_controller_test.rb -n "/logs.*magic_link/"
```

Expected: both tests FAIL (nothing is logging these events yet).

- [ ] **Step 8.3: Instrument `MagicLinksController#create`**

Edit `app/controllers/magic_links_controller.rb`. Replace `create`:

```ruby
def create
  link = MagicLink.consume(params[:code])
  unless link && pending_auth_email == link.user.email
    SecurityEventLogger.log(:magic_link_consume_failed,
      reason: link ? :email_mismatch : :invalid_or_expired)
    return render_invalid
  end

  link.user.verify_email!
  ensure_join_membership(link) if link.join?
  start_new_session_for(link.user)
  clear_pending_auth

  SecurityEventLogger.log(:magic_link_consumed, user_id: link.user.id, purpose: link.purpose)
  redirect_to after_sign_in_path_for(link)
end
```

- [ ] **Step 8.4: Run the tests, confirm they pass**

```bash
ruby -Itest test/controllers/magic_links_controller_test.rb
```

Expected: all tests PASS.

- [ ] **Step 8.5: Add `with:` blocks to all auth rate_limit calls for event logging**

The `with:` proc executes in the controller instance context, so a private instance method is reachable from inside the proc. Add a small `log_rate_limited` private method to each rate-limited controller and pass a `with:` block that calls it.

**`app/controllers/sessions_controller.rb`**: change the existing `rate_limit` line (currently line 22) to:

```ruby
rate_limit to: 10, within: 15.minutes, by: -> { request.remote_ip },
           with: -> { log_rate_limited; head(:too_many_requests) }, only: :create
```

Then add this to the private section of the controller (anywhere below `private`):

```ruby
def log_rate_limited
  SecurityEventLogger.log(:rate_limited,
    controller: controller_name, action: action_name, ip: request.remote_ip)
end
```

**`app/controllers/magic_links_controller.rb`**: change the existing `rate_limit` line (currently line 22) the same way:

```ruby
rate_limit to: 10, within: 15.minutes, by: -> { request.remote_ip },
           with: -> { log_rate_limited; head(:too_many_requests) }, only: :create
```

Add the same `log_rate_limited` private method (copy-paste — this small duplication is intentional; a shared concern would add more structure than it saves at three call sites).

**`app/controllers/joins_controller.rb`**: it has two `rate_limit` lines after Task 6. Change both:

```ruby
rate_limit to: 10, within: 1.hour, by: -> { request.remote_ip },
           with: -> { log_rate_limited; head(:too_many_requests) }, only: :verify
rate_limit to: 10, within: 15.minutes, by: -> { request.remote_ip },
           with: -> { log_rate_limited; head(:too_many_requests) }, only: :create
```

Add the same `log_rate_limited` private method.

- [ ] **Step 8.6: Update the existing rate-limit tests to assert the log line**

Find the existing rate-limit test in `test/controllers/sessions_controller_test.rb`:

```ruby
test 'POST /sessions is rate-limited' do
  11.times { post sessions_path, params: { email: @user.email } }

  assert_response :too_many_requests
end
```

Replace:

```ruby
test 'POST /sessions is rate-limited and logs the event' do
  io = StringIO.new
  Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
  begin
    11.times { post sessions_path, params: { email: @user.email } }
  ensure
    Rails.logger = Rails.application.config.logger || Rails.logger
  end

  assert_response :too_many_requests
  assert_match(/\[security\].*"event":"rate_limited"/, io.string)
end
```

Apply the same pattern to the rate-limit tests in `magic_links_controller_test.rb` and `joins_controller_test.rb`.

- [ ] **Step 8.7: Run the three controller test files**

```bash
bundle exec rails test test/controllers/sessions_controller_test.rb test/controllers/magic_links_controller_test.rb test/controllers/joins_controller_test.rb
```

Expected: all tests PASS.

- [ ] **Step 8.8: Instrument `TransfersController#show`**

Edit `app/controllers/transfers_controller.rb`. Replace `show`:

```ruby
def show
  user = resolve_token
  kitchen = resolve_kitchen(user)

  unless user && kitchen
    SecurityEventLogger.log(:transfer_token_consume_failed,
      reason: user ? :kitchen_membership_missing : :invalid_token)
    @error = 'This link is invalid or has expired.'
    return render :show_error, status: :unprocessable_content
  end

  SecurityEventLogger.log(:transfer_token_consumed, user_id: user.id, kitchen_id: kitchen.id)
  start_new_session_for(user)
  redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
end
```

- [ ] **Step 8.9: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Instrument auth controllers with SecurityEventLogger

Adds structured audit-log events for magic link consume success/failure,
transfer token consume success/failure, and rate-limit hits across
SessionsController, MagicLinksController, and JoinsController. Each
rate-limited controller now has a local log_rate_limited helper and
a with: block on its rate_limit call.

Part of the auth security audit bundle — finding H1 instrumentation.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Log session lifecycle + advisory drift detection

Goal: Emit session_created / session_destroyed events from the Authentication concern and add advisory-only session-drift logging (no blocking).

**Files:**
- Modify: `app/controllers/concerns/authentication.rb`
- Create: `test/integration/session_drift_test.rb`

- [ ] **Step 9.1: Write the failing integration test**

Create `test/integration/session_drift_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class SessionDriftTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'resume_session logs :session_drift when UA differs from stored session' do
    log_in
    session = Session.last
    session.update!(user_agent: 'original-agent/1.0')

    io = StringIO.new
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
    begin
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: { 'User-Agent' => 'different-agent/2.0' }
    ensure
      Rails.logger = Rails.application.config.logger || Rails.logger
    end

    assert_response :success
    assert_match(/\[security\].*"event":"session_drift"/, io.string)
  end

  test 'resume_session does NOT log drift when UA matches' do
    log_in
    session = Session.last

    io = StringIO.new
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
    begin
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: { 'User-Agent' => session.user_agent }
    ensure
      Rails.logger = Rails.application.config.logger || Rails.logger
    end

    assert_no_match(/session_drift/, io.string)
  end

  test 'start_new_session_for logs :session_created' do
    io = StringIO.new
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
    begin
      log_in
    ensure
      Rails.logger = Rails.application.config.logger || Rails.logger
    end

    assert_match(/\[security\].*"event":"session_created"/, io.string)
  end

  test 'terminate_session logs :session_destroyed' do
    log_in

    io = StringIO.new
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
    begin
      delete logout_path
    ensure
      Rails.logger = Rails.application.config.logger || Rails.logger
    end

    assert_match(/\[security\].*"event":"session_destroyed"/, io.string)
  end
end
```

- [ ] **Step 9.2: Run the tests, confirm they fail**

```bash
ruby -Itest test/integration/session_drift_test.rb
```

Expected: all four tests FAIL.

- [ ] **Step 9.3: Instrument `Authentication` concern**

Edit `app/controllers/concerns/authentication.rb`. Replace `resume_session`, `start_new_session_for`, and `terminate_session`:

```ruby
def resume_session
  Current.session ||= find_session_by_cookie
  warn_on_session_drift if Current.session
  Current.session
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
    SecurityEventLogger.log(:session_created, session_id: new_session.id, user_id: user.id)
  end
end

def terminate_session
  if Current.session
    SecurityEventLogger.log(:session_destroyed, session_id: Current.session.id)
    Current.session.destroy
  end
  cookies.delete(:session_id)
  Current.reset
end

def warn_on_session_drift
  return unless Current.session

  ip_changed = Current.session.ip_address != request.remote_ip
  ua_changed = Current.session.user_agent != request.user_agent
  return unless ip_changed || ua_changed

  SecurityEventLogger.log(:session_drift,
    session_id: Current.session.id,
    ip_changed: ip_changed, ua_changed: ua_changed)
end
```

- [ ] **Step 9.4: Run the tests, confirm they pass**

```bash
ruby -Itest test/integration/session_drift_test.rb
```

Expected: all four tests PASS.

- [ ] **Step 9.5: Run the full controller test suite to check for regressions**

```bash
bundle exec rails test test/controllers/ test/integration/
```

Expected: all tests PASS. Note: the `SecurityEventLogger.log(:session_created, ...)` call means every test that calls `log_in` now also emits a log line — this is expected and should not break assertions unless a test is pattern-matching against stdout/logger output (unlikely outside our new tests).

- [ ] **Step 9.6: Commit**

```bash
git add app/controllers/concerns/authentication.rb test/integration/session_drift_test.rb
git commit -m "$(cat <<'EOF'
Log session lifecycle + advisory drift detection

start_new_session_for, terminate_session, and resume_session now emit
SecurityEventLogger events. resume_session additionally checks whether
the stored ip_address / user_agent on the Session row differs from the
current request and logs :session_drift when they do — advisory only,
no blocking. Homelab users roam IPs and update browsers; strict pinning
would be a UX disaster, but an audit trail of drift is cheap.

If drift logs turn out to be noisy, downgrade the trigger to "both IP
and UA differ" rather than "either."

Part of the auth security audit bundle — findings F5 + H1.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Switch session cookie to `signed_id`

Goal: Defense-in-depth — store a purpose-scoped `signed_id` in the session cookie instead of the raw integer PK. Matches Fizzy's pattern and the Rails 8 Authentication Zero idiom. This is the only task that invalidates existing sessions, so it lands last.

**Files:**
- Modify: `app/controllers/concerns/authentication.rb`
- Modify: `app/channels/application_cable/connection.rb`
- Modify: `test/controllers/application_controller_test.rb` (optional, for the cookie format assertion)

- [ ] **Step 10.1: Write the failing test**

Append to `test/controllers/application_controller_test.rb` (create as integration test if the existing file is a unit test):

Create `test/integration/session_cookie_format_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class SessionCookieFormatTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'session cookie stores a signed_id (not a bare integer)' do
    log_in

    cookie_value = cookies[:session_id].to_s

    assert_not_empty cookie_value
    assert_not_match(/\A\d+\z/, cookie_value,
      'session cookie should not be a bare integer PK')
  end

  test 'Session.find_signed resolves the cookie value to the session record' do
    log_in
    session_row = Session.last
    cookie_value = cookies[:session_id].to_s

    resolved = Session.find_signed(cookie_value, purpose: :session)

    assert_equal session_row, resolved
  end

  test 'authenticated requests after log_in succeed with the signed_id cookie' do
    log_in

    get kitchen_root_path(kitchen_slug: @kitchen.slug)

    assert_response :success
  end
end
```

- [ ] **Step 10.2: Run the tests, confirm they fail**

```bash
ruby -Itest test/integration/session_cookie_format_test.rb
```

Expected: the `signed_id` test FAILS (cookie is currently a bare integer), the `find_signed` test FAILS (cookie can't be resolved via `find_signed`), and the authenticated-request test may pass accidentally via the current `find_by` path — that's fine, it'll still pass after the change.

- [ ] **Step 10.3: Switch `Authentication` concern to `signed_id`**

Edit `app/controllers/concerns/authentication.rb`. Replace `find_session_by_cookie` and the cookie assignment in `start_new_session_for`:

```ruby
def find_session_by_cookie
  Session.find_signed(cookies.signed[:session_id], purpose: :session)
end

def start_new_session_for(user)
  user.sessions.create!(
    user_agent: request.user_agent,
    ip_address: request.remote_ip
  ).tap do |new_session|
    Current.session = new_session
    cookies.signed.permanent[:session_id] = {
      value: new_session.signed_id(purpose: :session),
      httponly: true, same_site: :lax, secure: Rails.env.production?
    }
    SecurityEventLogger.log(:session_created, session_id: new_session.id, user_id: user.id)
  end
end
```

- [ ] **Step 10.4: Switch `ApplicationCable::Connection` to `find_signed`**

Edit `app/channels/application_cable/connection.rb`. Replace `find_verified_user` (currently at lines 16-19):

```ruby
def find_verified_user
  session = Session.find_signed(cookies.signed[:session_id], purpose: :session)
  session&.user || reject_unauthorized_connection
end
```

- [ ] **Step 10.5: Run the cookie-format tests, confirm they pass**

```bash
ruby -Itest test/integration/session_cookie_format_test.rb
```

Expected: all three tests PASS.

- [ ] **Step 10.6: Run the full test suite**

```bash
bundle exec rake test
```

Expected: all tests PASS.

- [ ] **Step 10.7: Manual smoke test**

```bash
bin/dev
```

In another terminal:
```bash
curl -i http://localhost:3030/dev/login/1 -c /tmp/cookies.txt
curl -i http://localhost:3030/recipes -b /tmp/cookies.txt
```

Expected: first curl sets a long `session_id` cookie (not a bare integer). Second curl returns 200 with content (session resumes via `find_signed`).

Stop `bin/dev` (Ctrl-C).

- [ ] **Step 10.8: Commit**

```bash
git add app/controllers/concerns/authentication.rb app/channels/application_cable/connection.rb test/integration/session_cookie_format_test.rb
git commit -m "$(cat <<'EOF'
Store session.signed_id in the session cookie

Defense-in-depth: the cookie is already signed by cookies.signed, so
forgery requires secret_key_base, but storing the raw PK leaves no
purpose binding. Using session.signed_id(purpose: :session) adds a
second layer and follows the Rails 8 Authentication Zero idiom (also
what Fizzy does). Two-file change: Authentication concern for HTTP
requests, ApplicationCable::Connection for WebSocket resume.

Deployment note: existing sessions fail to resume on first boot after
deploy, forcing re-login. Acceptable — no production traffic yet.

Part of the auth security audit bundle — finding F3.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Delete obsoleted plan doc

Goal: Small cleanup — the trusted-header hardening plan at `docs/superpowers/plans/2026-04-10-harden-trusted-header-auth-plan.md` was obsoleted by PR #371 (which removed the trusted-header path entirely) but the plan artifact lingered.

**Files:**
- Delete: `docs/superpowers/plans/2026-04-10-harden-trusted-header-auth-plan.md`

- [ ] **Step 11.1: Verify it's truly obsolete**

Use the Grep tool with pattern `REMOTE_USER|authenticate_from_headers|trusted_header` and glob `{app,config}/**/*.rb`. Expected: zero hits. (If non-zero, stop — the plan isn't actually obsolete.)

- [ ] **Step 11.2: Delete the file**

```bash
rm docs/superpowers/plans/2026-04-10-harden-trusted-header-auth-plan.md
```

- [ ] **Step 11.3: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Delete obsoleted trusted-header hardening plan

PR #371 removed the trusted-header auth path entirely. This plan was
written the day before, never landed, and GH #365 (its parent issue)
is already closed as COMPLETED. Deleting the artifact.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Playwright pen tests

Goal: Lock in regression coverage at the HTTP level for the new rate limit and the timing convergence. These run against a live dev server via `rake release:audit:security`.

**Files:**
- Modify: `test/security/auth_security.spec.mjs` (add `/join/complete` rate-limit case)
- Create: `test/security/timing_invariance.spec.mjs`

- [ ] **Step 12.1: Read the existing auth_security.spec.mjs to match its style**

Read `test/security/auth_security.spec.mjs` in full.

Look for the existing rate-limit test on `/join` (the `:verify` endpoint). Use it as a template.

- [ ] **Step 12.2: Add the `/join/complete` rate-limit test case**

Append to `test/security/auth_security.spec.mjs`, mirroring the existing `/join` verify rate-limit test:

```javascript
test('POST /join/complete is rate limited', async ({ request }) => {
  const { signedKitchenId } = await getSignedKitchenIdForAudit(request);

  let lastStatus = 0;
  for (let i = 0; i < 12; i++) {
    const res = await postForm(request, '/join/complete', {
      signed_kitchen_id: signedKitchenId,
      email: `floodtest${i}@example.com`,
      name: 'Flood Test',
    });
    lastStatus = res.status();
  }

  expect(lastStatus).toBe(429);
});
```

Note: the helper function names (`getSignedKitchenIdForAudit`, `postForm`) are placeholders — use whatever helpers already exist in the file. If none match, read the existing `/join verify` rate-limit test and reuse its exact pattern.

- [ ] **Step 12.3: Create the timing invariance spec**

Create `test/security/timing_invariance.spec.mjs`:

```javascript
// @ts-check
import { test, expect } from '@playwright/test';
import { BASE_URL } from './helpers.mjs';

// Rough timing-variance assertion: the known-email and unknown-email branches
// of POST /sessions should return in comparable time. This catches
// regressions that reintroduce synchronous-delivery (deliver_now) timing
// tells; it is NOT a cryptographic guarantee — a determined attacker with a
// stopwatch can still distinguish the branches within a few ms.

const SAMPLE_COUNT = 10;
const TOLERANCE_RATIO = 3.0; // known branch must not be more than 3x slower than unknown

async function timePost(request, email) {
  const start = Date.now();
  const res = await request.post(`${BASE_URL}/sessions`, {
    form: { email },
    maxRedirects: 0,
  }).catch(() => null);
  return Date.now() - start;
}

test.describe('Timing invariance on POST /sessions', () => {
  test('known and unknown email branches return in comparable time', async ({ request }) => {
    const knownSamples = [];
    const unknownSamples = [];

    for (let i = 0; i < SAMPLE_COUNT; i++) {
      knownSamples.push(await timePost(request, 'security-test@example.com'));
      unknownSamples.push(await timePost(request, `stranger${i}@example.com`));
    }

    const median = (arr) => arr.sort((a, b) => a - b)[Math.floor(arr.length / 2)];
    const knownMedian = median(knownSamples);
    const unknownMedian = median(unknownSamples);

    expect(knownMedian).toBeLessThanOrEqual(unknownMedian * TOLERANCE_RATIO);
  });
});
```

Note: `security-test@example.com` must correspond to a real seeded user with a membership in the pen-test database. Check `test/security/seed_security_kitchens.rb` to see which emails are seeded; use an existing one or add a new one.

- [ ] **Step 12.4: Seed the pen-test database**

```bash
bin/rails runner test/security/seed_security_kitchens.rb
```

- [ ] **Step 12.5: Start the dev server and run the new Playwright tests**

Start the dev server in the background:

```bash
bin/dev
```

In another terminal:

```bash
npx playwright test test/security/auth_security.spec.mjs
npx playwright test test/security/timing_invariance.spec.mjs
```

Expected: all tests PASS. If `timing_invariance` is flaky, increase `TOLERANCE_RATIO` or `SAMPLE_COUNT` — the goal is regression detection, not statistical rigor.

Stop the dev server.

- [ ] **Step 12.6: Commit**

```bash
git add test/security/auth_security.spec.mjs test/security/timing_invariance.spec.mjs
git commit -m "$(cat <<'EOF'
Playwright pen tests for rate limit + timing invariance

Adds /join/complete rate-limit coverage to auth_security.spec.mjs and a
new timing_invariance.spec.mjs that compares median response times
between known-email and unknown-email branches of POST /sessions. The
timing test is a regression guard, not a cryptographic assertion —
tolerance is generous (3x) to avoid flakes.

Part of the auth security audit bundle — finding H3.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Final acceptance verification

Goal: Run every gate and confirm we're shipping-ready.

- [ ] **Step 13.1: Run the full Rails test suite**

```bash
bundle exec rake test
```

Expected: all tests PASS, Bullet clean, no warnings.

- [ ] **Step 13.2: Run RuboCop**

```bash
bundle exec rake lint
```

Expected: 0 offenses.

- [ ] **Step 13.3: Run Brakeman**

```bash
bundle exec rake security
```

Expected: 0 new warnings. If new warnings appear, triage each one — either fix the underlying issue or add a narrow ignore entry to `config/brakeman.ignore` with a note explaining why.

- [ ] **Step 13.4: Run the security pen tests**

```bash
bin/dev
```

In another terminal:

```bash
bin/rails runner test/security/seed_security_kitchens.rb
bundle exec rake release:audit:security
```

Expected: all specs PASS.

Stop `bin/dev`.

- [ ] **Step 13.5: Assert clean greps**

Use the Grep tool for these patterns and confirm zero hits:

- `auto_login_in_development` — search glob `{app,config}/**/*.rb`
- `skip_dev_auto_login` — search glob `{app,config}/**/*.rb`
- `REMOTE_USER|authenticate_from_headers|trusted_header` — search glob `{app,config}/**/*.rb`

Expected: zero matches in any of these.

- [ ] **Step 13.6: Manual end-to-end smoke test**

```bash
bin/dev
```

In the browser:
1. Visit `http://localhost:3030/sessions/new`
2. Enter an email that matches `@user` (e.g., `test@example.com`)
3. Watch `docker logs` or the dev server console for the magic link code
4. Visit `/sessions/magic_link`, enter the code
5. Confirm redirect to a kitchen root page and a logged-in state
6. In the dev server console, look for `[security]` tagged log lines: `magic_link_issued`, `session_created`, `magic_link_consumed`
7. `curl -H 'User-Agent: different/1.0' -b <session_cookie> http://localhost:3030/`
8. Look for a `session_drift` log line
9. Visit `/logout`
10. Look for `session_destroyed`

Expected: every step succeeds, every log line appears.

Stop `bin/dev`.

- [ ] **Step 13.7: Push the branch and open the PR**

```bash
git push -u origin feature/security-audit
gh pr create --title "Auth security audit: fixes + hardening" --body "$(cat <<'EOF'
## Summary

Closes GH #373. Bundled auth security audit + fix pass following the
Phase-2 magic-link merge (PR #375). Design doc:
`docs/superpowers/specs/2026-04-11-auth-security-audit-design.md`.

### Findings closed

- **F1** — rate-limit `POST /join/complete` (email enumeration)
- **F2** — `deliver_later` + branch convergence (timing side channel)
- **F3** — `signed_id` session cookie (defense-in-depth)
- **F4** — opportunistic `MagicLink.cleanup_expired` (table growth)
- **F5** — advisory session-drift logging (no blocking)
- **F6** — encrypted `pending_auth` cookie + 15-line concern
- **F7** — unified magic-link error responses (code-validity leak)

### Hardening

- **H1** — `SecurityEventLogger` service + instrumentation across auth surface
- **H2** — removed `auto_login_in_development` footgun

### Follow-ups (out of scope, tracked separately)

- #382 — Sign out everywhere button
- #383 — Per-account rate limits for hosted deployment
- #384 — Promote F4 to Solid Queue recurring job

## Test plan

- [ ] `bundle exec rake test` green (includes new unit, controller, integration tests)
- [ ] `bundle exec rake lint` clean
- [ ] `bundle exec rake security` clean
- [ ] `bundle exec rake release:audit:security` green (Playwright pen tests)
- [ ] Manual: sign in via magic link, check `[security]` log lines for expected events
- [ ] Manual: verify session drift logs on UA/IP change, does not block the request
- [ ] Grep `auto_login_in_development` / `skip_dev_auto_login` / `REMOTE_USER` in `app/` and `config/` — zero hits

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Post-implementation

- [ ] **Announce completion** with the PR URL and a summary of any unexpected detours encountered during implementation.
- [ ] **Leave `feature/security-audit` open** until the PR is reviewed and merged. Do not merge from the CLI without user approval.
