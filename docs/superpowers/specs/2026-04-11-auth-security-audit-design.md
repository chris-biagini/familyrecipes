# Auth Security Audit Design

A structured post-merge security review of the Phase-2 magic-link auth stack
(PR #368 → #375) before the hosted-deployment pre-deploy punch list proceeds.
Catalogues every real vulnerability and cohesive hardening gap, then bundles
the fixes into a single PR against `feature/security-audit`.

Closes GH #373.

## Goals

- Identify concrete auth vulnerabilities and quantify their impact
- Close the vulnerabilities in one cohesive PR
- Add observability for auth events (audit-log gap, not a vuln)
- Remove the `auto_login_in_development` footgun rather than papering over it
- Lock in regression coverage via unit, controller, and Playwright pen tests
- Produce a methodology artifact we can re-run after future auth changes

## Non-Goals

- Hosted-deployment hardening (per-account rate limits, secret rotation
  procedures, Fly/Kamal config) — deferred to Phase 3/4 deployment work
- Multi-tenant query auditing — covered by `acts_as_tenant` + existing
  `tenant_isolation_test.rb` pen tests
- CSP changes — already tighter than Fizzy's reference implementation
- Passkeys, OAuth, 2FA, account recovery UX
- Email-change flow or "trusted device" toggles
- Refactoring that isn't load-bearing for a fix

## Threat Model

Assumptions we're designing against:

- HTTPS is enforced in production (`force_ssl = true`); no inbound proxy
  forwarding untrusted headers
- Attacker can hit any public endpoint at arbitrary rate subject to rate
  limits
- Attacker does **not** have `secret_key_base` — breaking signed cookies or
  `MessageVerifier` tokens is out of scope
- Homelab reality: users roam IPs (mobile, VPN, browser updates), so any
  session pinning is advisory-log, not enforcing
- Trusted-header auth is gone (verified: zero references to `REMOTE_USER`,
  `authenticate_from_headers`, or `trusted_header` in `app/**` or `config/**`;
  the obsoleted `2026-04-10-harden-trusted-header-auth-plan.md` never landed)

## Audit Methodology

A repeatable process, documented here so it can be re-run after material auth
changes:

1. **Inventory the attack surface.** Every controller that produces a
   logged-in session (sessions, magic_links, joins, transfers, dev_sessions)
   plus the `Authentication` and `PendingAuthToken` concerns and all
   models touched by them.
2. **Read the Rails Security Guide** relevant chapters (sessions, CSRF,
   user management, injection, mass assignment, intranet and admin security).
3. **Parallel subagent deep-read** of our auth code with explicit prompts
   on information disclosure, token handling, session fixation, CSRF, mass
   assignment, timing attacks, open redirect, and email enumeration.
4. **Parallel Fizzy comparison** (basecamp/fizzy is our reference
   implementation). Identify patterns Fizzy uses that we don't, patterns we
   use that Fizzy doesn't, and patterns we borrowed but may have misapplied.
5. **Verify every subagent claim against the actual code.** Subagents
   hallucinate; file:line references must be re-read before anything is
   accepted. Discarded claims are documented as "not a bug."
6. **Classify by severity**: Critical / High / Medium / Low / Operational /
   Hardening.
7. **Bundle cohesive fixes into one PR** when the surface is small enough
   that coordinating across PRs costs more than it saves.

## Findings Catalogue

### Vulnerabilities

#### F1. `JoinsController#create` is unrate-limited — High

`app/controllers/joins_controller.rb:19` applies `rate_limit` only to
`:verify`. `POST /join/complete` has no limit. An attacker holding a valid
`signed_kitchen_id` (cheap to get: hit `/join` with any valid join code) can
enumerate email addresses by submitting different emails and observing
whether the controller renders the name form (new user) or issues a link
(existing user). Branch is visible at `joins_controller.rb:46` via
`new_user_missing_name?`.

**Fix.** Add the same rate limit as `SessionsController#create`:

```ruby
rate_limit to: 10, within: 15.minutes, by: -> { request.remote_ip }, only: :create
```

#### F2. Timing-based email enumeration via `deliver_now` — Medium

`app/controllers/sessions_controller.rb:61` and
`app/controllers/joins_controller.rb:67` both call
`MagicLinkMailer.sign_in_instructions(link).deliver_now`.
`SessionsController#issue_magic_link_for` returns early at line 51 for
unknown or membershipless emails without doing any work. Response time
differs between the two branches by whatever `deliver_now` takes
(~50–500ms for real SMTP, ~5ms for the homelab `:logger` delivery).

**Fix.** Two sub-changes:

1. Switch both call sites to `.deliver_later`. The Active Job adapter is
   `:async` in dev, Solid Queue in prod. The `:logger` delivery method
   works with `deliver_later` — it just queues instead of delivering
   inline.
2. Restructure `issue_magic_link_for` so both branches do comparable
   work before returning: the unknown-email branch calls
   `SecurityEventLogger.log(:unknown_email_auth_attempt, email:)` (a
   non-trivial string-format + `Rails.logger.info` call); the
   known-email branch calls `deliver_later` (an enqueue, not a send).
   Both return in ~1–5ms. The two are not bit-identical, but the
   gap collapses from 50–500ms to noise.

We explicitly accept that a determined attacker with a stopwatch and
perfect network timing can still distinguish the two branches. A
fixed-delay `sleep` was considered and rejected — adding artificial
latency is worse than accepting a narrowing imperfection.

#### F3. Session cookie stores raw PK, not `signed_id` — Low (defense-in-depth)

`app/controllers/concerns/authentication.rb:46` writes `new_session.id`
into `cookies.signed[:session_id]`; line 36 reads it with
`Session.find_by(id:)`. Same pattern in
`app/channels/application_cable/connection.rb:17`. The cookie is already
signed by `cookies.signed`, so forgery requires `secret_key_base`.
However, Fizzy's pattern — `session.signed_id(purpose: :session)` +
`Session.find_signed(..., purpose: :session)` — adds a purpose-scoped
second layer and follows the Rails 8 Authentication Zero idiom. Cheap
defense-in-depth.

**Fix.** Store `session.signed_id(purpose: :session)` in the cookie
value; read with `Session.find_signed(..., purpose: :session)`. Two
files: `authentication.rb`, `application_cable/connection.rb`.

**Deployment note.** Existing sessions fail to resume on first boot
after deploy, forcing re-login. Acceptable — no production traffic yet.

#### F4. `MagicLink` rows accumulate forever — Low (operational)

No cleanup mechanism for consumed or expired rows. The table grows
unboundedly on an attacker-touched surface. Fizzy runs cleanup every 4
hours via `config/recurring.yml`, but Solid Queue isn't installed in
this app (verified: no queue adapter configured, default `:async`
adapter has no recurring runner). Installing Solid Queue is
deployment-phase scope and out of bounds for this PR.

**Fix.** Opportunistic inline cleanup inside `MagicLink.consume`.
Every successful consume also deletes expired and previously-consumed
rows. Self-contained, no infrastructure, and rows naturally get pruned
whenever the table is actively touched.

```ruby
# app/models/magic_link.rb
def self.consume(raw_code)
  sanitized = normalize(raw_code)
  return nil if sanitized.blank?

  updated = where(code: sanitized, consumed_at: nil)
            .where('expires_at > ?', Time.current)
            .update_all(consumed_at: Time.current)
  return nil unless updated == 1

  cleanup_expired
  find_by(code: sanitized)
end

def self.cleanup_expired
  where('expires_at < ? OR (consumed_at IS NOT NULL AND consumed_at < ?)',
        Time.current, 1.hour.ago).delete_all
end
```

The 1-hour grace on `consumed_at` keeps recently-consumed rows around
long enough that a malformed re-submit doesn't return a confusing
`nil` (race between `update_all` and `find_by`). Expired-but-unconsumed
rows are deleted immediately since there's no reason to retain them.

When Solid Queue lands in the hosted-deployment phase, promote this to
a recurring job and remove the inline call. Tracked as a follow-up.

#### F5. No session pinning or drift detection — Medium

`Session` has `ip_address` and `user_agent` columns, written at creation
(`authentication.rb:41-42`) but never validated on resume. A stolen
signed cookie works from any IP or browser.

**Fix.** Advisory logging, not enforcement. Homelab mobile-roaming,
VPNs, and browser updates make strict pinning a UX disaster. Log a
`session_drift` event via `SecurityEventLogger` (H1) when the stored IP
or UA differs from the current request. No blocking, no forced
re-auth.

If drift logs turn out to be noisy in practice, downgrade the trigger
to "log only when both IP *and* UA differ".

A companion "sign out everywhere" button in the settings dialog —
backed by a `User#destroy_all_sessions!` method — is tracked as a
follow-up issue. Not in this PR: the advisory log covers the immediate
audit gap, and the button is UX work that can ship independently.

#### F6. `pending_auth` cookie is signed but not encrypted — Very Low

`app/controllers/concerns/pending_auth_token.rb:26` uses
`cookies.signed[:pending_auth]`. The email is visible in the cookie
value to anyone who can read the user's cookies (which they already
could, since the user just typed the email on the previous form). No
meaningful confidentiality loss, but `cookies.encrypted` is a one-line
change and also lets us drop the internal `MessageVerifier` wrapping.

