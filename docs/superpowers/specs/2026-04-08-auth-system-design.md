# Auth System Design

Passwordless authentication for the family recipes app, replacing the
Authelia-only trusted-header flow with join codes, session-based auth, and a
path toward a hosted multi-tenant model.

## Phasing

Three phases, each independently shippable:

- **Phase 1 (this spec):** Join codes, kitchen creation, session auth, re-auth
  via join code. Zero external dependencies. Beta-ready.
- **Phase 2 (future):** Email-verified kitchen creation. Action Mailer +
  provider. Gates self-service creation for hosted mode.
- **Phase 3 (future):** Magic link re-auth. Email-based login as an alternative
  to join code re-entry.

This spec covers Phase 1 in detail. Phases 2 and 3 are outlined at the end
for context.

## Design Decisions

**Passwordless.** No passwords, no password resets, no credential stuffing
surface. The join code is the shared secret; email is identification, not
authentication. Family members trust each other — the code proves you belong.

**Public reads, authenticated writes.** Current behavior preserved.
`allow_unauthenticated_access` stays on public controllers.
`require_membership` continues to gate writes. No changes to existing
authorization logic.

**Trusted-header auth stays.** The Authelia flow remains as a parallel auth
path. Headers checked first, session cookie as fallback. Zero disruption to
homelab setups.

**Self-service kitchen creation (ungated in Phase 1).** Anyone can create a
kitchen for beta. Phase 2 adds email verification for hosted mode.
`MULTI_KITCHEN=true` enables multiple kitchens (existing env var).

**Join codes over email invitations.** Kitchen owner shares a 4-word
cooking-themed code however they want (text, sticky note, verbal). No mailer
infrastructure needed. Inspired by Campfire's join-code model.

## Join Code Format

Four words: `technique ingredient ingredient dish`.

Examples:
- `braised eggplant cardamom casserole`
- `grilled halibut tempeh tacos`
- `smoked pistachio lemongrass ratatouille`
- `caramelized fig porcini galette`

### Word List

Curated YAML file at `db/seeds/resources/join-code-words.yaml` with three
sections: `techniques`, `ingredients`, `dishes`. ASCII only — no diacritics
(`souffle` not `soufflé`). Target sizes: ~80 techniques, ~250 ingredients,
~120 dishes.

Loaded once at boot via initializer into a frozen module (thread-safe).
The module exposes `generate` (returns a 4-word string) and the individual
word arrays for testing.

### Entropy

With 80 techniques × 250 × 249 ingredients (no repeat) × 120 dishes =
~598 million combinations. At 10 guesses/hour (rate limit), brute-force
takes ~6.8 million years.

### Storage and Lookup

Codes stored as space-separated lowercase strings in `Kitchen#join_code`.
Unique index on the column. Input normalized (strip, downcase, squish)
before lookup via `Kitchen.find_by(join_code:)` — unscoped, since codes are
globally unique. Retry generation on collision (astronomically unlikely).

### Regeneration

Kitchen owner regenerates from the settings dialog. Old code stops working
immediately for new joins and re-auths. Existing sessions and memberships
are unaffected.

## Schema Changes

One migration: add `join_code` (string, not null, unique index) to kitchens.
Backfill existing kitchens with generated codes in the same migration.

The existing `role` column on Membership (default: `"member"`) is used to
distinguish kitchen creators (`"owner"`) from joiners (`"member"`). Phase 1
does not enforce role-based permissions — the distinction is recorded for
future use (code regeneration, member management).

No other schema changes. User, Session, Membership, Current are unchanged.

## User Flows

### Flow 1: Create Kitchen

1. Visitor hits `/` (root)
2. No kitchens exist → redirect to `/new`; or visitor clicks "Create a kitchen"
   from the multi-kitchen landing page
3. Form: your name, your email, kitchen name
4. Submit → single transaction:
   - Create Kitchen (with auto-generated join code, slug from name)
   - Create User (or find by email if they already exist)
   - Create Membership (role: `"owner"`)
   - Create MealPlan
   - `start_new_session_for(user)`
5. Redirect to kitchen homepage

