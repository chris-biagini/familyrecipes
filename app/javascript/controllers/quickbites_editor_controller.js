import { Controller } from "@hotwired/stimulus"
import HighlightOverlay from "utilities/highlight_overlay"

/**
 * Syntax-highlighting overlay for the QuickBites textarea. Delegates overlay
 * lifecycle, auto-dash, and scroll sync to HighlightOverlay. This controller
 * provides only the Quick Bites line classification (categories bold/accent,
 * ingredients muted) and the placeholder text.
 *
 * - editor_controller: owns the dialog lifecycle; this controller is additive
 * - highlight_overlay: overlay positioning, auto-dash, scroll sync
 * - style.css (.hl-*): highlight colors
 */
export default class extends Controller {
  static targets = ["textarea"]

  textareaTargetConnected(element) {
    this.setPlaceholder(element)
    this.hlOverlay = new HighlightOverlay(element, (text) => this.buildFragment(text))
    this.hlOverlay.attach()
  }

  textareaTargetDisconnected() {
    this.hlOverlay?.detach()
    this.hlOverlay = null
  }

  buildFragment(text) {
    const fragment = document.createDocumentFragment()

    text.split("\n").forEach((line, i) => {
      if (i > 0) fragment.appendChild(document.createTextNode("\n"))

      if (/^[^-].+:\s*$/.test(line)) {
        const span = document.createElement("span")
        span.classList.add("hl-category")
        span.textContent = line
        fragment.appendChild(span)
      } else if (/^\s*-\s+/.test(line)) {
        const colonIdx = line.indexOf(":", line.indexOf("-") + 2)
        if (colonIdx !== -1) {
          const nameSpan = document.createElement("span")
          nameSpan.classList.add("hl-item")
          nameSpan.textContent = line.slice(0, colonIdx)
          fragment.appendChild(nameSpan)

          const ingSpan = document.createElement("span")
          ingSpan.classList.add("hl-ingredients")
          ingSpan.textContent = line.slice(colonIdx)
          fragment.appendChild(ingSpan)
        } else {
          const span = document.createElement("span")
          span.classList.add("hl-item")
          span.textContent = line
          fragment.appendChild(span)
        }
      } else {
        fragment.appendChild(document.createTextNode(line))
      }
    })

    return fragment
  }

  setPlaceholder(textarea) {
    if (!textarea.getAttribute("data-placeholder-set")) {
      textarea.placeholder = "Snacks:\n- Hummus with Pretzels: Hummus, Pretzels\n- String cheese\n\nBreakfast:\n- Cereal with Milk: Cereal, Milk"
      textarea.setAttribute("data-placeholder-set", "true")
    }
  }
}
