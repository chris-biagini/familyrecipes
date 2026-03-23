import assert from "node:assert/strict"
import { test } from "node:test"
import { matchIngredients } from "../../app/javascript/utilities/ingredient_match.js"

const corpus = [
  "Butter", "Buttermilk", "Milk", "Miso Paste", "Mint",
  "Mixed Greens", "Flour", "Peanut Butter"
]

test("prefix match ranks higher than substring", () => {
  const results = matchIngredients("mi", corpus)
  assert.equal(results[0], "Milk")
  assert.ok(results.includes("Mint"))
  assert.ok(results.includes("Miso Paste"))
})

test("exact match ranks first", () => {
  const results = matchIngredients("milk", corpus)
  assert.equal(results[0], "Milk")
})

test("case insensitive matching", () => {
  const results = matchIngredients("MILK", corpus)
  assert.equal(results[0], "Milk")
})

test("substring match finds interior matches", () => {
  const results = matchIngredients("nut", corpus)
  assert.ok(results.includes("Peanut Butter"))
})

test("no match returns empty array", () => {
  const results = matchIngredients("xyz", corpus)
  assert.equal(results.length, 0)
})

test("empty query returns empty array", () => {
  const results = matchIngredients("", corpus)
  assert.equal(results.length, 0)
})

test("results limited to max parameter", () => {
  const results = matchIngredients("m", corpus, { max: 3 })
  assert.equal(results.length, 3)
})

test("shorter names ranked higher among prefix matches", () => {
  const results = matchIngredients("butter", corpus)
  assert.equal(results[0], "Butter")
  assert.equal(results[1], "Buttermilk")
})

test("custom items included with aisle info preserved", () => {
  const customs = [{ name: "Birthday Candles", aisle: "Party Supplies" }]
  const results = matchIngredients("birth", corpus, { customItems: customs })
  assert.equal(results[0], "Birthday Candles")
})
