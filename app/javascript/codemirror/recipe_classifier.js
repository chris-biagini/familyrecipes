/**
 * CodeMirror ViewPlugin for recipe syntax highlighting. Mirrors the server-side
 * LineClassifier and the HighlightOverlay patterns in recipe_plaintext_controller.
 * Exports a pure classifyRecipeLine function (testable without DOM/CM) and a
 * recipeClassifier ViewPlugin that applies Decoration.mark() ranges over visible
 * lines.
 *
 * - editor_setup.js: receives recipeClassifier as the `classifier` extension
 * - recipe_plaintext_controller.js: original pattern source (classifyLine, highlightIngredient, highlightProseLinks)
 * - style.css (.hl-*): highlight colours consumed by the decoration class names
 */
import { ViewPlugin, Decoration } from "@codemirror/view"
import { RangeSetBuilder } from "@codemirror/state"

// Pure function — no DOM, no CM state. Returns [{from, to, class}] spans for
// one line. `ctx` is mutated: ctx.inFooter flips to true on a divider line.
// Positions are character offsets within the line string (0-based).
export function classifyRecipeLine(line, ctx) {
  if (line.length === 0) return []

  if (/^# .+$/.test(line)) {
    return [{ from: 0, to: line.length, class: "hl-title" }]
  }

  if (/^## .+$/.test(line)) {
    return [{ from: 0, to: line.length, class: "hl-step-header" }]
  }

  if (/^- .+$/.test(line)) {
    return classifyIngredient(line)
  }

  if (/^\s*>\s*@\[.+$/.test(line)) {
    return [{ from: 0, to: line.length, class: "hl-cross-ref" }]
  }

  if (/^---\s*$/.test(line)) {
    ctx.inFooter = true
    return [{ from: 0, to: line.length, class: "hl-divider" }]
  }

  if (/^(Makes|Serves|Category|Tags):\s+.+$/.test(line)) {
    return [{ from: 0, to: line.length, class: "hl-front-matter" }]
  }

  if (ctx.inFooter) {
    return [{ from: 0, to: line.length, class: "hl-front-matter" }]
  }

  return classifyProseLinks(line)
}

// Mirrors highlightIngredient: comma-first splits name/qty, colon-first splits qty/prep.
function classifyIngredient(line) {
  const colonIdx = line.indexOf(":", 2)
  const left = colonIdx !== -1 ? line.slice(0, colonIdx) : line
  const prepStart = colonIdx !== -1 ? colonIdx : null

  const commaIdx = left.indexOf(",", 2)
  const nameEnd = commaIdx !== -1 ? commaIdx : left.length
  const qtyEnd = prepStart !== null ? prepStart : null

  const spans = [{ from: 0, to: nameEnd, class: "hl-ingredient-name" }]
  if (commaIdx !== -1) spans.push({ from: nameEnd, to: qtyEnd ?? left.length, class: "hl-ingredient-qty" })
  if (prepStart !== null) spans.push({ from: prepStart, to: line.length, class: "hl-ingredient-prep" })

  return spans
}

// Mirrors highlightProseLinks: splits prose around @[Title] recipe link tokens.
function classifyProseLinks(line) {
  const pattern = /@\[(.+?)\]/g
  const spans = []
  let lastIndex = 0
  let match

  while ((match = pattern.exec(line)) !== null) {
    if (match.index > lastIndex) spans.push({ from: lastIndex, to: match.index, class: null })
    spans.push({ from: match.index, to: pattern.lastIndex, class: "hl-recipe-link" })
    lastIndex = pattern.lastIndex
  }

  if (lastIndex < line.length) {
    spans.push({ from: lastIndex, to: line.length, class: null })
  } else if (lastIndex === 0) {
    spans.push({ from: 0, to: line.length, class: null })
  }

  return spans
}

// CodeMirror ViewPlugin that decorates visible lines using classifyRecipeLine.
// ctx.inFooter persists across lines within a single update pass, reset each
// decoration rebuild (decorations are rebuilt from scratch each update).
export const recipeClassifier = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = buildDecorations(view)
    }

    update(update) {
      if (update.docChanged || update.viewportChanged) {
        this.decorations = buildDecorations(update.view)
      }
    }
  },
  { decorations: (v) => v.decorations }
)

function buildDecorations(view) {
  const builder = new RangeSetBuilder()
  const ctx = { inFooter: false }

  for (const { from, to } of view.visibleRanges) {
    let pos = from
    while (pos <= to) {
      const line = view.state.doc.lineAt(pos)
      const lineText = line.text
      const spans = classifyRecipeLine(lineText, ctx)

      for (const span of spans) {
        if (span.class) {
          const absFrom = line.from + span.from
          const absTo = line.from + span.to
          if (absFrom < absTo) {
            builder.add(absFrom, absTo, Decoration.mark({ class: span.class }))
          }
        }
      }

      pos = line.to + 1
    }
  }

  return builder.finish()
}