**Fix.** Collapse the 42-line concern to ~15 lines using
`cookies.encrypted` with an `expires:` option:

```ruby
module PendingAuthToken
  extend ActiveSupport::Concern

  def set_pending_auth_email(email)
    cookies.encrypted[:pending_auth] = {
      value: email, expires: 15.minutes.from_now,
      httponly: true, same_site: :lax, secure: Rails.env.production?
    }
  end

  def pending_auth_email = cookies.encrypted[:pending_auth].presence
  def clear_pending_auth = cookies.delete(:pending_auth)
end
```

#### F7. Code-validity leak in `MagicLinksController` — Low

`render_invalid` (`magic_links_controller.rb:56`, 200 + form) and
`fail_mismatch` (line 62, 302 + redirect) return materially different
responses. An attacker without the `pending_auth` cookie but with an
intercepted code gets the 302; without a valid code gets 200. This
reveals code validity to a cookie-less attacker, bounded by the
10/15-min rate limit.

**Fix.** Unify the two error paths. Both conditions collapse into a
single `render_invalid` call with the same 200 status, same flash, same
`render :new`. Also stop clearing `pending_auth` on mismatch — the
cookie expires in 15 min on its own, and keeping it lets the user retry
without starting over.

```ruby
def create
  link = MagicLink.consume(params[:code])
  return render_invalid unless link && pending_auth_email == link.user.email
  # ...success path unchanged...
end
```

