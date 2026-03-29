import assert from "node:assert/strict"
import { test } from "node:test"
import { matchTier } from "../../app/javascript/utilities/search_match.js"

function makeRecipe({ title = "", description = "", category = "", tags = [], ingredients = [] }) {
  return {
    _title: title.toLowerCase(),
    _description: description.toLowerCase(),
    _category: category.toLowerCase(),
    _tags: tags.map(t => t.toLowerCase()),
    _ingredients: ingredients.map(i => i.toLowerCase())
  }
}

const pancakes = makeRecipe({
  title: "Pancakes",
  description: "Fluffy buttermilk pancakes",
  category: "Breakfast",
  tags: ["sweet", "quick"],
  ingredients: ["flour", "buttermilk", "eggs", "sugar"]
})

const tacos = makeRecipe({
  title: "Fish Tacos",
  description: "Crispy battered fish tacos",
  category: "Mexican",
  tags: ["quick", "seafood"],
  ingredients: ["cod", "tortillas", "cabbage", "lime"]
})

// Single token
test("single token matching title returns tier 0", () => {
  assert.equal(matchTier(pancakes, ["pancakes"]), 0)
})

test("single token matching description returns tier 1", () => {
  assert.equal(matchTier(pancakes, ["fluffy"]), 1)
})

test("single token matching category returns tier 2", () => {
  assert.equal(matchTier(pancakes, ["breakfast"]), 2)
})

test("single token matching tag returns tier 3", () => {
  assert.equal(matchTier(pancakes, ["sweet"]), 3)
})

test("single token matching ingredient returns tier 4", () => {
  assert.equal(matchTier(pancakes, ["flour"]), 4)
})

test("single token matching nothing returns tier 5", () => {
  assert.equal(matchTier(pancakes, ["xyzzy"]), 5)
})

// Multi-token AND — the new behavior
test("multi-token: all match returns best tier", () => {
  assert.equal(matchTier(pancakes, ["pancakes", "sweet"]), 0)
})

test("multi-token: one unmatched token excludes recipe", () => {
  assert.equal(matchTier(pancakes, ["pancakes", "xyzzy"]), 5)
})

test("multi-token: both match low-priority fields", () => {
  assert.equal(matchTier(pancakes, ["flour", "eggs"]), 4)
})

test("multi-token: matches across different field types", () => {
  assert.equal(matchTier(tacos, ["fish", "seafood", "lime"]), 0)
})

test("multi-token: partial title match with tag", () => {
  assert.equal(matchTier(tacos, ["tacos", "quick"]), 0)
})

// Empty tokens
test("empty token array returns tier 0 (no constraints)", () => {
  assert.equal(matchTier(pancakes, []), 0)
})
