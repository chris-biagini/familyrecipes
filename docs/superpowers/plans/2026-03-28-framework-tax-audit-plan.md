# Framework Tax Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible Playwright-based audit that measures exactly where the 500-700ms client-side framework tax goes, producing a data-backed report that identifies the top contributors.

**Architecture:** A standalone Node.js script using Playwright to load pages in two modes (JS enabled, JS disabled) with authenticated sessions. Captures navigation timing, long tasks, and resource timing via native browser Performance APIs. Outputs both machine-readable JSON and a human-readable markdown report. Runs against both the seed kitchen (8 recipes) and stress kitchen (200 recipes) for comparison.

**Tech Stack:** Playwright (already installed globally via npx), Node.js, Chrome DevTools Performance APIs

**Spec:** `docs/superpowers/specs/2026-03-28-framework-tax-audit-design.md`

---

## File Map

### Audit script
- Create: `test/performance/framework_tax_audit.js` — Playwright audit script
- Create: `test/performance/README.md` — methodology documentation (how to run, when to revisit)

### Output directory
- Create: `test/performance/results/.gitkeep` — ensures directory exists in git
- Gitignored: `test/performance/results/*.json` — raw timing data (machine-generated)
- Committed: `test/performance/results/framework-tax-audit.md` — human-readable report (after first run)

### Project docs
- Modify: `.gitignore` — ignore raw JSON results
- Modify: `CLAUDE.md` — add framework tax audit to performance profiling section and commands

---

### Task 1: Directory Structure and Gitignore

**Files:**
- Create: `test/performance/results/.gitkeep`
- Modify: `.gitignore`

- [ ] **Step 1: Create the directory structure**

```bash
mkdir -p test/performance/results
touch test/performance/results/.gitkeep
```

- [ ] **Step 2: Add gitignore entry for raw JSON results**

In `.gitignore`, add at the end:

```
# Performance audit raw data (machine-generated, not committed)
test/performance/results/*.json
```

The markdown report will be committed manually after review; the JSON is
ephemeral data for programmatic comparison between runs.

- [ ] **Step 3: Commit**

```bash
git add test/performance/results/.gitkeep .gitignore
git commit -m "Add test/performance directory structure for framework tax audit"
```

---

### Task 2: Write the Playwright Audit Script

**Files:**
- Create: `test/performance/framework_tax_audit.js`

This is the core deliverable. The script:
1. Launches Chromium, authenticates via `/dev/login/:id`
2. For each page, runs 5 loads with JS enabled and 5 with JS disabled
3. Captures navigation timing, long tasks, and resource timing
4. Computes framework tax (DomComplete difference)
5. Writes JSON data and markdown report

- [ ] **Step 1: Write the audit script**

Create `test/performance/framework_tax_audit.js`:

