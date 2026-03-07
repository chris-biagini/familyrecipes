import { Controller } from "@hotwired/stimulus"

/**
 * Hamburger menu for narrow viewports. Toggles a slide-down drawer of
 * nav links and morphs the hamburger SVG into an X via CSS transforms
 * keyed on aria-expanded.
 *
 * - Collaborators: _nav.html.erb, style.css (hamburger/drawer rules)
 * - Drawer animates via CSS grid-template-rows (0fr <-> 1fr)
 * - Closes on Escape, click outside, and Turbo navigation
 */
export default class extends Controller {
  static targets = ["button", "drawer"]

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.drawerTarget.setAttribute("aria-hidden", "false")
  }

  close() {
    if (!this.isOpen) return
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.drawerTarget.setAttribute("aria-hidden", "true")
  }

  closeOutside(event) {
    if (this.isOpen && !this.element.contains(event.target)) this.close()
  }

  get isOpen() {
    return this.buttonTarget.getAttribute("aria-expanded") === "true"
  }
}
