import { Controller } from "@hotwired/stimulus"
import { getCsrfToken, showErrors } from "../utilities/editor_utils"

/**
 * Manages the AI recipe import dialog. Posts pasted recipe text to the
 * server-side Anthropic endpoint, then hands off the generated Markdown to
 * the recipe editor via editor_controller.openWithContent(), which dispatches
 * editor:content-loaded for proper dual-mode editor integration. Supports a
 * try-again flow with user feedback.
 *
 * Collaborators:
 * - editor_controller (openWithContent for dialog lifecycle + content handoff)
 * - dual_mode_editor_controller (handles editor:content-loaded to populate editor)
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

    const editorCtrl = this.application.getControllerForElementAndIdentifier(editorDialog, "editor")
    if (!editorCtrl) return

    const dualCtrl = this.application.getControllerForElementAndIdentifier(editorDialog, "dual-mode-editor")
    if (dualCtrl) dualCtrl.mode = "plaintext"

    editorCtrl.openWithContent({ markdown_source: markdown })
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
