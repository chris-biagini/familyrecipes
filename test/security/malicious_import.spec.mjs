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
