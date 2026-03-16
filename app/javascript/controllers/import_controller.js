import { Controller } from "@hotwired/stimulus"
import { getCsrfToken } from "../utilities/editor_utils"
import { show as notifyShow } from "../utilities/notify"

/**
 * Manages file selection, upload, and result notification for kitchen data
 * import. Opens a hidden file input on click, submits via fetch (multipart),
 * and shows a toast with the server's summary message.
 *
 * - ImportsController: receives the multipart POST, returns JSON
 * - notify.js: toast notification for import results
 */
export default class extends Controller {
  static targets = ["fileInput"]
  static values = { url: String }

  choose() {
    this.fileInputTarget.click()
  }

  submit() {
    if (this.fileInputTarget.files.length === 0) return

    const formData = new FormData()
    for (const file of this.fileInputTarget.files) {
      formData.append("files[]", file)
    }

    fetch(this.urlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": getCsrfToken() || "" },
      body: formData
    })
      .then(response => response.json())
      .then(data => {
        // Delay toast so Turbo morph (from broadcast_update) settles first
        setTimeout(() => notifyShow(data.message, { persistent: true }), 500)
      })
      .catch(() => notifyShow("Import failed. Please try again."))
      .finally(() => { this.fileInputTarget.value = "" })
  }
}
