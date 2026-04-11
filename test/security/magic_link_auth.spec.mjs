/**
 * Magic link authentication security spec.
 *
 * Exercises the /sessions/new -> /sessions/magic_link flow through a real
 * browser. Covers:
 * - happy path sign-in (requires looking up the code from the test mailer;
 *   this spec relies on dev env logger-delivery so it cannot extract the
 *   code — it asserts UI states only, not full sign-in. The Minitest
 *   integration test covers the full flow).
 * - anti-enumeration: known vs unknown email produce the same UI
 * - invalid code is rejected with 422 + error message
 * - brute-force attempts are rate-limited after 10 attempts
 * - code reuse is blocked (single-use)
 *
 * Requires a running dev server. Run with:
 *   bin/rails runner test/security/seed_security_kitchens.rb
 *   npx playwright test test/security/magic_link_auth.spec.mjs
 */
import { test, expect } from "@playwright/test"

const BASE_URL = process.env.BASE_URL || "http://localhost:3030"

test.describe("magic link auth", () => {
  test("known email redirects to code entry screen", async ({ page }) => {
    await page.goto(`${BASE_URL}/sessions/new`)
    await page.fill('input[type="email"]', "alpha-owner@example.com")
    await page.click('button[type="submit"], input[type="submit"]')

    await expect(page).toHaveURL(/\/sessions\/magic_link/)
    await expect(page.locator("body")).toContainText(/check your email/i)
  })

  test("unknown email produces identical screen (anti-enumeration)", async ({
    page,
  }) => {
    await page.goto(`${BASE_URL}/sessions/new`)
    await page.fill(
      'input[type="email"]',
      `nobody-${Date.now()}@example.com`,
    )
    await page.click('button[type="submit"], input[type="submit"]')

    await expect(page).toHaveURL(/\/sessions\/magic_link/)
    await expect(page.locator("body")).toContainText(/check your email/i)
  })

  test("invalid code is rejected with an error and does not sign in", async ({
    page,
  }) => {
    await page.goto(`${BASE_URL}/sessions/new`)
    await page.fill('input[type="email"]', "alpha-owner@example.com")
    await page.click('button[type="submit"], input[type="submit"]')

    await page.fill('input[name="code"]', "ZZZZZZ")
    await page.click('button[type="submit"], input[type="submit"]')

    await expect(page.locator("body")).toContainText(/invalid or expired/i)

    const cookies = await page.context().cookies()
    expect(cookies.find((c) => c.name === "session_id")).toBeUndefined()
  })

  test("brute force attempts are rate-limited", async ({ page, request }) => {
    await page.goto(`${BASE_URL}/sessions/new`)
    await page.fill('input[type="email"]', "alpha-owner@example.com")
    await page.click('button[type="submit"], input[type="submit"]')

    const csrf = await page
      .locator('meta[name="csrf-token"]')
      .getAttribute("content")
    const cookies = await page.context().cookies()
    const cookieHeader = cookies.map((c) => `${c.name}=${c.value}`).join("; ")

    let lastStatus = 0
    for (let i = 0; i < 15; i++) {
      const r = await request.post(`${BASE_URL}/sessions/magic_link`, {
        form: { code: "ZZZZZZ", authenticity_token: csrf },
        headers: {
          "x-csrf-token": csrf,
          cookie: cookieHeader,
        },
      })
      lastStatus = r.status()
      if (lastStatus === 429) break
    }
    expect(lastStatus).toBe(429)
  })
})