```javascript
/**
 * Framework Tax Audit — measures the client-side cost of running Turbo Drive,
 * Stimulus, and ActionCable vs static HTML+CSS rendering.
 *
 * Captures navigation timing, long tasks, and resource timing via native
 * browser Performance APIs. Runs against both seed and stress kitchens with
 * authenticated sessions.
 *
 * Usage:
 *   node test/performance/framework_tax_audit.js                    # both kitchens
 *   node test/performance/framework_tax_audit.js --kitchen=stress   # stress only
 *   node test/performance/framework_tax_audit.js --kitchen=seed     # seed only
 *
 * Prerequisites:
 *   - Dev server running on port 3030 (bin/dev)
 *   - Seed data loaded (rails db:seed)
 *   - Stress kitchen generated (rake profile:generate_stress_data)
 *   - Playwright available (npx playwright)
 */
import { chromium } from "playwright"
import { writeFileSync, mkdirSync } from "fs"
import { dirname, join } from "path"
import { fileURLToPath } from "url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const RESULTS_DIR = join(__dirname, "results")
const BASE_URL = process.env.BASE_URL || "http://localhost:3030"
const RUNS_PER_PAGE = 5

const KITCHENS = {
  seed: {
    slug: "our-kitchen",
    label: "Seed (8 recipes)",
    userId: 1,
    recipeSlugs: ["oatmeal-cookies"],
  },
  stress: {
    slug: "stress-kitchen",
    label: "Stress (200 recipes)",
    userId: 1,
    recipeSlugs: ["homestyle-turkey-rice"],
  },
}

function pagesFor(kitchen) {
  const prefix = `/kitchens/${kitchen.slug}`
  const recipeSlug = kitchen.recipeSlugs[0]
  return [
    { name: "Homepage", path: prefix },
    { name: "Menu", path: `${prefix}/menu` },
    { name: "Groceries", path: `${prefix}/groceries` },
    { name: "Ingredients", path: `${prefix}/ingredients` },
    { name: "Recipe", path: `${prefix}/recipes/${recipeSlug}` },
  ]
}

// --- Measurement helpers ---

/**
 * Install a PerformanceObserver for long tasks BEFORE navigation so it
 * captures tasks during initial page load. Returns a handle to retrieve
 * the collected entries after the page settles.
 */
async function installLongTaskObserver(page) {
  await page.evaluateOnNewDocument(() => {
    window.__longTasks = []
    const observer = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        window.__longTasks.push({
          startTime: Math.round(entry.startTime),
          duration: Math.round(entry.duration),
          name: entry.name,
        })
      }
    })
    try {
      observer.observe({ type: "longtask", buffered: true })
    } catch {
      // longtask not supported in this browser build — degrade gracefully
    }
  })
}

async function collectTimings(page) {
  return page.evaluate(() => {
    const nav = performance.getEntriesByType("navigation")[0]
    if (!nav) return null

    return {
      fetchStart: Math.round(nav.fetchStart),
      responseEnd: Math.round(nav.responseEnd),
      domContentLoadedEventEnd: Math.round(nav.domContentLoadedEventEnd),
      domComplete: Math.round(nav.domComplete),
      loadEventEnd: Math.round(nav.loadEventEnd),
    }
  })
}

async function collectResourceTimings(page) {
  return page.evaluate(() => {
    return performance
      .getEntriesByType("resource")
      .filter(
        (r) => r.initiatorType === "script" || r.name.endsWith(".js")
      )
      .map((r) => ({
        name: r.name.split("/").pop().split("?")[0],
        fullUrl: r.name,
        transferSize: r.transferSize,
        decodedBodySize: r.decodedBodySize,
        duration: Math.round(r.duration),
        startTime: Math.round(r.startTime),
        responseEnd: Math.round(r.responseEnd),
      }))
  })
}

async function collectLongTasks(page) {
  return page.evaluate(() => window.__longTasks || [])
}

// --- Authentication ---

async function authenticate(context, kitchen) {
  const page = await context.newPage()
  await page.goto(
    `${BASE_URL}/dev/login/${kitchen.userId}`,
    { waitUntil: "networkidle" }
  )
  await page.close()
}

// --- Single page measurement ---

async function measurePage(browser, pageInfo, jsEnabled) {
  const runs = []

  for (let i = 0; i < RUNS_PER_PAGE; i++) {
    // Fresh context per run — cold cache, no stale connections
    const context = await browser.newContext({ javaScriptEnabled: jsEnabled })

    // Authenticate for JS-enabled runs (pages render different DOM for members)
    if (jsEnabled) {
      await authenticate(context, pageInfo.kitchen)
    }

    const page = await context.newPage()

    if (jsEnabled) {
      await installLongTaskObserver(page)
    }

    await page.goto(`${BASE_URL}${pageInfo.path}`, {
      waitUntil: "load",
      timeout: 30000,
    })

    // Brief settle time for any post-load async work
    await page.waitForTimeout(500)

    const timings = await collectTimings(page)
    const resources = jsEnabled ? await collectResourceTimings(page) : []
    const longTasks = jsEnabled ? await collectLongTasks(page) : []

    if (timings) {
      runs.push({ timings, resources, longTasks })
    }

    await context.close()
  }

  return runs
}

// --- Statistics ---

function median(arr) {
  const sorted = [...arr].sort((a, b) => a - b)
  const mid = Math.floor(sorted.length / 2)
  return sorted.length % 2 ? sorted[mid] : Math.round((sorted[mid - 1] + sorted[mid]) / 2)
}

function summarizeRuns(runs) {
  if (runs.length === 0) return null

  const fields = Object.keys(runs[0].timings)
  const timings = {}
  for (const field of fields) {
    timings[field] = median(runs.map((r) => r.timings[field]))
  }

  // Derived breakdowns
  const breakdown = {
    network: timings.responseEnd - timings.fetchStart,
    parseAndExec: timings.domContentLoadedEventEnd - timings.responseEnd,
    asyncWork: timings.domComplete - timings.domContentLoadedEventEnd,
    loadHandlers: timings.loadEventEnd - timings.domComplete,
  }

  // Merge long tasks across runs, take the run closest to the median domComplete
  const domCompletes = runs.map((r) => r.timings.domComplete)
  const medianDC = median(domCompletes)
  const closestRun = runs.reduce((best, run) =>
    Math.abs(run.timings.domComplete - medianDC) <
    Math.abs(best.timings.domComplete - medianDC)
      ? run
      : best
  )

  return {
    timings,
    breakdown,
    longTasks: closestRun.longTasks,
    resources: closestRun.resources,
    allDomCompletes: domCompletes,
  }
}

// --- Report generation ---

function generateReport(results) {
  const lines = []
  const timestamp = new Date().toISOString().slice(0, 19).replace("T", " ")

  lines.push("# Framework Tax Audit Report")
  lines.push("")
  lines.push(`**Generated:** ${timestamp}`)
  lines.push(`**Runs per page:** ${RUNS_PER_PAGE} (median reported)`)
  lines.push(`**Server:** ${BASE_URL}`)
  lines.push(`**Browser:** Headless Chromium (Playwright)`)
  lines.push("")

  for (const kitchenKey of Object.keys(results)) {
    const kitchenResults = results[kitchenKey]
    const kitchen = KITCHENS[kitchenKey]

    lines.push(`## ${kitchen.label}`)
    lines.push("")

    // Framework tax summary table
    lines.push("### Framework Tax")
    lines.push("")
    lines.push("| Page | Static DomComplete | JS DomComplete | Framework Tax | All JS runs (ms) |")
    lines.push("|------|-------------------|----------------|---------------|------------------|")

    for (const pageResult of kitchenResults) {
      const staticDC = pageResult.static?.timings.domComplete ?? "—"
      const jsDC = pageResult.js?.timings.domComplete ?? "—"
      const tax =
        pageResult.js && pageResult.static
          ? pageResult.js.timings.domComplete - pageResult.static.timings.domComplete
          : "—"
      const allRuns = pageResult.js?.allDomCompletes?.join(", ") ?? "—"
      lines.push(
        `| ${pageResult.name} | ${staticDC}ms | ${jsDC}ms | **${tax}ms** | ${allRuns} |`
      )
    }
    lines.push("")

    // Timing breakdown table
    lines.push("### Timing Breakdown (JS enabled)")
    lines.push("")
    lines.push("| Page | Network | Parse+Exec | Async Work | Load Handlers | Total |")
    lines.push("|------|---------|------------|------------|---------------|-------|")

    for (const pageResult of kitchenResults) {
      const b = pageResult.js?.breakdown
      if (!b) continue
      const total = pageResult.js.timings.loadEventEnd - pageResult.js.timings.fetchStart
      lines.push(
        `| ${pageResult.name} | ${b.network}ms | ${b.parseAndExec}ms | ${b.asyncWork}ms | ${b.loadHandlers}ms | ${total}ms |`
      )
    }
    lines.push("")

    // Long tasks
    lines.push("### Long Tasks (>50ms main thread blocks)")
    lines.push("")

    for (const pageResult of kitchenResults) {
      const tasks = pageResult.js?.longTasks || []
      if (tasks.length === 0) {
        lines.push(`**${pageResult.name}:** No long tasks detected`)
      } else {
        lines.push(`**${pageResult.name}:** ${tasks.length} long task(s)`)
        lines.push("")
        lines.push("| # | Start (ms) | Duration (ms) |")
        lines.push("|---|-----------|---------------|")
        tasks.forEach((t, i) => {
          lines.push(`| ${i + 1} | ${t.startTime} | ${t.duration} |`)
        })
      }
      lines.push("")
    }

    // Resource loading (JS files)
    lines.push("### JS Resources Loaded")
    lines.push("")

    for (const pageResult of kitchenResults) {
      const resources = pageResult.js?.resources || []
      if (resources.length === 0) continue

      lines.push(`**${pageResult.name}:**`)
      lines.push("")
      lines.push("| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |")
      lines.push("|------|--------------|-------------|---------------|-----------|")
      for (const r of resources) {
        const transfer = r.transferSize ? (r.transferSize / 1024).toFixed(1) : "cached"
        const decoded = r.decodedBodySize ? (r.decodedBodySize / 1024).toFixed(1) : "—"
        lines.push(
          `| ${r.name} | ${transfer} | ${decoded} | ${r.duration} | ${r.startTime} |`
        )
      }
      lines.push("")
    }

    // CodeMirror prefetch check
    lines.push("### CodeMirror Prefetch Analysis")
    lines.push("")
    for (const pageResult of kitchenResults) {
      const resources = pageResult.js?.resources || []
      const cmChunks = resources.filter(
        (r) => r.name.includes("editor_setup") || r.name.includes("chunk-")
      )
      if (cmChunks.length > 0) {
        const names = cmChunks.map((r) => r.name).join(", ")
        const latestEnd = Math.max(...cmChunks.map((r) => r.responseEnd))
        const domComplete = pageResult.js?.timings.domComplete ?? 0
        const verdict =
          latestEnd > domComplete
            ? "AFTER DomComplete — contributes to framework tax"
            : "BEFORE DomComplete — may contribute to framework tax"
        lines.push(
          `- **${pageResult.name}:** Loaded ${names}. Last response at ${latestEnd}ms, DomComplete at ${domComplete}ms. ${verdict}`
        )
      } else {
        lines.push(`- **${pageResult.name}:** No CodeMirror chunks loaded`)
      }
    }
    lines.push("")
  }

  // Summary
  lines.push("## Top Contributors (Analysis)")
  lines.push("")
  lines.push("_Fill in after reviewing the data above._")
  lines.push("")
  lines.push("1. ")
  lines.push("2. ")
  lines.push("3. ")
  lines.push("")

  return lines.join("\n")
}

