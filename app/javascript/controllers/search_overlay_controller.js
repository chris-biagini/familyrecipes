import { Controller } from "@hotwired/stimulus"
import { loadSmartTagData } from "../utilities/search_data"
import ListenerManager from "../utilities/listener_manager"
import { matchTier } from "../utilities/search_match"

function normalizeForSearch(str) {
  return (str || "")
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/[\u201C\u201D]/g, '"')
}

/**
 * Spotlight-style recipe search overlay with pill-based tag/category filtering.
 * Opens on "/" keypress or nav button click, searches a pre-embedded JSON blob
 * client-side, and navigates to the selected recipe on Enter/click. Typing a
 * known tag or category name followed by space converts it to a filter pill.
 * All DOM construction uses createElement/textContent (no innerHTML) for CSP.
 *
 * Collaborators:
 * - SearchDataHelper (server-side, provides the JSON data blob)
 * - shared/_search_overlay.html.erb (dialog markup and data script tag)
 * - application.js (turbo:before-cache closes open dialogs)
 * - ListenerManager: clean event listener teardown
 */
export default class extends Controller {
  static targets = ["dialog", "input", "results", "data", "pillArea", "inputWrapper"]

  connect() {
    this.loadData()
    this.loadSmartTags()
    this.activePills = []
    this.selectedIndex = -1
    this.listeners = new ListenerManager()
    this.listeners.add(document, "keydown", this.globalKeydown.bind(this))
    this.listeners.add(document, "turbo:morph", () => this.loadData())
  }

  disconnect() {
    this.listeners.teardown()
  }

  loadSmartTags() {
    const data = loadSmartTagData()
    this.smartTags = Object.keys(data).length > 0 ? data : null
  }

  loadData() {
    const data = this.hasDataTarget
      ? JSON.parse(this.dataTarget.textContent || "{}")
      : {}
    this.recipes = (data.recipes || []).map(r => ({
      ...r,
      _title: normalizeForSearch(r.title).toLowerCase(),
      _description: normalizeForSearch(r.description).toLowerCase(),
      _ingredients: r.ingredients.map(i => normalizeForSearch(i).toLowerCase()),
      _tags: r.tags?.map(t => normalizeForSearch(t).toLowerCase()),
      _category: normalizeForSearch(r.category).toLowerCase()
    }))
    this.allTags = new Set((data.all_tags || []).map(t => normalizeForSearch(t).toLowerCase()))
    this.allCategories = new Set((data.all_categories || []).map(c => normalizeForSearch(c).toLowerCase()))
  }

  open() {
    if (!this.hasDialogTarget || this.dialogTarget.open) return
    this.dialogTarget.showModal()
    this.inputTarget.value = ""
    this.activePills = []
    this.renderPills()
    this.clearResults()
    this.inputTarget.focus()
  }

  close() {
    this.dialogTarget.close()
  }

