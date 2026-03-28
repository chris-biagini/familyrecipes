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
