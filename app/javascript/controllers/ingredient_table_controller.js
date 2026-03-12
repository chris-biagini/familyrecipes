import { Controller } from "@hotwired/stimulus"

/**
 * Ingredients page table: client-side search filtering, status filtering
 * (all/complete/custom/no aisle/no nutrition/no density), sortable columns
 * (name, aisle, recipes), and keyboard navigation for row activation.
 * Works entirely on DOM data attributes — no server calls.
 *
 * Persists sort order, active filter pill, and search text to sessionStorage
 * so state survives page reloads, Turbo visits, and broadcast morphs.
 */
export default class extends Controller {
  static targets = ["searchInput", "row", "filterButton", "table"]

  connect() {
    this.currentFilter = sessionStorage.getItem("ingredients:filter") || "all"
    this.sortKey = sessionStorage.getItem("ingredients:sortKey") || "name"
    this.sortAsc = sessionStorage.getItem("ingredients:sortAsc") !== "false"

    this.restore()

    this.boundRestore = () => this.restore()
    document.addEventListener("turbo:morph", this.boundRestore)
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.boundRestore)
  }

  search() {
    sessionStorage.setItem("ingredients:search", this.searchInputTarget.value)
    this.applyFilters()
  }

  filter(event) {
    this.currentFilter = event.currentTarget.dataset.filter
    sessionStorage.setItem("ingredients:filter", this.currentFilter)
    this.restoreFilter()
    this.applyFilters()
  }

  sort(event) {
    const key = event.currentTarget.dataset.sortKey
    if (this.sortKey === key) {
      this.sortAsc = !this.sortAsc
    } else {
      this.sortKey = key
      this.sortAsc = true
    }

    sessionStorage.setItem("ingredients:sortKey", this.sortKey)
    sessionStorage.setItem("ingredients:sortAsc", this.sortAsc)
    this.updateSortIndicators()
    this.sortRows()
  }

  openEditor(event) {
    if (event.target.closest("a")) return
  }

  rowKeydown(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      event.currentTarget.click()
    }
  }

  // Private

  restore() {
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.value = sessionStorage.getItem("ingredients:search") || ""
    }
    this.restoreFilter()
    this.updateSortIndicators()
    this.sortRows()
    this.applyFilters()
  }

  restoreFilter() {
    this.filterButtonTargets.forEach(btn => {
      const active = btn.dataset.filter === this.currentFilter
      btn.classList.toggle("active", active)
      btn.setAttribute("aria-pressed", active)
    })
  }

  applyFilters() {
    const query = this.hasSearchInputTarget
      ? this.searchInputTarget.value.toLowerCase().trim()
      : ""

    this.rowTargets.forEach(row => {
      const name = (row.dataset.ingredientName || "").toLowerCase()
      const matchesSearch = !query || name.includes(query)
      const matchesFilter = this.matchesStatus(row)
      row.closest("tbody").hidden = !(matchesSearch && matchesFilter)
    })
  }

  matchesStatus(row) {
    switch (this.currentFilter) {
      case "all": return true
      case "complete": return row.dataset.status === "complete"
      case "custom": return row.dataset.source === "custom"
      case "no_aisle": return !row.dataset.aisle
      case "no_nutrition": return row.dataset.hasNutrition === "false"
      case "no_density": return row.dataset.hasDensity === "false"
      case "not_resolvable": return row.dataset.resolvable === "false"
      default: return true
    }
  }

  updateSortIndicators() {
    this.element.querySelectorAll("th.sortable").forEach(th => {
      const arrow = th.querySelector(".sort-arrow")
      if (th.dataset.sortKey === this.sortKey) {
        th.setAttribute("aria-sort", this.sortAsc ? "ascending" : "descending")
        arrow.textContent = this.sortAsc ? " \u25B2" : " \u25BC"
      } else {
        th.removeAttribute("aria-sort")
        arrow.textContent = ""
      }
    })
  }

  sortRows() {
    const table = this.tableTarget
    const bodies = Array.from(table.querySelectorAll("tbody"))

    bodies.sort((a, b) => {
      const rowA = a.querySelector("tr")
      const rowB = b.querySelector("tr")
      const cmp = this.compareSortValues(rowA, rowB)
      return this.sortAsc ? cmp : -cmp
    })

    bodies.forEach(tb => table.appendChild(tb))
  }

  compareSortValues(rowA, rowB) {
    const valA = this.sortValue(rowA)
    const valB = this.sortValue(rowB)

    if (typeof valA === "string") return valA.localeCompare(valB)
    return valA - valB
  }

  sortValue(row) {
    switch (this.sortKey) {
      case "name":
        return (row.dataset.ingredientName || "").toLowerCase()
      case "aisle": {
        const aisle = (row.dataset.aisle || "").toLowerCase()
        return aisle || "\uffff"
      }
      case "recipes":
        return parseInt(row.dataset.recipeCount, 10) || 0
      default:
        return ""
    }
  }
}
