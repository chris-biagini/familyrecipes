# Trusted-Header Auth and Onboarding

Closes #93 (orphan users), #94 (ActionCable auth).

## Context

New OAuth users get a `User` record but no `Membership`, leaving them on a dead-end
landing page. ActionCable has no authentication at all. Rather than patch the OAuth flow,
we're replacing it with trusted-header auth — the app will run behind Authelia/Caddy in
production, so the proxy handles identity and the app trusts the forwarded headers.

## Decisions

- **Homelab is the priority deployment.** Hosted multi-tenant is a future possibility, not
  a current requirement. The multi-tenant data model (Kitchen, Membership, acts_as_tenant)
  stays intact.
- **No custom authentication.** No passwords, no lost-password flows. Identity comes from
  the reverse proxy (Authelia) in production and `DevSessionsController` in dev/test.
- **Single shared identity is fine.** No need to distinguish individual family members yet.
  The data model supports it if needed later.
- **Read paths stay unauthenticated at the Rails level.** Authelia provides the access
  boundary in homelab deployments. This enables future public link sharing without code
  changes.

## 1. Trusted-Header Authentication

Authelia sets `Remote-User`, `Remote-Name`, and `Remote-Email` headers on proxied requests.
A before_action in `ApplicationController` reads these headers:

1. If no `Remote-User` header is present, do nothing (no-op for dev/test).
2. If the header is present and a valid session cookie already exists, do nothing.
3. If the header is present and no session exists, find-or-create a `User` from the header
   values, then call `start_new_session_for` to set the signed cookie.

Subsequent requests authenticate via the session cookie as today — headers are only read
when establishing a new session.

### Removed

- `omniauth` and `omniauth-rails_csrf_protection` gems
- `OmniauthCallbacksController`
- OmniAuth initializer and routes (`/auth/:provider/callback`, `/login`, `/auth/failure`)
- `ConnectedService` model and table (only existed for OAuth identity linking)

### Kept

- `User`, `Session`, `Membership` models — unchanged
- `Authentication` concern — `start_new_session_for`, `resume_session`, `terminate_session`
- Signed cookie sessions — the cookie authenticates subsequent requests, not the headers
- `DevSessionsController` — gated to dev/test, used by `log_in` test helper

### Future OAuth Path

The session layer is auth-agnostic. To add Apple/Google OAuth later:

1. Re-add OmniAuth with the desired provider gems.
2. Add a callback controller that calls `start_new_session_for`.
3. Both paths converge at the same session system — no architectural changes needed.

## 2. Auto-Join Sole Kitchen

When a user is identified (via headers) and has zero memberships, and exactly one Kitchen
exists in the system, auto-create a `Membership`. This happens in the same before_action
as header auth.

Edge cases:
- Multiple kitchens → no auto-join (future: invite codes or kitchen creation).
- User already has memberships → skip.
- No kitchens → skip (only if `db:seed` was skipped).

The `Membership#role` column exists but is unused. Left for future owner/member distinction.

## 3. Landing Page Redirect

When exactly one Kitchen exists, `LandingController#show` redirects to that kitchen's
homepage. The landing page (kitchen list) only renders when there are zero or multiple
kitchens.

The redirect is unconditional on auth status — kitchen pages are publicly readable.

## 4. Auth Gates

Consistent rule: **read paths are public, write paths require membership.**

| Controller | Action | Guard |
|---|---|---|
| `RecipesController` | `show` | None (public read) |
| `RecipesController` | `create`, `update`, `destroy` | `require_membership` |
| `GroceriesController` | `show`, `state`, `aisle_order_content` | None (public read) — **changed** |
| `GroceriesController` | all write actions | `require_membership` |
| `NutritionEntriesController` | all actions (POST/DELETE) | `require_membership` |
| `HomepageController` | `show` | None (public read) |

## 5. ActionCable Authentication (Issue #94)

**`ApplicationCable::Connection`:** Identify users from the session cookie (same cookie the
`Authentication` concern uses). Reject connections with no valid session.

**`GroceryListChannel#subscribed`:** After finding the kitchen, check
`kitchen.member?(current_user)`. Reject if not a member.

## 6. Dev/Test

No changes to the dev/test auth story:

- `DevSessionsController` stays, gated to dev/test environments.
- `log_in` test helper stays.
- Header auth is a no-op when headers are absent — no environment checks needed.
- The presence of `Remote-User` is the signal, not `Rails.env`.
