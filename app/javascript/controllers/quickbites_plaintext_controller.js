import { Controller } from "@hotwired/stimulus"
import HighlightOverlay from "../utilities/highlight_overlay"

/**
 * Plaintext Quick Bites editor: textarea with syntax-highlighting overlay.
 * Handles only the textarea view in plaintext mode. The parent
 * quickbites_editor_controller (coordinator) manages mode toggling and routes
 * lifecycle events to the active child.
 *
 * - quickbites_editor_controller: coordinator, routes lifecycle events
 * - HighlightOverlay: overlay positioning, auto-dash, scroll sync
 * - style.css (.hl-*): highlight colors
 */
export default class extends Controller {
  static targets = ["textarea"]

  textareaTargetConnected(element) {
    this.hlOverlay?.detach()
    this.setPlaceholder(element)
    this.hlOverlay = new HighlightOverlay(element, (text) => this.buildFragment(text))
    this.hlOverlay.attach()
  }

  textareaTargetDisconnected() {
    this.hlOverlay?.detach()
    this.hlOverlay = null
  }

  disconnect() {
    this.hlOverlay?.detach()
    this.hlOverlay = null
  }

  get content() {
    return this.textareaTarget.value
  }

  set content(text) {
    this.textareaTarget.value = text
    this.ensureOverlay()
    this.hlOverlay.highlight()
  }

  ensureOverlay() {
    if (this.hlOverlay) return

    this.hlOverlay = new HighlightOverlay(this.textareaTarget, (text) => this.buildFragment(text))
    this.hlOverlay.attach()
  }

  isModified(originalContent) {
    return this.textareaTarget.value !== originalContent
  }

  buildFragment(text) {
    const fragment = document.createDocumentFragment()

    text.split("\n").forEach((line, i) => {
      if (i > 0) fragment.appendChild(document.createTextNode("\n"))

      if (/^[^-].+:\s*$/.test(line)) {
        this.appendSpan(fragment, line, "hl-category")
      } else if (/^\s*-\s+/.test(line)) {
        this.highlightItem(line, fragment)
      } else {
        fragment.appendChild(document.createTextNode(line))
      }
    })

    return fragment
  }

  highlightItem(line, fragment) {
    const colonIdx = line.indexOf(":", line.indexOf("-") + 2)
    if (colonIdx !== -1) {
      this.appendSpan(fragment, line.slice(0, colonIdx), "hl-item")
      this.appendSpan(fragment, line.slice(colonIdx), "hl-ingredients")
    } else {
      this.appendSpan(fragment, line, "hl-item")
    }
  }

  appendSpan(fragment, text, className) {
    const span = document.createElement("span")
    span.classList.add(className)
    span.textContent = text
    fragment.appendChild(span)
  }

  setPlaceholder(textarea) {
    if (!textarea.getAttribute("data-placeholder-set")) {
      textarea.placeholder = "Snacks:\n- Hummus with Pretzels: Hummus, Pretzels\n- String cheese\n\nBreakfast:\n- Cereal with Milk: Cereal, Milk"
      textarea.setAttribute("data-placeholder-set", "true")
    }
  }
}
