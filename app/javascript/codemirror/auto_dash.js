/**
 * CodeMirror keymap for auto-continuing bulleted lists. On Enter at the end
 * of a "- text" line, inserts a new "- " bullet. On Enter on a bare "- "
 * line, clears the dash (exits list mode).
 *
 * - plaintext_editor_controller: consumes as an extra extension
 * - editor_setup.js: added via extraExtensions option
 */
import { keymap } from "@codemirror/view"

export const autoDashKeymap = keymap.of([{
  key: "Enter",
  run(view) {
    const { state } = view
    const { head } = state.selection.main
    const line = state.doc.lineAt(head)

    if (head !== line.to) return false

    if (line.text === "- ") {
      view.dispatch({ changes: { from: line.from, to: line.to, insert: "" } })
      return true
    }

    if (/^- .+$/.test(line.text)) {
      view.dispatch({
        changes: { from: head, insert: "\n- " },
        selection: { anchor: head + 3 }
      })
      return true
    }

    return false
  }
}])
