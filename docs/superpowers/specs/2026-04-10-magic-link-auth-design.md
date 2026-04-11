# Magic Link Auth Design (Phase 2)

Replaces the join-code-as-password auth model with email-verified magic link
sign-in, deletes the trusted-header auth path, and readies the app for an
invite-only beta on fly.io. Supersedes and collapses the old Phase 2
(email-verified kitchen creation) and Phase 3 (magic link re-auth) outlines
from `2026-04-08-auth-system-design.md` into a single phase.

## Goals

- Safe to expose to the public internet on fly.io as an invite-only beta
- Email verification is the auth anchor — no shared-password path remains
- One auth flow to reason about, not two; no homelab vs. hosted branching
- Minimal code added, meaningful code removed
- Join code continues to exist, but purely as an invitation secret

## Non-Goals

- Self-serve kitchen creation in hosted mode (closed for the beta)
- Passkeys, OAuth, or any alternative auth mechanism
- Email change flow, trusted-device toggles, password fallback
- Billing, admin dashboard, audit log of sign-in events
- `deliver_later` / background job delivery (synchronous until we need async)

## Design Decisions

**Email is the auth anchor.** Every sign-in and every new membership requires
proving you control the email address. The join code gates who is *allowed*
to propose a new membership; the magic link gates who is *authenticated*.

**Fizzy-style dual-delivery.** SMTP required for hosted; a Rails logger
fallback delivers the magic link to stdout when `SMTP_ADDRESS` is unset. Same
code path, same DB record, same email content — just a different transport.
Homelab installs without outbound email still work via `docker logs`.

**Single auth flow.** The trusted-header / Authelia path is deleted. The
author (the only existing homelab user) signs in via magic link like everyone
else. Deleting ~300 lines of security-critical code is worth more than
preserving an invisible-sign-in UX that mattered on LAN and doesn't matter on
the public internet.

**Email-first front door.** `/sessions/new` is the primary entry: one email
field, nothing else. Returning members never touch the join code again after
their first join. New members hit `/join`, enter a code and email, then also
verify via magic link before a membership is created.

**Single-use magic links with 15-minute expiry.** Fizzy's pattern. A link
sitting in an inbox for 15 minutes is more exposed than a QR on-screen for 5,
so single-use is the right default. `MagicLink.consume(code)` is a single
atomic update with a `WHERE consumed_at IS NULL AND expires_at > NOW()` guard.

**6-character alphanumeric code.** `A-Z2-9` minus `I, O` = 32 chars. Six
characters give ~10⁹ combinations. Combined with single-use and rate
limiting, brute force is infeasible. The code is email-mangle-proof: if a
mail client breaks the URL, the user can still type the code directly.

**Anti-enumeration.** `/sessions/new` returns the same response for known
and unknown emails. Unknown emails don't create a DB record; the pending-auth
token just carries the typed email forward, and the code-entry screen
displays the same "check your email" message regardless. An attacker cannot
enumerate kitchen members by probing the sign-in form.

**Invite-only beta gate.** Kitchen creation (`/new`) is closed in hosted
deployments via `DISABLE_SIGNUPS=true`. Homelab fresh installs still let you
create the first kitchen; additional kitchens require `ALLOW_SIGNUPS=true`.
Beta kitchens on fly.io are seeded via `rake kitchen:create` from a shell
console. No hosted signup flow ships in this phase.

**No `Identity` / `User` split.** Fizzy separates the auth principal
(`Identity`) from the per-tenant membership (`User`). Our `User` + `Membership`
already models the same idea with different names; the rename would be pure
churn. We keep `User` as the auth principal (email, sessions, magic links)
and `Membership` as the per-kitchen join.

**Synchronous mail delivery.** `deliver_now`, not `deliver_later`. Solid
Queue wiring is skipped entirely for this phase. When first async job ships,
we'll wire it and flip the mailer in the same PR.

## Data Model