If the visitor already has a valid session and arrives at `/new` without
an explicit navigation action (e.g., direct URL entry or bookmark), redirect
to their kitchen homepage to prevent accidental double-submission. The
"Create a kitchen" link on the multi-kitchen landing page bypasses this
redirect — logged-in users can intentionally create additional kitchens.

### Flow 2: Join Kitchen (new members and returning members)

Single unified flow handles both joining and re-authentication:

1. Visitor hits `/join`
2. Form: enter join code
3. Submit → validate code (rate limited: 10/hour/IP)
   - Invalid → error message, re-render form
   - Valid → kitchen found
4. Form: enter your email
5. Submit → check email against kitchen's members
   - **Path A (returning member):** email matches →
     `start_new_session_for(user)` → redirect to kitchen homepage. No records
     created.
   - **Path B (new member):** email not recognized → "What's your name?" form
     → find or create User by email, create Membership (role: `"member"`) →
     `start_new_session_for(user)` → redirect to kitchen homepage.

Path B handles the edge case where a User exists (from another kitchen) but
is not a member of this kitchen — creates Membership only, skips both User
creation and the "What's your name?" prompt (we already have their name).

The kitchen ID is passed between steps via a signed value (Rails
`MessageVerifier`) to prevent tampering. Someone cannot skip the code
validation step or substitute a different kitchen.

## Routes

All new routes live outside the kitchen scope (no tenant context needed):

| Verb   | Path            | Controller#action | Purpose                          |
|--------|-----------------|-------------------|----------------------------------|
| GET    | /new            | kitchens#new      | Create-kitchen form              |
| POST   | /new            | kitchens#create   | Create kitchen + user + session  |
| GET    | /join           | joins#new         | Join-code entry form             |
| POST   | /join           | joins#verify      | Validate code, show email form   |
| POST   | /join/complete  | joins#create      | Email → re-auth or register      |
| DELETE | /logout         | sessions#destroy  | End session                      |

## Controllers

### KitchensController (new)

- `allow_unauthenticated_access`
- `skip_before_action :set_kitchen_from_path`
- `rate_limit to: 5, within: 1.hour, by: -> { request.remote_ip }`
- `new`: render creation form. Redirect to kitchen homepage if already
  logged in.
- `create`: validate inputs → transaction (Kitchen + User + Membership +
  MealPlan) → `start_new_session_for` → redirect. Re-render form on
  validation errors.

### JoinsController (new)

- `allow_unauthenticated_access`
- `skip_before_action :set_kitchen_from_path`
- `rate_limit to: 10, within: 1.hour, by: -> { request.remote_ip }`
- `new`: render join-code form
- `verify`: normalize and look up code → render email form with signed
  kitchen ID. Error message on invalid code.
- `create`: verify signed kitchen ID → look up member by email →
  Path A (re-auth) or Path B (registration). Multi-step form, each step
  is a server round-trip.

### SessionsController (new)

- `allow_unauthenticated_access`
- `skip_before_action :set_kitchen_from_path`
- `destroy`: `terminate_session` → redirect to root. The `DELETE /logout`
  route moves from `DevSessionsController` to this controller.
  `DevSessionsController` retains only `create` (dev login, gated to
  local environments).

### Modified: LandingController

- No kitchens exist → redirect to `/new`
- Single kitchen + logged in → kitchen homepage
- Single kitchen + not logged in → public kitchen homepage
- Multiple kitchens → kitchen list with "Create a kitchen" and "Join a
  kitchen" links

### Modified: ApplicationController

Remove `auto_join_sole_kitchen`. This method silently granted membership to
any authenticated user when one Kitchen existed — safe when only Authelia
users could authenticate, but with join codes the population of
authenticated-but-unaffiliated users grows. The explicit join flow replaces
this behavior. The rest of the before-action pipeline is unchanged
(`resume_session` → `authenticate_from_headers` → `auto_login_in_development`
→ `set_kitchen_from_path`).

### Modified: Settings Dialog

Three new sections:

- **Join code:** display current code + regenerate button (regenerate is
  owner-only; display visible to all members)
