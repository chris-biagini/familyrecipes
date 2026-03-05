import { Controller } from "@hotwired/stimulus"
import { getCsrfToken, showErrors, clearErrors } from "utilities/editor_utils"

/**
 * Multi-field nutrition editor dialog for the ingredients page. Manages the
 * structured form (nutrients, density, portions, aisle) loaded via Turbo Frame.
 * Saves via JSON; the broadcast morph from Kitchen#broadcast_update handles
 * refreshing the ingredients table for all clients. Client-side validation
 * prevents invalid submissions. Also handles the "reset to built-in" action
 * that deletes a kitchen-scoped override.
 */
export default class extends Controller {
  static targets = [
    "dialog", "title", "errors", "formContent",
    "saveButton",
    "basisGrams", "nutrientField",
    "densityVolume", "densityUnit", "densityGrams",
    "portionList", "portionRow", "portionName", "portionGrams",
    "aisleSelect", "aisleInput",
    "aliasList", "aliasInput", "aliasChip"
  ]

  static values = {
    baseUrl: String,
    editUrl: String
  }

  connect() {
    this.currentIngredient = null
    this.originalSnapshot = null
    this.saving = false

    this.boundEditClick = (event) => {
      const btn = event.target.closest("[data-open-editor]")
      if (btn) this.openForIngredient(btn)
    }

    this.boundResetClick = (event) => {
      const btn = event.target.closest("[data-reset-ingredient]")
      if (btn) this.resetIngredient(btn)
    }

    this.boundFrameLoad = () => this.onFrameLoad()

    this.boundCancel = (event) => {
      if (this.isModified()) {
        event.preventDefault()
        this.close()
      }
    }

    this.boundPrefetch = (event) => {
      const row = event.target.closest("[data-open-editor]")
      if (row) this.prefetch(row.dataset.ingredientName)
    }

    document.addEventListener("click", this.boundEditClick)
    document.addEventListener("click", this.boundResetClick)
    document.addEventListener("pointerenter", this.boundPrefetch, true)

    this.dialogTarget.addEventListener("cancel", this.boundCancel)
    this.turboFrame.addEventListener("turbo:frame-load", this.boundFrameLoad)
  }

  disconnect() {
    document.removeEventListener("click", this.boundEditClick)
    document.removeEventListener("click", this.boundResetClick)
    document.removeEventListener("pointerenter", this.boundPrefetch, true)
    this.dialogTarget.removeEventListener("cancel", this.boundCancel)
    this.turboFrame.removeEventListener("turbo:frame-load", this.boundFrameLoad)
  }

  // Actions

  openForIngredient(btn) {
    const name = btn.dataset.ingredientName
    this.currentIngredient = name
    this.titleTarget.textContent = `Edit ${name}`
    clearErrors(this.errorsTarget)

    this.turboFrame.src = this.editUrlFor(name)
    this.dialogTarget.showModal()
  }

  prefetch(name) {
    if (this.prefetchedName === name) return

    this.prefetchedName = name
    fetch(this.editUrlFor(name), { headers: { Accept: "text/html" } })
  }

  close() {
    if (this.isModified() && !confirm("You have unsaved changes. Discard them?")) return

    this.dialogTarget.close()
    this.currentIngredient = null
    this.originalSnapshot = null
  }

  async save() {
    await this.performSave()
  }

  addPortion() {
    const row = document.createElement("div")
    row.className = "portion-row"
    row.setAttribute("data-nutrition-editor-target", "portionRow")

    const nameInput = document.createElement("input")
    nameInput.type = "text"
    nameInput.className = "portion-name-input"
    nameInput.placeholder = "e.g. stick, slice"
    nameInput.setAttribute("data-nutrition-editor-target", "portionName")
    nameInput.setAttribute("aria-label", "Portion name")

    const eqSpan = document.createElement("span")
    eqSpan.className = "portion-eq"
    eqSpan.textContent = "="

    const gramsInput = document.createElement("input")
    gramsInput.type = "number"
    gramsInput.className = "portion-grams-input field-narrow"
    gramsInput.inputMode = "decimal"
    gramsInput.step = "any"
    gramsInput.min = "0"
    gramsInput.setAttribute("data-nutrition-editor-target", "portionGrams")
    gramsInput.setAttribute("aria-label", "Portion grams")

    const unitSpan = document.createElement("span")
    unitSpan.className = "portion-unit"
    unitSpan.textContent = "g"

    const removeBtn = document.createElement("button")
    removeBtn.type = "button"
    removeBtn.className = "btn-icon"
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
    event.currentTarget.closest(".portion-row").remove()
  }

