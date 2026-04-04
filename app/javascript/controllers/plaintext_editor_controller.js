/**
 * Unified CodeMirror 6 plaintext editor for both recipes and Quick Bites.
 * Parameterized via Stimulus values: the classifier and fold service are
 * looked up by name from the codemirror registry, so the same controller
 * serves any content type that has a registered classifier.
 *
 * - dual_mode_editor_controller: coordinator, calls .content and .isModified()
 * - editor_setup.js: shared CodeMirror factory
 * - registry.js: maps string keys to classifier/fold-service extensions
 * - auto_dash.js: shared bullet-continuation keymap
 */
import { Controller } from "@hotwired/stimulus"
import { createEditor } from "../codemirror/editor_setup"
import { classifiers, foldServices } from "../codemirror/registry"
import { autoDashKeymap } from "../codemirror/auto_dash"
import { foldAll, unfoldCode } from "@codemirror/language"

export default class extends Controller {
  static targets = ["mount"]
  static values = {
    classifier: String,
    foldService: String,
    placeholder: String,
    initial: String
  }

  mountTargetConnected(element) {
    this.editorView?.destroy()

    let doc = ""
    if (this.hasInitialValue) {
      doc = this.initialValue
    } else {
      const jsonEl = this.element.closest("turbo-frame")
        ?.querySelector("script[data-editor-markdown]")
      if (jsonEl) {
        const data = JSON.parse(jsonEl.textContent)
        doc = data.plaintext || ""
      }
    }

    this.editorView = createEditor({
      parent: element,
      doc,
      classifier: classifiers[this.classifierValue],
      foldService: this.hasFoldServiceValue ? foldServices[this.foldServiceValue] : null,
      placeholder: this.hasPlaceholderValue ? this.placeholderValue : "",
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

  get initialContent() {
    return this.hasInitialValue ? this.initialValue : null
  }

  get content() {
    return this.editorView?.state.doc.toString() || ""
  }

  set content(text) {
    if (!this.editorView) return

    this.editorView.dispatch({
      changes: { from: 0, to: this.editorView.state.doc.length, insert: text }
    })
  }

  isModified(originalContent) {
    return this.content !== originalContent
  }

  focusCategory(name) {
    if (!this.editorView) return
    const view = this.editorView

    requestAnimationFrame(() => {
      foldAll(view)

      const doc = view.state.doc
      const target = `## ${name}`
      for (let i = 1; i <= doc.lines; i++) {
        const line = doc.line(i)
        if (line.text.trimEnd() === target) {
          view.dispatch({ selection: { anchor: line.from } })
          unfoldCode(view)
          return
        }
      }
    })
  }
}
