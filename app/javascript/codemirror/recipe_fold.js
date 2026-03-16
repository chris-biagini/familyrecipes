// Code folding service for recipe documents.
// Folds step blocks (## headers) down to the last non-blank content line before
// the next header or divider, and front matter runs (Serves/Makes/Category/Tags)
// down to the last FM line in the contiguous block.
// Collaborators:
//   - @codemirror/language foldService (wraps findFoldRange for CM6 integration)
//   - editor_setup.js (registers this service in the extension array)

import { foldService } from "@codemirror/language"

const STEP_HEADER = /^## .+$/
const FRONT_MATTER = /^(Makes|Serves|Category|Tags):\s+.+$/
const DIVIDER = /^---$/

// Pure function for testing: given an array of line strings and a zero-based
// line index, return {from, to} character offsets or null.
function findFoldRange(lines, lineIndex) {
  const line = lines[lineIndex]

  if (STEP_HEADER.test(line)) return foldStepBlock(lines, lineIndex)
  if (FRONT_MATTER.test(line)) return foldFrontMatterBlock(lines, lineIndex)
  return null
}

function lineOffset(lines, lineIndex) {
  let offset = 0
  for (let i = 0; i < lineIndex; i++) offset += lines[i].length + 1
  return offset
}

function endOf(lines, lineIndex) {
  return lineOffset(lines, lineIndex) + lines[lineIndex].length
}

function foldStepBlock(lines, headerIndex) {
  const from = endOf(lines, headerIndex)

  // Find end boundary: next ## header, divider, or EOF
  let endIndex = lines.length
  for (let i = headerIndex + 1; i < lines.length; i++) {
    if (STEP_HEADER.test(lines[i]) || DIVIDER.test(lines[i])) {
      endIndex = i
      break
    }
  }

  // Walk back from boundary to skip trailing blank lines
  let lastContent = endIndex - 1
  while (lastContent > headerIndex && lines[lastContent].trim() === "") lastContent--

  if (lastContent <= headerIndex) return null

  return { from, to: endOf(lines, lastContent) }
}

function foldFrontMatterBlock(lines, startIndex) {
  const from = endOf(lines, startIndex)

  // Find contiguous FM lines
  let lastFM = startIndex
  for (let i = startIndex + 1; i < lines.length; i++) {
    if (FRONT_MATTER.test(lines[i])) lastFM = i
    else break
  }

  if (lastFM === startIndex) return null

  return { from, to: endOf(lines, lastFM) }
}

// CodeMirror foldService integration: converts doc positions to line array and
// delegates to findFoldRange. findFoldRange returns absolute character offsets
// (from doc start), which CM6 foldService expects directly.
const recipeFoldService = foldService.of((state, from) => {
  const lines = state.doc.toString().split("\n")
  const lineIndex = state.doc.lineAt(from).number - 1
  return findFoldRange(lines, lineIndex)
})

export { findFoldRange, recipeFoldService }
