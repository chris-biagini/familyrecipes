import { Controller } from "@hotwired/stimulus"

/**
 * Spotlight-style recipe search overlay. Opens on "/" keypress or nav button
 * click, searches a pre-embedded JSON blob client-side, and navigates to the
 * selected recipe on Enter/click. All DOM construction uses createElement/
 * textContent (no innerHTML) for CSP compliance.
 *
 * Collaborators:
 * - SearchDataHelper (server-side, provides the JSON data blob)
 * - shared/_search_overlay.html.erb (dialog markup and data script tag)
 * - application.js (turbo:before-cache closes open dialogs)
 */
export default class extends Controller {
  static targets = ["dialog", "input", "results", "data"]

  connect() {
    this.recipes = this.hasDataTarget
      ? JSON.parse(this.dataTarget.textContent || "[]")
      : []
    this.selectedIndex = -1
    this.boundKeydown = this.globalKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  open() {
    if (!this.hasDialogTarget || this.dialogTarget.open) return
    this.dialogTarget.showModal()
    this.inputTarget.value = ""
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
    const query = this.inputTarget.value.trim().toLowerCase()
    if (query.length < 2) {
      this.clearResults()
      return
    }

    const matches = this.rankResults(query)
    this.selectedIndex = -1
    this.renderResults(matches)
  }

  keydown(event) {
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

  rankResults(query) {
    const scored = []

    for (const recipe of this.recipes) {
      const tier = this.matchTier(recipe, query)
      if (tier < 4) scored.push({ recipe, tier })
    }

    scored.sort((a, b) => {
      if (a.tier !== b.tier) return a.tier - b.tier
      return a.recipe.title.localeCompare(b.recipe.title)
    })

    return scored.map(s => s.recipe)
  }

  matchTier(recipe, query) {
    if (recipe.title.toLowerCase().includes(query)) return 0
    if (recipe.description.toLowerCase().includes(query)) return 1
    if (recipe.category.toLowerCase().includes(query)) return 2
    if (recipe.ingredients.some(i => i.toLowerCase().includes(query))) return 3
    return 4
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