// --- Main ---

async function main() {
  const kitchenArg = process.argv.find((a) => a.startsWith("--kitchen="))
  const kitchenFilter = kitchenArg ? kitchenArg.split("=")[1] : null

  const kitchensToTest = kitchenFilter
    ? { [kitchenFilter]: KITCHENS[kitchenFilter] }
    : KITCHENS

  if (kitchenFilter && !KITCHENS[kitchenFilter]) {
    console.error(`Unknown kitchen: ${kitchenFilter}. Use 'seed' or 'stress'.`)
    process.exit(1)
  }

  console.log("Framework Tax Audit")
  console.log("===================")
  console.log(`Server: ${BASE_URL}`)
  console.log(`Runs per page: ${RUNS_PER_PAGE}`)
  console.log("")

  const browser = await chromium.launch({ headless: true })
  const allResults = {}

  for (const [kitchenKey, kitchen] of Object.entries(kitchensToTest)) {
    console.log(`\n--- ${kitchen.label} ---\n`)
    const pages = pagesFor(kitchen)
    const kitchenResults = []

    for (const pageInfo of pages) {
      const enrichedPage = { ...pageInfo, kitchen }
      console.log(`  ${pageInfo.name} (${pageInfo.path})`)

      process.stdout.write("    JS enabled:  ")
      const jsRuns = await measurePage(browser, enrichedPage, true)
      const jsSummary = summarizeRuns(jsRuns)
      console.log(`${jsSummary?.timings.domComplete ?? "—"}ms (median DomComplete)`)

      process.stdout.write("    JS disabled: ")
      const staticRuns = await measurePage(browser, enrichedPage, false)
      const staticSummary = summarizeRuns(staticRuns)
      console.log(`${staticSummary?.timings.domComplete ?? "—"}ms (median DomComplete)`)

      const tax =
        jsSummary && staticSummary
          ? jsSummary.timings.domComplete - staticSummary.timings.domComplete
          : null
      if (tax !== null) {
        console.log(`    Framework tax: ${tax}ms`)
      }

      kitchenResults.push({
        name: pageInfo.name,
        path: pageInfo.path,
        js: jsSummary,
        static: staticSummary,
      })
    }

    allResults[kitchenKey] = kitchenResults
  }

  await browser.close()

  // Write results
  mkdirSync(RESULTS_DIR, { recursive: true })

  const jsonPath = join(RESULTS_DIR, "framework-tax-raw.json")
  writeFileSync(jsonPath, JSON.stringify(allResults, null, 2))
  console.log(`\nRaw data: ${jsonPath}`)

  const reportPath = join(RESULTS_DIR, "framework-tax-audit.md")
  writeFileSync(reportPath, generateReport(allResults))
  console.log(`Report:   ${reportPath}`)
}

