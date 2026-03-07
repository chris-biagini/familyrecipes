import { Controller } from "@hotwired/stimulus"

/**
 * Manages file selection and form submission for kitchen data import.
 * Programmatically opens a hidden file input when the Import button is
 * clicked, then submits the enclosing form when files are selected.
 *
 * - ImportsController: receives the multipart POST
 */
export default class extends Controller {
  static targets = ["fileInput"]

  choose() {
    this.fileInputTarget.click()
  }

  submit() {
    if (this.fileInputTarget.files.length > 0) {
      this.element.requestSubmit()
    }
  }
}
