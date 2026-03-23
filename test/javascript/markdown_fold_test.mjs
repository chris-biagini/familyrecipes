import assert from "node:assert/strict"
import { test } from "node:test"
import { findFoldRange } from "../../app/javascript/codemirror/markdown_fold.js"

const DOC = [
  "# My Recipe",          // 0
  "",                      // 1
  "A description.",        // 2
  "",                      // 3
  "## Make the sauce.",   // 4
  "",                      // 5
  "- Tomatoes, 400 g",    // 6
  "- Garlic, 2 cloves",   // 7
  "",                      // 8
  "Cook until soft.",     // 9
  "",                      // 10
  "## Cook the pasta.",   // 11
  "",                      // 12
  "- Pasta, 400 g",       // 13
  "",                      // 14
  "Boil until al dente.", // 15
  "",                      // 16
]

function lineOffset(lineNum) {
  let offset = 0
  for (let i = 0; i < lineNum; i++) offset += DOC[i].length + 1
  return offset
}

function endOf(lineNum) {
  return lineOffset(lineNum) + DOC[lineNum].length
}

test("folds h2 to content before next h2", () => {
  const result = findFoldRange(DOC, 4)
  assert.deepEqual(result, { from: endOf(4), to: endOf(9) })
})

test("folds last h2 to content before EOF", () => {
  const result = findFoldRange(DOC, 11)
  assert.deepEqual(result, { from: endOf(11), to: endOf(15) })
})

test("h1 is not foldable", () => {
  assert.equal(findFoldRange(DOC, 0), null)
})

test("plain prose is not foldable", () => {
  assert.equal(findFoldRange(DOC, 2), null)
})

test("blank line is not foldable", () => {
  assert.equal(findFoldRange(DOC, 1), null)
})

test("h3 folds to next h2 (higher level stops fold)", () => {
  const lines = [
    "## Section",        // 0
    "",                   // 1
    "### Subsection",    // 2
    "",                   // 3
    "Detail text.",      // 4
    "",                   // 5
    "## Next Section",   // 6
    "",                   // 7
    "More text.",        // 8
  ]
  function end(i) {
    let offset = 0
    for (let j = 0; j < i; j++) offset += lines[j].length + 1
    return offset + lines[i].length
  }

  const result = findFoldRange(lines, 2)
  assert.deepEqual(result, { from: end(2), to: end(4) })
})

test("h3 does not fold past sibling h3", () => {
  const lines = [
    "### First",    // 0
    "Content A.",   // 1
    "",              // 2
    "### Second",   // 3
    "Content B.",   // 4
  ]
  function end(i) {
    let offset = 0
    for (let j = 0; j < i; j++) offset += lines[j].length + 1
    return offset + lines[i].length
  }

  const result = findFoldRange(lines, 0)
  assert.deepEqual(result, { from: end(0), to: end(1) })
})

test("h2 with only blank lines after it returns null", () => {
  const lines = ["## Empty", "", ""]
  assert.equal(findFoldRange(lines, 0), null)
})