### `MagicLink` (new)

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | PK |
| `user_id` | bigint | FK, not null (unknown emails don't create rows — see Flow A) |
| `code` | string(6) | unique index, uppercase `A-Z2-9` minus `I, O` (32 chars) |
| `purpose` | integer | enum: `sign_in`, `join` |
| `kitchen_id` | bigint | FK, nullable, set only when `purpose = join` |
| `expires_at` | datetime | `15.minutes.from_now` on create |
| `consumed_at` | datetime | nullable; set atomically on redeem |
| `request_ip` | string | stored for the "was this you?" display |
| `request_user_agent` | string | stored for the "was this you?" display |
| `created_at` | datetime | |
| `updated_at` | datetime | |

Indexes:

- `magic_links(code)` unique
- `magic_links(user_id)`
- `magic_links(expires_at)` for cleanup scans

Class methods:

```ruby
def self.consume(code)
  sanitized = normalize(code)
  updated = where(code: sanitized, consumed_at: nil)
    .where("expires_at > ?", Time.current)
    .update_all(consumed_at: Time.current)
  find_by(code: sanitized) if updated == 1
end

def self.cleanup
  where("expires_at < ?", 1.hour.ago).delete_all
end
```

`consume` is TOCTOU-free: the update itself is the check. Periodic cleanup
runs via a future Solid Queue job (not wired in this phase; cleanup can run
on boot in a `rails runner` cron instead, or not at all — the table grows
slowly and a `where consumed_at is not null` index sweep is cheap).

### `User#email_verified_at`

Already planted as a nullable datetime in the previous phase. This work makes
it meaningful: set to `Time.current` on the first successful
`MagicLinksController#create` and never cleared. Existing users remain `nil`
until they next sign in — we do not force re-verification on deploy.

### `Kitchen#join_code`

Unchanged. Four-word magic phrase, encrypted deterministic, rotatable. Only
the role changes: this is now an invitation secret, not an auth secret.

### Schema Migration

One migration: `create_magic_links`. No backfills, no data transforms, no
other schema changes.

## User Flows

### Flow A — Returning member signs in

1. Visitor hits `/sessions/new` (or any authenticated path, which redirects
   there).
2. Form: email address.
3. `SessionsController#create`:
   - Rate-limit check (10 per 15 min per IP).
   - `user = User.find_by(email: normalized)`.
   - **Known user with ≥ 1 membership:**
     - Create `MagicLink(user:, purpose: :sign_in, request_ip:,
       request_user_agent:)`.
     - `MagicLinkMailer.sign_in_instructions(magic_link).deliver_now`.
   - **Unknown email, or known but with zero memberships:**
     - No DB write.
     - No email sent.
   - Either way: build a signed `pending_auth` token carrying the normalized
     email, `MessageVerifier` purpose `:pending_auth`, 15-minute expiry.
     Set it as a signed cookie. Redirect to `/sessions/magic_link`. The
     cookie does *not* need to carry the magic link ID — the code-entry
     action looks up the link via the code itself and then cross-checks the
     user's email against the cookie.
4. `MagicLinksController#new` ("check your email"):
   - Verifies the signed pending-auth cookie. Missing/expired → redirect to
     `/sessions/new` with "start over" flash.
   - Displays the masked email (`…@gmail.com`), the request metadata
     ("requested at 15:42 from $user_agent"), a 6-character code input, and
     a "resend" link back to `/sessions/new`.
5. User types code (or clicks email link which pre-fills it) →
   `MagicLinksController#create`:
   - Rate-limit check (10 per 15 min per IP).
   - `magic_link = MagicLink.consume(params[:code])`.
   - Nil → "Invalid or expired code" error, re-render form.
   - Verify `magic_link.user.email == signed_token.email`. Mismatch → fail
     closed, clear cookie, redirect to `/sessions/new`.
   - `start_new_session_for(magic_link.user)`.
   - `user.update!(email_verified_at: Time.current)` if currently `nil`.
   - Clear pending-auth cookie.
   - Redirect to the user's kitchen homepage (first membership's kitchen).

### Flow B — New member joins a kitchen

1. Visitor hits `/join` (URL shared alongside the invitation).
2. `JoinsController#new` — code form.
3. `JoinsController#verify` — validates the code, renders the email + name
   form with a signed kitchen ID (`MessageVerifier` `:join` purpose, 15 min).
