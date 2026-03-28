# Performance Testing

Client-side performance measurement tools. These are on-demand diagnostic
scripts, not part of the regular test suite.

## Framework Tax Audit

Measures the client-side cost of running JavaScript frameworks (Turbo Drive,
Stimulus, ActionCable) compared to static HTML+CSS rendering.

### What it measures

- **Framework tax**: DomComplete with JS enabled minus DomComplete with JS
  disabled. This is the total cost of parsing, compiling, and executing the
  JS bundle on each page.
- **Timing breakdown**: Where the time goes — network transfer, HTML parse +
  synchronous script execution, async work (deferred scripts, dynamic imports,
  WebSocket setup), and load event handlers.
- **Long tasks**: Main-thread tasks exceeding 50ms that block user interaction.
  Each entry shows when it started and how long it lasted.
- **Resource timing**: Which JS files loaded, their sizes, and how long each
  took to fetch. Reveals whether lazy-loaded chunks (like CodeMirror) affect
  page load timing.

### How to run

```bash
# Prerequisites
bin/dev                                    # dev server on port 3030
rake db:seed                               # seed data (if not already)
rake profile:generate_stress_data          # stress kitchen (if not already)

# Run the audit
node test/performance/framework_tax_audit.js                    # both kitchens
node test/performance/framework_tax_audit.js --kitchen=stress   # stress only
node test/performance/framework_tax_audit.js --kitchen=seed     # seed only
```

### Output

- `results/framework-tax-audit.md` — human-readable report with tables
- `results/framework-tax-raw.json` — machine-readable data for comparison

### How to interpret results

**Framework tax > 300ms**: Something is wrong. Investigate the timing
breakdown and long tasks to find the culprit.

**Framework tax 100-300ms**: Normal range for a Turbo Drive + Stimulus app
with 20+ controllers. Look for easy wins in the long task list.

**Framework tax < 100ms**: Excellent. The framework overhead is imperceptible.

**Long tasks**: These are the specific main-thread blocks to optimize. A page
with one 200ms long task has a clear optimization target. A page with ten
30ms tasks (none individually "long") has diffuse overhead that's harder to
address but less impactful on feel.

**CodeMirror prefetch**: If CodeMirror chunks appear in the resource list for
pages without editors (Groceries, Ingredients), the prefetch scope is too
broad. If they load but finish after DomComplete, they don't affect the
framework tax measurement.

### When to revisit

- **Before releases**: Run against both kitchens and compare to previous
  results. Regressions in framework tax indicate new JS overhead.
- **After JS bundle changes**: Adding npm packages, new Stimulus controllers,
  or modifying the esbuild config. Compare before/after.
- **After Turbo/Stimulus upgrades**: Framework version bumps can change
  initialization cost.
- **When the app feels slow**: If navigation or interactions feel sluggish,
  run the audit to distinguish client-side overhead from server-side slowness.
  Pair with `rake profile:baseline` for the server-side picture.

### Relationship to other profiling tools

| Tool | What it measures | When to use |
|------|-----------------|-------------|
| `rake profile:baseline` | Server-side: response time, query count, HTML size | Server performance, N+1 detection |
| `framework_tax_audit.js` | Client-side: JS parse/exec, long tasks, resource loading | Client-side sluggishness, bundle bloat |
| rack-mini-profiler | Per-request server timing (always-on badge) | During development, spotting regressions |
| `?pp=flamegraph` | Server CPU profiling via stackprof | Deep-diving a slow endpoint |
| Bullet | N+1 query detection | During development and in tests |
| `npm run size` | JS bundle size (CI gate) | Preventing bundle bloat |
