import { Controller } from "@hotwired/stimulus"
import {
  getCsrfToken, showErrors, clearErrors,
  closeWithConfirmation, saveRequest, guardBeforeUnload, handleSave
} from "utilities/editor_utils"
import { show as notifyShow } from "utilities/notify"

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

    if (this.hasOpenSelectorValue) {
      this.openButton = document.querySelector(this.openSelectorValue)
      if (this.openButton) {
        this.boundOpen = this.open.bind(this)
        this.openButton.addEventListener("click", this.boundOpen)
      }
    }

    this.guard = guardBeforeUnload(this.element, () => this.isModified())

    this.boundCancel = this.handleCancel.bind(this)
    this.element.addEventListener("cancel", this.boundCancel)

    this.checkRefsUpdated()
  }

  disconnect() {
    if (this.openButton && this.boundOpen) {
      this.openButton.removeEventListener("click", this.boundOpen)
    }
    if (this.guard) this.guard.remove()
    this.element.removeEventListener("cancel", this.boundCancel)
  }

  open() {
    this.clearErrorDisplay()

    if (this.hasLoadUrlValue) {
      this.openWithRemoteContent()
    } else {
      if (this.hasTextareaTarget) this.originalContent = this.textareaTarget.value
      this.element.showModal()
    }
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
      this.guard.markSaving()

      if (this.onSuccessValue === "reload") {
        window.location.reload()
      } else if (this.onSuccessValue === "close") {
        this.element.close()
      } else {
        let redirectUrl = responseData.redirect_url
        if (!redirectUrl || !redirectUrl.startsWith("/")) {
          window.location.reload()
          return
        }
        if (responseData.updated_references?.length > 0) {
          const param = encodeURIComponent(responseData.updated_references.join(", "))
          const separator = redirectUrl.includes("?") ? "&" : "?"
          redirectUrl += `${separator}refs_updated=${param}`
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

  clearErrorDisplay() {
    if (this.hasErrorsTarget) clearErrors(this.errorsTarget)
  }

  openWithRemoteContent() {
    if (this.hasTextareaTarget) {
      this.textareaTarget.value = ""
      this.textareaTarget.disabled = true
      this.textareaTarget.placeholder = "Loading\u2026"
    }
    this.element.showModal()

    fetch(this.loadUrlValue, {
      headers: { "Accept": "application/json", "X-CSRF-Token": getCsrfToken() }
    })
      .then(r => r.json())
      .then(data => {
        if (this.hasTextareaTarget) {
          this.textareaTarget.value = data[this.loadKeyValue] || ""
          this.originalContent = this.textareaTarget.value
          this.textareaTarget.disabled = false
          this.textareaTarget.placeholder = ""
          this.textareaTarget.focus()
        }
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

  checkRefsUpdated() {
    const params = new URLSearchParams(window.location.search)
    const refsUpdated = params.get("refs_updated")
    if (refsUpdated) {
      notifyShow(`Updated references in ${refsUpdated}.`)
      const cleanUrl = window.location.pathname + window.location.hash
      history.replaceState(null, "", cleanUrl)
    }
  }
}