4. `JoinsController#create`:
   - Verify signed kitchen ID.
   - `user = User.find_or_create_by!(email: normalized) do |u| u.name = params[:name] end`.
   - `magic_link = MagicLink.create!(user:, purpose: :join, kitchen_id:,
     request_ip:, request_user_agent:)`.
   - `MagicLinkMailer.sign_in_instructions(magic_link).deliver_now`.
   - Set signed `pending_auth` cookie carrying the normalized email
     (same shape as Flow A).
   - Redirect to `/sessions/magic_link`.
5. `MagicLinksController#create` (same action as Flow A):
   - Consume the link.
   - Verify email matches pending-auth token.
   - If `purpose: :join`: `Membership.find_or_create_by!(user:,
     kitchen: magic_link.kitchen, role: "member")`. Idempotent in case the
     user double-submits.
   - `start_new_session_for(user)`.
   - Set `email_verified_at`.
   - Redirect to the joined kitchen's homepage.

No welcome screen. The join code is not a secret to preserve post-join; the
user knows it already, and showing it again was a Phase 1.5 pattern that
leaked it to shoulder-surfers and made it feel password-ish.

### Flow C — Kitchen creation (homelab / dev only)

1. Visitor hits `/new`.
2. `KitchensController` `before_action :enforce_accepting_signups`:
   - `Kitchen.accepting_signups?` returns false → 404.
   - True → continue.
3. Form: your name, your email, kitchen name. Unchanged from today.
4. `KitchensController#create` — single transaction, creates Kitchen + User +
   Membership (owner) + MealPlan, `start_new_session_for(user)`, redirects.
   No email verification — the first user of a homelab install has root
   trust, and hosted installs don't reach this path.

For the hosted beta, kitchen creation happens via a new rake task:

```bash
bin/rake kitchen:create[BiaginiFamily,chris@example.com,Chris]
```

which prints the join code to stdout. The operator shares it with the first
member by hand.

### Flow D — Logout

`SessionsController#destroy`: `terminate_session`, redirect to `/` with
`flash[:notice] = "You've been signed out."` **No interstitial, no join code
display.** The old `app/views/sessions/destroy.html.erb` is deleted.

## Routes

```
# Auth
get    '/sessions/new'        → sessions#new
post   '/sessions'            → sessions#create       # email entry
get    '/sessions/magic_link' → magic_links#new       # "check your email" + code entry
post   '/sessions/magic_link' → magic_links#create    # consume code → session
delete '/logout'              → sessions#destroy

# Invitation flow (modified)
get    '/join'                → joins#new
post   '/join'                → joins#verify
post   '/join/complete'       → joins#create          # now issues a magic link

# Homelab kitchen creation (404 in hosted)
get    '/new'                 → kitchens#new
post   '/new'                 → kitchens#create

# Self-transfer QR (Phase 1.5, retained)
post   '/transfer'            → transfers#create
get    '/transfer/:token'     → transfers#show
```

### Deleted routes

- `get '/welcome'` — the join-code-revealing welcome screen
- `post '/members/:id/login_link'` — member-to-member login links

## Controllers

### `SessionsController` (rewritten)

- `allow_unauthenticated_access`
- `skip_before_action :set_kitchen_from_path`
- `rate_limit to: 10, within: 15.minutes, only: :create`
- `new` — render email form; redirect to root if already signed in
- `create`:
  - Normalize and validate email format
  - Look up user
  - Known with memberships: create magic link, deliver, set pending-auth
    cookie
  - Otherwise: no DB write, still set pending-auth cookie carrying the typed
    email (anti-enumeration)
  - Redirect to `/sessions/magic_link`
- `destroy` — `terminate_session`, redirect to root with flash

### `MagicLinksController` (new)

- `allow_unauthenticated_access`
- `skip_before_action :set_kitchen_from_path`
- `rate_limit to: 10, within: 15.minutes, only: :create`
- `before_action :ensure_pending_auth_token` — verifies the signed cookie;
  missing/expired → redirect to `/sessions/new`
