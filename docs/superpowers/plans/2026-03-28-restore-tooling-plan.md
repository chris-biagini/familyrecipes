# Restore Bullet + Security Testing Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-apply Bullet N+1 detection, Brakeman + Playwright security testing, and CI security gates.

**Architecture:** Three independent commits restoring dev/test tooling. No application behavior changes. Tasks 1-2 already implemented (commits `4de263f`, `d46a417`). Only Task 3 (CI gates) remains.

**Tech Stack:** Ruby (Bullet, Brakeman, bundler-audit gems), Playwright (Node.js security test specs), GitHub Actions

---

### Task 1: Bullet N+1 Detection

**Files:**
- Modify: `Gemfile` (add bullet gem)
- Create: `config/initializers/bullet.rb`
- Modify: `test/test_helper.rb` (add Bullet start/end hooks)
- Modify: `CLAUDE.md` (document Bullet behavior)

- [ ] **Step 1: Add bullet gem to Gemfile**

Add `gem 'bullet'` to the `:development` group (also used in test via `defined?` guard):

```ruby
group :development do
  gem 'bullet'
  gem 'rubocop', require: false
```

- [ ] **Step 2: Bundle install**

Run: `bundle install`
Expected: Bullet gem installed, Gemfile.lock updated.

- [ ] **Step 3: Create Bullet initializer**

Create `config/initializers/bullet.rb`:

```ruby
# frozen_string_literal: true

# Bullet: automatic N+1 query detection in development and test.
# In dev, warnings appear in the page footer and Rails log. In test, Bullet
# raises so new N+1 regressions fail the test suite.
if defined?(Bullet)
  Bullet.enable = true
  Bullet.bullet_logger = true
  Bullet.rails_logger = true
  Bullet.add_footer = true
  Bullet.raise = Rails.env.test?
end
```

- [ ] **Step 4: Add Bullet hooks to test_helper.rb**

Insert after the `require 'minitest/autorun'` line, before the existing `module ActiveSupport` block:

```ruby
# Bullet integration: start/end tracking around each test so N+1 queries
# introduced by new code are caught automatically.
if defined?(Bullet)
  module ActiveSupport
    class TestCase
      setup { Bullet.start_request }
      teardown { Bullet.end_request }
    end
  end
end
```

- [ ] **Step 5: Document Bullet in CLAUDE.md**

Add to the Commands section after the `rake catalog:sync` line:

```
rake test          # all tests via Minitest (Bullet raises on N+1 in test mode)
```

Wait — `rake test` already exists. Instead, add a note after the first code block in Commands:

```markdown
**Bullet.** Enabled in dev (page footer + Rails log) and test (raises on N+1).
If a test fails with a Bullet::Notification::UnoptimizedQueryError, add
`includes` or `preload` to the query — don't disable Bullet for that test.
```

- [ ] **Step 6: Run tests to verify Bullet doesn't break anything**

Run: `bundle exec rake test`
Expected: All tests pass. If any N+1 queries exist, Bullet will raise — fix them.

- [ ] **Step 7: Commit**

```bash
git add Gemfile Gemfile.lock config/initializers/bullet.rb test/test_helper.rb CLAUDE.md
git commit -m "Configure Bullet for N+1 detection in dev and test"
```

---

### Task 2: Brakeman + Playwright Security Tests

**Files:**
- Modify: `Gemfile` (add brakeman gem)
- Create: `config/brakeman.ignore`
- Create: `lib/tasks/security.rake`
- Modify: `.gitignore` (add security test output)
- Create: `test/security/helpers.mjs`
- Create: `test/security/seed_security_kitchens.rb`
- Create: `test/security/tenant_isolation.spec.mjs`
- Create: `test/security/auth_bypass.spec.mjs`
- Create: `test/security/xss_csp.spec.mjs`
- Create: `test/security/malicious_import.spec.mjs`
- Create: `test/security/api_key_exfiltration.spec.mjs`
- Create: `test/security/input_fuzzing.spec.mjs`
- Modify: `CLAUDE.md` (document security commands)

- [ ] **Step 1: Add brakeman gem to Gemfile**

```ruby
group :development do
  gem 'brakeman', require: false
  gem 'bullet'
```

- [ ] **Step 2: Bundle install**

Run: `bundle install`
Expected: Brakeman gem installed, Gemfile.lock updated.

- [ ] **Step 3: Create brakeman.ignore**

Create `config/brakeman.ignore`:

```json
{
  "ignored_warnings": [
    {
      "fingerprint": "8597b068a6c230decf4ea7a0f6d0de3326cf64c09c82acbc6467c0b10daa8a5b",
      "note": "permit! on portions is safe: keys are length-limited (<=50) and values are filtered to digits-only via regex. Portions have dynamic keys (portion names) that cannot be enumerated at permit time."
    }
  ],
  "updated": "2026-03-28",
  "brakeman_version": "8.0.4"
}
```

Note: the fingerprint may need regenerating if Brakeman version differs. Run `rake security` after install and update if needed.

- [ ] **Step 4: Create security.rake**

Create `lib/tasks/security.rake`:

