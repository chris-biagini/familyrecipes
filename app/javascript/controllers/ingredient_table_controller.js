import { Controller } from "@hotwired/stimulus"

/**
 * Ingredients page table: client-side search filtering, status filtering
 * (all/complete/missing nutrition/missing density), sortable columns (name,
 * nutrition, density, aisle), and keyboard navigation for row activation.
 * Works entirely on DOM data attributes — no server calls.
 */
export default class extends Controller {
  static targets = ["searchInput", "row", "filterButton", "table"]

  connect() {
    this.currentFilter = "all"
    this.sortKey = "name"
    this.sortAsc = true
  }

  search() {
    this.applyFilters()
  }

  filter(event) {
    this.currentFilter = event.currentTarget.dataset.filter
    this.filterButtonTargets.forEach(btn => {
      const active = btn.dataset.filter === this.currentFilter
      btn.classList.toggle("active", active)
      btn.setAttribute("aria-pressed", active)
    })
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
    if (this.currentFilter === "all") return true
    if (this.currentFilter === "complete") return row.dataset.status === "complete"
    if (this.currentFilter === "missing_nutrition") return row.dataset.hasNutrition === "false"
    if (this.currentFilter === "missing_density") {
      return row.dataset.hasNutrition === "true" && row.dataset.hasDensity === "false"
    }
    return true
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
      case "nutrition":
        return row.dataset.hasNutrition === "true" ? 0 : 1
      case "density":
        return row.dataset.hasDensity === "true" ? 0 : 1
      case "aisle": {
        const aisle = (row.dataset.aisle || "").toLowerCase()
        return aisle || "\uffff"
      }
      default:
        return ""
    }
  }
}