- `new` — render code entry form with masked email + request metadata
- `create`:
  - `MagicLink.consume(params[:code])`
  - Nil → re-render with error
  - Email mismatch against pending-auth token → fail closed, clear cookie,
    redirect to `/sessions/new`
  - `start_new_session_for(user)`
  - Set `email_verified_at` if nil
  - If `purpose: :join`, `find_or_create_by!` the Membership
  - Clear pending-auth cookie
  - Redirect to the target kitchen

### `JoinsController` (modified)

`verify` unchanged. `create` no longer calls `start_new_session_for`
directly. Instead it:

- `find_or_create_by!(User)` by email
- Creates a `MagicLink(purpose: :join, kitchen:)`
- Delivers the mail
- Sets the pending-auth cookie
- Redirects to `/sessions/magic_link`

The membership is created inside `MagicLinksController#create` when the link
is consumed. This keeps the "no session without verified email" invariant in
one place.

### `KitchensController` (modified)

- New `before_action :enforce_accepting_signups`:

  ```ruby
  def enforce_accepting_signups
    head :not_found unless Kitchen.accepting_signups?
  end
  ```

- Everything else unchanged.

### `Authentication` concern (shrunk)

Keep: `resume_session`, `start_new_session_for`, `terminate_session`,
`require_membership`, `require_authentication`.

Delete: `authenticate_from_headers`, `trusted_header_ip_allowed?`,
`auto_join_sole_kitchen`, and all supporting helpers.

### `TransfersController` (modified)

Keep `create` (self-transfer QR — device-to-device, 5-minute
`signed_id(:transfer)`) and `show` (consume token → session). Delete
`create_for_member` and the corresponding route. The member-to-member login
link is redundant once email magic links exist: asking someone to sign in is
now equivalent to asking them to type their email at `/sessions/new`.

### `DevSessionsController` (retained, unchanged)

Gated to `Rails.env.local?` only. Used by the Minitest `log_in` helper so
controller tests don't have to go through a real mailer. Not exposed in
production; the view file stays deleted.

### Deleted controllers

- `WelcomeController` — the post-join welcome screen

## `Kitchen.accepting_signups?`

```ruby
class Kitchen < ApplicationRecord
  def self.accepting_signups?
    return false if ENV["DISABLE_SIGNUPS"] == "true"
    return true  if count.zero?
    ENV["ALLOW_SIGNUPS"] == "true"
  end
end
```

Precedence: explicit disable wins > fresh install wins > explicit enable
wins > default deny.

- **Hosted fly.io:** `DISABLE_SIGNUPS=true` → `/new` is a 404, period
- **Homelab fresh install:** no env vars, zero kitchens → `/new` works
- **Homelab after first kitchen:** 404 unless operator sets `ALLOW_SIGNUPS=true`

## Mailer

### `MagicLinkMailer`

```ruby
class MagicLinkMailer < ApplicationMailer
  def sign_in_instructions(magic_link)
    @magic_link = magic_link
    @code = magic_link.code
    @expires_in = "15 minutes"
    @request_ip = magic_link.request_ip
    @request_user_agent = magic_link.request_user_agent
    @login_url = sessions_magic_link_url(code: magic_link.code)
    mail(to: magic_link.user.email, subject: "Sign in to Family Recipes")
  end
end
```

Templates: `app/views/magic_link_mailer/sign_in_instructions.{html,text}.erb`.
Multipart, no images, minimal inline CSS. Shows the code prominently, a
one-click link, the expiry, the request metadata, and a "wasn't you? ignore
this email" line.

Standard Rails mailer layout at `app/views/layouts/mailer.{html,text}.erb`.

### Delivery config

`config/environments/production.rb`:

```ruby
config.action_mailer.delivery_method = ENV["SMTP_ADDRESS"].present? ? :smtp : :logger
config.action_mailer.smtp_settings = {
  address:              ENV["SMTP_ADDRESS"],
  port:                 ENV.fetch("SMTP_PORT", 587).to_i,
  user_name:            ENV["SMTP_USERNAME"],
  password:             ENV["SMTP_PASSWORD"],
  authentication:       ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym,
  enable_starttls_auto: true,
}
config.action_mailer.default_url_options = {
  host:     URI.parse(ENV.fetch("BASE_URL", "http://localhost:3030")).host,
  protocol: :https,
}
config.action_mailer.default options: { from: ENV.fetch("MAILER_FROM_ADDRESS", "no-reply@localhost") }
```

Logger delivery is the default fallback: if `SMTP_ADDRESS` is unset, the full
email writes to stdout / Rails log. A homelabber without SMTP retrieves the
code via `docker logs familyrecipes | grep -A20 "Magic link"`.

### Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `BASE_URL` | yes (for correct magic link URLs) | `http://localhost:3030` | canonical public URL |
| `MAILER_FROM_ADDRESS` | yes | `no-reply@localhost` | `From:` header |
| `SMTP_ADDRESS` | no | unset → log delivery | SMTP host |
| `SMTP_PORT` | no | `587` | SMTP port |
| `SMTP_USERNAME` | no | — | SMTP auth |
| `SMTP_PASSWORD` | no | — | SMTP auth |
| `SMTP_AUTHENTICATION` | no | `plain` | SMTP auth method |
| `DISABLE_SIGNUPS` | no | unset | `true` on hosted |
| `ALLOW_SIGNUPS` | no | unset | `true` to allow multi-kitchen on homelab after first kitchen |

Added to `.env.example`, the README deploy section, and CLAUDE.md.

### Provider choice

SMTP intentionally — no provider SDK. The operator plugs creds for Postmark,
Resend, SendGrid, AWS SES, Mailgun, or an ISP relay identically. Provider
gems can be added later if we need template APIs or webhook ingestion.
Informal recommendation if the operator wants one: Postmark first, Resend
second, SES third.

## Security

### Threat model

The app sits on the public internet on fly.io behind a DNS name. Assume
attackers scan it, attempt credential stuffing, attempt email enumeration,
attempt brute-forcing codes, and attempt to replay tokens.

### Controls

- **Email as auth anchor.** Every sign-in and every new membership requires
  proving control of the email. No shared-password path remains.
- **Anti-enumeration.** `/sessions/new` returns the same response shape for
  known and unknown emails; unknown emails don't create DB rows or send mail.
  Rate limits cap probe rate independently.
- **Magic link brute force.** Code space 32⁶ ≈ 10⁹, single-use, 15-minute
  expiry, rate-limited 10 per 15 min per IP. An attacker's expected attempts
  to find a valid code in the window exceed the rate limit by 10⁶.
- **Single-use enforcement.** `MagicLink.consume(code)` is an atomic
  `update_all` guarded by `consumed_at IS NULL AND expires_at > NOW()`,
  succeeds iff one row is touched. TOCTOU-free under concurrency.
- **Signed pending-auth cookie.** The token carrying the typed email
  between `/sessions/new → /sessions/magic_link` uses Rails `MessageVerifier`
  with `purpose: :pending_auth`, 15-minute expiry. Code consumption verifies
  the consumed link's user email matches the cookie's email — prevents a
  passerby from hijacking a half-finished sign-in with a code they obtained
  elsewhere.
- **Request metadata displayed on code-entry screen.** "Requested at 15:42
  from Chrome on Mac in Seattle" catches phishing attempts where the attacker
  submitted the victim's email on a different device.
- **Email squatting closed.** Even if an attacker with the join code submits
  Bob's email at `/join`, the magic link goes to Bob's actual inbox. The
  attacker never sees the code, never consumes the link, never gets a
  membership.
- **Rate limits.**
  - `SessionsController#create`: 10 per 15 min per IP
  - `MagicLinksController#create`: 10 per 15 min per IP
  - `JoinsController#verify`: 10 per hour per IP (unchanged)
  - `KitchensController#create`: 5 per hour per IP (unchanged)

### Deleted surface

- Trusted-header auth (`authenticate_from_headers`, IP allowlist,
  `auto_join_sole_kitchen`)
