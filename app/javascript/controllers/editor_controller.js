import { Controller } from "@hotwired/stimulus"
import {
  getCsrfToken, showErrors, clearErrors,
  closeWithConfirmation, saveRequest, guardBeforeUnload, handleSave
} from "../utilities/editor_utils"
import { show as notifyShow } from "../utilities/notify"
import ListenerManager from "../utilities/listener_manager"

/**
 * Generic <dialog> lifecycle controller for editor modals. Handles open, save
 * (PATCH/POST via fetch), dirty-checking, close with confirmation, beforeunload
 * guards, and Turbo Drive navigation guards. Simple dialogs need zero custom
 * JS — just Stimulus data attributes on the <dialog>. Custom dialogs hook in
 * via lifecycle events: editor:collect, editor:save, editor:modified,
 * editor:reset, editor:content-loaded. Dual-mode editors (recipe editor) use a
 * coordinator that sets `handled = true` on these events to override default
 * textarea behavior. Three open modes: open() for new content from template,
 * openWithRemoteContent() for server-fetched content, openWithContent(data)
 * for caller-provided content (e.g. AI import).
 *
 * - editor_utils: CSRF tokens, error display, save requests, close-with-confirmation
 * - notify: toast notifications for save success/failure feedback
 */
export default class extends Controller {
  static targets = ["textarea", "saveButton", "deleteButton", "errors"]

  static values = {
    url: String,
    method: { type: String, default: "PATCH" },
    onSuccess: { type: String, default: "redirect" },
    bodyKey: { type: String, default: "markdown_source" },
    openSelector: String,
    loadUrl: String,
    loadKey: { type: String, default: "content" }
  }

  connect() {
    this.originalContent = ""
    this.listeners = new ListenerManager()

    if (this.hasOpenSelectorValue) {
      this.listeners.add(document, "click", (event) => {
        if (event.target.closest(this.openSelectorValue)) this.open()
      })
    }

    this.guard = guardBeforeUnload(this.element, () => this.isModified())

    this.listeners.add(this.element, "cancel", (e) => this.handleCancel(e))
    this.listeners.add(document, "turbo:before-visit", (e) => this.handleBeforeVisit(e))
  }

  disconnect() {
    this.listeners.teardown()
    if (this.guard) this.guard.remove()
  }

  open() {
    this.clearErrorDisplay()
    this.resetSaveButton()

    if (this.hasLoadUrlValue) {
      this.openWithRemoteContent()
    } else {
      if (this.hasTextareaTarget) this.originalContent = this.textareaTarget.value
      this.element.showModal()
      this.dispatchEditorEvent("editor:opened")
    }
  }

  openWithContent(data) {
    this.clearErrorDisplay()
    this.resetSaveButton()
    this.element.showModal()
    this.dispatchEditorEvent("editor:content-loaded", data)
  }

  close() {
    closeWithConfirmation(this.element, () => this.isModified(), () => this.resetContent())
  }

  save() {
    const collectResult = this.dispatchEditorEvent("editor:collect", { data: null })
    const data = collectResult.handled
      ? collectResult.data
      : { [this.bodyKeyValue]: this.hasTextareaTarget ? this.textareaTarget.value : null }

    const saveResult = this.dispatchEditorEvent("editor:save", { data, saveFn: null })
    const saveFn = saveResult.handled && saveResult.saveFn
      ? saveResult.saveFn
      : () => saveRequest(this.urlValue, this.methodValue, data)

    handleSave(this.saveButtonTarget, this.errorsTarget, saveFn, (responseData) => {
      if (responseData.warnings?.length > 0) {
        this.showWarnings(responseData.warnings)
        this.originalContent = this.hasTextareaTarget ? this.textareaTarget.value : ""
        return
      }

      this.guard.markSaving()

      if (this.onSuccessValue === "reload") {
        window.location.reload()
      } else if (this.onSuccessValue === "close") {
        if (responseData.slug) {
          const currentSlug = window.location.pathname.split("/").pop()
          if (responseData.slug !== currentSlug) {
            const newPath = window.location.pathname.replace(/\/[^/]+$/, `/${responseData.slug}`)
            history.replaceState(null, "", newPath)
          }
        }
        if (responseData.updated_references?.length > 0) {
          notifyShow(`Updated references in ${responseData.updated_references.join(", ")}.`)
        }
        this.element.close()
      } else {
        let redirectUrl = responseData.redirect_url
        if (!redirectUrl || !redirectUrl.startsWith("/")) {
          window.location.reload()
          return
        }
        window.location = redirectUrl
      }
    })
  }