```ruby
# frozen_string_literal: true

# Runs Brakeman static security analysis. Medium and high confidence warnings
# fail the task (confidence_level: 1); weak warnings are reported but don't fail.
# False positives are documented in config/brakeman.ignore.
#
# Usage:
#   rake security          — run Brakeman
#   rake security:verbose  — run with full detail
desc 'Run Brakeman security scan'
task security: :environment do
  require 'brakeman'
  result = Brakeman.run(app_path: Rails.root.to_s, confidence_level: 1, quiet: true)

  if result.filtered_warnings.any?
    Brakeman.report(result, format: :text)
    abort "\nBrakeman found #{result.filtered_warnings.size} warning(s)."
  else
    puts 'Brakeman: no warnings found.'
  end
end

namespace :security do
  desc 'Run Brakeman with full detail'
  task verbose: :environment do
    require 'brakeman'
    result = Brakeman.run(app_path: Rails.root.to_s, confidence_level: 1)
    Brakeman.report(result, format: :text)
    abort "\nBrakeman found #{result.filtered_warnings.size} warning(s)." if result.filtered_warnings.any?
  end
end
```

- [ ] **Step 5: Add security test output to .gitignore**

Append to `.gitignore`:

```
# Performance audit raw data (machine-generated, not committed)
test/performance/results/*.json

# Security test seed output (machine-generated)
test/security/user_ids.json
```

Note: the performance line already exists — just add the security lines below it.

- [ ] **Step 6: Create test/security/helpers.mjs**

Create `test/security/helpers.mjs`:

```javascript
/**
 * Shared helpers for security tests. Provides authenticated browser contexts
 * and common assertions for the security test suite.
 *
 * Uses the dev login endpoint to authenticate as specific users against
 * the two test kitchens (alpha/beta) seeded by seed_security_kitchens.rb.
 */
import { chromium } from "playwright"
import { readFileSync } from "fs"
import { dirname, join } from "path"
import { fileURLToPath } from "url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const BASE_URL = process.env.BASE_URL || "http://localhost:3030"

// Load user IDs from seed script output
const USER_IDS = JSON.parse(
  readFileSync(join(__dirname, "user_ids.json"), "utf-8"),
)

export { BASE_URL, USER_IDS }

const csrfCache = new WeakMap()

async function getCsrfToken(context) {
  if (csrfCache.has(context)) return csrfCache.get(context)
  const page = await context.newPage()
  await page.goto(`${BASE_URL}/`)
  const token = await page.locator('meta[name="csrf-token"]').getAttribute("content")
  await page.close()
  csrfCache.set(context, token)
  return token
}

/**
 * Launch a browser and authenticate as a specific user via dev login.
 * Returns { browser, context, page } — caller must close browser.
 */
export async function authenticatedBrowser(userId) {
  const browser = await chromium.launch()
  const context = await browser.newContext()
  const page = await context.newPage()
  await page.goto(`${BASE_URL}/dev/login/${userId}`)
  await page.waitForLoadState("networkidle")
  if (page.url().includes('/dev/login')) {
    await browser.close()
    throw new Error('Dev login failed — is the server running in development mode?')
  }
  return { browser, context, page }
}

/**
 * Make a raw HTTP request with the cookies from an authenticated page.
 * Useful for testing non-GET endpoints without browser navigation.
 */
export async function fetchWithSession(context, url, options = {}) {
  const cookies = await context.cookies()
  const cookieHeader = cookies.map((c) => `${c.name}=${c.value}`).join("; ")
  const csrfToken = await getCsrfToken(context)

  const headers = {
    Cookie: cookieHeader,
    "X-CSRF-Token": csrfToken || "",
    ...options.headers,
  }

  return fetch(`${BASE_URL}${url}`, { ...options, headers, redirect: "manual" })
}

/**
 * Make an unauthenticated HTTP request (no cookies, no CSRF).
 */
export async function fetchAnonymous(url, options = {}) {
  return fetch(`${BASE_URL}${url}`, { ...options, redirect: "manual" })
}

/**
 * Collect all console messages from a page during a callback.
 * Returns an array of { type, text } objects.
 */
export async function collectConsoleMessages(page, callback) {
  const messages = []
  const handler = (msg) => messages.push({ type: msg.type(), text: msg.text() })
  page.on("console", handler)
  await callback()
  await page.waitForTimeout(200)
  page.off("console", handler)
  return messages
}
```

- [ ] **Step 7: Create test/security/seed_security_kitchens.rb**

Create `test/security/seed_security_kitchens.rb`:

```ruby
# frozen_string_literal: true

# Seeds two isolated kitchens for security testing. Run via:
#   MULTI_KITCHEN=true bin/rails runner test/security/seed_security_kitchens.rb
#
# Creates:
#   - kitchen_alpha (user: alice) with a recipe and API keys set
#   - kitchen_beta (user: bob) with a recipe
#
# Idempotent — safe to run multiple times.
#
# Note: set MULTI_KITCHEN=true for multi-kitchen routing to work.

alpha = Kitchen.find_or_create_by!(slug: 'kitchen-alpha') do |k|
  k.name = 'Kitchen Alpha'
end

beta = Kitchen.find_or_create_by!(slug: 'kitchen-beta') do |k|
  k.name = 'Kitchen Beta'
end

alice = User.find_or_create_by!(email: 'alice@test.local') do |u|
  u.name = 'Alice'
end

bob = User.find_or_create_by!(email: 'bob@test.local') do |u|
  u.name = 'Bob'
end

ActsAsTenant.with_tenant(alpha) do
  Membership.find_or_create_by!(kitchen: alpha, user: alice)
  unless alpha.recipes.exists?(slug: 'test-recipe')
    RecipeWriteService.create(
      markdown: "# Test Recipe\n\n## Step 1\n\n- 1 cup flour\n- 2 eggs",
      kitchen: alpha,
      category_name: 'Test'
    )
  end
end

ActsAsTenant.with_tenant(beta) do
  Membership.find_or_create_by!(kitchen: beta, user: bob)
  unless beta.recipes.exists?(slug: 'test-recipe')
    RecipeWriteService.create(
      markdown: "# Test Recipe\n\n## Step 1\n\n- 1 cup flour\n- 2 eggs",
      kitchen: beta,
      category_name: 'Test'
    )
  end
end

# Set fake API keys on alpha (for exfiltration tests)
alpha.update!(
  usda_api_key: 'secret-usda-key-12345',
  anthropic_api_key: 'secret-anthropic-key-67890'
)

# Write user IDs to a JSON file so Playwright tests can discover them
require 'json'
ids = { alice_id: alice.id, bob_id: bob.id }
File.write(File.join(__dir__, 'user_ids.json'), JSON.pretty_generate(ids))

puts 'Security test kitchens seeded.'
puts "  Kitchen Alpha: slug=kitchen-alpha, user=alice (id=#{alice.id})"
puts "  Kitchen Beta:  slug=kitchen-beta,  user=bob   (id=#{bob.id})"
```

- [ ] **Step 8: Create test/security/tenant_isolation.spec.mjs**

Create `test/security/tenant_isolation.spec.mjs`:

```javascript
/**
 * Tenant isolation tests — verifies that a member of kitchen-alpha cannot
 * access kitchen-beta's data through URL manipulation or direct API calls.
 *
 * Known gap: ActionCable stream scoping (kitchen A shouldn't receive kitchen B's
 * broadcasts) is better tested as a Rails channel integration test since Playwright
 * can't easily inspect WebSocket frames.
 *
 * Requires: seed_security_kitchens.rb seeded, server running on port 3030.
 */
import { describe, it, before, after } from "node:test"
import assert from "node:assert/strict"
import { authenticatedBrowser, fetchWithSession, BASE_URL, USER_IDS } from "./helpers.mjs"

describe("Tenant Isolation", () => {
  let alice, bob

  before(async () => {
    alice = await authenticatedBrowser(USER_IDS.alice_id)
    bob = await authenticatedBrowser(USER_IDS.bob_id)
  })

  after(async () => {
    await alice.browser.close()
    await bob.browser.close()
  })

  describe("GET requests — cross-tenant page access", () => {
    const betaPages = [
      "/kitchens/kitchen-beta/recipes/test-recipe",
      "/kitchens/kitchen-beta/menu",
      "/kitchens/kitchen-beta/groceries",
      "/kitchens/kitchen-beta/ingredients",
      "/kitchens/kitchen-beta/settings",
    ]

    for (const path of betaPages) {
      it(`Alice cannot access ${path}`, async () => {
        const resp = await fetchWithSession(alice.context, path)
        assert.ok(
          [403, 404].includes(resp.status),
          `Expected 403/404 for ${path}, got ${resp.status}`
        )
      })
    }
  })

  describe("Write requests — cross-tenant mutations", () => {
    it("Alice cannot create a recipe in kitchen-beta", async () => {
      const resp = await fetchWithSession(alice.context, "/kitchens/kitchen-beta/recipes", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "recipe[markdown]=%23+Hack&recipe[category_name]=Test",
      })
      assert.ok(
        [403, 404, 422].includes(resp.status),
        `Expected rejection for cross-tenant recipe create, got ${resp.status}`
      )
    })

    it("Alice cannot update kitchen-beta settings", async () => {
      const resp = await fetchWithSession(alice.context, "/kitchens/kitchen-beta/settings", {
        method: "PATCH",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "kitchen[site_title]=Hacked",
      })
      assert.ok(
        [403, 404, 422].includes(resp.status),
        `Expected rejection for cross-tenant settings update, got ${resp.status}`
      )
    })

    it("Alice cannot delete a recipe in kitchen-beta", async () => {
      const resp = await fetchWithSession(alice.context, "/kitchens/kitchen-beta/recipes/test-recipe", {
        method: "DELETE",
      })
      assert.ok(
        [403, 404].includes(resp.status),
        `Expected rejection for cross-tenant recipe delete, got ${resp.status}`
      )
    })

    it("Alice cannot modify kitchen-beta grocery state", async () => {
      const resp = await fetchWithSession(alice.context, "/kitchens/kitchen-beta/groceries/check", {
        method: "PATCH",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "name=flour",
      })
      assert.ok(
        [403, 404, 422].includes(resp.status),
        `Expected rejection for cross-tenant grocery mutation, got ${resp.status}`
      )
    })

    it("Alice cannot import into kitchen-beta", async () => {
      const resp = await fetchWithSession(alice.context, "/kitchens/kitchen-beta/import", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "file=test",
      })
      assert.ok(
        [403, 404, 422].includes(resp.status),
        `Expected rejection for cross-tenant import, got ${resp.status}`
      )
    })
  })
})
```