- `WelcomeController` and the join-code-revealing welcome screen
- Logout interstitial that displayed the join code
- `TransfersController#create_for_member` and the member-to-member login
  link UI
- All associated tests, Brakeman allowlist entries, and Authelia setup docs

### Brakeman and dependency audit

`rake security` CI gate runs unchanged. Net-zero-to-negative findings
expected — the change removes auth code and adds standard Rails patterns.
No new `brakeman.ignore` entries anticipated.

## Testing

### Model tests

- `MagicLinkTest` — code generation uniqueness, expiry, atomic consume
  (including a concurrent-consume race test using threads), purpose enum,
  cleanup scope
- `UserTest` — `email_verified_at` set on first magic link consume, not
  cleared on subsequent; unchanged if already set

### Mailer tests

- `MagicLinkMailerTest` — delivered email contains the code, the link,
  the expiry, the request metadata; correct `to`, `from`, `subject`;
  multipart HTML + text
- `test/mailers/previews/magic_link_mailer_preview.rb` — for eyeballing at
  `/rails/mailers` in dev

### Controller integration tests

- `SessionsControllerTest` — rewritten. Known email happy path, unknown
  email anti-enumeration parity, rate limit, logged-in redirect, destroy
  clears session
- `MagicLinksControllerTest` — happy path, invalid code, expired code,
  double-consume fails, email mismatch fails, missing pending-auth cookie,
  rate limit, `purpose: :join` creates Membership idempotently
- `JoinsControllerTest` — updated. `create` no longer starts a session;
  asserts magic link + mail + redirect instead
- `KitchensControllerTest` — `accepting_signups?` gate: unset env returns
  success on fresh install, `DISABLE_SIGNUPS=true` returns 404,
  `ALLOW_SIGNUPS=true` after first kitchen returns success
- `AuthFlowTest` (new integration test) — full email → mailer → code →
  session happy path using `ActionMailer::Base.deliveries`

### Existing test helper

`log_in` continues to use `DevSessionsController` (gated to `Rails.env.local?`).
Forcing every controller test through a real mailer is out of proportion to
the value.

### Playwright security specs

- `auth_bypass.spec.mjs` — updated to reference the new routes; intent
  unchanged
- `tenant_isolation.spec.mjs` — unchanged
- `trusted_header.spec.mjs` — **deleted**
- `magic_link_auth.spec.mjs` (new) — happy path sign-in, brute-force defense
  (rate limit 429), single-use enforcement (reused code fails), expired code,
  mismatched email, enumeration parity (known vs unknown email → identical
  response shape)

### Bullet

`MagicLink.consume` returns a bare record; downstream code calls
`magic_link.user` and `magic_link.kitchen`. Add `includes(:user)` on the
consume path if Bullet flags it. Standard.

## Cutover

- **Your homelab install.** First hit of the deployed version lands on
  `/sessions/new`. You type your email, the logger delivers the code to the
  Rails log, you paste it in, you're signed in. Your existing kitchen,
  memberships, and sessions are untouched. `email_verified_at` flips from
  `nil` to `Time.current`.
- **Existing sessions.** Not invalidated. `resume_session` is unchanged;
  anyone with a live cookie stays signed in until it expires or they log out.
- **Existing `User` rows with `email_verified_at = nil`.** Verified lazily
  the next time they sign in. No forced re-verification.
- **Join codes.** Unchanged. Existing encrypted values stay. Their role
  changes from "password" to "invitation"; no data transform.
- **Schema migration.** One migration creates `magic_links`. No backfills.
- **Fly.io deploy steps** (for the PR body when we get there):
  1. Merge PR
  2. CI builds + pushes Docker image
  3. `fly secrets set DISABLE_SIGNUPS=true BASE_URL=... MAILER_FROM_ADDRESS=... SMTP_*=...`
  4. `fly deploy`
  5. `fly ssh console -C "bin/rake db:migrate"`
  6. `fly ssh console -C "bin/rake kitchen:create[BiaginiFamily,chris@example.com,Chris]"`
  7. Share the printed join code with the first member

