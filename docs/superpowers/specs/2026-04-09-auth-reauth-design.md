# Re-Authentication Design

Separates invitation (magic phrase) from re-authentication (session transfer,
login links, join code fallback). Phase 1 auth gave us join codes and sessions;
this spec adds the missing "how do I get back in?" layer without email
infrastructure.

## Context

Phase 1 shipped join codes as the sole entry mechanism. The join code works for
both first-time joins and returning members, but that dual role makes it feel
like a shared password. In practice, there's no way to re-authenticate without
knowing the join code — clearing cookies or switching devices means re-entering
the phrase. This spec adds two new re-auth paths so the join code can return to
being purely an invitation, plus UX improvements that make the fallback more
robust.

## Design Decisions

**No email infrastructure.** All three mechanisms work without a mailer. Email
magic links are a future option (Phase 3), not a prerequisite.

**`signed_id` as the universal primitive.** Rails' built-in `signed_id`
generates tamper-proof, time-limited, purpose-scoped tokens. Session transfer,
login links, and future magic links all use this same primitive with different
purposes and expiry windows.

**Any member can help any member.** Login link generation is not restricted to
owners. This is a family app — gatekeeping who can help Grandma log in just
adds friction. If this needs tightening for hosted mode, role checks can be
added later without changing the mechanism.

**Join code re-entry stays as universal fallback.** It always works if you know
the code. The new mechanisms make it so you rarely need it.

**`email_verified_at` planted now, enforced later.** A nullable column on users,
unused in this phase. Avoids a migration when Phase 2 adds email verification.
Existing users remain unverified (`nil`) — they were all invited by trusted
people.

## Schema Changes

One migration adds `email_verified_at` (datetime, nullable) to `users`. No
default, no index (not queried until Phase 2). No other schema changes.

## Mechanism 1: Session Transfer (device-to-device)

For the "I'm on my laptop and want to also use my phone" scenario.

### Flow

1. Logged-in member opens settings, clicks "Log in on another device"
2. `POST /transfer` generates a signed token, returns a URL + inline SVG QR code
3. Member scans QR or copies the link to their other device
4. `GET /transfer/:token` verifies the token, creates a new session, redirects
   to kitchen homepage
5. Token expires after 5 minutes

### Token

`current_user.signed_id(purpose: :transfer, expires_in: 5.minutes)`

Purpose-scoped — a `:transfer` token cannot be used as a `:login` token or
vice versa. Time-limited to 5 minutes because both devices are in hand. Not
explicitly single-use; the short expiry is sufficient for protecting recipe
access.

### QR Code

Server-side SVG via the `rqrcode` gem. Generated inline per request — no
caching needed for 5-minute tokens. Rendered as raw SVG in the settings dialog
response.

### Settings Dialog Integration

A "Log in on another device" button in the settings dialog (visible to all
members). Clicking it makes an async request to `POST /transfer` and displays
the QR code + copyable link inline. A client-side 5-minute countdown shows
remaining time; on expiry the QR disappears with a "Generate new link" prompt.

## Mechanism 2: Login Links (member-to-member)

For the "Grandma got a new iPad" and "I signed out and I'm locked out"
scenarios.

### Flow

1. Any logged-in member opens settings, goes to the members list
2. Next to a member's name, taps "Login link"
3. `POST /members/:id/login_link` generates a signed token, returns a copyable
   URL
4. Member texts/messages the link to the target person
5. Recipient taps `GET /transfer/:token`, gets a session, lands in the kitchen
6. Token expires after 24 hours

### Token

`target_user.signed_id(purpose: :login, expires_in: 24.hours)`

Longer expiry than self-transfer because it travels through a text message and
the recipient may not tap it immediately.

### Authorization

Requires authentication + membership in the kitchen. The target user must also
be a member of the current kitchen. Any member can generate for any other
member — no owner restriction.

### Settings Dialog Integration

Each row in the members list gets a small link icon/button. Tapping it makes an
async request and displays the copyable URL inline. No QR code — the use case
is copy-paste into a text message.

## Mechanism 3: Polished Join Code Fallback

No changes to the join flow logic. Two new moments where the code is surfaced.

### Sign-Out Interstitial

`SessionsController#destroy` renders a view instead of redirecting. The view
shows the kitchen's join code and links to sign back in or go to the homepage.
The join code is read while still authenticated (before `terminate_session`),
then the session is terminated and the view is rendered. This prevents the
"clicked sign out and now I'm locked out" problem.

Implementation: `destroy` loads `@join_code` and `@kitchen_name` from
`Current.session.user.kitchens`, calls `terminate_session`, then renders
`sessions/destroy`. If the user belonged to multiple kitchens, show all codes.

### Welcome Screen After First Join

After the join flow creates a new membership (Path B in `JoinsController`),
redirect to a welcome page instead of the kitchen homepage. The welcome page
displays the kitchen name, join code, and a prompt to screenshot or write it
down. A "Got it" button proceeds to the kitchen.

Returning members (Path A) skip this — they've seen the code before.

Implementation: `JoinsController#register_new_member` redirects to
`GET /welcome` with a signed kitchen ID param. `WelcomeController#show` renders
the code and "Got it" link. The signed param prevents bookmarking the welcome
page as a way to peek at join codes.

### Rake Task Escape Hatch

```bash
rake kitchen:show_join_code KITCHEN=slug-here
```

