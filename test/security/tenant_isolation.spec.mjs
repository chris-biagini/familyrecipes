/**
 * Tenant isolation tests — verifies that a member of kitchen-alpha cannot
 * access kitchen-beta's data through URL manipulation or direct API calls.
 *
 * Known gap: ActionCable stream scoping (kitchen A shouldn't receive kitchen B's
 * broadcasts) is better tested as a Rails channel integration test since Playwright
 * can't easily inspect WebSocket frames.
 *
 * Uses a single shared browser with separate contexts per user to avoid
 * thread exhaustion on constrained systems.
 *
 * Requires: seed_security_kitchens.rb seeded, server running on port 3030.
 */
import { describe, it, before, after } from "node:test"
import assert from "node:assert/strict"
import { chromium } from "playwright"
import { fetchWithSession, BASE_URL, USER_IDS } from "./helpers.mjs"

describe("Tenant Isolation", () => {
  let browser, aliceCtx, bobCtx

  before(async () => {
    browser = await chromium.launch()

    aliceCtx = await browser.newContext()
    const alicePage = await aliceCtx.newPage()
    await alicePage.goto(`${BASE_URL}/dev/login/${USER_IDS.alice_id}`)
    await alicePage.waitForLoadState("networkidle")
    await alicePage.close()

    bobCtx = await browser.newContext()
    const bobPage = await bobCtx.newPage()
    await bobPage.goto(`${BASE_URL}/dev/login/${USER_IDS.bob_id}`)
    await bobPage.waitForLoadState("networkidle")
    await bobPage.close()
  })

  after(async () => {
    await browser.close()
  })

  describe("GET requests — cross-tenant page access", () => {
    // Recipe show pages are intentionally public (read-only for all visitors)
    const protectedPages = [
      "/kitchens/kitchen-beta/menu",
      "/kitchens/kitchen-beta/groceries",
      "/kitchens/kitchen-beta/ingredients",
      "/kitchens/kitchen-beta/settings",
    ]

    it("Alice can read a public recipe in kitchen-beta", async () => {
      const resp = await fetchWithSession(aliceCtx, "/kitchens/kitchen-beta/recipes/test-recipe")
      assert.equal(resp.status, 200, "Recipe show should be publicly readable")
    })

    for (const path of protectedPages) {
      it(`Alice cannot access ${path}`, async () => {
        const resp = await fetchWithSession(aliceCtx, path)
        assert.ok(
          [403, 404].includes(resp.status),
          `Expected 403/404 for ${path}, got ${resp.status}`
        )
      })
    }
  })

  describe("Write requests — cross-tenant mutations", () => {
    it("Alice cannot create a recipe in kitchen-beta", async () => {
      const resp = await fetchWithSession(aliceCtx, "/kitchens/kitchen-beta/recipes", {
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
      const resp = await fetchWithSession(aliceCtx, "/kitchens/kitchen-beta/settings", {
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
      const resp = await fetchWithSession(aliceCtx, "/kitchens/kitchen-beta/recipes/test-recipe", {
        method: "DELETE",
      })
      assert.ok(
        [403, 404].includes(resp.status),
        `Expected rejection for cross-tenant recipe delete, got ${resp.status}`
      )
    })

    it("Alice cannot modify kitchen-beta grocery state", async () => {
      const resp = await fetchWithSession(aliceCtx, "/kitchens/kitchen-beta/groceries/check", {
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
      const resp = await fetchWithSession(aliceCtx, "/kitchens/kitchen-beta/import", {
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
