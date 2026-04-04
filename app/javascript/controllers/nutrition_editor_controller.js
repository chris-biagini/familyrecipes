import { Controller } from "@hotwired/stimulus"
import { getCsrfToken, saveRequest } from "../utilities/editor_utils"
import ListenerManager from "../utilities/listener_manager"

const VOLUME_TO_ML = {
  tsp: 4.929, tbsp: 14.787, 'fl oz': 29.5735,
  cup: 236.588, pt: 473.176, qt: 946.353,
  gal: 3785.41, ml: 1, l: 1000
}

/**
 * Companion controller for the nutrition editor dialog. Hooks into the shared
 * editor controller's lifecycle events to provide custom data collection,
 * validation, save logic, and dirty detection. Manages the structured form
 * (nutrients, density, portions, aisle, aliases) loaded via Turbo Frame.
 *
 * - editor_controller: dialog lifecycle (open/close, save button state, errors, beforeunload)
 * - editor_utils: CSRF tokens
 * - NutritionEntriesController: JSON save endpoint and Turbo Frame edit partial
 * - CatalogWriteService (server): orchestrates upsert, aisle sync, and broadcast
 * - ListenerManager: clean event listener teardown
 */
export default class extends Controller {
  static targets = [
    "formContent",
    "basisGrams", "nutrientField",
    "densityVolume", "densityUnit", "densityGrams",
    "portionList", "portionRow", "portionName", "portionGrams",
    "aisleSelect", "aisleInput", "omitCheckbox",
    "aliasList", "aliasInput", "aliasChip", "aliasHint",
    "nutrientSummary", "nutrientDetail",
    "usdaPanel", "usdaQuery", "usdaResults", "usdaSearchBtn",
    "densityCandidates", "densityCandidateList"
  ]

  static values = {
    baseUrl: String,
    editUrl: String,
    usdaSearchUrl: String,
    usdaShowUrl: String
  }

  connect() {
    this.currentIngredient = null
    this.originalSnapshot = null
    this.listeners = new ListenerManager()

    this.listeners.add(document, "click", (event) => {
      const btn = event.target.closest("[data-open-editor]")
      if (btn) this.openForIngredient(btn)
    })
    this.listeners.add(document, "click", (event) => {
      const btn = event.target.closest("[data-reset-ingredient]")
      if (btn) this.resetIngredient(btn)
    })
    this.listeners.add(document, "pointerenter", (event) => {
      if (!event.target.closest) return
      const row = event.target.closest("[data-open-editor]")
      if (row) this.prefetch(row.dataset.ingredientName)
    }, true)

    this.listeners.add(this.turboFrame, "turbo:frame-load", () => this.onFrameLoad())
    this.listeners.add(this.element, "editor:collect", (e) => this.handleCollect(e))
    this.listeners.add(this.element, "editor:save", (e) => this.handleSave(e))
    this.listeners.add(this.element, "editor:modified", (e) => this.handleModified(e))
    this.listeners.add(this.element, "editor:reset", (e) => this.handleReset(e))
  }

  disconnect() {
    this.listeners.teardown()
  }

  // Open flow

  openForIngredient(btn) {
    const name = btn.dataset.ingredientName
    this.currentIngredient = name
    this.element.querySelector(".editor-header h2").textContent = `Edit ${name}`

    this.turboFrame.src = this.editUrlFor(name)
    this.editorController.open()
  }

  prefetch(name) {
    if (this.prefetchedName === name) return

    this.prefetchedName = name
    fetch(this.editUrlFor(name), { headers: { Accept: "text/html" } }).catch(() => {})
  }

  // Editor lifecycle event handlers

  handleCollect(event) {
    event.detail.handled = true
    event.detail.data = this.collectFormData()
  }

