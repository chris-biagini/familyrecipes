import { Controller } from "@hotwired/stimulus"
import HighlightOverlay from "utilities/highlight_overlay"

/**
 * Syntax-highlighting overlay and category dropdown for the recipe markdown
 * textarea. Delegates overlay lifecycle, auto-dash, and scroll sync to
 * HighlightOverlay. This controller provides recipe-specific line
 * classification (titles, steps, ingredients, cross-refs, front matter) and
 * participates in editor:collect/editor:modified events to include category
 * in the save payload and dirty checking.
 *
 * - editor_controller: owns the dialog lifecycle; this controller is additive
 * - highlight_overlay: overlay positioning, auto-dash, scroll sync
 * - style.css (.hl-*): highlight colors
 */
export default class extends Controller {
  static targets = ["textarea", "categorySelect", "categoryInput"]

  connect() {
    this.boundCollect = (e) => this.handleCollect(e)
    this.boundModified = (e) => this.handleModified(e)
    this.element.addEventListener("editor:collect", this.boundCollect)
    this.element.addEventListener("editor:modified", this.boundModified)
  }

  disconnect() {
    this.hlOverlay?.detach()
    this.hlOverlay = null
    if (this.boundCollect) this.element.removeEventListener("editor:collect", this.boundCollect)
    if (this.boundModified) this.element.removeEventListener("editor:modified", this.boundModified)
  }

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

  buildFragment(text) {
    const fragment = document.createDocumentFragment()
    this.inFooter = false

    text.split("\n").forEach((line, i) => {
      if (i > 0) fragment.appendChild(document.createTextNode("\n"))
      this.classifyLine(line, fragment)
    })

    return fragment
  }

  classifyLine(line, fragment) {
    if (/^# .+$/.test(line)) {
      this.appendSpan(fragment, line, "hl-title")
    } else if (/^## .+$/.test(line)) {
      this.appendSpan(fragment, line, "hl-step-header")
    } else if (/^- .+$/.test(line)) {
      this.highlightIngredient(line, fragment)
    } else if (/^>\s*@\[.+$/.test(line)) {
      this.appendSpan(fragment, line, "hl-cross-ref")
    } else if (/^---\s*$/.test(line)) {
      this.inFooter = true
      this.appendSpan(fragment, line, "hl-divider")
    } else if (/^(Makes|Serves):\s+.+$/.test(line)) {
      this.appendSpan(fragment, line, "hl-front-matter")
    } else if (this.inFooter) {
      this.appendSpan(fragment, line, "hl-front-matter")
    } else {
      this.highlightProseLinks(line, fragment)
    }
  }

  highlightIngredient(line, fragment) {
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

  highlightProseLinks(line, fragment) {
    const pattern = /@\[(.+?)\]/g
    let lastIndex = 0
    let match

    while ((match = pattern.exec(line)) !== null) {
      if (match.index > lastIndex) {
        fragment.appendChild(document.createTextNode(line.slice(lastIndex, match.index)))
      }
      this.appendSpan(fragment, match[0], "hl-recipe-link")
      lastIndex = pattern.lastIndex
    }

    if (lastIndex < line.length) {
      fragment.appendChild(document.createTextNode(line.slice(lastIndex)))
    } else if (lastIndex === 0) {
      fragment.appendChild(document.createTextNode(line))
    }
  }

  appendSpan(fragment, text, className) {
    const span = document.createElement("span")
    span.classList.add(className)
    span.textContent = text
    fragment.appendChild(span)
  }

  handleCollect(event) {
    event.detail.handled = true
    event.detail.data = {
      markdown_source: this.hasTextareaTarget ? this.textareaTarget.value : null,
      category: this.selectedCategory()
    }
  }

  handleModified(event) {
    if (this.hasCategorySelectTarget && this.originalCategory !== undefined) {
      if (this.selectedCategory() !== this.originalCategory) {
        event.detail.handled = true
        event.detail.modified = true
      }
    }
  }

  selectedCategory() {
    if (!this.hasCategorySelectTarget) return null
    const val = this.categorySelectTarget.value
    if (val === "__new__") {
      return this.hasCategoryInputTarget ? this.categoryInputTarget.value.trim() : null
    }
    return val
  }

  categorySelectTargetConnected(element) {
    this.originalCategory = element.value
    element.addEventListener("change", () => this.handleCategoryChange())
  }

  handleCategoryChange() {
    if (!this.hasCategorySelectTarget || !this.hasCategoryInputTarget) return
    if (this.categorySelectTarget.value === "__new__") {
      this.categoryInputTarget.hidden = false
      this.categorySelectTarget.hidden = true
      this.categoryInputTarget.focus()
    }
  }

  categoryInputTargetConnected(element) {
    element.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        this.categoryInputTarget.hidden = true
        this.categorySelectTarget.hidden = false
        this.categorySelectTarget.value = this.originalCategory
      }
    })
  }

  setPlaceholder(textarea) {
    if (!textarea.getAttribute("data-placeholder-set")) {
      textarea.placeholder = [
        "# Recipe Title",
        "",
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
      textarea.setAttribute("data-placeholder-set", "true")
    }
  }
}