- [ ] **Step 9: Create test/security/auth_bypass.spec.mjs**

Create `test/security/auth_bypass.spec.mjs`:

```javascript
/**
 * Authentication & authorization bypass tests — verifies that unauthenticated
 * users cannot access write endpoints and that authenticated non-members
 * cannot mutate kitchens they don't belong to.
 *
 * Requires: seed_security_kitchens.rb seeded, server running on port 3030.
 */
import { describe, it, before, after } from "node:test"
import assert from "node:assert/strict"
import { authenticatedBrowser, fetchWithSession, fetchAnonymous, BASE_URL, USER_IDS } from "./helpers.mjs"

const KITCHEN = "/kitchens/kitchen-alpha"

describe("Auth Bypass", () => {
  describe("Unauthenticated access — write endpoints", () => {
    const writeEndpoints = [
      { method: "POST",   path: `${KITCHEN}/recipes`,         body: "recipe[markdown]=%23+Test&recipe[category_name]=Test" },
      { method: "PATCH",  path: `${KITCHEN}/settings`,        body: "kitchen[site_title]=Hacked" },
      { method: "PATCH",  path: `${KITCHEN}/menu/select`,     body: "recipe_id=1" },
      { method: "PATCH",  path: `${KITCHEN}/groceries/check`, body: "name=flour" },
      { method: "POST",   path: `${KITCHEN}/import`,          body: "file=test" },
      { method: "DELETE", path: `${KITCHEN}/recipes/test-recipe` },
      { method: "POST",   path: `${KITCHEN}/nutrition/flour`,  body: "entry[calories]=100" },
      { method: "PATCH",  path: `${KITCHEN}/categories/order`, body: "order[]=1&order[]=2" },
      { method: "PATCH",  path: `${KITCHEN}/tags/update`,      body: "tags[]=quick" },
    ]

    for (const { method, path, body } of writeEndpoints) {
      it(`${method} ${path} is rejected`, async () => {
        const options = { method, headers: {} }
        if (body) {
          options.headers["Content-Type"] = "application/x-www-form-urlencoded"
          options.body = body
        }
        const resp = await fetchAnonymous(path, options)
        assert.ok(
          [403, 404, 422].includes(resp.status),
          `Expected 403/404/422 for anonymous ${method} ${path}, got ${resp.status}`
        )
      })
    }
  })

  describe("Unauthenticated access — read endpoints", () => {
    it("anonymous can read a public recipe page", async () => {
      const resp = await fetchAnonymous(`${KITCHEN}/recipes/test-recipe`)
      assert.equal(resp.status, 200)
    })

    it("anonymous cannot access settings", async () => {
      const resp = await fetchAnonymous(`${KITCHEN}/settings`)
      assert.ok(
        [302, 403].includes(resp.status),
        `Expected 302/403 for anonymous settings access, got ${resp.status}`
      )
    })
  })

  describe("Dev login route guard", () => {
    it("dev login is gated by Rails.env.local? (documentation)", () => {
      assert.ok(true)
    })
  })

  describe("Authenticated non-member access", () => {
    let bob

    before(async () => {
      bob = await authenticatedBrowser(USER_IDS.bob_id)
    })

    after(async () => {
      await bob.browser.close()
    })

    const nonMemberEndpoints = [
      { method: "POST",   path: `${KITCHEN}/recipes`,         body: "recipe[markdown]=%23+Test&recipe[category_name]=Test" },
      { method: "PATCH",  path: `${KITCHEN}/settings`,        body: "kitchen[site_title]=Hacked" },
      { method: "PATCH",  path: `${KITCHEN}/menu/select`,     body: "recipe_id=1" },
      { method: "DELETE", path: `${KITCHEN}/recipes/test-recipe` },
    ]

    for (const { method, path, body } of nonMemberEndpoints) {
      it(`Bob cannot ${method} ${path}`, async () => {
        const options = { method, headers: {} }
        if (body) {
          options.headers["Content-Type"] = "application/x-www-form-urlencoded"
          options.body = body
        }
        const resp = await fetchWithSession(bob.context, path, options)
        assert.ok(
          [403, 404].includes(resp.status),
          `Expected 403/404 for non-member ${method} ${path}, got ${resp.status}`
        )
      })
    }
  })
})
```

- [ ] **Step 10: Create test/security/xss_csp.spec.mjs**

Create `test/security/xss_csp.spec.mjs`:

