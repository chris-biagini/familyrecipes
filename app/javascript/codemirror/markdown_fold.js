// Generic Markdown heading fold service for CodeMirror 6. Folds any heading
// at level 2+ (##, ###, etc.) to the next heading of equal or lesser depth,
// or EOF, skipping trailing blank lines. H1 (#) is intentionally excluded —
// it serves as the document title and folding it would hide everything.
// Collaborators:
//   - @codemirror/language foldService (wraps findFoldRange for CM6 integration)
//   - editor_setup.js (registers this service in the extension array)
//   - registry.js (maps the "markdown" key to this service)

import { foldService } from "@codemirror/language"

const HEADING = /^(#{2,6})\s+.+$/

function headingDepth(line) {
  const match = line.match(HEADING)
  return match ? match[1].length : 0
}

// Pure function for testing: given an array of line strings and a zero-based
// line index, return {from, to} character offsets or null.
function findFoldRange(lines, lineIndex) {
  const depth = headingDepth(lines[lineIndex])
  if (depth === 0) return null

  const from = endOf(lines, lineIndex)

  let endIndex = lines.length
  for (let i = lineIndex + 1; i < lines.length; i++) {
    const d = headingDepth(lines[i])
    if (d > 0 && d <= depth) {
      endIndex = i
      break
    }
  }

  let lastContent = endIndex - 1
  while (lastContent > lineIndex && lines[lastContent].trim() === "") lastContent--

  if (lastContent <= lineIndex) return null

  return { from, to: endOf(lines, lastContent) }
}

function lineOffset(lines, lineIndex) {
  let offset = 0
  for (let i = 0; i < lineIndex; i++) offset += lines[i].length + 1
  return offset
}

function endOf(lines, lineIndex) {
  return lineOffset(lines, lineIndex) + lines[lineIndex].length
}

const markdownFoldService = foldService.of((state, from) => {
  const lines = state.doc.toString().split("\n")
  const lineIndex = state.doc.lineAt(from).number - 1
  return findFoldRange(lines, lineIndex)
})

export { findFoldRange, markdownFoldService }