Delete `fail_mismatch` entirely.

### Hardening (non-vulnerability)

#### H1. `SecurityEventLogger` + instrumentation

No structured record of login success/failure, rate-limit hits, token
consume failures, or transfer-token use. Observability and forensics
gap.

**Design decision.** A narrow service object, not an
`ActiveSupport::Notifications` subscriber. Notifications add async
complexity that buys us nothing for a homelab-scale app. If a future
hosted-deployment phase needs an async subscriber, we can bolt one on.

```ruby
# app/services/security_event_logger.rb
class SecurityEventLogger
  def self.log(event, **attrs)
    Rails.logger.tagged('security') do
      Rails.logger.info({ event: event, at: Time.current.iso8601, **attrs }.to_json)
    end
  end
end
```

**Instrumentation points:**

| Call site | Event |
|---|---|
| `SessionsController#create` (known email) | `:magic_link_issued` (purpose: sign_in) |
| `SessionsController#create` (unknown email) | `:unknown_email_auth_attempt` |
| `JoinsController#create` | `:magic_link_issued` (purpose: join) |
| `MagicLinksController#create` (success) | `:magic_link_consumed` |
| `MagicLinksController#create` (failure) | `:magic_link_consume_failed` (with reason) |
| `Authentication#start_new_session_for` | `:session_created` |
| `Authentication#terminate_session` | `:session_destroyed` |
| `Authentication#warn_on_session_drift` | `:session_drift` |
| `TransfersController#show` | `:transfer_token_consumed` |
| Rate-limited endpoints (on trip) | `:rate_limited` |

