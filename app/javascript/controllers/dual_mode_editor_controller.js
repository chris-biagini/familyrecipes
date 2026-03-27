/**
 * Coordinator for dual-mode editing (plaintext ↔ graphical). Manages the
 * mode toggle, routes editor lifecycle events to the active child controller,
 * and handles mode-switch serialization via server-side parse/serialize
 * endpoints. Parameterized by Stimulus values so the same controller serves
 * both recipes and Quick Bites.
 *
 * - editor_controller: dialog lifecycle (parent)
 * - plaintext_editor_controller: child, plaintext mode (always "plaintext-editor")
 * - recipe_graphical_controller / quickbites_graphical_controller: child, graphical mode
 */
import { Controller } from "@hotwired/stimulus"
import { csrfHeaders } from "../utilities/editor_utils"
import ListenerManager from "../utilities/listener_manager"

export default class extends Controller {
  static targets = ["plaintextContainer", "graphicalContainer", "modeToggle"]
  static values = {
    parseUrl: String,
    serializeUrl: String,
    contentKey: String,
    graphicalId: String
  }

  connect() {
    this.mode = localStorage.getItem("editorMode") || "graphical"
    this.originalContent = null
    this.originalStructure = null

    this.listeners = new ListenerManager()
    this.listeners.add(this.element, "editor:collect", (e) => this.handleCollect(e))
    this.listeners.add(this.element, "editor:modified", (e) => this.handleModified(e))
    this.listeners.add(this.element, "editor:content-loaded", (e) => this.handleContentLoaded(e))
    this.listeners.add(this.element, "editor:opened", (e) => this.handleOpened(e))
    this.listeners.add(this.element, "editor:reset", (e) => this.handleReset(e))
  }

  disconnect() {
    this.listeners.teardown()
  }

  toggleMode() {
    const newMode = this.mode === "plaintext" ? "graphical" : "plaintext"
    this.switchTo(newMode)
  }

  async switchTo(newMode) {
    if (newMode === this.mode) return
    const key = this.contentKeyValue

    try {
      if (newMode === "plaintext") {
        if (!this.graphicalController.isModified(this.originalStructure)) {
          this.plaintextController.content = this.originalContent
        } else {
          const structure = this.graphicalController.toStructure()
          const response = await fetch(this.serializeUrlValue, {
            method: "POST",
            headers: { ...csrfHeaders(), "Content-Type": "application/json" },
            body: JSON.stringify({ structure })
          })
          const data = await response.json()
          this.plaintextController.content = data[key]
        }
      } else {
        if (!this.plaintextController.isModified(this.originalContent)) {
          this.graphicalController.loadStructure(this.originalStructure)
        } else {
          const content = this.plaintextController.content
          const response = await fetch(this.parseUrlValue, {
            method: "POST",
            headers: { ...csrfHeaders(), "Content-Type": "application/json" },
            body: JSON.stringify({ [key]: content })
          })
          const ir = await response.json()
          this.graphicalController.loadStructure(ir)
        }
      }

      this.mode = newMode
      localStorage.setItem("editorMode", newMode)
      this.showActiveMode()
    } catch {
      const errorsEl = this.element.querySelector("[data-editor-target='errors']")
      if (errorsEl) {
        errorsEl.textContent = "Failed to switch editor mode. Please try again."
        errorsEl.hidden = false
      }
    }
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
      event.detail.data = { [this.contentKeyValue]: this.plaintextController.content }
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

  async handleOpened() {
    if (this.originalContent !== null) return
    await this.plaintextController.whenReady()
    this.originalContent = this.plaintextController.content
    this.showActiveMode()
  }

  handleReset(event) {
    event.detail.handled = true
    if (this.originalContent !== null) {
      this.plaintextController.content = this.originalContent
    }
    if (this.originalStructure !== null) {
      this.graphicalController.loadStructure(this.originalStructure)
    }
    this.originalContent = null
    this.originalStructure = null
  }

  handleContentLoaded(event) {
    event.detail.handled = true
    const data = event.detail
    const category = event.detail.category

    if (!data[this.contentKeyValue]) {
      const jsonEl = this.element.querySelector("script[data-editor-markdown]")
      if (!jsonEl) {
        this.originalContent = this.plaintextController.content
        this.originalStructure = this.graphicalController.toStructure()
        this.enableEditing()
        this.showActiveMode()
        this.applyFocusCategory(category)
        return
      }
      const parsed = JSON.parse(jsonEl.textContent)
      this.originalContent = parsed.plaintext || ""
      this.plaintextController.content = this.originalContent
      this.originalStructure = this.graphicalController.toStructure()
      this.enableEditing()
      this.showActiveMode()
      this.applyFocusCategory(category)
      return
    }

    this.originalContent = data[this.contentKeyValue]
    this.originalStructure = data.structure

    this.plaintextController.content = data[this.contentKeyValue]
    if (data.structure) {
      this.graphicalController.loadStructure(data.structure)
    }

    this.enableEditing()
    this.showActiveMode()
    this.applyFocusCategory(category)
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

  applyFocusCategory(category) {
    if (!category) return
    if (this.mode === "graphical") {
      this.graphicalController.focusCategory?.(category)
    } else {
      this.plaintextController.focusCategory?.(category)
    }
  }

  get plaintextController() {
    const el = this.plaintextContainerTarget.querySelector('[data-controller~="plaintext-editor"]')
    return this.application.getControllerForElementAndIdentifier(el, "plaintext-editor")
  }

  get graphicalController() {
    const id = this.graphicalIdValue
    const el = this.graphicalContainerTarget.querySelector(`[data-controller~="${id}"]`)
    return this.application.getControllerForElementAndIdentifier(el, id)
  }
}