Prints the join code to the terminal. For the homelab case, you have shell
access. For hosted, this is a support tool. Solves the "solo owner, no sessions
anywhere, forgot the code" edge case.

## Routes

New routes, all outside the kitchen scope:

| Verb | Path | Controller#Action | Purpose |
|------|------|-------------------|---------|
| POST | /transfer | transfers#create | Generate self-transfer token + QR |
| GET | /transfer/:token | transfers#show | Consume any signed token (transfer or login) |
| POST | /members/:id/login_link | transfers#create_for_member | Generate login link for another member |
| GET | /welcome | welcome#show | Post-join welcome screen |

## Controllers

### TransfersController (new)

Three actions:

- `create` — requires authentication. Generates a `:transfer` signed_id for
  `current_user`. Returns the URL + SVG QR code. Rendered inline in the
  settings dialog via async request.
- `create_for_member` — requires authentication + membership. Looks up the
  target user, verifies they're a member of the same kitchen. Generates a
  `:login` signed_id. Returns the URL for copy-paste.
- `show` — allows unauthenticated access. Finds the user via
  `User.find_signed(params[:token], purpose:)`. Tries `:transfer` first;
  if that returns nil (wrong purpose), tries `:login`. If either succeeds,
  verifies kitchen membership, calls `start_new_session_for`, and redirects.
  If both return nil (invalid, expired, or tampered), renders an error page
  with a link to `/join`.

`show` needs to determine which kitchen to redirect to. For `:transfer`
tokens, use the kitchen from the generating user's most recent session
(the one they were looking at when they clicked the button). For `:login`
tokens, the kitchen context is implicit — the member list is kitchen-scoped,
so we know which kitchen. To handle this cleanly: encode the kitchen slug
as a query parameter on the transfer URL (`/transfer/:token?k=slug`). The
controller verifies membership before creating the session.

### WelcomeController (new)

Single action:

- `show` — allows unauthenticated access. Verifies the signed kitchen ID
  param, renders the join code and kitchen name. The "Got it" link goes to
  the kitchen homepage.

### Modified: SessionsController

`destroy` changes from redirect to render. Loads kitchen info before
terminating the session, then renders `sessions/destroy` with the join code(s).

### Modified: JoinsController

`register_new_member` redirects to `/welcome` with a signed kitchen ID param
instead of directly to the kitchen homepage.

## Dependencies

**`rqrcode` gem.** Pure Ruby QR code generator. Produces SVG (no binary
dependencies, no image processing). Used by Campfire for the same purpose.
MIT licensed. Added to Gemfile, no Dockerfile changes needed.

## Token Expiry Summary

| Token | Purpose | Expiry | Use Case |
|-------|---------|--------|----------|
| Self-transfer | `:transfer` | 5 minutes | Both devices in hand |
| Login link | `:login` | 24 hours | Async text message delivery |
| Join flow signed kitchen ID | `:join` | 15 minutes | Existing, unchanged |

## Security

**No new attack surface beyond `GET /transfer/:token`.** This endpoint
validates a Rails `signed_id` — the same primitive used for password reset
tokens across the Rails ecosystem. Tokens are signed with `secret_key_base`,
purpose-scoped, and time-limited.

**Rate limiting.** `TransfersController#create` and `create_for_member` are
behind `require_authentication`, so unauthenticated spam isn't possible. The
`show` action accepts unauthenticated requests but the token is unguessable
(signed with `secret_key_base`). No rate limit needed on `show` — there's
nothing to brute-force.

**Token leakage.** If a transfer URL is intercepted (e.g., shoulder-surfing a
QR code), the attacker gets a session as that user. Mitigation: 5-minute expiry
for self-transfers. For login links (24h), the risk is equivalent to texting
someone a password reset link — acceptable for the threat model (recipes, not
state secrets).

**Kitchen scoping.** `create_for_member` verifies the target user is a member
of `current_kitchen`. The redirect URL includes the kitchen slug, and `show`
verifies membership before creating the session.

**Cross-purpose protection.** `:transfer` and `:login` are separate purposes.
A token generated for one purpose cannot be consumed as the other.

## Testing

### Controller Tests

**TransfersController:**
- `create` requires authentication, returns URL + SVG
- `create` token works: `show` with valid token creates session + redirects
- `show` with expired token renders error
- `show` with invalid/tampered token renders error
- `show` with wrong-purpose token renders error
- `create_for_member` requires authentication + membership
- `create_for_member` rejects targets who aren't kitchen members
- `create_for_member` token works: creates session for target user

**WelcomeController:**
- `show` with valid signed kitchen ID renders join code
- `show` with invalid/expired param redirects to root

**SessionsController:**
- `destroy` renders interstitial with join code (not redirect)
- `destroy` when not logged in redirects to root

**JoinsController:**
- New member (Path B) redirects to welcome page, not kitchen

### Playwright Security Tests

- Transfer token cannot be reused after expiry
- Login link for non-member is rejected
- Tampered transfer token is rejected
- Cross-kitchen login link is rejected

## Future Phases (unchanged from Phase 1 spec)

- **Phase 2:** Email verification gates kitchen creation. `email_verified_at`
  column (planted in this phase) gets populated. Action Mailer + provider.
- **Phase 3:** "Email me a login link" as a fourth re-auth path. Same
  `signed_id` mechanism, email delivery channel.
- **OAuth, passkeys:** additional identity resolution methods, same session
  system.
