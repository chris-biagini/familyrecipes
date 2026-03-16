/**
 * CodeMirror ViewPlugin for Quick Bites syntax highlighting. Classifies each
 * line as a category header, item (with optional ingredients span), or plain
 * text, producing Decoration ranges consumed by the editor overlay.
 *
 * - editor_setup.js: consumes quickbitesClassifier as a classifier extension
 * - plaintext_editor_controller.js: consumes quickbitesClassifier via registry
 * - style.css (.hl-category, .hl-item, .hl-ingredients): decoration styles
 */
import { ViewPlugin, Decoration } from "@codemirror/view"
import { RangeSetBuilder } from "@codemirror/state"

const CATEGORY_RE = /^##\s+.+$/
const ITEM_RE = /^\s*-\s+/

// Returns an array of {from, to, class} span descriptors for a single line of
// Quick Bites text. Offsets are relative to the start of the line.
export function classifyQuickBitesLine(line) {
  if (line.length === 0) return []

  if (CATEGORY_RE.test(line)) {
    return [{ from: 0, to: line.length, class: "hl-category" }]
  }

  if (ITEM_RE.test(line)) {
    const colonIdx = line.indexOf(":", line.indexOf("-") + 2)
    if (colonIdx !== -1) {
      return [
        { from: 0, to: colonIdx, class: "hl-item" },
        { from: colonIdx, to: line.length, class: "hl-ingredients" },
      ]
    }
    return [{ from: 0, to: line.length, class: "hl-item" }]
  }

  return [{ from: 0, to: line.length, class: null }]
}

function buildDecorations(view) {
  const builder = new RangeSetBuilder()
  for (const { from, to } of view.visibleRanges) {
    for (let pos = from; pos <= to;) {
      const line = view.state.doc.lineAt(pos)
      const spans = classifyQuickBitesLine(line.text)
      for (const span of spans) {
        if (span.class) {
          builder.add(
            line.from + span.from,
            line.from + span.to,
            Decoration.mark({ class: span.class })
          )
        }
      }
      pos = line.to + 1
    }
  }
  return builder.finish()
}

export const quickbitesClassifier = ViewPlugin.fromClass(
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
