/**
 * Auth flow security tests — verifies rate limiting on join code verification,
 * signed token tamper resistance, and unauthenticated write rejection.
 *
 * Rate limiting requires the dev server's memory cache store (not null_store).
 * The join code brute force test sends 12 rapid requests against a 10/hour
 * limit — at least one should return 429.
 *
 * Requires: seed_security_kitchens.rb seeded, server running on port 3030.
 */
import { describe, it } from "node:test"
import assert from "node:assert/strict"
import { fetchAnonymous, fetchAnonymousWithCsrf, BASE_URL } from "./helpers.mjs"

describe("Auth Security", () => {
  it("join code brute force is rate limited", async () => {
    const responses = []
    for (let i = 0; i < 12; i++) {
      const resp = await fetchAnonymousWithCsrf("/join", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `join_code=invalid+attempt+${i}`,
      })
      responses.push(resp.status)
    }

    const rateLimited = responses.filter((s) => s === 429)
    assert.ok(
      rateLimited.length > 0,
      `Expected at least one 429 response, got statuses: ${responses.join(", ")}`,
    )
  })

  it("tampered signed kitchen ID is rejected", async () => {
    const resp = await fetchAnonymousWithCsrf("/join/complete", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: "email=test%40example.com&signed_kitchen_id=tampered-value",
    })

    assert.equal(resp.status, 302, "Should redirect on tampered token")
    assert.ok(
      resp.headers.get("location")?.includes("/join"),
      `Expected redirect to /join, got: ${resp.headers.get("location")}`,
    )
  })

  it("logged out user cannot create a recipe", async () => {
    const resp = await fetchAnonymous("/kitchens/kitchen-alpha/recipes", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: "recipe[markdown]=%23+Test&recipe[category_name]=Test",
    })

    assert.ok(
      [403, 404, 422].includes(resp.status),
      `Expected 403/404/422 for anonymous recipe create, got ${resp.status}`,
    )
  })

  it("/join/complete is rate limited", async () => {
    const responses = []
    for (let i = 0; i < 12; i++) {
      const resp = await fetchAnonymousWithCsrf("/join/complete", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `email=flood${i}%40example.com&name=Flood&signed_kitchen_id=dummy`,
      })
      responses.push(resp.status)
    }

    const rateLimited = responses.filter((s) => s === 429)
    assert.ok(
      rateLimited.length > 0,
      `Expected at least one 429 response, got statuses: ${responses.join(", ")}`,
    )
  })
})
