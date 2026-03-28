# Restore Bullet + Security Testing Tooling

**Date:** 2026-03-28
**Context:** After reverting 19 post-v0.7 commits that degraded client-side
performance, re-apply two pieces of infrastructure that were lost in the
revert: Bullet (N+1 detection) and security testing (Brakeman + Playwright).

## Scope

Two independent commits. No application behavior changes — pure dev/test
tooling.

### Commit 1: Bullet N+1 Detection

- `gem 'bullet'` in Gemfile (development + test group)
- `config/initializers/bullet.rb`: enable, Rails logger, page footer in dev,
  raise in test
- `test/test_helper.rb`: `Bullet.start_request` / `Bullet.end_request` hooks
  in `ActiveSupport::TestCase` setup/teardown
- CLAUDE.md: document Bullet test-mode raise behavior

### Commit 2: Brakeman + Playwright Security Tests

- `gem 'brakeman'` in Gemfile (development group)
- `lib/tasks/security.rake`: `rake security` runs Brakeman
- `config/brakeman.ignore`: existing warning suppressions
- `.gitignore`: `test/security/user_ids.json`
- `test/security/helpers.mjs`: shared Playwright auth/fetch utilities
- `test/security/seed_security_kitchens.rb`: creates alpha/beta kitchens
- 7 Playwright spec files: tenant isolation, auth bypass, XSS/CSP, malicious
  imports, API key exfiltration, input fuzzing
- CLAUDE.md: document `rake security` and Playwright security test commands

### Explicitly excluded

- Session expiry (migration, model changes, auth concern changes)
- rack-mini-profiler, stackprof, vernier, size-limit
- All performance profiling rake tasks and baselines
- All performance design specs and plans