main().catch((err) => {
  console.error("Audit failed:", err)
  process.exit(1)
})
```

- [ ] **Step 2: Verify the script parses without errors**

Run: `node --check test/performance/framework_tax_audit.js`

Expected: No output (clean parse).

- [ ] **Step 3: Commit**

```bash
git add test/performance/framework_tax_audit.js
git commit -m "Add Playwright framework tax audit script (#302)

Measures client-side framework tax (JS enabled vs disabled DomComplete)
across 5 pages for both seed and stress kitchens. Captures navigation
timing, long tasks, and resource timing via native Performance APIs.
Outputs JSON + markdown report."
```

---

### Task 3: Write the Testing Methodology Documentation

**Files:**
- Create: `test/performance/README.md`
- Modify: `CLAUDE.md`

Document what the audit measures, how to run it, when to revisit, and how
to interpret results. This is the "so we know how to revisit it" deliverable.

- [ ] **Step 1: Create the README**

Create `test/performance/README.md`:

```markdown
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
```

- [ ] **Step 2: Update CLAUDE.md performance profiling section**

In `CLAUDE.md`, find the paragraph starting with `**Performance profiling.**`
(around line 343). After the sentence ending with `...before merging.`, add:

```
`node test/performance/framework_tax_audit.js` measures client-side framework
tax (JS-enabled vs JS-disabled DomComplete) with long task and resource timing
breakdowns. Run before releases and after JS bundle changes. See
`test/performance/README.md` for methodology and interpretation.
```

- [ ] **Step 3: Update CLAUDE.md commands section**

In `CLAUDE.md`, find the commands code block (around line 388). After the
`rake profile:generate_stress_data` line, add:

```
node test/performance/framework_tax_audit.js  # client-side framework tax audit (needs bin/dev running)
```

- [ ] **Step 4: Run lint to verify CLAUDE.md is clean**

Run: `bundle exec rubocop CLAUDE.md` — this file isn't Ruby so RuboCop won't
check it, but verify no accidental syntax issues by reading the modified
sections.

- [ ] **Step 5: Commit**

```bash
git add test/performance/README.md CLAUDE.md
git commit -m "Document framework tax audit methodology

