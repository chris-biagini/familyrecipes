/**
 * Toggles a password field between masked and visible. Used on the settings
 * page for API key fields.
 *
 * - Targets: input (the password field), button (the toggle button)
 */
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]

  toggle() {
    const isPassword = this.inputTarget.type === "password"
    this.inputTarget.type = isPassword ? "text" : "password"
    this.buttonTarget.textContent = isPassword ? "Hide" : "Show"
  }
}
