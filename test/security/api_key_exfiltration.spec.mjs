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
