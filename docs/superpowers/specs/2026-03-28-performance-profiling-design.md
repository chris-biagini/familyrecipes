# Performance Profiling — Design Spec

**Date:** 2026-03-28

Formalize performance profiling for the v1.0 launch and beyond. Establishes
dev-time tooling, CI gates, a repeatable baseline process, and a maintenance
cadence. Complements the ad-hoc optimization work in the 2026-03-27
performance optimization spec — this spec is about the *process*, not
individual fixes.

## Goals

1. Make performance visible by default during development (always-on profiler
   badge, automatic N+1 detection).
2. Prevent regressions via CI (JS bundle size gate).
3. Make re-profiling the app a one-command operation (`rake profile:baseline`).
4. Establish a lightweight maintenance cadence that scales from homelab to
   hosted multi-tenant.

## Non-Goals

- Production APM (Datadog, New Relic, Skylight). Premature for homelab; revisit
  when moving to hosted.
- Lighthouse CI. Requires a running server in CI — significant workflow
  complexity for marginal value over manual DevTools checks.
- Load testing (k6, wrk). Not needed until multi-tenant hosted deployment.
- Back-end performance assertions in CI. Query count tests are brittle;
  rack-mini-profiler catches the same issues in dev with less maintenance.

## 1. Gem & Package Additions

### Ruby — development group only

```ruby
group :development do
  gem 'rack-mini-profiler'
  gem 'stackprof'
  gem 'vernier'
  gem 'bullet'
end
```

- **rack-mini-profiler** — always-on badge showing queries, timing, memory per
  request. The single most impactful profiling tool for Rails.
- **stackprof** — sampling CPU/wall profiler, generates flamegraphs. Invoked
  via `?pp=flamegraph` through rack-mini-profiler or programmatically.
- **vernier** — newer sampling profiler (Shopify/John Hawthorn), lighter weight
  with better flamegraph output. Alternative to stackprof for deep dives.
- **bullet** — automatic N+1 and unused eager load detection.

No production dependencies added. All profiling tools are dev-only.

### npm — devDependencies

```json
{
  "devDependencies": {
    "size-limit": "^11.0.0",
    "@size-limit/file": "^11.0.0"
  }
}
```

- **size-limit** — CI gate on JS bundle size. Fails the build if the main
  bundle exceeds a configured threshold.
- **@size-limit/file** — plugin that measures gzipped file size.

## 2. Configuration

### rack-mini-profiler

Initializer at `config/initializers/mini_profiler.rb`:

- Storage: `MemoryStore` (default, appropriate for single-process dev).
- Position: bottom-left badge showing ms / queries on every page.
- Flamegraph support: `?pp=flamegraph` query param (uses stackprof).
- CSP: wire `content_security_policy_nonce` to the existing Rails nonce
  generator so the injected script tag satisfies strict CSP.
- Dev-only: no production activation. When moving to hosted, gate behind
  an admin check.

### Bullet

Initializer at `config/initializers/bullet.rb`:

- Enabled in development and test (test mode raises on N+1 so new tests
  catch regressions).
- `alert = false` — no browser popups.
- `bullet_logger = true` — writes to `log/bullet.log`.
- `rails_logger = true` — appends warnings to the Rails log.
- `add_footer = true` — shows N+1 warnings in the page footer.
- Allowlist known acceptable cases (e.g., intentional `has_many :through`
  traversals where we use preloaded data via `steps.flat_map`).

### size-limit

`.size-limit.json` in project root:

```json
[
  {
    "name": "Main JS bundle",
    "path": "app/assets/builds/application.js",
    "limit": "200 kB",
    "gzip": true
  }
]
```

Threshold set to current main bundle gzipped size + ~15% headroom. The
CodeMirror chunk is excluded — it is lazy-loaded and does not affect initial
page load. When intentionally adding a dependency that increases bundle size,
bump the threshold in `.size-limit.json` and commit — this forces a conscious
decision.

npm script:

```json
{
  "scripts": {
    "size": "size-limit",
    "size:report": "size-limit --json"
  }
}
```