  handleSave(event) {
    const data = event.detail.data
    event.detail.handled = true
    event.detail.saveFn = async () => {
      const errors = this.validateForm(data)
      if (errors.length > 0) {
        return new Response(JSON.stringify({ errors }), {
          status: 422,
          headers: { "Content-Type": "application/json" }
        })
      }
      return saveRequest(this.nutritionUrl(this.currentIngredient), "POST", data)
    }
  }

  handleModified(event) {
    event.detail.handled = true
    event.detail.modified = this.originalSnapshot !== null &&
      JSON.stringify(this.collectFormData()) !== this.originalSnapshot
  }

  handleReset(event) {
    event.detail.handled = true
    this.currentIngredient = null
    this.originalSnapshot = null
    if (this.hasUsdaResultsTarget) {
      this.usdaResultsTarget.hidden = true
      this.usdaResultsTarget.replaceChildren()
    }
    if (this.hasDensityCandidatesTarget) this.densityCandidatesTarget.hidden = true
  }

  // Nutrient summary updates

  updateNutrientSummary() {
    if (!this.hasNutrientSummaryTarget) return

    const basis = this.basisGramsTarget.value || "\u2014"
    const cal = this.findNutrientValue("calories") || "\u2014"
    const fat = this.findNutrientValue("fat") || "\u2014"
    const carbs = this.findNutrientValue("carbs") || "\u2014"
    const protein = this.findNutrientValue("protein") || "\u2014"

    const summary = this.nutrientSummaryTarget
    summary.replaceChildren()

    const items = [
      { label: "", value: cal, unit: "cal" },
      { label: "", value: fat, unit: "g fat" },
      { label: "", value: carbs, unit: "g carbs" },
      { label: "", value: protein, unit: "g protein" },
      { label: "per ", value: basis, unit: "g" }
    ]
    items.forEach(({ label, value, unit }) => {
      const span = document.createElement("span")
      if (label) span.appendChild(document.createTextNode(label))
      const strong = document.createElement("strong")
      strong.textContent = value
      span.appendChild(strong)
      span.appendChild(document.createTextNode(` ${unit}`))
      summary.appendChild(span)
    })
  }

  findNutrientValue(key) {
    const field = this.nutrientFieldTargets.find(
      f => f.dataset.nutrientKey === key
    )
    return field?.value || null
  }

  // Form interactions

  addPortion() {
    const row = document.createElement("div")
    row.className = "editor-portion-row"
    row.setAttribute("data-nutrition-editor-target", "portionRow")

    const nameInput = document.createElement("input")
    nameInput.type = "text"
    nameInput.className = "input-base"
    nameInput.placeholder = "e.g. stick, slice, each"
    nameInput.setAttribute("data-nutrition-editor-target", "portionName")
    nameInput.setAttribute("aria-label", "Portion name")

    const eqSpan = document.createElement("span")
    eqSpan.className = "editor-portion-eq"
    eqSpan.textContent = "="

    const gramsInput = document.createElement("input")
    gramsInput.type = "number"
    gramsInput.className = "input-base input-sm"
    gramsInput.inputMode = "decimal"
    gramsInput.step = "any"
    gramsInput.min = "0"
    gramsInput.setAttribute("data-nutrition-editor-target", "portionGrams")
    gramsInput.setAttribute("aria-label", "Portion grams")

    const unitSpan = document.createElement("span")
    unitSpan.className = "editor-portion-unit"
    unitSpan.textContent = "g"

    const removeBtn = document.createElement("button")
    removeBtn.type = "button"
    removeBtn.className = "editor-btn-icon"
    removeBtn.setAttribute("aria-label", "Remove portion")
    removeBtn.setAttribute("data-action", "click->nutrition-editor#removePortion")
    removeBtn.textContent = "\u00d7"

    row.appendChild(nameInput)
    row.appendChild(eqSpan)
    row.appendChild(gramsInput)
    row.appendChild(unitSpan)
    row.appendChild(removeBtn)

    this.portionListTarget.appendChild(row)
    nameInput.focus()
  }

  removePortion(event) {
    event.currentTarget.closest(".editor-portion-row").remove()
  }

