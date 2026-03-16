import assert from "node:assert/strict"
import { test } from "node:test"
import { findFoldRange } from "../../app/javascript/codemirror/recipe_fold.js"

const RECIPE = [
  "# My Recipe",          // 0
  "",                      // 1
  "A description.",        // 2
  "",                      // 3
  "Serves: 4",            // 4
  "Category: Basics",     // 5
  "Tags: quick",          // 6
  "",                      // 7
  "## Make the sauce.",   // 8
  "",                      // 9
  "- Tomatoes, 400 g",    // 10
  "- Garlic, 2 cloves: Minced.", // 11
  "",                      // 12
  "Cook until soft.",     // 13
  "",                      // 14
  "## Cook the pasta.",   // 15
  "",                      // 16
  "- Pasta, 400 g",       // 17
  "",                      // 18
  "Boil until al dente.", // 19
  "",                      // 20
  "---",                   // 21
  "",                      // 22
  "Enjoy!",               // 23
]

function lineOffset(lineNum) {
  let offset = 0
  for (let i = 0; i < lineNum; i++) offset += RECIPE[i].length + 1
  return offset
}

// Step block folds from end of header to end of last non-blank line before next header
test("folds step block from header to content before next header", () => {
  const result = findFoldRange(RECIPE, 8)
  const from = lineOffset(8) + RECIPE[8].length
  const to = lineOffset(13) + RECIPE[13].length
  assert.deepEqual(result, { from, to })
})

// Last step block folds to content before divider
test("folds last step block to content before divider", () => {
  const result = findFoldRange(RECIPE, 15)
  const from = lineOffset(15) + RECIPE[15].length
  const to = lineOffset(19) + RECIPE[19].length
  assert.deepEqual(result, { from, to })
})

// Front matter block folds from end of first FM line to end of last FM line
test("folds front matter block from first to last FM line", () => {
  const result = findFoldRange(RECIPE, 4)
  const from = lineOffset(4) + RECIPE[4].length
  const to = lineOffset(6) + RECIPE[6].length
  assert.deepEqual(result, { from, to })
})

// Title line has no fold
test("returns null for title line", () => {
  const result = findFoldRange(RECIPE, 0)
  assert.equal(result, null)
})

// Plain prose has no fold
test("returns null for prose line", () => {
  const result = findFoldRange(RECIPE, 2)
  assert.equal(result, null)
})

// Divider has no fold
test("returns null for divider line", () => {
  const result = findFoldRange(RECIPE, 21)
  assert.equal(result, null)
})
