import assert from "node:assert/strict"
import { test } from "node:test"
import {
  computeFinalWeights,
  weightedRandomPick
} from "../../app/javascript/utilities/dinner_picker_logic.js"

function assertCloseTo(actual, expected, delta) {
  assert.ok(Math.abs(actual - expected) <= delta,
    `Expected ${actual} to be within ${delta} of ${expected}`)
}

test("computeFinalWeights with no adjustments returns recency weights", () => {
  const recipes = [
    { slug: "tacos", tags: ["mexican"] },
    { slug: "bagels", tags: ["baking"] }
  ]
  const recencyWeights = { tacos: 0.5 }

  const result = computeFinalWeights(recipes, recencyWeights, {})

  assert.equal(result.tacos, 0.5)
  assert.equal(result.bagels, 1.0)
})

test("computeFinalWeights applies decline penalty", () => {
  const recipes = [{ slug: "tacos", tags: [] }]

  const result = computeFinalWeights(recipes, {}, { tacos: 1 })

  assertCloseTo(result.tacos, 0.3, 0.001)
})

test("computeFinalWeights compounds recency and decline", () => {
  const recipes = [{ slug: "tacos", tags: ["quick"] }]

  const result = computeFinalWeights(recipes, { tacos: 0.5 }, { tacos: 1 })

  // 0.5 * 0.3 = 0.15
  assertCloseTo(result.tacos, 0.15, 0.001)
})

test("weightedRandomPick selects from weighted pool", () => {
  const weights = { tacos: 1.0, bagels: 0.0001 }
  const originalRandom = Math.random
  Math.random = () => 0.5
  try {
    const result = weightedRandomPick(weights)
    assert.equal(result, "tacos")
  } finally {
    Math.random = originalRandom
  }
})

test("weightedRandomPick returns null for empty pool", () => {
  const result = weightedRandomPick({})
  assert.equal(result, null)
})
