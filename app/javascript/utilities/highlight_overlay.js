/**
 * Transparent-textarea-over-pre overlay for syntax highlighting. Layers a
 * <pre> behind a transparent <textarea> so users see colored text while
 * typing into a real textarea. Handles scroll sync, cursor initialization,
 * auto-dash on Enter, and re-highlight when content loads asynchronously.
 *
 * Consumers provide a highlightFn(text) that returns a DocumentFragment
 * with styled spans. The overlay calls it on every input and content load.
 *
 * - quickbites_editor_controller: Quick Bites line classification
 * - recipe_editor_controller: recipe markdown line classification
 * - style.css (.hl-*): overlay positioning and highlight colors
 */
export default class HighlightOverlay {
  constructor(textarea, highlightFn) {
    this.textarea = textarea
    this.highlightFn = highlightFn
    this.overlay = null
    this.cursorInitialized = false
    this.bound = {}
  }

  attach() {
    this.buildOverlay()

    this.bound.input = () => this.highlight()
    this.bound.scroll = () => this.syncScroll()
    this.bound.keydown = (e) => this.handleKeydown(e)
    this.bound.focus = () => this.handleFocus()

    this.textarea.addEventListener("input", this.bound.input)
    this.textarea.addEventListener("scroll", this.bound.scroll)
    this.textarea.addEventListener("keydown", this.bound.keydown)
    this.textarea.addEventListener("focus", this.bound.focus)

    this.observer = new MutationObserver(() => {
      if (this.textarea.disabled) {
        this.cursorInitialized = false
      } else {
        this.highlight()
      }
    })
    this.observer.observe(this.textarea, { attributes: true, attributeFilter: ["disabled"] })

    this.highlight()
  }

  detach() {
    if (!this.textarea) return

    this.textarea.removeEventListener("input", this.bound.input)
    this.textarea.removeEventListener("scroll", this.bound.scroll)
    this.textarea.removeEventListener("keydown", this.bound.keydown)
    this.textarea.removeEventListener("focus", this.bound.focus)
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
    this.bound = {}
  }

  highlight() {
    const text = this.textarea.value
    if (!text) {
      this.overlay.replaceChildren()
      return
    }

    const fragment = this.highlightFn(text)
    if (text.endsWith("\n")) fragment.appendChild(document.createTextNode("\n"))

    this.overlay.replaceChildren(fragment)
  }

  // -- private ---------------------------------------------------------------

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

  syncScroll() {
    this.overlay.scrollTop = this.textarea.scrollTop
    this.overlay.scrollLeft = this.textarea.scrollLeft
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
}