README covers what is measured, how to run, how to interpret results,
and when to revisit. CLAUDE.md updated with the new command and a
pointer to the methodology docs."
```

---

### Task 4: Run the Audit and Commit Results

**Files:**
- Create: `test/performance/results/framework-tax-audit.md` (generated)
- Create: `test/performance/results/framework-tax-raw.json` (generated, gitignored)

This task requires the dev server to be running. The subagent should start it
if it's not already running.

- [ ] **Step 1: Verify the dev server is running**

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3030/up
```

Expected: `200`. If not, start the server:

```bash
bin/dev &
sleep 5
curl -s -o /dev/null -w "%{http_code}" http://localhost:3030/up
```

- [ ] **Step 2: Run the audit against the stress kitchen first**

```bash
node test/performance/framework_tax_audit.js --kitchen=stress
```

Expected: Console output showing per-page measurements. Framework tax numbers
for the stress kitchen (200 recipes) — these should be higher than the seed
kitchen due to heavier DOM.

Review the console output. If any page fails or times out, investigate before
proceeding.

- [ ] **Step 3: Run the audit against the seed kitchen**

```bash
node test/performance/framework_tax_audit.js --kitchen=seed
```

Expected: Similar output with lower framework tax numbers (fewer DOM elements,
fewer controller instances).

- [ ] **Step 4: Run the full audit (both kitchens)**

```bash
node test/performance/framework_tax_audit.js
```

Expected: Combined report with both kitchens' data in a single markdown file.

- [ ] **Step 5: Review the generated report**

Read `test/performance/results/framework-tax-audit.md` and verify:
- Framework tax numbers are plausible (50-1000ms range)
- Timing breakdowns sum correctly
- Long tasks are captured (there should be at least some >50ms tasks)
- Resource timing shows the main JS bundle and any chunks loaded
- CodeMirror prefetch analysis shows whether chunks loaded on non-editor pages

- [ ] **Step 6: Fill in the Top Contributors section**

Edit `test/performance/results/framework-tax-audit.md` and replace the
placeholder "Top Contributors" section with analysis based on the data:

1. Identify the largest single contributor from the timing breakdown
   (Parse+Exec vs Async Work)
2. Identify the longest long task and what page it's on
3. Note any surprising resource loads (e.g., CodeMirror on Groceries page)

- [ ] **Step 7: Run esbuild bundle analysis**

```bash
npx esbuild --bundle --analyze app/javascript/application.js --outfile=/dev/null 2>&1 | head -40
```

Add a "Bundle Composition" section to the report with the top entries from
the analysis output.

- [ ] **Step 8: Commit the report**

```bash
git add test/performance/results/framework-tax-audit.md
git commit -m "Add framework tax audit results for seed and stress kitchens (#302)

Initial baseline measurements identifying top contributors to the
500-700ms client-side framework tax. Data from Playwright with
authenticated sessions, 5 runs per page, median reported."
```

---

## Task Dependency Graph

```
Task 1 (directory + gitignore) ──→ standalone, do first
Task 2 (audit script) ──────────→ depends on Task 1 (directory exists)
Task 3 (docs + CLAUDE.md) ──────→ independent of Task 2
Task 4 (run audit + results) ───→ depends on Tasks 2 and 3
```

Tasks 2 and 3 can be parallelized after Task 1. Task 4 requires both.
