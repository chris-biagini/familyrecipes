import { Controller } from "@hotwired/stimulus"
import { getCsrfToken, showErrors } from "../utilities/editor_utils"

/**
 * Manages the AI recipe import dialog. Posts pasted recipe text to the
 * server-side Anthropic endpoint, then hands off the generated Markdown to
 * the recipe editor dialog. Supports a try-again flow with user feedback.
 *
 * Collaborators:
 * - editor_controller (recipe editor dialog lifecycle)
 * - plaintext_editor_controller (sets editor content via .content setter)
 * - editor_utils (CSRF tokens, error display)
 */
export default class extends Controller {
  static targets = ["textarea", "feedback", "feedbackField", "errors", "submitButton"]
  static values = { url: String, editorDialogId: String }

  connect() {
    this.previousResult = null
    this.boundOpenClick = (e) => {
      if (e.target.closest('#ai-import-button')) this.open()
    }
    document.addEventListener('click', this.boundOpenClick)
  }

  disconnect() {
    document.removeEventListener('click', this.boundOpenClick)
  }

  open() {
    this.element.showModal()
    this.textareaTarget.focus()
  }

  close() {
    this.element.close()
  }

  async submit(event) {
    event.preventDefault()
    const text = this.textareaTarget.value.trim()
    if (!text) return

    this.setLoading(true)
    this.clearErrors()

    const body = { text }
    if (this.previousResult && this.hasFeedbackTarget && this.feedbackTarget.value.trim()) {
      body.previous_result = this.previousResult
      body.feedback = this.feedbackTarget.value.trim()
    }

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCsrfToken()
        },
        body: JSON.stringify(body)
      })
      const data = await response.json()

      if (!response.ok) {
        this.showError(data.error || "Import failed")
        return
      }

      this.previousResult = data.markdown
      this.showFeedbackField()
      this.element.close()
      this.openRecipeEditor(data.markdown)
    } catch {
      this.showError("Network error. Check your connection.")
    } finally {
      this.setLoading(false)
    }
  }

  openRecipeEditor(markdown) {
    const editorDialog = document.getElementById(this.editorDialogIdValue)
    if (!editorDialog) return

    editorDialog.showModal()

    requestAnimationFrame(() => {
      const plaintextEl = editorDialog.querySelector('[data-controller~="plaintext-editor"]')
      if (plaintextEl) {
        const ctrl = this.application.getControllerForElementAndIdentifier(plaintextEl, "plaintext-editor")
        if (ctrl) {
          ctrl.content = markdown
          return
        }
      }
      const textarea = editorDialog.querySelector('textarea')
      if (textarea) textarea.value = markdown
    })
  }

  showFeedbackField() {
    if (this.hasFeedbackFieldTarget) {
      this.feedbackFieldTarget.hidden = false
    }
    this.submitButtonTarget.textContent = "Try Again"
  }

  setLoading(loading) {
    this.submitButtonTarget.disabled = loading
    this.submitButtonTarget.textContent = loading
      ? "Importing\u2026"
      : (this.previousResult ? "Try Again" : "Import")
    this.textareaTarget.disabled = loading
    if (this.hasFeedbackTarget) this.feedbackTarget.disabled = loading
  }

  showError(message) {
    if (this.hasErrorsTarget) {
      showErrors(this.errorsTarget, [message])
    }
  }

  clearErrors() {
    if (this.hasErrorsTarget) {
      this.errorsTarget.hidden = true
      this.errorsTarget.textContent = ""
    }
  }
}
