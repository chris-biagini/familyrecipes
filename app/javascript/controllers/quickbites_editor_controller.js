import { Controller } from "@hotwired/stimulus"

/**
 * Syntax-highlighting overlay and auto-dash for the QuickBites textarea.
 * Layers a <pre> behind the transparent textarea so users see colored text
 * (categories bold/accent, ingredients muted) while typing into a real textarea.
 * Auto-dash: pressing Enter on a `- ` line continues the list; Enter on an
 * empty `- ` line removes the dash.
 *
 * - editor_controller: owns the dialog lifecycle; this controller is additive
 * - style.css (.qb-highlight-*): overlay positioning and highlight colors
 */
export default class extends Controller {
  static targets = ["textarea"]

  connect() {
    this.cursorInitialized = false
  }

  disconnect() {
    this.teardownTextarea()
  }

  textareaTargetConnected(element) {
    this.teardownTextarea()
    this.textarea = element
    this.buildOverlay()
    this.setPlaceholder()
    this.highlight()

    this.boundHighlight = () => this.highlight()
    this.boundSync = () => this.syncScroll()
    this.boundKeydown = (e) => this.handleKeydown(e)
    this.boundFocus = () => this.handleFocus()

    this.textarea.addEventListener("input", this.boundHighlight)
    this.textarea.addEventListener("scroll", this.boundSync)
    this.textarea.addEventListener("keydown", this.boundKeydown)
    this.textarea.addEventListener("focus", this.boundFocus)

    // Reset cursor flag when editor starts loading new content
    this.observer = new MutationObserver(() => {
      if (this.textarea.disabled) this.cursorInitialized = false
    })
    this.observer.observe(this.textarea, { attributes: true, attributeFilter: ["disabled"] })
  }

  textareaTargetDisconnected() {
    this.teardownTextarea()
  }

  teardownTextarea() {
    if (!this.textarea) return

    if (this.boundHighlight) this.textarea.removeEventListener("input", this.boundHighlight)
    if (this.boundSync) this.textarea.removeEventListener("scroll", this.boundSync)
    if (this.boundKeydown) this.textarea.removeEventListener("keydown", this.boundKeydown)
    if (this.boundFocus) this.textarea.removeEventListener("focus", this.boundFocus)
    this.observer?.disconnect()

    // Unwrap textarea from the highlight wrapper before it's removed
    const wrapper = this.textarea.closest(".qb-highlight-wrap")
    if (wrapper?.parentNode) {
      this.textarea.classList.remove("qb-highlight-input")
      wrapper.parentNode.insertBefore(this.textarea, wrapper)
      wrapper.remove()
    } else {
      this.overlay?.remove()
    }

    this.textarea = null
    this.overlay = null
    this.boundHighlight = null
    this.boundSync = null
    this.boundKeydown = null
    this.boundFocus = null
  }

  buildOverlay() {
    const wrapper = document.createElement("div")
    wrapper.classList.add("qb-highlight-wrap")

    this.overlay = document.createElement("pre")
    this.overlay.classList.add("qb-highlight-overlay")
    this.overlay.setAttribute("aria-hidden", "true")

    this.textarea.parentNode.insertBefore(wrapper, this.textarea)
    wrapper.appendChild(this.overlay)
    wrapper.appendChild(this.textarea)
    this.textarea.classList.add("qb-highlight-input")
  }

  highlight() {
    const text = this.textarea.value
    if (!text) {
      this.overlay.replaceChildren()
      return
    }

    const fragment = document.createDocumentFragment()

    text.split("\n").forEach((line, i) => {
      if (i > 0) fragment.appendChild(document.createTextNode("\n"))

      if (/^[^-].+:\s*$/.test(line)) {
        const span = document.createElement("span")
        span.classList.add("qb-hl-category")
        span.textContent = line
        fragment.appendChild(span)
      } else if (/^\s*-\s+/.test(line)) {
        const colonIdx = line.indexOf(":", line.indexOf("-") + 2)
        if (colonIdx !== -1) {
          const nameSpan = document.createElement("span")
          nameSpan.classList.add("qb-hl-item")
          nameSpan.textContent = line.slice(0, colonIdx)
          fragment.appendChild(nameSpan)

          const ingSpan = document.createElement("span")
          ingSpan.classList.add("qb-hl-ingredients")
          ingSpan.textContent = line.slice(colonIdx)
          fragment.appendChild(ingSpan)
        } else {
          const span = document.createElement("span")
          span.classList.add("qb-hl-item")
          span.textContent = line
          fragment.appendChild(span)
        }
      } else {
        fragment.appendChild(document.createTextNode(line))
      }
    })

    if (text.endsWith("\n")) fragment.appendChild(document.createTextNode("\n"))

    this.overlay.replaceChildren(fragment)
  }

  handleFocus() {
    this.highlight()
    if (!this.cursorInitialized) {
      this.cursorInitialized = true
      this.textarea.selectionStart = 0
      this.textarea.selectionEnd = 0
      this.textarea.scrollTop = 0
      this.overlay.scrollTop = 0
    }
  }

  syncScroll() {
    this.overlay.scrollTop = this.textarea.scrollTop
    this.overlay.scrollLeft = this.textarea.scrollLeft
  }

  handleKeydown(e) {
    if (e.key !== "Enter") return

    const { selectionStart } = this.textarea
    const text = this.textarea.value
    const lineStart = text.lastIndexOf("\n", selectionStart - 1) + 1
    const currentLine = text.slice(lineStart, selectionStart)

    if (/^- $/.test(currentLine.trimStart())) {
      e.preventDefault()
      this.textarea.setRangeText("\n", lineStart, selectionStart, "end")
      this.textarea.dispatchEvent(new Event("input", { bubbles: true }))
      return
    }

    if (/^- .+/.test(currentLine.trimStart())) {
      e.preventDefault()
      this.textarea.setRangeText("\n- ", selectionStart, selectionStart, "end")
      this.textarea.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }

  setPlaceholder() {
    if (!this.textarea.getAttribute("data-placeholder-set")) {
      this.textarea.placeholder = "Snacks:\n- Hummus with Pretzels: Hummus, Pretzels\n- String cheese\n\nBreakfast:\n- Cereal with Milk: Cereal, Milk"
      this.textarea.setAttribute("data-placeholder-set", "true")
    }
  }
}
