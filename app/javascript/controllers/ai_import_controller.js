import { Controller } from "@hotwired/stimulus"
import { saveRequest, showErrors } from "../utilities/editor_utils"
import ListenerManager from "../utilities/listener_manager"

/**
 * Manages the AI recipe import dialog. Posts pasted recipe text to the
 * server-side Anthropic endpoint, then hands off the generated Markdown to
 * the recipe editor via editor_controller.openWithContent(), which dispatches
 * editor:content-loaded for proper dual-mode editor integration.
 *
 * Supports two import modes: faithful (preserve source wording) and expert
 * (condense for experienced cooks), toggled by a checkbox in the dialog.
 *
 * Collaborators:
 * - editor_controller (openWithContent for dialog lifecycle + content handoff)
 * - dual_mode_editor_controller (handles editor:content-loaded to populate editor)
 * - editor_utils (CSRF tokens, error display)
 * - ListenerManager: clean event listener teardown
 */
export default class extends Controller {
  static targets = ["textarea", "errors", "submitButton", "expertCheckbox"]
  static values = { url: String, editorDialogId: String }

  connect() {
    this.listeners = new ListenerManager()
    this.listeners.add(document, 'click', (e) => {
      if (e.target.closest('#ai-import-button')) this.open()
    })
  }

  disconnect() {
    this.listeners.teardown()
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

    const mode = this.hasExpertCheckboxTarget && this.expertCheckboxTarget.checked
      ? 'expert' : 'faithful'

    try {
      const response = await saveRequest(this.urlValue, "POST", { text, mode })
      const data = await response.json()

      if (!response.ok) {
        this.showError(data.error || "Import failed")
        return
      }

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

  setLoading(loading) {
    this.submitButtonTarget.disabled = loading
    this.submitButtonTarget.textContent = loading ? "Importing\u2026" : "Import"
    this.textareaTarget.disabled = loading
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
