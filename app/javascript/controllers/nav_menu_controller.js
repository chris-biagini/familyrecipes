import { Controller } from "@hotwired/stimulus"

/**
 * Responsive nav with three layout states: inline (icon + label),
 * compact (stacked icon over label), and hamburger (drawer menu).
 * Uses ResizeObserver to detect actual content overflow rather than
 * hardcoded breakpoints — adapts to any link count or label length.
 *
 * - Collaborators: _nav.html.erb, style.css (.nav-compact / .nav-hamburger)
 * - Drawer animates via CSS grid-template-rows (0fr <-> 1fr)
 * - Closes on Escape, click outside, and Turbo navigation
 */
export default class extends Controller {
  static targets = ["button", "drawer", "navLinks", "container"]

  connect() {
    this.layoutObserver = new ResizeObserver(() => this.updateLayout())
    this.layoutObserver.observe(this.containerTarget)

    this.drawerObserver = new ResizeObserver(([entry]) => {
      this.element.style.setProperty("--drawer-height", `${entry.contentRect.height}px`)
    })
    this.drawerObserver.observe(this.drawerTarget)

    this.updateLayout()
  }

  disconnect() {
    this.layoutObserver.disconnect()
    this.drawerObserver.disconnect()
  }

  updateLayout() {
    const wasHamburger = this.element.classList.contains("nav-hamburger")

    this.element.classList.remove("nav-compact", "nav-hamburger")

    let needsHamburger = false
    if (this.overflows()) {
      this.element.classList.add("nav-compact")
      if (this.overflows()) {
        this.element.classList.add("nav-hamburger")
        needsHamburger = true
      }
    }

    if (wasHamburger && !needsHamburger) this.close()
  }

  overflows() {
    const links = this.navLinksTarget.querySelectorAll(":scope > a")
    links.forEach(link => {
      link.style.flexShrink = "0"
      link.style.flexBasis = "auto"
    })

    const result = this.navLinksTarget.scrollWidth > this.navLinksTarget.clientWidth

    links.forEach(link => {
      link.style.flexShrink = ""
      link.style.flexBasis = ""
    })

    return result
  }

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
