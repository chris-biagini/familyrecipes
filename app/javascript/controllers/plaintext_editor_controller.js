/**
 * Unified CodeMirror 6 plaintext editor for both recipes and Quick Bites.
 * Parameterized via Stimulus values: the classifier and fold service are
 * looked up by name from the codemirror registry, so the same controller
 * serves any content type that has a registered classifier.
 *
 * CodeMirror is loaded lazily via dynamic import() — the ~513KB library
 * only downloads when an editor actually mounts. The main bundle prefetches
 * the chunk in the background so it's typically cached before the user
 * opens an editor.
 *
 * - dual_mode_editor_controller: coordinator, calls .content and .isModified()
 * - editor_setup.js: shared CodeMirror factory
 * - registry.js: maps string keys to classifier/fold-service extensions
 * - auto_dash.js: shared bullet-continuation keymap
 */
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mount"]
  static values = {
    classifier: String,
    foldService: String,
    placeholder: String,
    initial: String
  }

  async mountTargetConnected(element) {
    this.editorView?.destroy()

    this._ready = this._mount(element)
    await this._ready
  }

  async _mount(element) {
    const [
      { createEditor },
      { classifiers, foldServices },
      { autoDashKeymap },
      { foldAll, unfoldCode }
    ] = await Promise.all([
      import("../codemirror/editor_setup"),
      import("../codemirror/registry"),
      import("../codemirror/auto_dash"),
      import("@codemirror/language")
    ])

    this._foldAll = foldAll
    this._unfoldCode = unfoldCode

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

  whenReady() {
    return this._ready || Promise.resolve()
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

  focusCategory(name) {
    if (!this.editorView || !this._foldAll) return
    const view = this.editorView

    requestAnimationFrame(() => {
      this._foldAll(view)

      const doc = view.state.doc
      const target = `## ${name}`
      for (let i = 1; i <= doc.lines; i++) {
        const line = doc.line(i)
        if (line.text.trimEnd() === target) {
          view.dispatch({ selection: { anchor: line.from } })
          this._unfoldCode(view)
          return
        }
      }
    })
  }
}
