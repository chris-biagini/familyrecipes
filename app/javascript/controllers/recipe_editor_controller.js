import { Controller } from "@hotwired/stimulus"

/**
 * Syntax-highlighting overlay and auto-dash for the recipe markdown textarea.
 * Same transparent-textarea-over-pre technique as quickbites_editor_controller.
 * Classifies lines using patterns that mirror LineClassifier, with ingredient
 * lines split into name/qty/prep spans mirroring IngredientParser.
 *
 * - editor_controller: owns the dialog lifecycle; this controller is additive
 * - style.css (.hl-*): overlay positioning and highlight colors
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

    const wrapper = this.textarea.closest(".hl-wrap")
    if (wrapper?.parentNode) {
      this.textarea.classList.remove("hl-input")
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
    wrapper.classList.add("hl-wrap")

    this.overlay = document.createElement("pre")
    this.overlay.classList.add("hl-overlay")
    this.overlay.setAttribute("aria-hidden", "true")

    this.textarea.parentNode.insertBefore(wrapper, this.textarea)
    wrapper.appendChild(this.overlay)
    wrapper.appendChild(this.textarea)
    this.textarea.classList.add("hl-input")
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
      this.classifyLine(line, fragment)
    })

    if (text.endsWith("\n")) fragment.appendChild(document.createTextNode("\n"))

    this.overlay.replaceChildren(fragment)
  }

  classifyLine(line, fragment) {
    if (/^# .+$/.test(line)) {
      this.appendSpan(fragment, line, "hl-title")
    } else if (/^## .+$/.test(line)) {
      this.appendSpan(fragment, line, "hl-step-header")
    } else if (/^- .+$/.test(line)) {
      this.highlightIngredient(line, fragment)
    } else if (/^>>>\s+.+$/.test(line)) {
      this.appendSpan(fragment, line, "hl-cross-ref")
    } else if (/^---\s*$/.test(line)) {
      this.appendSpan(fragment, line, "hl-divider")
    } else if (/^(Category|Makes|Serves):\s+.+$/.test(line)) {
      this.appendSpan(fragment, line, "hl-front-matter")
    } else {
      fragment.appendChild(document.createTextNode(line))
    }
  }

  highlightIngredient(line, fragment) {
    // Mirror IngredientParser: split on first ":" for prep note,
    // then first "," on left side for quantity
    const colonIdx = line.indexOf(":", 2)
    let left = colonIdx !== -1 ? line.slice(0, colonIdx) : line
    const prep = colonIdx !== -1 ? line.slice(colonIdx) : null

    const commaIdx = left.indexOf(",", 2)
    const name = commaIdx !== -1 ? left.slice(0, commaIdx) : left
    const qty = commaIdx !== -1 ? left.slice(commaIdx) : null

    this.appendSpan(fragment, name, "hl-ingredient-name")
    if (qty) this.appendSpan(fragment, qty, "hl-ingredient-qty")
    if (prep) this.appendSpan(fragment, prep, "hl-ingredient-prep")
  }

  appendSpan(fragment, text, className) {
    const span = document.createElement("span")
    span.classList.add(className)
    span.textContent = text
    fragment.appendChild(span)
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
      this.textarea.placeholder = [
        "# Recipe Title",
        "",
        "Category: Dinner",
        "Serves: 4",
        "",
        "## First step.",
        "",
        "- Ingredient one, 1 cup: diced",
        "- Ingredient two",
        "",
        "Instructions for this step.",
        "",
        "## Second step.",
        "",
        "- More ingredients",
        "",
        "More instructions."
      ].join("\n")
      this.textarea.setAttribute("data-placeholder-set", "true")
    }
  }
}
