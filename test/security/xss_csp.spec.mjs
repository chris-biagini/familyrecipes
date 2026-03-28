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
          // Server rejected the payload outright -- that's safe
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

        // Verify the script tag appears as visible escaped text, not as an element
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

      // Navigate to menu and verify no script execution
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

        // Attempt to inject a style tag without a nonce -- CSP should block it
        const result = await page.evaluate(() => {
          const style = document.createElement("style")
          style.textContent = "body { background: red !important; }"
          document.head.appendChild(style)

          const computed = getComputedStyle(document.body).backgroundColor
          // If CSP blocks it, background won't be red
          // "rgb(255, 0, 0)" means red was applied (CSP did not block)
          return { applied: computed === "rgb(255, 0, 0)", color: computed }
        })

        // CSP with style-src 'nonce-...' should block nonce-less style injection.
        // If it does apply, it means CSP is not enforcing style-src strictly --
        // still worth documenting but not necessarily a security failure since
        // style injection alone is lower severity than script injection.
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
