/**
 * Tenant isolation tests — verifies that a member of kitchen-alpha cannot
 * access kitchen-beta's data through URL manipulation or direct API calls.
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