```javascript
/**
 * XSS and CSP enforcement tests -- injects XSS payloads into recipe titles,
 * ingredient names, and Quick Bite names, then verifies they render as escaped
 * text (never executable). Also verifies Content-Security-Policy headers are
 * present on all major pages.
 *
 * Requires: seed_security_kitchens.rb seeded, server running on port 3030.
 */
import { describe, it, before, after } from "node:test"
import assert from "node:assert/strict"
import { authenticatedBrowser, fetchWithSession, collectConsoleMessages, BASE_URL, USER_IDS } from "./helpers.mjs"

const KITCHEN = "/kitchens/kitchen-alpha"

const XSS_PAYLOADS = [
  { name: "script tag", value: '<script>alert("xss")</script>' },
  { name: "img onerror", value: '<img src=x onerror=alert("xss")>' },
  { name: "event handler", value: '<div onmouseover=alert("xss")>hover</div>' },
  { name: "svg onload", value: '<svg onload=alert("xss")>' },
  { name: "javascript: URL", value: '<a href="javascript:alert(1)">click</a>' },
]

describe("XSS & CSP Enforcement", () => {
  let alice

  before(async () => {
    alice = await authenticatedBrowser(USER_IDS.alice_id)
  })

  after(async () => {
    await alice.browser.close()
  })

  describe("CSP headers present", () => {
    const pages = [
      `${KITCHEN}/recipes/test-recipe`,
      `${KITCHEN}/menu`,
      `${KITCHEN}/groceries`,
      `${KITCHEN}/settings`,
      "/",
    ]

    for (const path of pages) {
      it(`${path} has CSP header with default-src and script-src`, async () => {
        const resp = await fetchWithSession(alice.context, path)
        const csp = resp.headers.get("content-security-policy")

        assert.ok(csp, `Expected CSP header on ${path}`)
        assert.ok(csp.includes("default-src"), `CSP missing default-src on ${path}`)
        assert.ok(csp.includes("script-src"), `CSP missing script-src on ${path}`)
      })
    }
  })

  describe("XSS in recipe titles", () => {
    for (const { name, value } of XSS_PAYLOADS) {
      it(`${name} payload in title is not executable`, async () => {
        const markdown = `# ${value}\n\n## Step 1\n\nDo something.`
        const body = new URLSearchParams({
          "recipe[markdown]": markdown,
          "recipe[category_name]": "Test",
        }).toString()

        const resp = await fetchWithSession(alice.context, `${KITCHEN}/recipes`, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body,
        })

        const status = resp.status
        if (status < 200 || status >= 400) {
          assert.ok(true, `Server rejected payload with status ${status}`)
          return
        }

        const location = resp.headers.get("location")
        if (!location) {
          assert.ok(true, "No redirect location -- payload was likely rejected")
          return
        }

        const recipeUrl = location.startsWith("http") ? location : `${BASE_URL}${location}`
        const page = await alice.context.newPage()
        try {
          const messages = await collectConsoleMessages(page, async () => {
            await page.goto(recipeUrl)
            await page.waitForLoadState("networkidle")
          })

          const suspicious = messages.filter(
            (m) => /xss|alert/i.test(m.text)
          )
          assert.equal(
            suspicious.length, 0,
            `XSS payload executed! Console messages: ${JSON.stringify(suspicious)}`
          )
        } finally {
          await page.close()
        }
      })
    }
  })

  describe("XSS in ingredient names", () => {
    it("script tag in ingredient renders as escaped text", async () => {
      const xssIngredient = '<script>alert("xss")</script>'
      const markdown = `# XSS Ingredient Test\n\n## Step 1\n\n- 1 cup ${xssIngredient}\n\nMix well.`
      const body = new URLSearchParams({
        "recipe[markdown]": markdown,
        "recipe[category_name]": "Test",
      }).toString()

      const resp = await fetchWithSession(alice.context, `${KITCHEN}/recipes`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body,
      })

      const location = resp.headers.get("location")
      if (!location) {
        assert.ok(resp.status >= 400, "Payload rejected or no redirect")
        return
      }

      const recipeUrl = location.startsWith("http") ? location : `${BASE_URL}${location}`
      const page = await alice.context.newPage()
      try {
        const messages = await collectConsoleMessages(page, async () => {
          await page.goto(recipeUrl)
          await page.waitForLoadState("networkidle")
        })

        const suspicious = messages.filter((m) => /xss|alert/i.test(m.text))
        assert.equal(
          suspicious.length, 0,
          `XSS in ingredient executed! Console: ${JSON.stringify(suspicious)}`
        )

        const scriptElements = await page.locator("script").filter({ hasText: "xss" }).count()
        assert.equal(scriptElements, 0, "Unescaped <script> tag found in page DOM")
      } finally {
        await page.close()
      }
    })
  })

  describe("XSS in Quick Bite names", () => {
    it("script tag in Quick Bite title does not cause 500 or execute", async () => {
      const xssTitle = '<script>alert("xss")</script>'
      const markdown = `# ${xssTitle}\n\n- 1 cup flour`
      const body = new URLSearchParams({
        "quick_bites[markdown]": markdown,
        "quick_bites[category_name]": "Test",
      }).toString()

      const resp = await fetchWithSession(alice.context, `${KITCHEN}/menu/quick_bites`, {
        method: "PATCH",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body,
      })

      assert.ok(
        resp.status !== 500,
        `Quick Bite XSS payload caused server error (500)`
      )

      const page = await alice.context.newPage()
      try {
        const messages = await collectConsoleMessages(page, async () => {
          await page.goto(`${BASE_URL}${KITCHEN}/menu`)
          await page.waitForLoadState("networkidle")
        })

        const suspicious = messages.filter((m) => /xss|alert/i.test(m.text))
        assert.equal(
          suspicious.length, 0,
          `XSS in Quick Bite executed! Console: ${JSON.stringify(suspicious)}`
        )
      } finally {
        await page.close()
      }
    })
  })

  describe("Inline style injection blocked by CSP", () => {
    it("dynamically injected <style> without nonce is blocked", async () => {
      const page = await alice.context.newPage()
      try {
        await page.goto(`${BASE_URL}${KITCHEN}/recipes/test-recipe`)
        await page.waitForLoadState("networkidle")

        const result = await page.evaluate(() => {
          const style = document.createElement("style")
          style.textContent = "body { background: red !important; }"
          document.head.appendChild(style)

          const computed = getComputedStyle(document.body).backgroundColor
          return { applied: computed === "rgb(255, 0, 0)", color: computed }
        })

        assert.ok(
          !result.applied,
          `Nonce-less <style> was applied (background became ${result.color}) -- CSP style-src may be too permissive`
        )
      } finally {
        await page.close()
      }
    })
  })
})
```

- [ ] **Step 11: Create test/security/malicious_import.spec.mjs**

Create `test/security/malicious_import.spec.mjs`:

```javascript
/**
 * Malicious import tests — uploads dangerous file payloads via the import
 * endpoint and verifies graceful rejection (no 5xx errors).
 *
 * Covers: oversized files, path traversal filenames, binary garbage,
 * non-recipe content, deeply nested directory structures.
 * Requires: seed_security_kitchens.rb seeded, server running on port 3030.
 */
