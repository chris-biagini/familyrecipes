import { Controller } from "@hotwired/stimulus"

/**
 * Phone FAB — bottom-center floating action button for phone-sized screens.
 * Manages the panel open/close lifecycle, genie animation with staggered
 * item reveals, and cross-controller dispatch for search/settings.
 *
 * - Collaborators: _phone_fab.html.erb, navigation.css (.phone-fab),
 *   search_overlay_controller (dispatched via openSearch),
 *   editor_controller (settings button clicked programmatically)
 * - CSS phone media query controls visibility — this controller is inert
 *   on non-phone screens even though it connects to the DOM.
 * - Closes on: Escape, overlay click, Turbo navigation, orientation change
 */
export default class extends Controller {
  static targets = ["button", "panel", "overlay"]

  connect() {
    this.phoneQuery = window.matchMedia(
      "(pointer: coarse) and (hover: none) and (max-width: 600px)"
    )
    this.boundMediaChange = this.handleMediaChange.bind(this)
    this.phoneQuery.addEventListener("change", this.boundMediaChange)
  }

  disconnect() {
    this.phoneQuery.removeEventListener("change", this.boundMediaChange)
    clearTimeout(this.closeTimer)
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.overlayTarget.hidden = false
    this.panelTarget.hidden = false

    requestAnimationFrame(() => {
      this.panelTarget.classList.add("fab-open")
      this.overlayTarget.classList.add("fab-open")
    })

    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.trapFocusListener = this.trapFocus.bind(this)
    this.element.addEventListener("keydown", this.trapFocusListener)

    this.firstFocusable?.focus()
  }

  close() {
    if (!this.isOpen) return

    this.panelTarget.classList.remove("fab-open")
    this.overlayTarget.classList.remove("fab-open")
    this.buttonTarget.setAttribute("aria-expanded", "false")

    this.element.removeEventListener("keydown", this.trapFocusListener)

    const cleanup = () => {
      clearTimeout(this.closeTimer)
      this.panelTarget.hidden = true
      this.overlayTarget.hidden = true
    }

    this.panelTarget.addEventListener("transitionend", (e) => {
      if (e.propertyName === "opacity") cleanup()
    }, { once: true })

    this.closeTimer = setTimeout(cleanup, 250)
    this.buttonTarget.focus()
  }

  instantClose() {
    if (!this.isOpen) return

    clearTimeout(this.closeTimer)
    this.panelTarget.classList.remove("fab-open")
    this.overlayTarget.classList.remove("fab-open")
    this.panelTarget.hidden = true
    this.overlayTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.element.removeEventListener("keydown", this.trapFocusListener)
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
      ...this.panelTarget.querySelectorAll("a:not([hidden]), button:not([hidden])"),
      this.buttonTarget
    ]
  }

  get firstFocusable() {
    return this.panelTarget.querySelector("a, button")
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
