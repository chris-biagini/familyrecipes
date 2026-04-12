/**
 * Rough timing-variance assertion: the known-email and unknown-email branches
 * of POST /sessions should return in comparable time after the deliver_later
 * switch. Not a cryptographic guarantee — catches regressions, not attacks.
 *
 * Requires: seed_security_kitchens.rb seeded, server running on port 3030.
 */
import { describe, it } from "node:test"
import assert from "node:assert/strict"
import { BASE_URL } from "./helpers.mjs"

const SAMPLE_COUNT = 10
const TOLERANCE_RATIO = 5.0

async function timePost(email, sessionCookie, csrfToken) {
  const start = Date.now()
  await fetch(`${BASE_URL}/sessions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Cookie: sessionCookie,
      "X-CSRF-Token": csrfToken,
    },
    body: `email=${encodeURIComponent(email)}`,
    redirect: "manual",
  })
  return Date.now() - start
}

async function getSessionAndCsrf() {
  const primer = await fetch(`${BASE_URL}/sessions/new`, { redirect: "manual" })
  const setCookies = primer.headers.getSetCookie?.() ?? []
  const sessionCookie = setCookies
    .map((c) => c.split(";")[0])
    .filter(Boolean)
    .join("; ")
  const html = await primer.text()
  const tokenMatch = html.match(/<meta name="csrf-token" content="([^"]+)"/)
  return { sessionCookie, csrfToken: tokenMatch ? tokenMatch[1] : "" }
}

function median(arr) {
  const sorted = [...arr].sort((a, b) => a - b)
  return sorted[Math.floor(sorted.length / 2)]
}

describe("Timing invariance on POST /sessions", () => {
  it("known and unknown email branches return in comparable time", async () => {
    const knownSamples = []
    const unknownSamples = []

    for (let i = 0; i < SAMPLE_COUNT; i++) {
      const { sessionCookie: kCookie, csrfToken: kToken } =
        await getSessionAndCsrf()
      knownSamples.push(await timePost("alice@test.local", kCookie, kToken))

      const { sessionCookie: uCookie, csrfToken: uToken } =
        await getSessionAndCsrf()
      unknownSamples.push(
        await timePost(`stranger${i}@example.com`, uCookie, uToken),
      )
    }

    const knownMedian = median(knownSamples)
    const unknownMedian = median(unknownSamples)

    assert.ok(
      knownMedian <= unknownMedian * TOLERANCE_RATIO,
      `Known-email median (${knownMedian}ms) should not exceed ` +
        `${TOLERANCE_RATIO}x unknown-email median (${unknownMedian}ms)`,
    )
  })
})
