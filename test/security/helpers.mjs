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
  await page.waitForLoadState("domcontentloaded")
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
