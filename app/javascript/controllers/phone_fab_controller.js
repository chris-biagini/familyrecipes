import { Controller } from "@hotwired/stimulus"

/**
 * Phone FAB — bottom-center floating action button for phone-sized screens.
 * Manages the panel open/close lifecycle and cross-controller dispatch for
 * search/settings. The panel is always in the DOM at opacity:0 /
 * pointer-events:none; toggling .fab-open animates it in without display
 * changes, eliminating the layout flash that hidden→visible caused.
 *
 * - Collaborators: _phone_fab.html.erb, navigation.css (.phone-fab),
 *   search_overlay_controller (dispatched via openSearch),
 *   editor_controller (settings button clicked programmatically)
 * - CSS phone media query controls visibility — this controller is inert
 *   on non-phone screens even though it connects to the DOM.
 * - Closes on: Escape, outside tap, Turbo navigation, orientation change
 */
export default class extends Controller {
  static targets = ["button", "panel"]

  connect() {
    this.phoneQuery = window.matchMedia(
      "(pointer: coarse) and (hover: none) and (max-width: 600px)"
    )
    this.boundMediaChange = this.handleMediaChange.bind(this)
    this.phoneQuery.addEventListener("change", this.boundMediaChange)

    this.boundOutsideTap = this.outsideTap.bind(this)
  }

  disconnect() {
    this.phoneQuery.removeEventListener("change", this.boundMediaChange)
    document.removeEventListener("pointerdown", this.boundOutsideTap)
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.panelTarget.classList.add("fab-open")
    this.buttonTarget.setAttribute("aria-expanded", "true")

    this.trapFocusListener = this.trapFocus.bind(this)
    this.element.addEventListener("keydown", this.trapFocusListener)
    document.addEventListener("pointerdown", this.boundOutsideTap)

    this.firstFocusable?.focus()
  }

  close() {
    if (!this.isOpen) return

    this.panelTarget.classList.remove("fab-open")
    this.buttonTarget.setAttribute("aria-expanded", "false")

    this.element.removeEventListener("keydown", this.trapFocusListener)
    document.removeEventListener("pointerdown", this.boundOutsideTap)
    this.buttonTarget.focus()
  }

  instantClose() {
    this.panelTarget.classList.remove("fab-open")
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.element.removeEventListener("keydown", this.trapFocusListener)
    document.removeEventListener("pointerdown", this.boundOutsideTap)
  }

  openSearch() {
    this.instantClose()
    const overlay = this.application.getControllerForElementAndIdentifier(
      document.body, "search-overlay"
    )
    if (overlay) overlay.open()
  }

  openSettings() {
    this.instantClose()
    document.getElementById("settings-button")?.click()
  }

  closeOnNavigate() {
    this.instantClose()
  }

  // -- Private --

  get isOpen() {
    return this.buttonTarget.getAttribute("aria-expanded") === "true"
  }

  get focusableItems() {
    return [
      ...this.panelTarget.querySelectorAll("a, button"),
      this.buttonTarget
    ]
  }

  get firstFocusable() {
    return this.panelTarget.querySelector("a, button")
  }

  outsideTap(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  trapFocus(event) {
    if (event.key !== "Tab") return

    const items = this.focusableItems
    if (items.length === 0) return

    const first = items[0]
    const last = items[items.length - 1]

    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  handleMediaChange() {
    if (!this.phoneQuery.matches) this.instantClose()
  }
}
