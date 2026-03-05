import { Controller } from "@hotwired/stimulus"

/**
 * Confirms and initiates a data export download. Reads the export URL from
 * a data attribute and navigates to it after user confirmation.
 *
 * - ExportsController: serves the ZIP at the configured URL
 */
export default class extends Controller {
  static values = { url: String }

  download() {
    if (confirm("Export all recipes, Quick Bites, and custom ingredients?")) {
      window.location = this.urlValue
    }
  }
}
