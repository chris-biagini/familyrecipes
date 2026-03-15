import { Controller } from "@hotwired/stimulus"

/**
 * Gates an export download link behind a confirmation dialog. The actual
 * download is handled by the browser via an <a download> link — no
 * navigation occurs, so this works identically in browser and PWA modes.
 *
 * - ExportsController: serves the ZIP at the link's href
 */
export default class extends Controller {
  confirm(event) {
    if (!confirm("Export all recipes, Quick Bites, and custom ingredients?")) {
      event.preventDefault()
    }
  }
}
