import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["searchInput", "row", "filterButton", "countLabel"]

  connect() {
    this.currentFilter = "all"
    this.expandedRowId = null
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

  toggleRow(event) {
    if (event.target.closest("button, a")) return

    const row = event.currentTarget
    const expandId = `ingredient-expand-${row.dataset.ingredientName.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "")}`
    const expandRow = document.getElementById(expandId)
    if (!expandRow) return

    if (this.expandedRowId === expandId) {
      this.collapseRow(expandRow, row)
    } else {
      this.collapseCurrentRow()
      expandRow.hidden = false
      this.expandedRowId = expandId
      row.setAttribute("aria-expanded", "true")
    }
  }

  rowKeydown(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      this.toggleRow(event)
    }
  }

  // Private

  applyFilters() {
    const query = this.hasSearchInputTarget
      ? this.searchInputTarget.value.toLowerCase().trim()
      : ""
    let visible = 0
    const total = this.rowTargets.length

    this.rowTargets.forEach(row => {
      const name = (row.dataset.ingredientName || "").toLowerCase()
      const matchesSearch = !query || name.includes(query)
      const matchesFilter = this.matchesStatus(row.dataset.status)
      const show = matchesSearch && matchesFilter

      row.hidden = !show
      this.hideExpandRowWhenFiltered(row, show)
      if (show) visible++
    })

    if (this.hasCountLabelTarget) {
      this.countLabelTarget.textContent = `Showing ${visible} of ${total} ingredients`
    }
  }

  matchesStatus(status) {
    if (this.currentFilter === "all") return true
    if (this.currentFilter === "incomplete") return status !== "complete"
    if (this.currentFilter === "complete") return status === "complete"
    return true
  }

  hideExpandRowWhenFiltered(row, visible) {
    const expandId = this.expandIdFor(row)
    const expandRow = document.getElementById(expandId)
    if (!expandRow || visible) return

    expandRow.hidden = true
    if (this.expandedRowId === expandId) this.expandedRowId = null
  }

  collapseRow(expandRow, dataRow) {
    expandRow.hidden = true
    this.expandedRowId = null
    dataRow.removeAttribute("aria-expanded")
  }

  collapseCurrentRow() {
    if (!this.expandedRowId) return

    const prev = document.getElementById(this.expandedRowId)
    if (prev) {
      prev.hidden = true
      const prevDataRow = prev.previousElementSibling
      if (prevDataRow) prevDataRow.removeAttribute("aria-expanded")
    }
    this.expandedRowId = null
  }

  expandIdFor(row) {
    return `ingredient-expand-${row.dataset.ingredientName.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "")}`
  }
}