  addAlias() {
    const name = this.aliasInputTarget.value.trim()
    if (!name) return

    if (this.collectAliases().includes(name)) {
      this.aliasInputTarget.value = ""
      return
    }

    const chip = document.createElement("span")
    chip.className = "alias-chip"
    chip.setAttribute("data-nutrition-editor-target", "aliasChip")

    const text = document.createElement("span")
    text.className = "alias-chip-text"
    text.textContent = name

    const removeBtn = document.createElement("button")
    removeBtn.type = "button"
    removeBtn.className = "alias-chip-remove"
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
    event.currentTarget.closest(".alias-chip").remove()
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
        showErrors(this.errorsTarget, ["Failed to reset. Please try again."])
      }
    } catch {
      btn.disabled = false
      showErrors(this.errorsTarget, ["Network error. Please check your connection and try again."])
    }
  }

  // Data collection and validation

  collectFormData() {
    return {
      nutrients: this.collectNutrients(),
      density: this.collectDensity(),
      portions: this.collectPortions(),
      aisle: this.currentAisle(),
      aliases: this.collectAliases()
    }
  }

  validateForm(data) {
    const errors = []
    const hasAnyNutrient = Object.entries(data.nutrients)
      .some(([key, val]) => key !== "basis_grams" && val !== null)

    if (hasAnyNutrient && (!data.nutrients.basis_grams || data.nutrients.basis_grams <= 0)) {
      errors.push("Per (basis grams) must be greater than 0 when nutrients are provided.")
    }

    Object.entries(data.nutrients).forEach(([key, val]) => {
      if (key === "basis_grams") return
      if (val !== null && (val < 0 || val > 10000)) {
        errors.push(`${key.replace(/_/g, " ")} must be between 0 and 10,000.`)
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

  isModified() {
    if (!this.originalSnapshot) return false

    return JSON.stringify(this.collectFormData()) !== this.originalSnapshot
  }

  // Private

  get turboFrame() {
    return this.dialogTarget.querySelector("turbo-frame")
  }

  get originalAisle() {
    return this._originalAisle
  }

  onFrameLoad() {
    this._originalAisle = this.currentAisle()
    this.originalSnapshot = JSON.stringify(this.collectFormData())

    if (this.hasBasisGramsTarget) this.basisGramsTarget.focus()
  }

  async performSave() {
    const data = this.collectFormData()
    const errors = this.validateForm(data)

    if (errors.length > 0) {
      showErrors(this.errorsTarget, errors)
      return
    }

    this.disableSaveButtons("Saving\u2026")
    clearErrors(this.errorsTarget)
    this.saving = true

    try {
      await this.saveWithJson(data)
    } catch {
      showErrors(this.errorsTarget, ["Network error. Please check your connection and try again."])
    } finally {
      this.saving = false
      this.enableSaveButtons()
    }
  }

  async saveWithJson(payload) {
    const response = await fetch(this.nutritionUrl(this.currentIngredient), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": getCsrfToken()
      },
      body: JSON.stringify(payload)
    })

    if (response.ok) {
      this.dialogTarget.close()
      this.currentIngredient = null
      this.originalSnapshot = null
    } else if (response.status === 422) {
      const result = await response.json()
      showErrors(this.errorsTarget, result.errors)
    } else {
      showErrors(this.errorsTarget, [`Server error (${response.status}). Please try again.`])
    }
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

  disableSaveButtons(text) {
    this.saveButtonTarget.disabled = true
    this.saveButtonTarget.textContent = text
  }

  enableSaveButtons() {
    this.saveButtonTarget.disabled = false
    this.saveButtonTarget.textContent = "Save"
  }

}

function parseFloatOrNull(value) {
  if (!value || value.trim() === "") return null

  const num = parseFloat(value)
  return Number.isNaN(num) ? null : num
}

