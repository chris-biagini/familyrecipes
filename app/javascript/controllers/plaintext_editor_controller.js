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
    element.classList.remove("cm-loading")

    this.editorView = createEditor({
      parent: element,
      doc: this.hasInitialValue ? this.initialValue : "",
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
}
