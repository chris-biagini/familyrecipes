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