The rate-limit hook uses the `with:` block on Rails 8's `rate_limit`
macro to explicitly call `SecurityEventLogger.log`. Rails' default
logger output is kept in parallel.

#### H2. Remove `auto_login_in_development`

`application_controller.rb:61-70` auto-logs in as `User.first` in dev
when no session and no `skip_dev_auto_login` cookie. Trivial benefit
(saves one click per `bin/dev` restart). Non-trivial footgun (a single
misconfigured deploy that runs with `Rails.env == 'development'` in
production turns this into total auth bypass).

**Fix.** Delete the method and everything propping it up, rather than
adding a production guardrail. Affected:

- `app/controllers/application_controller.rb:23, 61-70` — delete the
  `before_action` and the method
- `app/controllers/sessions_controller.rb:39` — delete
  `cookies[:skip_dev_auto_login] = true`
- `app/controllers/dev_sessions_controller.rb:19` — delete
  `cookies.delete(:skip_dev_auto_login)`
- `test/security/helpers.mjs` — drop the `skip_dev_auto_login=1`
  plumbing (memory notes this was a flake-fix for exactly the behavior
  we're removing; it becomes dead code)

Dev workflow after removal: `bin/dev`, then visit `/dev/login/1` once
per session. Trivial.

#### H3. Test coverage

**Unit / controller tests:**

- `test/controllers/joins_controller_test.rb` — assert rate limit fires
  on `:create`, assert no response differential between "new user" and
  "existing user" beyond what we can measure
- `test/controllers/sessions_controller_test.rb` — assert `deliver_later`
  via `ActionMailer::TestHelper#assert_enqueued_emails`; assert both
  branches call `SecurityEventLogger.log`
- `test/controllers/magic_links_controller_test.rb` — assert unified
  error response (no 302 on mismatch); assert `pending_auth` cookie
  persists across failed attempts
- `test/models/magic_link_test.rb` — assert `cleanup_expired` deletes
  the right rows and leaves fresh unconsumed links alone
- New `test/services/security_event_logger_test.rb` — assert the JSON
  shape and the `security` tag
- New `test/integration/session_drift_test.rb` — assert drift is logged
  and does not block the request
- `test/controllers/application_controller_test.rb` — assert no
  auto-login occurs when no explicit `log_in` call was made

**Pen tests (Playwright):**

- `test/security/auth_security.spec.mjs` — add `/join/complete`
  rate-limit case
- New `test/security/timing_invariance.spec.mjs` — issue 10 requests
  each for known and unknown emails, assert the distributions are
  within a loose tolerance (catching regressions, not doing
  statistics)
- `test/security/helpers.mjs` — remove `skip_dev_auto_login` plumbing

## Rollout

### Branch strategy

Work happens on `feature/security-audit`, branched from `main` before
this design doc was committed (per the "branch before first commit"
workflow rule). One squash-merged PR at the end.

### Implementation order

Ordered by risk and dependency:

1. **H2 (remove auto-login)** — reduces dev-environment complexity for
   everything that follows; any test regressions surface immediately
2. **F4 (MagicLink cleanup)** — purely additive
3. **F6 (pending_auth simplification)** — localized to one concern
4. **F7 (unify error responses)** — one controller
5. **F1 (rate limit `/join/complete`)** — one line + test
6. **F2 (deliver_later + branch convergence)** — two controllers
7. **H1 (SecurityEventLogger)** — service + instrumentation sweep
8. **F5 (advisory pinning)** — depends on H1
9. **F3 (signed_id session cookie)** — last; only change that
   invalidates existing sessions

### Risks

- **F3 session cutover.** Existing dev sessions and any local
  Playwright state bounce to `/sessions/new` on first boot. No prod
  traffic yet, so this is fine. `DevSessionsController#create` still
  calls the updated `start_new_session_for`, so `test/security/` seeding
  continues to work.
- **F2 `deliver_later` + homelab `:logger` delivery.** The async adapter
  runs the mailer in a thread; the logged code appears in `docker logs`
  a few ms after the request rather than synchronously. Read-from-logs
  still works; it just takes a beat. Worth a line in the homelab README.
- **H2 removing auto-login.** Potentially 5–20 tests break if any
  relied on implicit auto-login. We'll find out during implementation
  and add explicit `log_in` calls where needed.
- **F5 advisory pinning false positives.** Mobile ↔ WiFi handoffs will
  log every time. Expected, but log volume is worth watching. Fallback:
  downgrade the trigger to "log only when both IP and UA differ".

## Acceptance Criteria

- All new tests pass
- `rake test` green (Bullet clean, no new Brakeman warnings)
- `rake security` clean
- `rake release:audit:security` green (Playwright pen tests)
- Manual smoke: `bin/dev`, visit `/sessions/new`, enter email, read
  code from `docker logs`, consume it, hit an authenticated page from a
  different user-agent via curl, observe `session_drift` log line
- `auto_login_in_development` grep returns zero hits in `app/` and
  `config/`
- `REMOTE_USER`/`trusted_header` grep returns zero hits in runtime code
  (already true; asserted in the audit as current state)
- Single PR squash-merged to `main`, reviewed before merge

## Discarded Claims

Subagent audit passes raised three claims that were wrong or overstated
on verification; they're listed here so future re-audits don't
re-surface them as "new" findings:

- **"Set-Cookie differentiates known vs unknown emails"** — Wrong.
  `sessions_controller.rb:33` always calls `set_pending_auth_email`
  after `issue_magic_link_for` regardless of whether a link was issued.
  Only the timing side-channel remains (tracked as F2).
- **"`MagicLink.consume` doesn't validate purpose"** — Not a bug. The
  `purpose` column is implicitly enforced by the presence or absence of
  `link.kitchen` combined with the `if link.join?` check in
  `MagicLinksController#create:34`.
- **"Session fixation is critical"** — Misframed. Rails session
  fixation is about an attacker planting a session cookie in the
  victim's browser. Our session cookie is signed, so forgery requires
  `secret_key_base`. The real issue is captured as F5 (no
  rotation/pinning) and is Medium, not Critical.

## Follow-ups (out of scope, track as issues)

- **Close #365** (harden trusted-header auth) as moot — the code path
  was removed in #375. The obsoleted plan at
  `docs/superpowers/plans/2026-04-10-harden-trusted-header-auth-plan.md`
  should also be deleted or moved to an archive directory.
- **"Sign out everywhere" button** in settings dialog — needs a
  `User#destroy_all_sessions!` method and a settings-dialog button.
- **Per-account rate limits** (not just per-IP) for the hosted
  deployment phase — current per-IP limits are fine for homelab scale
  but don't help against a NAT'd attacker at scale.
- **Magic link code entropy** — 28⁶ ≈ 481M = ~29 bits. Acceptable with
  current rate limits but on the low end. Revisit if/when rate limits
  change for hosted deployment.
- **Promote F4 to a real recurring job** when Solid Queue is installed
  during the hosted-deployment phase. The opportunistic inline cleanup
  is a bridge, not the intended end state.