- **Members:** list of members (name, email, role)
- **Profile:** edit own name and email

## Session Lifecycle

- **Duration:** 30 days (signed permanent cookie, existing implementation)
- **Multiple devices:** each gets its own Session record (existing behavior)
- **Logout:** destroys Session record + clears cookie
- **Code regeneration:** does NOT invalidate existing sessions

## Security

**Rate limiting.** Rails 8 `rate_limit` on `JoinsController`: 10
attempts/hour/IP. `KitchensController`: 5 creations/hour/IP. Both return
429 with a friendly message.

**Signed tokens between steps.** Kitchen ID passed through the join flow via
`MessageVerifier` with `purpose: :join` and `expires_in: 15.minutes`.
Prevents skipping code validation, substituting a different kitchen, or
replaying stale tokens.

**Join code storage.** `encrypts :join_code, deterministic: true` — encrypted
at rest (consistent with `usda_api_key` and `anthropic_api_key`), queryable
via `find_by` thanks to deterministic mode.

**User creation race condition.** `find_or_create_by!(email:)` rescues
`ActiveRecord::RecordNotUnique` and retries with `find_by` — standard Rails
pattern for concurrent creation.

**Email squatting.** Without email verification, someone with the join code
could claim an email before the real owner. Known limitation for Phase 1;
Phase 2 email verification closes this gap.

**`auto_join_sole_kitchen` removed.** Previously granted membership to any
authenticated user when one Kitchen existed. With join codes widening the
authenticated user pool, this is no longer safe. The explicit join flow
replaces it.

**Input validation.** All inputs go through existing model validations.
Join code lookup uses parameterized queries. Slug auto-generated via
`parameterize`. No new `.html_safe` or `raw()` calls.

**Brakeman.** Existing `rake security` CI gate covers new controllers. No
expected changes to `brakeman.ignore`.

## Testing

### Model Tests

- Kitchen join code: generated on create, 4-word format, unique, regeneration
  produces different code
- Word list: three non-empty frozen arrays, no duplicates within or across
  arrays, all words match `/\A[a-z]+\z/`

### Integration Tests

**KitchensController:**
- Create kitchen happy path (creates Kitchen + User + Membership + MealPlan +
  Session)
- Validation errors re-render form
- Redirects if already logged in

**JoinsController:**
- Invalid code → error message
- Valid code → email form
- Known email → re-auth (session started, no new records)
- Unknown email → name form → creates User + Membership
- Existing User from another kitchen → creates Membership only
- Rate limiting → 429 after 10 attempts
- Tampered signed kitchen ID → rejected

**SessionsController:**
- Logout clears session + cookie
- Logout when not logged in → redirect to root

### Existing Tests

All pass unchanged: trusted-header auth, dev login, `require_membership`.
Test helper `log_in` continues using the dev login path.

### Playwright Security Tests

- Join code brute-force → 429 after threshold
- Tampered hidden fields rejected
- Logged-out user cannot access write paths
- Cross-kitchen isolation

## Phase 2: Email-Verified Kitchen Creation (outline)

Action Mailer setup with an email provider (Resend, Postmark, or similar).
Kitchen creation flow gains an email verification step: enter email → receive
magic link → click → creation form. Uses `MessageVerifier` or `signed_id`
with a `:kitchen_creation` purpose and short expiry. One mailer class, one
template. Everything from Phase 1 continues unchanged.

## Phase 3: Magic Link Re-auth (outline)

"Email me a login link" as an alternative to join code re-entry for returning
members. Enter email → receive link with `:login` purpose → click → session
started. Builds on Phase 2's mailer. Join code re-auth stays as a fallback.
Separate from Phase 2 because the UX, rate limiting, and token expiry differ.
May not be needed based on beta feedback.

## Future Escape Hatches (not planned)

- **OAuth (Sign in with Google/Apple):** another way to resolve email → User,
  same session creation
- **Passkeys/WebAuthn:** different proof of identity, same session system
- **Per-kitchen privacy:** "Public" vs "Private" toggle gating read access
- **Role enforcement:** owner vs member permissions (manage members, regenerate
  codes, delete kitchen)
