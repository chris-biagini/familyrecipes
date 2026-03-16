import { Controller } from "@hotwired/stimulus"
import { csrfHeaders } from "../utilities/editor_utils"

/**
 * Coordinator for dual-mode recipe editing. Manages a mode toggle between
 * plaintext (textarea + highlight overlay) and graphical (form-based) child
 * controllers. Routes editor lifecycle events to the active child. Handles
 * mode-switch serialization via server-side parse/serialize endpoints.
 *
 * - editor_controller: dialog lifecycle (parent)
 * - recipe_plaintext_controller: child, plaintext mode
 * - recipe_graphical_controller: child, graphical mode
 */
export default class extends Controller {
  static targets = ["plaintextContainer", "graphicalContainer", "modeToggle"]
  static values = {
    parseUrl: String,
    serializeUrl: String
  }

  connect() {
    this.mode = localStorage.getItem("editorMode") || "graphical"
    this.originalContent = null
    this.originalStructure = null

    this.boundCollect = (e) => this.handleCollect(e)
    this.boundModified = (e) => this.handleModified(e)
    this.boundContentLoaded = (e) => this.handleContentLoaded(e)

    this.element.addEventListener("editor:collect", this.boundCollect)
    this.element.addEventListener("editor:modified", this.boundModified)
    this.element.addEventListener("editor:content-loaded", this.boundContentLoaded)
  }

  disconnect() {
    this.element.removeEventListener("editor:collect", this.boundCollect)
    this.element.removeEventListener("editor:modified", this.boundModified)
    this.element.removeEventListener("editor:content-loaded", this.boundContentLoaded)
  }

  toggleMode() {
    const newMode = this.mode === "plaintext" ? "graphical" : "plaintext"
    this.switchTo(newMode)
  }

  async switchTo(newMode) {
    if (newMode === this.mode) return

    if (newMode === "plaintext") {
      const structure = this.graphicalController.toStructure()
      const response = await fetch(this.serializeUrlValue, {
        method: "POST",
        headers: { ...csrfHeaders(), "Content-Type": "application/json" },
        body: JSON.stringify({ structure })
      })
      const { markdown } = await response.json()
      this.plaintextController.content = markdown
    } else {
      const markdown = this.plaintextController.content
      const response = await fetch(this.parseUrlValue, {
        method: "POST",
        headers: { ...csrfHeaders(), "Content-Type": "application/json" },
        body: JSON.stringify({ markdown_source: markdown })
      })
      const ir = await response.json()
      this.graphicalController.loadStructure(ir)
    }

    this.mode = newMode
    localStorage.setItem("editorMode", newMode)
    this.showActiveMode()
  }

  showActiveMode() {
    const isPlaintext = this.mode === "plaintext"
    if (this.hasPlaintextContainerTarget) {
      this.plaintextContainerTarget.hidden = !isPlaintext
    }
    if (this.hasGraphicalContainerTarget) {
      this.graphicalContainerTarget.hidden = isPlaintext
    }
    if (this.hasModeToggleTarget) {
      this.modeToggleTarget.title = isPlaintext
        ? "Switch to graphical editor"
        : "Switch to plaintext editor"
    }
  }

  handleCollect(event) {
    event.detail.handled = true
    if (this.mode === "plaintext") {
      event.detail.data = { markdown_source: this.plaintextController.content }
    } else {
      event.detail.data = { structure: this.graphicalController.toStructure() }
    }
  }

  handleModified(event) {
    event.detail.handled = true
    if (this.mode === "plaintext") {
      event.detail.modified = this.plaintextController.isModified(this.originalContent)
    } else {
      event.detail.modified = this.graphicalController.isModified(this.originalStructure)
    }
  }

  handleContentLoaded(event) {
    event.detail.handled = true
    const data = event.detail

    this.originalContent = data.markdown_source
    this.originalStructure = data.structure

    this.plaintextController.content = data.markdown_source
    if (data.structure) {
      this.graphicalController.loadStructure(data.structure)
    }

    this.enableEditing()
    this.showActiveMode()
  }

  enableEditing() {
    const textarea = this.element.querySelector("[data-editor-target='textarea']")
    if (textarea) {
      textarea.disabled = false
      textarea.placeholder = ""
    }
    const saveBtn = this.element.querySelector("[data-editor-target='saveButton']")
    if (saveBtn) saveBtn.disabled = false
  }

  get plaintextController() {
    const el = this.plaintextContainerTarget.querySelector('[data-controller~="recipe-plaintext"]')
    return this.application.getControllerForElementAndIdentifier(el, "recipe-plaintext")
  }

  get graphicalController() {
    const el = this.graphicalContainerTarget.querySelector('[data-controller~="recipe-graphical"]')
    return this.application.getControllerForElementAndIdentifier(el, "recipe-graphical")
  }
}