  backdropClick(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  search() {
    this.checkForPillConversion()
    this.updateHint()
    this.performSearch()
  }

  keydown(event) {
    if (event.key === "Backspace" && this.inputTarget.value === "" && this.activePills.length > 0) {
      const last = this.activePills.pop()
      this.inputTarget.value = last.text
      this.renderPills()
      event.preventDefault()
      return
    }

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.moveSelection(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.moveSelection(-1)
        break
      case "Enter":
        event.preventDefault()
        this.selectCurrent()
        break
    }
  }

  openWithTag(tagName) {
    this.open()
    this.addPill(tagName, "tag")
    this.inputTarget.value = ""
    this.performSearch()
  }

  // Private

  globalKeydown(event) {
    if (event.key !== "/") return
    if (this.hasDialogTarget && this.dialogTarget.open) return
    if (this.insideInput(event.target)) return
    if (document.querySelector("dialog[open]")) return

    event.preventDefault()
    this.open()
  }

  insideInput(element) {
    const tag = element.tagName
    return tag === "INPUT" || tag === "TEXTAREA" || element.isContentEditable
  }

  checkForPillConversion() {
    const value = this.inputTarget.value
    const word = value.trimEnd()
    if (!word || value.slice(-1) !== " ") return

    const lower = normalizeForSearch(word).toLowerCase()
    const type = this.allTags.has(lower) ? "tag" : this.allCategories.has(lower) ? "category" : null
    if (!type) return

    this.addPill(word, type)
    this.inputTarget.value = ""
  }

  addPill(text, type) {
    const lower = text.toLowerCase()
    if (this.activePills.some(p => p.text === lower)) return

    this.activePills.push({ text: lower, type })
    this.renderPills()
    this.performSearch()
  }

  removePill(index) {
    this.activePills.splice(index, 1)
    this.renderPills()
    this.performSearch()
    this.inputTarget.focus()
  }

  renderPills() {
    this.pillAreaTarget.replaceChildren()

    this.activePills.forEach((pill, index) => {
      const span = document.createElement("span")
      span.className = `tag-pill tag-pill--${pill.type}`
      span.textContent = pill.text
      if (this.smartTags && pill.type === "tag") {
        const entry = this.smartTags[pill.text]
        if (entry) {
          span.classList.add(`tag-pill--${entry.color}`)
          const icon = document.createElement("span")
          icon.className = "smart-icon"
          if (entry.style === "crossout") icon.classList.add("smart-icon--crossout")
          icon.textContent = entry.emoji
          span.prepend(icon)
        }
      }

      const btn = document.createElement("button")
      btn.className = "tag-pill__remove"
      btn.textContent = "\u00d7"
      btn.type = "button"
      btn.addEventListener("click", () => this.removePill(index))

      span.appendChild(btn)
      this.pillAreaTarget.appendChild(span)
    })
  }

  updateHint() {
    const word = normalizeForSearch(this.inputTarget.value).trim().toLowerCase()
    const matches = word && (this.allTags.has(word) || this.allCategories.has(word))
    this.inputTarget.classList.toggle("search-input--hinted", matches)
  }

  performSearch() {
    const query = normalizeForSearch(this.inputTarget.value).toLowerCase().trim()
    if (!query && this.activePills.length === 0) {
      this.resultsTarget.replaceChildren()
      this.selectedIndex = -1
      return
    }

    let candidates = this.recipes
    for (const pill of this.activePills) {
      candidates = candidates.filter(r => this.matchesPill(r, pill))
    }

    const tokens = query ? query.split(/\s+/).filter(Boolean) : []
    const results = tokens.length ? this.rankResults(tokens, candidates) : candidates
    this.renderResults(results)
    this.selectFirst()
  }

  matchesPill(recipe, pill) {
    const text = pill.text
    if (pill.type === "tag") {
      return recipe._tags?.some(t => t === text) || this.textContains(recipe, text)
    }
    if (pill.type === "category") {
      return recipe._category === text || this.textContains(recipe, text)
    }
    return false
  }

  textContains(recipe, text) {
    return recipe._title.includes(text) ||
      recipe._description.includes(text) ||
      recipe._ingredients.some(i => i.includes(text))
  }

  rankResults(tokens, candidates = this.recipes) {
    const scored = []

    for (const recipe of candidates) {
      const tier = matchTier(recipe, tokens)
      if (tier < 5) scored.push({ recipe, tier })
    }

    scored.sort((a, b) => {
      if (a.tier !== b.tier) return a.tier - b.tier
      return a.recipe.title.localeCompare(b.recipe.title)
    })

    return scored.map(s => s.recipe)
  }

  renderResults(recipes) {
    this.clearResults()
    const list = this.resultsTarget

    if (recipes.length === 0) {
      const li = document.createElement("li")
      li.className = "search-no-results"
      li.textContent = "No matches"
      li.setAttribute("role", "option")
      list.appendChild(li)
      return
    }

    recipes.forEach((recipe, index) => {
      const li = document.createElement("li")
      li.className = "search-result"
      li.setAttribute("role", "option")
      li.dataset.index = index
      li.dataset.slug = recipe.slug

      const title = document.createElement("span")
      title.className = "search-result-title"
      title.textContent = recipe.title

      const category = document.createElement("span")
      category.className = "search-result-category"
      category.textContent = recipe.category

      li.appendChild(title)
      li.appendChild(category)
      li.addEventListener("click", () => this.navigateTo(recipe.slug))
      list.appendChild(li)
    })
  }

  clearResults() {
    this.resultsTarget.replaceChildren()
    this.selectedIndex = -1
  }

  selectFirst() {
    const first = this.resultsTarget.querySelector(".search-result")
    if (!first) return

    this.selectedIndex = 0
    first.classList.add("selected")
  }

  moveSelection(delta) {
    const items = this.resultsTarget.querySelectorAll(".search-result")
    if (items.length === 0) return

    if (this.selectedIndex >= 0 && this.selectedIndex < items.length) {
      items[this.selectedIndex].classList.remove("selected")
    }

    this.selectedIndex += delta
    if (this.selectedIndex < 0) this.selectedIndex = items.length - 1
    if (this.selectedIndex >= items.length) this.selectedIndex = 0

    items[this.selectedIndex].classList.add("selected")
    items[this.selectedIndex].scrollIntoView({ block: "nearest" })
  }

  selectCurrent() {
    const items = this.resultsTarget.querySelectorAll(".search-result")
    const index = this.selectedIndex >= 0 ? this.selectedIndex : 0
    if (items.length === 0) return

    this.navigateTo(items[index].dataset.slug)
  }

  navigateTo(slug) {
    this.close()
    const base = this.element.dataset.searchOverlayBasePath || ""
    Turbo.visit(`${base}/recipes/${slug}`)
  }
}
