/**
 * Plaintext recipe editor backed by CodeMirror 6. Replaces the former
 * textarea + HighlightOverlay with a proper editor featuring syntax
 * decorations, step/front-matter folding, and an auto-dash keymap for
 * ingredient entry.
 *
 * - recipe_editor_controller: coordinator, calls .content and .isModified()
 * - editor_setup.js: shared CodeMirror factory
 * - recipe_classifier.js: syntax decoration ViewPlugin
 * - recipe_fold.js: step and front-matter fold service
 */
import { Controller } from "@hotwired/stimulus"
import { keymap } from "@codemirror/view"
import { createEditor } from "../codemirror/editor_setup"
import { recipeClassifier } from "../codemirror/recipe_classifier"
import { recipeFoldService } from "../codemirror/recipe_fold"

const autoDashKeymap = keymap.of([{
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

export default class extends Controller {
  static targets = ["mount"]

  mountTargetConnected(element) {
    this.editorView?.destroy()
    element.classList.remove("cm-loading")

    this.editorView = createEditor({
      parent: element,
      doc: "",
      classifier: recipeClassifier,
      foldService: recipeFoldService,
      placeholder: "Paste or type a recipe\u2026",
      extraExtensions: [autoDashKeymap]
    })
  }

  mountTargetDisconnected() {
    this.editorView?.destroy()
    this.editorView = null
  }

  disconnect() {
    this.editorView?.destroy()
    this.editorView = null
  }

  get content() {
    return this.editorView?.state.doc.toString() || ""
  }

  set content(markdown) {
    if (!this.editorView) return

    this.editorView.dispatch({
      changes: { from: 0, to: this.editorView.state.doc.length, insert: markdown }
    })
  }

  isModified(originalContent) {
    return this.content !== originalContent
  }
}