  async delete() {
    const btn = this.deleteButtonTarget
    const title = btn.dataset.recipeTitle
    const referencing = JSON.parse(btn.dataset.referencingRecipes || "[]")

    let message
    if (referencing.length > 0) {
      message = `Delete "${title}"?\n\nCross-references in ${referencing.join(", ")} will be converted to plain text.\n\nThis cannot be undone.`
    } else {
      message = `Delete "${title}"?\n\nThis cannot be undone.`
    }

    if (!confirm(message)) return

    btn.disabled = true
    btn.textContent = "Deleting\u2026"

    try {
      const response = await fetch(this.urlValue, {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCsrfToken()
        }
      })

      if (response.ok) {
        const data = await response.json()
        this.guard.markSaving()
        const deleteRedirect = data.redirect_url
        if (!deleteRedirect || !deleteRedirect.startsWith("/")) {
          window.location.reload()
          return
        }
        window.location = deleteRedirect
      } else {
        showErrors(this.errorsTarget, [`Failed to delete (${response.status}). Please try again.`])
        btn.disabled = false
        btn.textContent = "Delete"
      }
    } catch {
      showErrors(this.errorsTarget, ["Network error. Please check your connection and try again."])
      btn.disabled = false
      btn.textContent = "Delete"
    }
  }

  dispatchEditorEvent(name, extra) {
    const detail = Object.assign({ handled: false }, extra)
    const event = new CustomEvent(name, { detail, bubbles: false })
    this.element.dispatchEvent(event)
    return event.detail
  }

  isModified() {
    const result = this.dispatchEditorEvent("editor:modified", { modified: false })
    if (result.handled) return result.modified
    return this.hasTextareaTarget ? this.textareaTarget.value !== this.originalContent : false
  }

  resetContent() {
    const result = this.dispatchEditorEvent("editor:reset")
    if (!result.handled && this.hasTextareaTarget) this.textareaTarget.value = this.originalContent
    this.clearErrorDisplay()
  }

  handleCancel(event) {
    if (this.isModified()) {
      event.preventDefault()
      this.close()
    }
  }

  handleBeforeVisit(event) {
    if (!this.element.open) return
    if (this.isModified()) {
      event.preventDefault()
      this.close()
    } else {
      this.element.close()
    }
  }

  resetSaveButton() {
    if (this.hasSaveButtonTarget) {
      this.saveButtonTarget.disabled = false
      this.saveButtonTarget.textContent = "Save"
    }
  }

  clearErrorDisplay() {
    if (this.hasErrorsTarget) {
      clearErrors(this.errorsTarget)
      this.errorsTarget.classList.remove("editor-warnings")
    }
  }

  showWarnings(warnings) {
    let messages
    if (warnings.length <= 3) {
      messages = warnings
    } else {
      const lines = warnings.map(w => {
        const match = w.match(/\d+/)
        return match ? match[0] : "?"
      })
      messages = [`${warnings.length} lines were not recognized (lines ${lines.join(", ")})`]
    }
    showErrors(this.errorsTarget, messages)
    this.errorsTarget.classList.add("editor-warnings")
  }

  openWithRemoteContent() {
    if (this.hasTextareaTarget) {
      this.textareaTarget.value = ""
      this.textareaTarget.disabled = true
      this.textareaTarget.placeholder = "Loading\u2026"
    }
    if (this.hasSaveButtonTarget) this.saveButtonTarget.disabled = true
    this.element.showModal()

    fetch(this.loadUrlValue, {
      headers: { "Accept": "application/json", "X-CSRF-Token": getCsrfToken() }
    })
      .then(r => r.json())
      .then(data => {
        const loadResult = this.dispatchEditorEvent("editor:content-loaded", data)
        if (!loadResult.handled && this.hasTextareaTarget) {
          this.textareaTarget.value = data[this.loadKeyValue] || ""
          this.originalContent = this.textareaTarget.value
          this.textareaTarget.disabled = false
          this.textareaTarget.placeholder = ""
          this.textareaTarget.focus()
        }
        if (this.hasSaveButtonTarget) this.saveButtonTarget.disabled = false
      })
      .catch(() => {
        if (this.hasTextareaTarget) {
          this.textareaTarget.value = ""
          this.textareaTarget.disabled = false
          this.textareaTarget.placeholder = ""
        }
        showErrors(this.errorsTarget, ["Failed to load content. Close and try again."])
      })
  }
}
