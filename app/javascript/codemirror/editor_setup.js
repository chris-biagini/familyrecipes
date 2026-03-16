/**
 * Shared CodeMirror editor factory. Creates an EditorView with the common
 * extension stack used by both recipe and QuickBites plaintext editors.
 * Callers provide a classifier (ViewPlugin for syntax decorations) and an
 * optional fold service.
 *
 * - recipe_plaintext_controller: recipe editing
 * - quickbites_plaintext_controller: quick bites editing
 * - recipe_classifier.js: recipe syntax decorations
 * - quickbites_classifier.js: quick bites syntax decorations
 */
import { EditorView, keymap, highlightActiveLine,
         drawSelection, dropCursor, rectangularSelection,
         highlightSpecialChars, placeholder as cmPlaceholder } from "@codemirror/view"
import { EditorState } from "@codemirror/state"
import { defaultKeymap, history, historyKeymap,
         indentWithTab } from "@codemirror/commands"
import { syntaxHighlighting, defaultHighlightStyle, foldGutter,
         bracketMatching } from "@codemirror/language"
import { markdown } from "@codemirror/lang-markdown"

const baseTheme = EditorView.theme({
  "&": {
    fontSize: "0.85rem",
    fontFamily: "var(--font-mono)",
  },
  ".cm-content": {
    fontFamily: "var(--font-mono)",
    lineHeight: "1.6",
    padding: "1.5rem",
  },
  ".cm-gutters": {
    backgroundColor: "transparent",
    borderRight: "none",
    color: "var(--text-soft)",
  },
  ".cm-activeLineGutter": {
    backgroundColor: "transparent",
  },
  ".cm-activeLine": {
    backgroundColor: "color-mix(in srgb, var(--text) 5%, transparent)",
  },
  "&.cm-focused": {
    outline: "none",
  },
  ".cm-scroller": {
    overflow: "auto",
  },
  ".cm-foldGutter .cm-gutterElement": {
    cursor: "pointer",
    padding: "0 4px",
  },
  "&.cm-focused .cm-matchingBracket": {
    backgroundColor: "color-mix(in srgb, var(--accent) 25%, transparent)",
    outline: "1px solid color-mix(in srgb, var(--accent) 40%, transparent)",
  },
})

export function createEditor({ parent, doc, classifier, foldService: foldSvc,
                                placeholder, onUpdate, extraExtensions }) {
  const extensions = [
    baseTheme,
    highlightActiveLine(),
    highlightSpecialChars(),
    history(),
    drawSelection(),
    dropCursor(),
    rectangularSelection(),
    bracketMatching(),
    EditorView.lineWrapping,
    markdown(),
    syntaxHighlighting(defaultHighlightStyle),
    keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
  ]

  if (classifier) extensions.push(classifier)
  if (foldSvc) {
    extensions.push(foldSvc)
    extensions.push(foldGutter())
  }
  if (placeholder) extensions.push(cmPlaceholder(placeholder))
  if (onUpdate) {
    extensions.push(EditorView.updateListener.of((update) => {
      if (update.docChanged) onUpdate(update)
    }))
  }
  if (extraExtensions) extensions.push(...extraExtensions)

  return new EditorView({
    state: EditorState.create({ doc: doc || "", extensions }),
    parent,
  })
}