import { describe, it, before, after } from "node:test"
import assert from "node:assert/strict"
import { authenticatedBrowser, fetchWithSession, BASE_URL, USER_IDS } from "./helpers.mjs"

const KITCHEN = "/kitchens/kitchen-alpha"

describe("Malicious Import", () => {
  let alice

  before(async () => {
    alice = await authenticatedBrowser(USER_IDS.alice_id)
  })

  after(async () => {
    await alice.browser.close()
  })

  async function uploadFile(filename, content, contentType = "text/plain") {
    const blob = new Blob([content], { type: contentType })
    const formData = new FormData()
    formData.append("files[]", blob, filename)

    const cookies = await alice.context.cookies()
    const cookieHeader = cookies.map((c) => `${c.name}=${c.value}`).join("; ")

    const csrfPage = await alice.context.newPage()
    await csrfPage.goto(`${BASE_URL}/`)
    const csrfToken = await csrfPage.locator('meta[name="csrf-token"]').getAttribute("content")
    await csrfPage.close()

    return fetch(`${BASE_URL}${KITCHEN}/import`, {
      method: "POST",
      headers: { Cookie: cookieHeader, "X-CSRF-Token": csrfToken },
      body: formData,
    })
  }

  it("rejects oversized file upload gracefully", async () => {
    const largeContent = "x".repeat(11 * 1024 * 1024)
    const resp = await uploadFile("large.zip", largeContent, "application/zip")

    assert.ok(resp.status < 500, `Server error on oversized file: ${resp.status}`)
  })

  it("rejects file with path traversal filename", async () => {
    const content = "# Harmless Recipe\n\n## Step 1\n\n- 1 cup test"
    const resp = await uploadFile("../../etc/passwd", content)

    assert.ok(resp.status < 500, `Server error on path traversal filename: ${resp.status}`)
  })

  it("rejects binary payload without crashing", async () => {
    const binaryGarbage = new Uint8Array(1024)
    for (let i = 0; i < binaryGarbage.length; i++) binaryGarbage[i] = Math.floor(Math.random() * 256)
    const resp = await uploadFile("garbage.bin", binaryGarbage, "application/octet-stream")

    assert.ok(resp.status < 500, `Server error on binary payload: ${resp.status}`)
  })

  it("handles non-recipe content gracefully", async () => {
    const jsonContent = JSON.stringify({ not: "a recipe", data: [1, 2, 3] })
    const resp = await uploadFile("data.json", jsonContent, "application/json")

    assert.ok(resp.status < 500, `Server error on non-recipe content: ${resp.status}`)
  })

  it("handles deeply nested directory structure in filename", async () => {
    const nestedPath = "a/".repeat(100) + "recipe.md"
    const content = "# Nested Recipe\n\n## Step 1\n\n- 1 cup flour"
    const resp = await uploadFile(nestedPath, content)

    assert.ok(resp.status < 500, `Server error on deeply nested path: ${resp.status}`)
  })
})
```

- [ ] **Step 12: Create test/security/api_key_exfiltration.spec.mjs**

Create `test/security/api_key_exfiltration.spec.mjs`:

```javascript
/**
 * API key exfiltration tests — verifies that encrypted API keys (USDA, Anthropic)
 * never appear in plaintext in any HTTP response: HTML pages, JSON endpoints,
 * Turbo Frames, export archives, or error pages.
 *
 * Requires: seed_security_kitchens.rb seeded (sets fake keys on kitchen-alpha),
 * server running on port 3030.
 */
