/**
 * Shared CodeMirror editor factory. Creates an EditorView with the common
 * extension stack used by both recipe and QuickBites plaintext editors.
 * Callers provide a classifier (ViewPlugin for syntax decorations) and an
 * optional fold service.
 *
 * - plaintext_editor_controller: unified plaintext editing (recipe + quick bites)
 * - recipe_classifier.js: recipe syntax decorations
 * - quickbites_classifier.js: quick bites syntax decorations
 */
import { EditorView, keymap, lineNumbers, highlightActiveLine,
         highlightActiveLineGutter, drawSelection, dropCursor,
         rectangularSelection, highlightSpecialChars,
         placeholder as cmPlaceholder } from "@codemirror/view"
import { EditorState } from "@codemirror/state"
import { defaultKeymap, history, historyKeymap,
         indentWithTab } from "@codemirror/commands"
import { syntaxHighlighting, defaultHighlightStyle, foldGutter,
         bracketMatching } from "@codemirror/language"
import { markdown } from "@codemirror/lang-markdown"

function getCspNonce() {
  return document.querySelector('meta[name="csp-nonce"]')?.content || ""
}

const baseTheme = EditorView.theme({
  "&": {
    height: "100%",
    fontSize: "0.85rem",
    fontFamily: "var(--font-mono)",
    border: "1px solid var(--rule)",
  },
  ".cm-scroller": {
    overflow: "auto",
  },
  ".cm-content": {
    fontFamily: "var(--font-mono)",
    lineHeight: "1.6",
    padding: "0.5rem 1rem",
  },
  ".cm-gutters": {
    backgroundColor: "var(--surface-alt, #f5f5f5)",
    color: "var(--text-light)",
    borderRight: "1px solid var(--rule)",
    paddingLeft: "4px",
  },
  ".cm-lineNumbers .cm-gutterElement": {
    minWidth: "2.5em",
    padding: "0 8px 0 4px",
    textAlign: "right",
    fontSize: "0.78rem",
  },
  ".cm-foldGutter .cm-gutterElement": {
    cursor: "pointer",
    padding: "0 4px",
  },
  ".cm-activeLineGutter": {
    backgroundColor: "color-mix(in srgb, var(--text) 5%, transparent)",
  },
  ".cm-activeLine": {
    backgroundColor: "color-mix(in srgb, var(--text) 5%, transparent)",
  },
  ".cm-cursor, .cm-cursor-primary": {
    borderLeftColor: "var(--text)",
  },
  "&.cm-focused": {
    outline: "none",
  },
  "&.cm-focused .cm-matchingBracket": {
    backgroundColor: "color-mix(in srgb, var(--accent) 25%, transparent)",
    outline: "1px solid color-mix(in srgb, var(--accent) 40%, transparent)",
  },
})

export function createEditor({ parent, doc, classifier, foldService: foldSvc,
                                placeholder, onUpdate, extraExtensions }) {
  const extensions = [
    EditorView.cspNonce.of(getCspNonce()),
    baseTheme,
    lineNumbers(),
    highlightActiveLine(),
    highlightActiveLineGutter(),
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
