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

  const result = computeFinalWeights(recipes, recencyWeights, {}, {})

  assert.equal(result.tacos, 0.5)
  assert.equal(result.bagels, 1.0)
})

test("computeFinalWeights applies tag up multiplier", () => {
  const recipes = [
    { slug: "tacos", tags: ["quick"] },
    { slug: "stew", tags: ["slow"] }
  ]

  const result = computeFinalWeights(recipes, {}, { quick: 2 }, {})

  assert.equal(result.tacos, 2.0)
  assert.equal(result.stew, 1.0)
})

test("computeFinalWeights applies tag down multiplier", () => {
  const recipes = [{ slug: "fish", tags: ["seafood"] }]

  const result = computeFinalWeights(recipes, {}, { seafood: 0.25 }, {})

  assert.equal(result.fish, 0.25)
})

test("computeFinalWeights compounds multiple tag multipliers", () => {
  const recipes = [{ slug: "tacos", tags: ["quick", "mexican"] }]

  const result = computeFinalWeights(recipes, {}, { quick: 2, mexican: 2 }, {})

  assert.equal(result.tacos, 4.0)
})

test("computeFinalWeights applies decline penalty", () => {
  const recipes = [{ slug: "tacos", tags: [] }]

  const result = computeFinalWeights(recipes, {}, {}, { tacos: 1 })

  assertCloseTo(result.tacos, 0.3, 0.001)
})

test("computeFinalWeights compounds all factors", () => {
  const recipes = [{ slug: "tacos", tags: ["quick"] }]

  const result = computeFinalWeights(recipes, { tacos: 0.5 }, { quick: 2 }, { tacos: 1 })

  // 0.5 * 2 * 0.3 = 0.3
  assertCloseTo(result.tacos, 0.3, 0.001)
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
