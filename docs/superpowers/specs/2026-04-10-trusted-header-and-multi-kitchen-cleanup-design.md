# Trusted-Header Hardening and MULTI_KITCHEN Cleanup

Resolves #363 and #365. Two cleanup/hardening tasks on the auth surface that
landed alongside the passwordless merge (PR #368), shipped as one coherent
design with two separate PRs so review and revert stay granular.

## Context

The passwordless merge left two loose ends on the auth surface:

**#363 — the `MULTI_KITCHEN` env var has outlived its purpose.** It was
introduced when the app had no multi-tenant user model, to lock beta
installs into single-kitchen mode. With passwordless auth shipped,
per-kitchen membership is always available; the flag is now pure
maintenance tax. Every new feature has to consider two modes, every test
either wraps itself in `with_multi_kitchen` or avoids the second kitchen.

**#365 — trusted-header auth is now a wider attack surface.** The
passwordless merge added a sole-kitchen auto-join (`auto_join_sole_kitchen`
in `ApplicationController`) so a brand-new trusted-header user lands
inside the single kitchen as a member instead of in an empty shell. This
restored the homelab onboarding UX but widened the blast radius of a
reverse-proxy misconfiguration: an attacker who can spoof `Remote-User`
from outside the proxy now gains write access to the sole kitchen, not
just a useless authenticated session. The trust model was documented in
code comments but not enforced in code — no peer IP check, no operator
guardrails, no startup validation.

These are independent at the file level but both are consequences of the
recent auth merge, both are prerequisites for the eventual Fly.io hosted
deployment, and both benefit from being designed together even when
shipped separately.

## Goals

1. Delete the `MULTI_KITCHEN` flag and everything it gated.
2. Keep two capabilities the flag was sometimes conflated with: the
   sole-kitchen URL convenience (`resolve_sole_kitchen`) and trusted-header
   auth (`authenticate_from_headers`). Both are independently valuable.
3. Add defense-in-depth to the trusted-header path so a
   proxy misconfiguration does not silently hand writable kitchen access
   to an unauthenticated attacker.
4. Align trusted-header behavior with the conventions used by other
   selfhosted apps (Gitea, Miniflux, Grafana) so homelab operators can
   carry their expectations over.
5. Leave Phase 2 (email-verified kitchen creation) and Phase 3 (magic link
   re-auth) of the auth plan unblocked and untouched.

## Design Decisions

**One spec, two PRs, #363 first.** The diffs barely overlap. #363 is
mostly deletions across tests, docs, and a model validation; #365 adds
config + a per-request gate + docs. Landing #363 first gives #365 a
cleaner base. A single spec keeps the "why now, why together" story
coherent; split PRs keep each review surface small and revertable.

**Keep trusted-header auth, don't drop it.** Trusted-header auth is the
homelabber's front door when they already run Authelia or Authentik.
Removing it would be a hostile change for the target install profile.
The hardening below makes it safer without removing it.

**Keep the sole-kitchen URL convenience.** Bare URLs (`/recipes/bagels`)
when exactly one Kitchen exists is a purely aesthetic win for the common
homelab install. Decoupled from the capacity flag — homelab users who
happen to create a second kitchen get slug-prefixed URLs, which is fine.

**Follow Gitea's trusted-proxy default.** Research across selfhosted apps
shows every serious project requires a peer IP allowlist for
trusted-header auth. Miniflux fails closed until the operator opts in;
Gitea ships `127.0.0.0/8,::1/128` as a default that covers same-host
docker-compose installs zero-config while forcing multi-host users to
opt in. Gitea's pattern is friendlier to the docker-compose homelabber
and still closes the CVE pattern (every header-spoofing CVE in the wild
comes from projects that trusted headers without a peer IP check).
Paperless-ngx's docs-only approach is the cautionary tale — its
discussion tracker is a long tail of misconfigurations.

**Make header names configurable.** `Remote-User` is the
Authelia/Apache convention; `X-Webauth-User` is Grafana's;
`X-Auth-Username` is oauth2-proxy's. Every serious project makes these
configurable at low cost. Three env vars, defaults preserve current
behavior.

**Warn at startup, don't hard-fail.** None of the researched projects
hard-fail boot over trusted-header config — too many valid topologies.
A `Rails.logger.warn` at boot is enough to catch the "I moved my proxy
and forgot to widen the allowlist" footgun without being hostile.

**No self-test rake task.** The research suggested a
`rake auth:verify_proxy` task that curls the public URL with a spoofed
`Remote-User` and asserts it does NOT authenticate. This is the right
idea eventually, but it's YAGNI for now — revisit if there's ever a
real misconfiguration report. Adding it would expand scope past the
two issues.

## Scope

### PR 1 — drop `MULTI_KITCHEN` (resolves #363)

**Model changes.** Remove `Kitchen#enforce_single_kitchen_mode` validation
(`app/models/kitchen.rb`). The `validate :enforce_single_kitchen_mode,
on: :create` line and the private method both go.

**Controller changes.** Remove
`KitchensController#require_multi_kitchen_mode` before-action and its
private method. The `redirect_if_logged_in` before-action and rate
limiting stay. Kitchen creation becomes ungated — this is consistent
with Phase 1 of the auth spec ("Self-service kitchen creation (ungated
in Phase 1)"), which will be re-gated by Phase 2 with email verification.

**Test helper.** Remove `with_multi_kitchen` from `test/test_helper.rb`.
Unwrap all call sites in the test suite. There are 30 call sites
across 21 test files:

- 9 controller test files (14 call sites): `kitchens_controller_test.rb` (5),
  `transfers_controller_test.rb` (2), `header_auth_test.rb`,
  `joins_controller_test.rb`, `landing_controller_test.rb`,
  `tenant_isolation_test.rb`, `auth_test.rb`,
  `groceries_controller_test.rb`, `pwa_controller_test.rb`
- 11 model test files (15 call sites): `kitchen_test.rb` (2),
  `kitchen_join_code_test.rb` (2), `cook_history_entry_test.rb` (2),
  `ingredient_catalog_test.rb` (2), `recipe_model_test.rb`,
  `category_test.rb`, `custom_grocery_item_test.rb`,
  `meal_plan_selection_test.rb`, `on_hand_entry_test.rb`,
  `quick_bite_test.rb`, `tag_test.rb`
- 1 service test file (1 call site): `aisle_write_service_test.rb`

All are mechanical: unwrap the block, indent the body back out.

**Test deletion.** The `enforce_single_kitchen_mode` test in
`kitchen_test.rb` goes away with the validation.

**Scripts and tasks.** Remove `MULTI_KITCHEN=true` from:
- `lib/tasks/release_audit.rake` (4 occurrences in security/exploratory
  tier tasks)
- `test/security/seed_security_kitchens.rb` (comments only — the seed
  script itself makes no env checks)
- `test/release/exploratory/accessibility.spec.mjs` (comment)
- `test/release/exploratory/setup.mjs` (comment)

**Documentation.** Update `CLAUDE.md` — three references at lines 188,
278, and 319. Remove the "`multi_kitchen` is an env var" sentence from
the write-path section, drop the `MULTI_KITCHEN=true` prefix from the
security pen test command, and drop it from the release audit:full
command note.

**README.md.** Grep shows no `MULTI_KITCHEN` references — no action
needed, but confirmed at implementation time.

**Historical docs.** Spec and plan files under `docs/superpowers/` that
reference `MULTI_KITCHEN` are historical records of past state and stay
untouched.

**Verification.** After PR 1:
- `rake test` passes
- `rake lint` passes
- `rake release:audit:full` passes without setting `MULTI_KITCHEN`
- Manual smoke: single-kitchen install routes to bare URLs via
  `resolve_sole_kitchen`; creating a second kitchen via the settings
  dialog / `/new` switches to slug-prefixed routing
- Trusted-header auth still works for the single-kitchen case

### PR 2 — harden trusted-header auth (resolves #365)

**New env vars.** All optional with safe defaults that preserve current
behavior for same-host docker-compose setups:

| Variable | Default | Purpose |
|---|---|---|
| `TRUSTED_PROXY_IPS` | `127.0.0.0/8,::1/128` | Comma-separated CIDRs. Peer IP must be in this set for trusted headers to be honored. |
| `TRUSTED_HEADER_USER` | `Remote-User` | Header name carrying the username/identifier. |
| `TRUSTED_HEADER_EMAIL` | `Remote-Email` | Header name carrying the email. |
| `TRUSTED_HEADER_NAME` | `Remote-Name` | Header name carrying the display name. |

**New config class.** `lib/familyrecipes/trusted_proxy_config.rb`:

- Frozen value object built once at boot from env vars via
  `TrustedProxyConfig.from_env`.
- Parses `TRUSTED_PROXY_IPS` into an array of `IPAddr` ranges; raises
  at boot on invalid CIDR (fail fast on typos).
- An explicitly empty string (`TRUSTED_PROXY_IPS=`) produces an empty
  allowlist — this is the escape hatch for disabling trusted-header
  auth entirely. `unset` (env var missing) falls back to the loopback
  default. Both behaviors are tested.
- Exposes `allow?(ip_string)` — returns `true` when the IP matches any
  allowed range, `false` otherwise. Handles `IPAddr::InvalidAddressError`
  by returning `false`.
- Exposes `user_header`, `email_header`, `name_header` — the Rack env
  key strings (e.g., `HTTP_REMOTE_USER`), derived from the configured
  header names. Rack's header-to-env conversion uppercases and replaces
  `-` with `_` and prefixes `HTTP_`, so a configured
  `TRUSTED_HEADER_USER=X-Webauth-User` yields `HTTP_X_WEBAUTH_USER`.
- Exposes `default_networks?` — `true` when `TRUSTED_PROXY_IPS` matches
  the default string, used by the startup warning initializer.
- Lives in `lib/familyrecipes/` because it's domain config loaded by an
  initializer (matching the convention used by
  `JoinCodeGenerator`), not Zeitwerk-autoloaded.

**New initializer.** `config/initializers/trusted_proxy.rb`:
Loads `FamilyRecipes::TrustedProxyConfig.from_env` into
`Rails.configuration.trusted_proxy_config`. Single source of truth —
the controller never touches `ENV` directly.

**New initializer.** `config/initializers/trusted_proxy_warning.rb`:
Production-only startup warning. Fires when
`Rails.env.production? && Rails.configuration.trusted_proxy_config.default_networks?`
with a `Rails.logger.warn` line explaining that the default allowlist
is loopback-only and the operator should set `TRUSTED_PROXY_IPS` if
their proxy is on a separate host or docker network. Does not hard-fail.
Does not fire in development or test.

**Controller change.** `ApplicationController#authenticate_from_headers`
is rewritten (in place, ~10 net lines changed):

1. Return if already authenticated (unchanged).
2. Load `cfg = Rails.configuration.trusted_proxy_config`.
3. **Peer IP gate:** return unless `cfg.allow?(request.remote_ip)`. This
   is the critical check — headers are ignored entirely if the TCP peer
   is not in the allowlist, and the request falls through to anonymous
   (passwordless auth still available).
4. Read the three headers using the configured keys
   (`request.env[cfg.user_header]`, etc.) — no more hardcoded
   `HTTP_REMOTE_USER`.
5. Rest of the flow (email fallback, `find_or_create_by`,
   `start_new_session_for`, `auto_join_sole_kitchen`) is unchanged.

The header comment on `ApplicationController` is updated to document
the new trust model precisely: peer IP check, configurable header
names, startup warning, README pointer.

**Tests.**

New `test/lib/familyrecipes/trusted_proxy_config_test.rb`:
- Parses default `127.0.0.0/8,::1/128` when `TRUSTED_PROXY_IPS` unset
- Parses comma-separated list with whitespace tolerance
- Parses IPv4 and IPv6 CIDRs
- `allow?` matches IPs inside and outside ranges
- `allow?` returns `false` for invalid IP strings
- `user_header` / `email_header` / `name_header` normalize
  `X-Webauth-User` → `HTTP_X_WEBAUTH_USER`
- `default_networks?` detection
- Invalid CIDR at boot raises with a clear error message

Extensions to `test/controllers/header_auth_test.rb`:
- Headers are honored when peer IP is `127.0.0.1` (default allowlist,
  the `ActionDispatch::IntegrationTest` default)
- Headers are ignored when peer IP is outside the allowlist (set
  `headers: { 'REMOTE_ADDR' => '203.0.113.5' }`) — request falls
  through to anonymous, no User/Session created
- Custom header name works when `TRUSTED_HEADER_USER=X-Webauth-User`
  is configured (via test-scoped config stubbing)
- Default `Remote-User` is ignored when a custom header name is
  configured (prevents dual-header surprise)
- The existing tests pass unchanged because the default allowlist
  includes `127.0.0.1`.

**README rewrite.** The "Add authentication (production)" section
(lines 130-153 of current `README.md`) is rewritten:

- A **Trust model** callout at the top: "Your reverse proxy MUST strip
  any inbound `Remote-User`, `Remote-Email`, and `Remote-Name` headers
  from external requests before forwarding to FamilyRecipes. If you
  cannot guarantee this, see 'Disabling trusted-header auth' below."
  Bold, not a footnote. The pointer gives operators an actionable
  path instead of a dead-end warning.
- The **underscore/dash footgun**: nginx strips headers containing
  underscores by default; Caddy, Traefik, and HAProxy do not. Operators
  on non-nginx proxies must explicitly strip both the hyphenated
  (`Remote-User`) and underscore (`Remote_User`) forms or they leave a
  bypass open. This is the source of half the known
  trusted-header-auth CVEs.
- The **Caddy example config** is kept, extended with an explicit
  `header_up -Remote-User` / `header_up -Remote-Email` /
  `header_up -Remote-Name` stanza in the `reverse_proxy` block as a
  visible reminder.
- New **`TRUSTED_PROXY_IPS`** section: explains the loopback default,
  when to change it (proxy on a separate host or different docker
  network), CIDR syntax.
- New **`TRUSTED_HEADER_USER` / `_EMAIL` / `_NAME`** section: explains
  configurability for Authentik, oauth2-proxy, Grafana-style
  `X-Webauth-*`, and Caddy `forward_auth` users.
- New **"Disabling trusted-header auth"** subsection. Explicit and
  prominent — set `TRUSTED_PROXY_IPS=` (empty string) in the
  environment. Explains the effect: the peer IP check rejects every
  request, trusted headers are ignored unconditionally, and users
  must sign in via join code or re-auth link instead. This is the
  right posture if the operator cannot guarantee the reverse proxy
  strips inbound `Remote-*` headers. Call out the distinction between
  *unset* (falls back to loopback default) and *set-to-empty*
  (explicit disable) so operators don't guess.
- The env var table in the preceding section gains four new rows for
  these vars.

**Verification.** After PR 2:
- `rake test` passes with new test cases
- `rake lint` passes
- `rake security` (Brakeman) passes
- `rake release:audit:full` passes — the security Playwright specs
  still work because they run against the dev server on loopback
- Manual smoke: request with `Remote-User` from `127.0.0.1` authenticates;
  request with same header from a non-loopback IP is ignored; custom
  header name via env var works end-to-end; startup warning fires in
  production with default allowlist and is silent in development

## Forward Compatibility

**Phase 2 (email-verified kitchen creation).** Will re-gate
`KitchensController#create` with a new before-action that requires a
verified email. Dropping `require_multi_kitchen_mode` in PR 1 leaves a
clean slot for that before-action. No conflict.

**Phase 3 (magic link re-auth).** Touches `JoinsController` and adds a
new mailer, not the trusted-header path. No interaction.

**Fly.io hosted deployment.** This hardening is a prerequisite. The
trusted-header path on a public-internet-facing deployment will need to
either be disabled entirely (set `TRUSTED_PROXY_IPS=` to an empty
string — the explicit escape hatch described above) or locked to Fly's
internal mesh IPs. The per-request peer IP gate added in PR 2 is the
knob that makes this possible without code changes.

## What's Intentionally Out of Scope

- **Self-test rake task** for trusted-header misconfiguration. The
  research suggested `rake auth:verify_proxy` that spoofs a header and
  asserts the app rejects it. Punted — revisit if anyone files a
  misconfiguration report.
- **Runtime config reload.** Env-var-only config matches the rest of
  the app (`SECRET_KEY_BASE`, `ALLOWED_HOSTS`, etc.).
- **Dropping trusted-header auth entirely.** Orthogonal question. The
  homelab install profile depends on it and the hardening here makes
  it safe.
- **Separate rate limiting on the header auth path.** Headers are not
  brute-forceable — the attack is spoofing, which the peer IP check
  kills. Existing rate limits on `/new` and `/join` cover the
  interesting surfaces.
- **Detecting Puma's bind address to gate the startup warning.**
  Research suggested warning when "not bound to loopback." Puma's
  binding lives in `config/puma.rb` or a launch flag; detecting it
  post-boot is fragile. Using `Rails.env.production? &&
  default_networks?` as the heuristic is simpler and catches the same
  mistake.

## Risk Assessment

**PR 1 risk — mechanical test unwrap.** 30 `with_multi_kitchen` call
sites across 21 files. If any are missed, the test file won't parse.
`rake test` is the backstop; the fix on failure is trivial.

**PR 2 risk — legitimate setups broken by the default allowlist.**
Operators running Authelia on a separate host or a different docker
network will find trusted-header auth stops working silently after
upgrade. Mitigations:
1. The startup warning fires in production with the default allowlist
2. The README rewrite is prominent and explicit
3. The fallback is not a 403 — auth simply becomes anonymous and the
   user sees the passwordless join page, which is actionable
4. The join code escape hatch (`rake kitchen:show_join_code`) still
   works on-box

**PR 2 risk — test fragility around `REMOTE_ADDR`.** The "outside
allowlist" test relies on `headers: { 'REMOTE_ADDR' => '203.0.113.5' }`
reaching `request.remote_ip`. This is well-supported by
`ActionDispatch::IntegrationTest` but worth verifying on first run.

## Acceptance Criteria

### PR 1 (#363)

- [ ] All references to `MULTI_KITCHEN` removed from code, tests,
      scripts, and `CLAUDE.md`
- [ ] Single-kitchen routing still works via `resolve_sole_kitchen`
      (bare URLs)
- [ ] Multi-kitchen routing still works via slug prefix
- [ ] Trusted-header auth still works for the sole-kitchen case
- [ ] `rake test` clean
- [ ] `rake release:audit:full` clean without setting `MULTI_KITCHEN`

### PR 2 (#365)

- [ ] `TRUSTED_PROXY_IPS` env var implemented with loopback default
- [ ] `TRUSTED_HEADER_USER` / `_EMAIL` / `_NAME` configurable with
      `Remote-*` defaults
- [ ] Per-request peer IP check in `authenticate_from_headers`
- [ ] Production startup warning when allowlist is at default
- [ ] Unit tests for `TrustedProxyConfig`
- [ ] Integration tests for peer IP gate and custom header names
- [ ] README "Add authentication (production)" section rewritten with
      trust model, underscore footgun, and new env vars
- [ ] `ApplicationController` header comment updated
- [ ] `rake test` clean, `rake lint` clean, `rake security` clean

## Related

- `feature/auth` branch — merged as PR #368 on 2026-04-10
- Phase 2 of the auth plan (email-verified kitchen creation) — unblocked
  by these changes
- Eventual Fly.io hosted deployment — depends on the peer IP gate
