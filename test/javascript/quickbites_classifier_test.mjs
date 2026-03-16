import assert from "node:assert/strict"
import { test } from "node:test"
import { classifyQuickBitesLine } from "../../app/javascript/codemirror/quickbites_classifier.js"

// Category header
test("classifies category header", () => {
  const spans = classifyQuickBitesLine("## Snacks")
  assert.deepEqual(spans, [{ from: 0, to: 9, class: "hl-category" }])
})

// Category header with trailing whitespace
test("classifies category header with trailing space", () => {
  const spans = classifyQuickBitesLine("## Breakfast  ")
  assert.deepEqual(spans, [{ from: 0, to: 14, class: "hl-category" }])
})

// Item without ingredients
test("classifies item without ingredients", () => {
  const spans = classifyQuickBitesLine("- String cheese")
  assert.deepEqual(spans, [{ from: 0, to: 15, class: "hl-item" }])
})

// Item with ingredients (colon splits name from ingredients)
test("classifies item with ingredients", () => {
  const spans = classifyQuickBitesLine("- Hummus with Pretzels: Hummus, Pretzels")
  assert.deepEqual(spans, [
    { from: 0, to: 22, class: "hl-item" },
    { from: 22, to: 40, class: "hl-ingredients" },
  ])
})

// Blank line
test("returns empty array for blank line", () => {
  const spans = classifyQuickBitesLine("")
  assert.deepEqual(spans, [])
})

// Plain text (note, unrecognized line)
test("classifies plain text as null class", () => {
  const spans = classifyQuickBitesLine("Some note")
  assert.deepEqual(spans, [{ from: 0, to: 9, class: null }])
})
