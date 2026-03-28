# Security Audit Design

**Issue:** #215
**Date:** 2026-03-28
**Approach:** Static analysis + scripted penetration tests, integrated into CI and local workflow

## Context

The app is currently deployed as a homelab instance behind Authelia (trusted-header
auth) with a small user base. The eventual goal is a hosted multi-user model. The
security practice needs to serve both: protect the current deployment while building
habits and tooling that scale to multi-tenant hosting.

A deep-dive audit of the current codebase found strong foundations — strict CSP,
encrypted API keys, parameterized queries, `acts_as_tenant` with
`require_tenant: true`, good input validation. This design codifies those strengths
into automated checks so they can't regress.

## Layer 1: Static Analysis with Brakeman

Brakeman is a Rails-specific static analysis tool. It scans source code for known
vulnerability patterns without running the app.

### Integration

- Add `brakeman` gem to the `:development` group in `Gemfile`.
- New rake task: `rake security` runs Brakeman. Medium and high confidence
  warnings fail (`--confidence 1`); weak confidence warnings are reported but
  don't fail.
- CI: dedicated step in `test.yml` after `bundle exec rake`.
- `brakeman.ignore` file for documented false positives (same discipline as
  `html_safe_allowlist.yml` — each entry gets a justification comment).

### What it catches

SQL injection, XSS, command injection, unsafe redirects, mass assignment, file
access, session manipulation, and other Rails-specific patterns. Brakeman
understands Rails conventions — it traces data flow from `params` through
controllers into views and queries.

## Layer 2: Scripted Penetration Tests

Playwright tests that hit the running app as a real browser. These live in
`test/security/` and run in CI with a live server.

### Tenant Isolation

The highest-priority category for the hosted future.

- Create two kitchens with separate members. Log in as kitchen A's member.
- Attempt to GET kitchen B's recipes, grocery state, settings, and ingredients via
  direct URL manipulation. Verify 403/404 on every protected endpoint.
- Attempt to POST/PATCH/DELETE against kitchen B's resources from kitchen A's
  session. Verify rejection.
- Verify ActionCable streams are kitchen-scoped — kitchen A should not receive
  kitchen B's broadcasts.

### Authentication & Authorization Bypass

- Hit every protected endpoint with no auth headers. Verify 403 on writes.
- Hit write endpoints with a valid user who is not a member of the target kitchen.
  Verify 403.
- Verify dev login routes are inaccessible in production mode.

### XSS / CSP Enforcement

- Create recipes with XSS payloads in: titles, ingredients, step text, notes, tags.
  Payloads: `<script>alert(1)</script>`, `<img onerror=...>`, event handler
  attributes, SVG-based injection.
- Render the recipe page and verify no script execution (check browser console for
  errors/messages, verify DOM state).
- Verify the CSP header is present and strict on every response.
- Attempt inline style injection to confirm CSP blocks it.
- Verify Quick Bite names and ingredients also resist XSS.

### Malicious Import

- Upload ZIP files with: path traversal filenames (`../../etc/passwd`), oversized
  files (> 10MB), excessive entry count (> 500), non-recipe content, binary payloads,
  deeply nested directory structures.
- Verify graceful rejection for each case — no crashes, no unexpected file writes,
  no 500 errors.

### API Key Exfiltration

- Verify encrypted API keys never appear in: HTML responses, JSON API responses,
  Turbo Stream updates, ActionCable broadcasts, or error pages.
- Verify settings forms don't echo back the full key value (masked or absent).
- Verify API keys are absent from server-rendered JavaScript.

### Input Fuzzing

- Send extremely long strings (10K+ characters), null bytes, unicode edge cases
  (RTL markers, zero-width characters, emoji), and control characters through:
  recipe creation, ingredient names, category names, tag names, search queries.
- Verify no 500 errors — the app either accepts, validates, or rejects cleanly.
- Verify long inputs don't cause excessive memory consumption or response time.

## Workflow Integration

### Local

- `rake security` — runs Brakeman only. Fast (~5s), no server needed. Run when
  touching auth, params, or anything security-sensitive.
- Not part of the default `rake` task. Security scanning is on-demand locally,
  mandatory in CI.

### CI

- **Brakeman job:** Runs after `bundle exec rake` in `test.yml`. Fails the build
  on medium/high confidence warnings.
- **Playwright security job:** Separate job in `test.yml`. Starts the server, seeds
  two test kitchens, runs the security suite, tears down. Fails on any test failure.
- Both can run in parallel with existing test steps.

### Maintenance

- `brakeman.ignore` for false positives — each entry requires a justification.
- When adding a new endpoint or feature, add corresponding security tests. Checklist:
  - New controller action → tenant isolation test
  - New form field → XSS payload test
  - New file processing → malicious input test
  - New API key or secret → exfiltration check

## Immediate Fixes

Issues surfaced by the initial audit, to be fixed as part of implementation:

1. **Session expiry:** Add `expires_at` column to sessions table. Add a cleanup
   mechanism for stale sessions (e.g., delete sessions older than 30 days on login).
2. **`.env` in git history:** Verify the `.env` file with the USDA API key is
   gitignored and not in commit history. If in history, rotate the key.

## Out of Scope (Future)

- **Agent-driven exploratory probing** (#215 stretch goal): Launch after this
  baseline is in place. Agents probe past automated defenses; findings get codified
  into permanent Playwright tests.
- **Rate limiting** (`rack-attack`): Not needed for homelab scale. Revisit when
  moving to hosted model.
- **Dependency scanning** (`bundler-audit`): Worth adding later as a CI step to
  catch vulnerable gem versions.
