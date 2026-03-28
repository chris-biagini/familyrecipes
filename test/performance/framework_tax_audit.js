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
