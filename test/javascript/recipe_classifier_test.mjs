import assert from "node:assert/strict"
import { test } from "node:test"
import { classifyRecipeLine } from "../../app/javascript/codemirror/recipe_classifier.js"

// Title line
test("classifies title line", () => {
  const ctx = { inFooter: false }
  const spans = classifyRecipeLine("# My Recipe", ctx)
  assert.deepEqual(spans, [{ from: 0, to: 11, class: "hl-title" }])
})

// Step header
test("classifies step header", () => {
  const ctx = { inFooter: false }
  const spans = classifyRecipeLine("## Make the sauce.", ctx)
  assert.deepEqual(spans, [{ from: 0, to: 18, class: "hl-step-header" }])
})

// Ingredient name only
test("classifies ingredient name only", () => {
  const ctx = { inFooter: false }
  const spans = classifyRecipeLine("- Salt", ctx)
  assert.deepEqual(spans, [{ from: 0, to: 6, class: "hl-ingredient-name" }])
})

// Ingredient with qty
test("classifies ingredient with name and qty", () => {
  const ctx = { inFooter: false }
  const spans = classifyRecipeLine("- Flour, 250 g", ctx)
  assert.deepEqual(spans, [
    { from: 0, to: 7, class: "hl-ingredient-name" },
    { from: 7, to: 14, class: "hl-ingredient-qty" },
  ])
})

// Ingredient with qty + prep
test("classifies ingredient with name, qty, and prep", () => {
  const ctx = { inFooter: false }
  const spans = classifyRecipeLine("- Butter, 115 g: Softened.", ctx)
  assert.deepEqual(spans, [
    { from: 0, to: 8, class: "hl-ingredient-name" },
    { from: 8, to: 15, class: "hl-ingredient-qty" },
    { from: 15, to: 26, class: "hl-ingredient-prep" },
  ])
})

// Ingredient with prep but no qty (colon before any comma)
test("classifies ingredient with name and prep but no qty", () => {
  const ctx = { inFooter: false }
  const spans = classifyRecipeLine("- Parmesan: Grated, for serving.", ctx)
  assert.deepEqual(spans, [
    { from: 0, to: 10, class: "hl-ingredient-name" },
    { from: 10, to: 32, class: "hl-ingredient-prep" },
  ])
})

// Cross-reference
test("classifies cross-reference line", () => {
  const ctx = { inFooter: false }
  const line = "> @[Simple Tomato Sauce]"
  const spans = classifyRecipeLine(line, ctx)
  assert.deepEqual(spans, [{ from: 0, to: line.length, class: "hl-cross-ref" }])
})

// Divider sets inFooter
test("classifies divider and sets ctx.inFooter to true", () => {
  const ctx = { inFooter: false }
  const spans = classifyRecipeLine("---", ctx)
  assert.deepEqual(spans, [{ from: 0, to: 3, class: "hl-divider" }])
  assert.equal(ctx.inFooter, true)
})

// Front matter: Serves
test("classifies Serves front matter", () => {
  const ctx = { inFooter: false }
  const spans = classifyRecipeLine("Serves: 4", ctx)
  assert.deepEqual(spans, [{ from: 0, to: 9, class: "hl-front-matter" }])
})

// Front matter: Tags
test("classifies Tags front matter", () => {
  const ctx = { inFooter: false }
  const spans = classifyRecipeLine("Tags: quick, weeknight", ctx)
  assert.deepEqual(spans, [{ from: 0, to: 22, class: "hl-front-matter" }])
})

// Footer prose treated as front matter
test("classifies footer prose as front-matter when inFooter is true", () => {
  const ctx = { inFooter: true }
  const spans = classifyRecipeLine("Some footer note.", ctx)
  assert.deepEqual(spans, [{ from: 0, to: 17, class: "hl-front-matter" }])
})

// Prose with recipe link
test("classifies prose line containing a recipe link", () => {
  const ctx = { inFooter: false }
  const spans = classifyRecipeLine("Try @[Simple Salad] sometime.", ctx)
  assert.deepEqual(spans, [
    { from: 0, to: 4, class: null },
    { from: 4, to: 19, class: "hl-recipe-link" },
    { from: 19, to: 29, class: null },
  ])
})

// Plain prose
test("classifies plain prose line", () => {
  const ctx = { inFooter: false }
  const spans = classifyRecipeLine("Mix until smooth.", ctx)
  assert.deepEqual(spans, [{ from: 0, to: 17, class: null }])
})

// Blank line
test("returns empty array for blank line", () => {
  const ctx = { inFooter: false }
  const spans = classifyRecipeLine("", ctx)
  assert.deepEqual(spans, [])
})