  addAlias() {
    const name = this.aliasInputTarget.value.trim()
    if (!name) return

    if (this.collectAliases().includes(name)) {
      this.aliasInputTarget.value = ""
      return
    }

    if (this.hasAliasHintTarget) this.aliasHintTarget.hidden = true

    const chip = document.createElement("span")
    chip.className = "editor-alias-chip"
    chip.setAttribute("data-nutrition-editor-target", "aliasChip")

    const text = document.createElement("span")
    text.className = "alias-chip-text"
    text.textContent = name

    const removeBtn = document.createElement("button")
    removeBtn.type = "button"
    removeBtn.className = "editor-alias-remove"
    removeBtn.setAttribute("aria-label", "Remove alias")
    removeBtn.setAttribute("data-action", "click->nutrition-editor#removeAlias")
    removeBtn.textContent = "\u00d7"

    chip.appendChild(text)
    chip.appendChild(removeBtn)
    this.aliasListTarget.appendChild(chip)
    this.aliasInputTarget.value = ""
    this.aliasInputTarget.focus()
  }

  removeAlias(event) {
    event.currentTarget.closest(".editor-alias-chip").remove()
    if (this.hasAliasHintTarget && this.aliasChipTargets.length === 0) {
      this.aliasHintTarget.hidden = false
    }
  }

  aliasInputKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.addAlias()
    }
  }

  aisleChanged() {
    if (this.aisleSelectTarget.value === "__other__") {
      this.aisleInputTarget.hidden = false
      this.aisleInputTarget.value = ""
      this.aisleInputTarget.focus()
    } else {
      this.aisleInputTarget.hidden = true
      this.aisleInputTarget.value = ""
    }
  }

  aisleInputKeydown(event) {
    if (event.key !== "Escape") return

    event.preventDefault()
    event.stopPropagation()
    this.aisleInputTarget.hidden = true
    this.aisleInputTarget.value = ""
    this.aisleSelectTarget.value = this.originalAisle || ""
  }

  async resetIngredient(btn) {
    const name = btn.dataset.ingredientName
    if (!confirm(`Reset "${name}" to built-in nutrition data?`)) return

    btn.disabled = true
    try {
      const response = await fetch(this.nutritionUrl(name), {
        method: "DELETE",
        headers: { "X-CSRF-Token": getCsrfToken() }
      })

      if (response.ok) {
        window.location.reload()
      } else {
        btn.disabled = false
      }
    } catch {
      btn.disabled = false
    }
  }

  // USDA search

  async usdaSearch() {
    const query = this.usdaQueryTarget.value.trim()
    if (!query) return

    this.usdaSearchBtnTarget.disabled = true
    this.usdaSearchBtnTarget.textContent = "Searching\u2026"
    this.usdaResultsTarget.hidden = false
    this.usdaResultsTarget.replaceChildren()
    this.lastImportedItem = null
    this.usdaCurrentPage = 0

    try {
      await this.fetchUsdaPage(query, 0)
    } finally {
      this.usdaSearchBtnTarget.disabled = false
      this.usdaSearchBtnTarget.textContent = "Search"
    }
  }

  usdaSearchKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.usdaSearch()
    }
  }

  async fetchUsdaPage(query, page) {
    const url = `${this.usdaSearchUrlValue}?q=${encodeURIComponent(query)}&page=${page}`
    const response = await fetch(url, {
      headers: { "Accept": "application/json", "X-CSRF-Token": getCsrfToken() }
    })

    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      this.showUsdaError(data.error || "Search failed")
      return
    }

    const data = await response.json()

    if (data.foods.length === 0 && page === 0) {
      const msg = document.createElement("div")
      msg.className = "usda-no-results"
      msg.textContent = "No results found"
      this.usdaResultsTarget.replaceChildren(msg)
      return
    }

    const moreBtn = this.usdaResultsTarget.querySelector(".usda-more-btn")
    if (moreBtn) moreBtn.remove()

    data.foods.forEach(food => {
      this.usdaResultsTarget.appendChild(this.buildResultItem(food))
    })

    if (data.current_page + 1 < data.total_pages) {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "usda-more-btn"
      btn.textContent = "More results\u2026"
      btn.addEventListener("click", () => {
        btn.disabled = true
        btn.textContent = "Loading\u2026"
        this.fetchUsdaPage(query, page + 1)
      })
      this.usdaResultsTarget.appendChild(btn)
    }
  }

  buildResultItem(food) {
    const item = document.createElement("div")
    item.className = "usda-result-item"

    const info = document.createElement("div")
    info.className = "usda-result-info"

    const name = document.createElement("div")
    name.className = "usda-result-name"
    name.textContent = food.description

    const meta = document.createElement("div")
    meta.className = "usda-result-nutrients"
    meta.textContent = food.nutrient_summary

    info.appendChild(name)
    info.appendChild(meta)

    const btn = document.createElement("button")
    btn.type = "button"
    btn.className = "usda-import-btn"
    btn.setAttribute("aria-label", `Import ${food.description}`)
    btn.appendChild(this.buildDownloadIcon())
    btn.addEventListener("click", () => this.importUsdaResult(food.fdc_id, item))

    item.appendChild(info)
    item.appendChild(btn)

    return item
  }

  buildDownloadIcon() {
    const ns = "http://www.w3.org/2000/svg"
    const svg = document.createElementNS(ns, "svg")
    svg.setAttribute("viewBox", "0 0 20 20")
    svg.setAttribute("fill", "currentColor")

    const arrow = document.createElementNS(ns, "path")
    arrow.setAttribute("d", "M10 3a1 1 0 0 1 1 1v7.586l2.293-2.293a1 1 0 1 1 1.414 1.414l-4 4a1 1 0 0 1-1.414 0l-4-4a1 1 0 1 1 1.414-1.414L9 11.586V4a1 1 0 0 1 1-1z")

    const tray = document.createElementNS(ns, "path")
    tray.setAttribute("d", "M4 14a1 1 0 0 1 1 1v1h10v-1a1 1 0 1 1 2 0v1a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-1a1 1 0 0 1 1-1z")

    svg.appendChild(arrow)
    svg.appendChild(tray)
    return svg
  }

  showUsdaError(message) {
    const div = document.createElement("div")
    div.className = "usda-error"
    div.textContent = message === "no_api_key"
      ? "No USDA API key configured. Add one in Settings."
      : message
    this.usdaResultsTarget.replaceChildren(div)
  }

  async importUsdaResult(fdcId, item) {
    item.classList.add("loading")

    try {
      const url = this.usdaShowUrlValue.replace("__FDC_ID__", fdcId)
      const response = await fetch(url, {
        headers: { "Accept": "application/json", "X-CSRF-Token": getCsrfToken() }
      })

      if (!response.ok) {
        item.classList.remove("loading")
        return
      }

      const data = await response.json()
      this.lastImportedItem?.classList.remove("loading")
      this.lastImportedItem = item
      this.populateFromUsda(data)
    } catch {
      item.classList.remove("loading")
    }
  }

  populateFromUsda(data) {
    if (data.nutrients) {
      if (this.hasBasisGramsTarget) {
        this.basisGramsTarget.value = data.nutrients.basis_grams || 100
      }
      this.nutrientFieldTargets.forEach(input => {
        const key = input.dataset.nutrientKey
        const value = data.nutrients[key]
        input.value = value != null ? this.formatValue(value) : ""
      })
    }

    if (data.density) {
      this.densityVolumeTarget.value = data.density.volume || ""
      this.densityUnitTarget.value = data.density.unit || ""
      this.densityGramsTarget.value = data.density.grams != null
        ? this.formatValue(data.density.grams) : ""
      this.updateDerivedVolumes()
    }

    this.portionListTarget.replaceChildren()
    if (data.portions) {
      data.portions.forEach(p => this.addPortionWithValues(p.name, p.grams))
    }

    if (data.density_candidates && data.density_candidates.length > 1) {
      this.showDensityCandidates(data.density_candidates, data.density)
    }

    this.updateNutrientSummary()
  }

  updateDerivedVolumes() {
  }

  formatValue(num) {
    if (num == null) return ""
    return String(Math.round(num * 100) / 100)
  }

  addPortionWithValues(name, grams) {
    this.addPortion()
    const rows = this.portionListTarget.querySelectorAll(".editor-portion-row")
    const lastRow = rows[rows.length - 1]
    lastRow.querySelector("[data-nutrition-editor-target='portionName']").value = name
    lastRow.querySelector("[data-nutrition-editor-target='portionGrams']").value = this.formatValue(grams)
  }

  showDensityCandidates(candidates, selectedDensity) {
    if (!this.hasDensityCandidatesTarget) return

    this.densityCandidatesTarget.hidden = false
    const list = this.densityCandidateListTarget
    list.replaceChildren()

    candidates.forEach((candidate, index) => {
      const unit = this.normalizeUnit(candidate.modifier)
      const perUnit = candidate.each
      const isSelected = selectedDensity &&
        Math.abs(perUnit - selectedDensity.grams) < 0.01 &&
        unit === selectedDensity.unit

      const label = document.createElement("label")
      label.className = "editor-density-candidate-row"

      const radio = document.createElement("input")
      radio.type = "radio"
      radio.name = "density-candidate"
      radio.value = index
      radio.checked = isSelected
      radio.addEventListener("change", () => {
        this.densityVolumeTarget.value = 1
        this.densityUnitTarget.value = unit
        this.densityGramsTarget.value = this.formatValue(perUnit)
        this.updateDerivedVolumes()
      })

      label.appendChild(radio)
      label.appendChild(document.createTextNode(
        ` ${this.formatValue(perUnit)}g per 1 ${unit}`
      ))
      list.appendChild(label)
    })
  }

  normalizeUnit(modifier) {
    const match = modifier.match(/^(cup|tablespoon|tbsp|teaspoon|tsp|fl oz|fluid ounce|ml|liter|litre|quart|pint|gallon)/i)
    return match ? match[1].toLowerCase() : modifier.toLowerCase().split(/[\s(]/)[0]
  }

  // Data collection and validation

  collectFormData() {
    return {
      nutrients: this.collectNutrients(),
      density: this.collectDensity(),
      portions: this.collectPortions(),
      aisle: this.currentAisle(),
      aliases: this.collectAliases(),
      omit_from_shopping: this.hasOmitCheckboxTarget && this.omitCheckboxTarget.checked
    }
  }

  validateForm(data) {
    const errors = []
    const hasAnyNutrient = Object.entries(data.nutrients)
      .some(([key, val]) => key !== "basis_grams" && val !== null)

    if (hasAnyNutrient && (!data.nutrients.basis_grams || data.nutrients.basis_grams <= 0)) {
      errors.push("Per (basis grams) must be greater than 0 when nutrients are provided.")
    }

    this.nutrientFieldTargets.forEach(input => {
      const key = input.dataset.nutrientKey
      const val = data.nutrients[key]
      const max = parseInt(input.dataset.nutrientMax, 10) || 10000
      if (val !== null && (val < 0 || val > max)) {
        errors.push(`${key.replace(/_/g, " ")} must be between 0 and ${max.toLocaleString()}.`)
      }
    })

    if (data.density) {
      if (!data.density.grams || data.density.grams <= 0) {
        errors.push("Density grams must be greater than 0 when volume is set.")
      }
    }

    const portionNames = Object.keys(data.portions)
    if (portionNames.length !== new Set(portionNames).size) {
      errors.push("Duplicate portion names are not allowed.")
    }

    Object.entries(data.portions).forEach(([name, grams]) => {
      if (!grams || grams <= 0) {
        errors.push(`Portion "${name === "~unitless" ? "each" : name}" must have grams greater than 0.`)
      }
    })

    return errors
  }

  // Private

  get turboFrame() {
    return this.element.querySelector("turbo-frame")
  }

  get originalAisle() {
    return this._originalAisle
  }

  get editorController() {
    return this.application.getControllerForElementAndIdentifier(this.element, "editor")
  }

  onFrameLoad() {
    this._originalAisle = this.currentAisle()
    this.originalSnapshot = JSON.stringify(this.collectFormData())
    this.moveResetButtonToFooter()
    this.restoreSectionStates()
    this.updateDerivedVolumes()
    if (this.hasNutrientDetailTarget) {
      this.nutrientDetailTarget.addEventListener("toggle", () => {
        if (!this.nutrientDetailTarget.open) this.updateNutrientSummary()
      })
    }
  }

  restoreSectionStates() {
    this.formContentTarget.querySelectorAll("details[data-section-key]").forEach(details => {
      const key = `editor:section:${details.dataset.sectionKey}`
      const stored = sessionStorage.getItem(key)
      if (stored === "open") details.open = true
      else if (stored === "closed") details.open = false

      details.addEventListener("toggle", () => {
        sessionStorage.setItem(key, details.open ? "open" : "closed")
      })
    })
  }

  moveResetButtonToFooter() {
    const footer = this.element.querySelector(".editor-footer")
    const oldBtn = footer.querySelector("[data-reset-ingredient]")
    const oldSpacer = footer.querySelector(".editor-footer-spacer")
    if (oldBtn) oldBtn.remove()
    if (oldSpacer) oldSpacer.remove()

    const resetBtn = this.element.querySelector("[data-reset-ingredient]")
    if (!resetBtn) return

    resetBtn.hidden = false
    const spacer = document.createElement("span")
    spacer.className = "editor-footer-spacer"
    footer.prepend(spacer)
    footer.prepend(resetBtn)
  }

  collectNutrients() {
    const nutrients = { basis_grams: parseFloatOrNull(this.basisGramsTarget.value) }

    this.nutrientFieldTargets.forEach(input => {
      nutrients[input.dataset.nutrientKey] = parseFloatOrNull(input.value)
    })

    return nutrients
  }

  collectDensity() {
    const volume = parseFloatOrNull(this.densityVolumeTarget.value)
    const unit = this.densityUnitTarget.value
    const grams = parseFloatOrNull(this.densityGramsTarget.value)

    if (!volume || !unit) return null

    return { volume, unit, grams }
  }

  collectPortions() {
    const portions = {}

    this.portionRowTargets.forEach(row => {
      const nameInput = row.querySelector("[data-nutrition-editor-target='portionName']")
      const gramsInput = row.querySelector("[data-nutrition-editor-target='portionGrams']")
      if (!nameInput || !gramsInput) return

      const rawName = nameInput.value.trim()
      if (!rawName) return

      const key = rawName.toLowerCase() === "each" ? "~unitless" : rawName
      const grams = parseFloatOrNull(gramsInput.value)
      if (grams !== null) portions[key] = grams
    })

    return portions
  }

  collectAliases() {
    return this.aliasChipTargets.map(chip =>
      chip.querySelector(".alias-chip-text").textContent.trim()
    )
  }

  currentAisle() {
    if (!this.hasAisleSelectTarget) return null

    const val = this.aisleSelectTarget.value
    if (val === "__other__") return this.aisleInputTarget.value.trim() || null
    return val || null
  }

  nutritionUrl(name) {
    return this.baseUrlValue.replace("__NAME__", encodeURIComponent(name))
  }

  editUrlFor(name) {
    return this.editUrlValue.replace("__NAME__", encodeURIComponent(name))
  }
}

function parseFloatOrNull(value) {
  if (!value || value.trim() === "") return null

  const num = parseFloat(value)
  return Number.isNaN(num) ? null : num
}
