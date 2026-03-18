/**
 * Manages the tag input field in the recipe editor side panel.
 * Renders existing tags as pills, provides autocomplete from the
 * kitchen's tag list, and exposes getters for recipe_editor_controller
 * to read during editor:collect and editor:modified events.
 *
 * - recipe_editor_controller: reads tags/modified getters during editor events
 * - editor_controller: dispatches editor:reset which triggers tag restoration
 * - SearchDataHelper: provides allTags data via embedded JSON attribute
 */
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pills", "input", "dropdown"]
  static values = {
    tags: { type: Array, default: [] },
    allTags: { type: Array, default: [] }
  }

  connect() {
    this.currentTags = [...this.tagsValue]
    this.originalTags = [...this.tagsValue]
    this.highlightedIndex = -1
    this.tagCounts = new Map(this.allTagsValue.map(([name, count]) => [name, count]))
    this.tagNames = this.allTagsValue.map(([name]) => name)
    this.loadSmartTags()
    this.renderPills()

    this.handleReset = () => { this.reset() }
    this.element.closest("[data-controller~='editor']")
      ?.addEventListener("editor:reset", this.handleReset)
  }

  disconnect() {
    this.element.closest("[data-controller~='editor']")
      ?.removeEventListener("editor:reset", this.handleReset)
  }

  get tags() { return [...this.currentTags] }

  get modified() {
    return JSON.stringify(this.currentTags.sort()) !== JSON.stringify(this.originalTags.sort())
  }

  loadSmartTags() {
    const el = document.querySelector('script[data-smart-tags]')
    this.smartTags = el ? JSON.parse(el.textContent) : null
  }

  loadTags(tags) {
    this.currentTags = [...tags]
    this.originalTags = [...tags]
    this.renderPills()
    this.inputTarget.value = ""
    this.hideDropdown()
  }

  reset() {
    this.currentTags = [...this.originalTags]
    this.renderPills()
    this.inputTarget.value = ""
    this.hideDropdown()
  }

  onInput() {
    const value = this.inputTarget.value.toLowerCase().replace(/[^a-z-]/g, "")
    if (value !== this.inputTarget.value) {
      this.inputTarget.value = value
    }
    this.showAutocomplete(value)
  }

  onKeydown(event) {
    if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault()
      if (this.highlightedIndex >= 0) {
        this.selectHighlighted()
      } else {
        this.addCurrentInput()
      }
    } else if (event.key === "ArrowDown") {
      event.preventDefault()
      this.moveHighlight(1)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.moveHighlight(-1)
    } else if (event.key === "Escape") {
      this.hideDropdown()
    } else if (event.key === "Backspace" && this.inputTarget.value === "") {
      this.currentTags.pop()
      this.renderPills()
    }
  }

  addCurrentInput() {
    const name = this.inputTarget.value.trim().toLowerCase()
    if (name && /^[a-z-]+$/.test(name) && !this.currentTags.includes(name)) {
      this.currentTags.push(name)
      this.renderPills()
    }
    this.inputTarget.value = ""
    this.hideDropdown()
  }

  addTag(name) {
    const lower = name.toLowerCase()
    if (!this.currentTags.includes(lower)) {
      this.currentTags.push(lower)
      this.renderPills()
    }
    this.inputTarget.value = ""
    this.hideDropdown()
    this.inputTarget.focus()
  }

  removeTag(index) {
    this.currentTags.splice(index, 1)
    this.renderPills()
  }

  renderPills() {
    this.pillsTarget.replaceChildren()
    this.currentTags.forEach((name, i) => {
      const pill = document.createElement("span")
      pill.className = "tag-pill tag-pill--tag"
      pill.textContent = name
      if (this.smartTags) {
        const entry = this.smartTags[name]
        if (entry) {
          pill.classList.add(`tag-pill--${entry.color}`)
          const icon = document.createElement("span")
          icon.className = "smart-icon"
          if (entry.style === "crossout") icon.classList.add("smart-icon--crossout")
          icon.textContent = entry.emoji
          pill.prepend(icon)
        }
      }

      const btn = document.createElement("button")
      btn.className = "tag-pill__remove"
      btn.textContent = "\u00d7"
      btn.type = "button"
      btn.addEventListener("click", () => this.removeTag(i))

      pill.appendChild(btn)
      this.pillsTarget.appendChild(pill)
    })
  }

  showAutocomplete(query) {
    if (!query) { this.hideDropdown(); return }

    const matches = this.tagNames
      .filter(t => t.startsWith(query) && !this.currentTags.includes(t))
      .slice(0, 8)

    if (matches.length === 0) { this.hideDropdown(); return }

    this.highlightedIndex = 0
    this.dropdownTarget.replaceChildren()

    matches.forEach((tag, i) => {
      const item = document.createElement("div")
      item.className = "tag-autocomplete__item"
      if (i === 0) item.classList.add("tag-autocomplete__item--highlighted")

      const nameSpan = document.createElement("span")
      nameSpan.textContent = tag
      if (this.smartTags) {
        const entry = this.smartTags[tag]
        if (entry) nameSpan.textContent = `${entry.emoji} ${tag}`
      }
      item.appendChild(nameSpan)

      const count = this.tagCounts.get(tag) || 0
      if (count > 0) {
        const countSpan = document.createElement("span")
        countSpan.className = "tag-autocomplete__count"
        countSpan.textContent = `${count} recipe${count === 1 ? "" : "s"}`
        item.appendChild(countSpan)
      }

      item.addEventListener("click", () => this.addTag(tag))
      this.dropdownTarget.appendChild(item)
    })

    this.dropdownTarget.hidden = false
    this.currentMatches = matches
  }

  hideDropdown() {
    this.dropdownTarget.hidden = true
    this.highlightedIndex = -1
    this.currentMatches = []
  }

  moveHighlight(direction) {
    if (!this.currentMatches?.length) return
    const items = this.dropdownTarget.querySelectorAll(".tag-autocomplete__item")
    if (this.highlightedIndex >= 0) {
      items[this.highlightedIndex]?.classList.remove("tag-autocomplete__item--highlighted")
    }
    this.highlightedIndex = Math.max(0, Math.min(this.currentMatches.length - 1,
      this.highlightedIndex + direction))
    items[this.highlightedIndex]?.classList.add("tag-autocomplete__item--highlighted")
  }

  selectHighlighted() {
    if (this.highlightedIndex >= 0 && this.currentMatches?.[this.highlightedIndex]) {
      this.addTag(this.currentMatches[this.highlightedIndex])
    }
  }
}