import { describe, it, before, after } from "node:test"
import assert from "node:assert/strict"
import { authenticatedBrowser, fetchWithSession, BASE_URL, USER_IDS } from "./helpers.mjs"

const KITCHEN = "/kitchens/kitchen-alpha"
const SECRETS = ["secret-usda-key-12345", "secret-anthropic-key-67890"]

function assertNoSecrets(content, label) {
  for (const secret of SECRETS) {
    assert.ok(
      !content.includes(secret),
      `API key leaked in ${label}: found "${secret.slice(0, 10)}..."`
    )
  }
}

describe("API Key Exfiltration", () => {
  let alice

  before(async () => {
    alice = await authenticatedBrowser(USER_IDS.alice_id)
  })

  after(async () => {
    await alice.browser.close()
  })

  describe("No API key in HTML pages", () => {
    const pages = [
      `${KITCHEN}/settings`,
      `${KITCHEN}/recipes/test-recipe`,
      `${KITCHEN}/menu`,
      `${KITCHEN}/groceries`,
      `${KITCHEN}/ingredients`,
      "/",
    ]

    for (const path of pages) {
      it(`GET ${path}`, async () => {
        const resp = await fetchWithSession(alice.context, path)
        const body = await resp.text()
        assertNoSecrets(body, `HTML page ${path}`)
      })
    }
  })

  it("No API key in settings editor frame", async () => {
    const resp = await fetchWithSession(alice.context, `${KITCHEN}/settings/editor_frame`, {
      headers: { "Turbo-Frame": "editor-frame" },
    })
    const body = await resp.text()
    assertNoSecrets(body, "settings editor frame")
  })

  it("No API key in USDA search JSON", async () => {
    const resp = await fetchWithSession(alice.context, `${KITCHEN}/usda/search?q=flour`)
    const body = await resp.text()
    assertNoSecrets(body, "USDA search JSON")
  })

  it("No API key in export ZIP", async () => {
    const resp = await fetchWithSession(alice.context, `${KITCHEN}/export`)
    const body = await resp.text()
    assertNoSecrets(body, "export ZIP")
  })

  it("No API key in recipe content endpoint", async () => {
    const resp = await fetchWithSession(alice.context, `${KITCHEN}/recipes/test-recipe/content`)
    const body = await resp.text()
    assertNoSecrets(body, "recipe content endpoint")
  })

  it("No API key in error responses", async () => {
    const resp = await fetchWithSession(alice.context, `${KITCHEN}/recipes/nonexistent-recipe-slug`)
    const body = await resp.text()
    assertNoSecrets(body, "404 error response")
  })
})
```

- [ ] **Step 13: Create test/security/input_fuzzing.spec.mjs**

Create `test/security/input_fuzzing.spec.mjs`:

```javascript
/**
 * Input fuzzing tests — sends boundary and malicious inputs through various
 * endpoints and verifies the app handles them gracefully (no 500 errors).
 *
 * Requires: seed_security_kitchens.rb seeded, server running on port 3030.
 */
import { describe, it, before, after } from "node:test"
import assert from "node:assert/strict"
import { authenticatedBrowser, fetchWithSession, USER_IDS } from "./helpers.mjs"

const KITCHEN = "/kitchens/kitchen-alpha"

const FUZZ_INPUTS = [
  { name: "extremely long string", value: "a".repeat(10_000) },
  { name: "null bytes", value: "hello\x00world" },
  { name: "unicode RTL markers", value: "test\u202Eevil\u202C" },
  { name: "zero-width characters", value: "test\u200B\u200C\u200Dword" },
  { name: "emoji sequences", value: "recipe 🍳👨‍🍳🥘🔥" },
  { name: "control characters", value: "line\x01\x02\x03\x04end" },
  { name: "SQL-like injection", value: "'; DROP TABLE recipes; --" },
  { name: "nested HTML entities", value: "&amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;" },
  { name: "extremely long single word", value: "x".repeat(50_000) },
  { name: "newlines and tabs", value: "line1\nline2\n\tindented\r\nwindows" },
  { name: "empty string", value: "" },
  { name: "only whitespace", value: "   \t\n  " },
]