## Bill of Materials

### Files added

- `app/models/magic_link.rb`
- `db/migrate/NNN_create_magic_links.rb`
- `app/controllers/magic_links_controller.rb`
- `app/mailers/magic_link_mailer.rb`
- `app/views/magic_link_mailer/sign_in_instructions.html.erb`
- `app/views/magic_link_mailer/sign_in_instructions.text.erb`
- `app/views/layouts/mailer.html.erb`
- `app/views/layouts/mailer.text.erb`
- `app/views/sessions/new.html.erb` (email form)
- `app/views/magic_links/new.html.erb` (code entry screen)
- `lib/tasks/kitchen.rake` (gains `kitchen:create`)
- `test/models/magic_link_test.rb`
- `test/mailers/magic_link_mailer_test.rb`
- `test/mailers/previews/magic_link_mailer_preview.rb`
- `test/controllers/magic_links_controller_test.rb`
- `test/integration/auth_flow_test.rb`
- `test/security/magic_link_auth.spec.mjs`

### Files modified

- `app/controllers/sessions_controller.rb` (rewritten: `new`, `create`,
  simplified `destroy`)
- `app/controllers/joins_controller.rb` (`create` issues magic link instead
  of session)
- `app/controllers/kitchens_controller.rb` (adds `accepting_signups?` gate)
- `app/controllers/transfers_controller.rb` (deletes `create_for_member`)
- `app/controllers/concerns/authentication.rb` (deletes trusted-header path,
  IP allowlist, `auto_join_sole_kitchen`)
- `app/models/kitchen.rb` (adds `self.accepting_signups?`)
- `app/views/kitchens/settings/_members.html.erb` (removes member login link
  button)
- `config/routes.rb`
- `config/environments/production.rb` (mailer config from env vars)
- `config/environments/development.rb` (defaults logger delivery)
- `.env.example`, `README.md`, `CLAUDE.md` (auth section rewrite)
- `test/controllers/sessions_controller_test.rb` (rewritten)
- `test/controllers/joins_controller_test.rb` (updated)
- `test/controllers/kitchens_controller_test.rb` (adds gate tests)
- `test/security/auth_bypass.spec.mjs` (updates routes)

### Files deleted

- `app/controllers/welcome_controller.rb`
- `app/views/welcome/show.html.erb`
- `app/views/sessions/destroy.html.erb` (logout interstitial)
- `test/security/trusted_header.spec.mjs`
- Any Authelia-specific docs under `docs/help/`

### Expected diff

Roughly -300 / +800 lines, net ~+500 LOC. Bulk of additions are tests,
templates, and the mailer. Controllers themselves are small because each
does one thing.

## Phasing Going Forward

This work collapses the old Phase 2 (email-verified kitchen creation) and
Phase 3 (magic link re-auth) from `2026-04-08-auth-system-design.md` into a
single new Phase 2.

- **Phase 2 (this spec):** Magic link auth, drop trusted-header, demote
  join code, fly.io beta. `/new` closed in hosted; kitchens seeded via rake.
- **Phase 3 (when we open fly.io to self-serve):** Open `/new` in hosted,
  require a magic link before kitchen creation. Trivial extension — add a
  `new_kitchen` value to the purpose enum, branch in the consume path.
  Add rate limiting + abuse handling + optional CAPTCHA.
- **Phase 4 (if ever):** Passkeys via `has_passkeys`. OAuth. Billing.
  Admin dashboard. Fizzy's `Gemfile.saas` split if a hosted-only dependency
  ever materializes. None of these are planned; listed so the phase map
  doesn't look like a cliff.

### Intentionally NOT in Phase 2

- Email-verified `/new` flow (hosted `/new` is just closed)
- Passkeys, OAuth, any alternative auth mechanism
- Billing, admin dashboard, audit log of sign-in events
- Email change flow
- "Trusted device" / "remember me" UI beyond the existing 30-day cookie
- Password fallback for users who can't get email
- Background delivery via Solid Queue (synchronous `deliver_now` until
  traffic demands otherwise)