### stackprof / vernier

No initializer needed. Invoked explicitly:

- Via `?pp=flamegraph` through rack-mini-profiler (stackprof).
- Via `Vernier.trace(out: "tmp/vernier.json") { ... }` for targeted profiling.
- Via the baseline rake task for automated profiling runs.

## 3. Baseline Profiling Rake Task

`rake profile:baseline` — repeatable one-command profiling of key pages.

### What it measures per page

Pages profiled: homepage, menu, groceries, a representative recipe show page.

Per page (warm, 3-run average):
- Response time (ms)
- SQL query count (via `ActiveSupport::Notifications` on `sql.active_record`)
- HTML response size (bytes)

### What it measures globally

- JS bundle sizes: main bundle and CodeMirror chunk, raw and gzipped
- CSS total size: raw and gzipped

### Implementation

The task boots Rails in development, creates a test kitchen with seed data
(reusing `db/seeds.rb` logic), and makes requests via
`ActionDispatch::Integration::Session` (same mechanism as integration tests —
no running server required). An `ActiveSupport::Notifications` subscriber
counts SQL queries per request.

### Output

Prints a markdown table to stdout and appends to `tmp/profile_baselines.log`
with a timestamp. The log file is not committed — it is local dev data.

```
## Baseline — 2026-03-28 14:30

| Page       | Time (avg) | Queries | HTML size |
|------------|-----------|---------|-----------|
| Homepage   | 18ms      | 28      | 58 KB     |
| Menu       | 72ms      | 41      | 112 KB    |
| Groceries  | 45ms      | 32      | 86 KB     |
| Recipe     | 12ms      | 8       | 24 KB     |

| Asset              | Raw     | Gzipped |
|--------------------|---------|---------|
| JS (main)          | 252 KB  | 176 KB  |
| JS (CM chunk)      | 513 KB  | 180 KB  |
| CSS (total)        | 75 KB   | 16 KB   |
```

### What the task does NOT do

No flamegraphs. Flamegraphs are investigative, not routine — use
`?pp=flamegraph` in the browser when you need one. The baseline task captures
the numbers you compare over time.

## 4. CI Integration

Single addition to the existing `test.yml` workflow — a new step after
test/lint:

```yaml
- name: Check JS bundle size
  run: npx size-limit
```

`size-limit` reads `.size-limit.json`, measures the built bundle, and exits
non-zero if the threshold is exceeded. No server, no browser, no Lighthouse
complexity.

### What is NOT in CI

- Back-end performance benchmarks (brittle, caught in dev instead).
- Lighthouse (requires running server, complex workflow).
- Bundle analysis visualization (useful ad-hoc, not worth CI time).

## 5. Maintenance Workflow

### During feature work

- rack-mini-profiler badge is always visible. If query count jumps or response
  time spikes, investigate before merging.
- Bullet logs N+1 warnings automatically. Check `log/bullet.log` and the page
  footer during development.

### Every PR

- CI bundle size gate runs automatically. Failures require a conscious
  threshold bump.

### Quarterly

- Run `rake profile:baseline`.
- Compare against the previous entry in `tmp/profile_baselines.log`.
- Investigate anything that drifted more than 20% from the previous baseline.
- Next quarterly baseline due ~2026-07-01.

### Before major releases

- Full deep dive: run baseline, flamegraph any page over 50ms, review
  accumulated Bullet warnings.
- Compare against the post-optimization baseline from 2026-03-27 as the
  long-term reference point.

## 6. Future Considerations (out of scope)

These become relevant when moving to hosted multi-tenant:

- **Production APM:** Skylight or Scout APM for request-level visibility in
  production. Skylight integrates well with Rails and has a free tier.
- **Load testing:** k6 scripts for concurrent user simulation. Important for
  validating per-tenant isolation overhead.
- **Lighthouse CI:** Reconsider when CI already has a running server (e.g.,
  Docker-based test stage).
- **Database query analysis:** SQLite `EXPLAIN QUERY PLAN` assertions for
  critical queries, or migration to PostgreSQL with `pg_stat_statements`.