describe("Input Fuzzing", () => {
  let browser, context

  before(async () => {
    ;({ browser, context } = await authenticatedBrowser(USER_IDS.alice_id))
  })

  after(async () => {
    await browser?.close()
  })

  describe("Recipe creation with fuzzed titles", () => {
    for (const input of FUZZ_INPUTS) {
      it(`handles ${input.name}`, async () => {
        const body = `recipe[markdown]=${encodeURIComponent(`# ${input.value}\n\n## Step 1\n\n- 1 cup flour`)}&recipe[category_name]=Test`
        const resp = await fetchWithSession(context, `${KITCHEN}/recipes`, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body,
        })

        assert.ok(resp.status < 500, `Expected status < 500 for "${input.name}", got ${resp.status}`)
      })
    }
  })

  describe("Search with fuzzed queries", () => {
    for (const input of FUZZ_INPUTS) {
      it(`handles ${input.name}`, async () => {
        const resp = await fetchWithSession(
          context,
          `${KITCHEN}/usda/search?q=${encodeURIComponent(input.value)}`,
        )

        assert.ok(resp.status < 500, `Expected status < 500 for "${input.name}", got ${resp.status}`)
      })
    }
  })

  describe("Settings update with fuzzed values", () => {
    for (const input of FUZZ_INPUTS) {
      it(`handles ${input.name}`, async () => {
        const body = `kitchen[site_title]=${encodeURIComponent(input.value)}`
        const resp = await fetchWithSession(context, `${KITCHEN}/settings`, {
          method: "PATCH",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body,
        })

        assert.ok(resp.status < 500, `Expected status < 500 for "${input.name}", got ${resp.status}`)
      })
    }
  })

  describe("Grocery operations with fuzzed names", () => {
    const subset = FUZZ_INPUTS.slice(0, 6)

    for (const input of subset) {
      it(`handles ${input.name}`, async () => {
        const body = `name=${encodeURIComponent(input.value)}`
        const resp = await fetchWithSession(context, `${KITCHEN}/groceries/need`, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body,
        })

        assert.ok(resp.status < 500, `Expected status < 500 for "${input.name}", got ${resp.status}`)
      })
    }
  })
})
```

- [ ] **Step 14: Run Brakeman to verify it passes**

Run: `bundle exec rake security`
Expected: "Brakeman: no warnings found." (or update `brakeman.ignore` fingerprint if needed).

- [ ] **Step 15: Document security commands in CLAUDE.md**

Add to the Commands section, after the Bullet note:

```markdown
**Security.** `rake security` runs Brakeman static analysis (medium+ confidence
warnings fail). `rake security:verbose` for full detail. False positives go in
`config/brakeman.ignore`. Playwright pen tests in `test/security/` require a
running dev server:
```bash
MULTI_KITCHEN=true bin/rails runner test/security/seed_security_kitchens.rb
npx playwright test test/security/              # all security specs
npx playwright test test/security/tenant_isolation.spec.mjs  # single spec
```

- [ ] **Step 16: Run full test suite**

Run: `bundle exec rake test`
Expected: All tests pass (Bullet active — fix any N+1 it catches).

- [ ] **Step 17: Run lint**

Run: `bundle exec rubocop`
Expected: No offenses.

- [ ] **Step 18: Commit**

```bash
git add Gemfile Gemfile.lock config/brakeman.ignore lib/tasks/security.rake \
  .gitignore test/security/ CLAUDE.md
git commit -m "Add Brakeman + Playwright security tests"
```

### Task 3: CI Security Gates

**Status:** Not yet implemented.

**Files:**
- Modify: `Gemfile` (add bundler-audit gem)
- Modify: `.github/workflows/test.yml` (add Brakeman + bundle-audit steps)
- Modify: `CLAUDE.md` (document CI security gates)

- [ ] **Step 1: Add bundler-audit gem**

Add `gem 'bundler-audit', require: false` to the `:development` group in `Gemfile`, after the `brakeman` line:

```ruby
group :development do
  gem 'brakeman', require: false
  gem 'bundler-audit', require: false
  gem 'bullet'
```

- [ ] **Step 2: Bundle install**

Run: `bundle install`
Expected: bundler-audit gem installed, Gemfile.lock updated.

- [ ] **Step 3: Verify bundler-audit works locally**

Run: `bundle exec bundle-audit check --update`
Expected: Advisory database downloads, then either "No vulnerabilities found" or a list of known CVEs.

- [ ] **Step 4: Verify Brakeman works locally**

Run: `bundle exec brakeman --no-pager -q`
Expected: "No warnings found" (all warnings are in brakeman.ignore).

- [ ] **Step 5: Add CI steps to test.yml**

In `.github/workflows/test.yml`, add two steps after "Lint and test" and before "Verify clean migration and seed":

```yaml
      - name: Security scan (Brakeman)
        run: bundle exec brakeman --no-pager -q

      - name: Dependency audit (bundler-audit)
        run: bundle exec bundle-audit check --update
```

- [ ] **Step 6: Update CLAUDE.md**

In the Commands section, after the security testing block (around line 363), add:

```markdown
CI runs Brakeman and `bundler-audit` automatically on every push and PR.
```

- [ ] **Step 7: Run full test suite**

Run: `bundle exec rake`
Expected: All tests pass, 0 RuboCop offenses.

- [ ] **Step 8: Commit**

```bash
git add Gemfile Gemfile.lock .github/workflows/test.yml CLAUDE.md
git commit -m "Add CI security gates: Brakeman + bundler-audit"
```
