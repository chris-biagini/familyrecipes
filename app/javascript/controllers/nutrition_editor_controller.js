import { Controller } from "@hotwired/stimulus"
import { getCsrfToken, showErrors, clearErrors } from "utilities/editor_utils"

export default class extends Controller {
  static targets = [
    "dialog", "title", "errors", "formContent",
    "saveButton", "saveNextButton", "nextLabel", "nextName",
    "basisGrams", "nutrientField",
    "servingVolume", "servingUnit", "servingDensityGrams",
    "densitySection", "densityVolume", "densityUnit", "densityGrams", "densityDerivedNote",
    "portionList", "portionRow", "portionName", "portionGrams",
    "aisleSelect", "aisleInput"
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

    document.addEventListener("click", this.boundEditClick)
    document.addEventListener("click", this.boundResetClick)

    this.turboFrame.addEventListener("turbo:frame-load", this.boundFrameLoad)
  }

  disconnect() {
    document.removeEventListener("click", this.boundEditClick)
    document.removeEventListener("click", this.boundResetClick)
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

  close() {
    if (this.isModified() && !confirm("You have unsaved changes. Discard them?")) return

    this.dialogTarget.close()
    this.currentIngredient = null
    this.originalSnapshot = null
  }

  async save() {
    await this.performSave(false)
  }

  async saveAndNext() {
    await this.performSave(true)
  }

  servingVolumeChanged() {
    const volume = parseFloat(this.servingVolumeTarget.value)
    const unit = this.servingUnitTarget.value
    const basisGrams = parseFloat(this.basisGramsTarget.value)

    if (volume > 0 && unit) {
      this.densityVolumeTarget.value = volume
      this.densityUnitTarget.value = unit
      this.densityGramsTarget.value = basisGrams > 0 ? basisGrams : ""
      this.densitySectionTarget.open = true
      this.densityDerivedNoteTarget.hidden = false

      const gramsDisplay = basisGrams > 0 ? formatNumber(basisGrams) : ""
      this.servingDensityGramsTarget.textContent = gramsDisplay
      this.updateMeasuredAsUnitLabel(basisGrams > 0)
    } else {
      this.densityDerivedNoteTarget.hidden = true
      this.servingDensityGramsTarget.textContent = ""
      this.updateMeasuredAsUnitLabel(false)
    }
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
        alert("Failed to reset. Please try again.")
      }
    } catch {
      btn.disabled = false
      alert("Network error. Please try again.")
    }
  }

  // Data collection and validation

  collectFormData() {
    return {
      nutrients: this.collectNutrients(),
      density: this.collectDensity(),
      portions: this.collectPortions(),
      aisle: this.currentAisle()
    }
  }

  validateForm(data) {
    const errors = []
    const hasAnyNutrient = Object.entries(data.nutrients)
      .some(([key, val]) => key !== "basis_grams" && val !== null)

    if (hasAnyNutrient && (!data.nutrients.basis_grams || data.nutrients.basis_grams <= 0)) {
      errors.push("Serving size (basis grams) must be greater than 0 when nutrients are provided.")
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
    this.updateSaveNextVisibility()

    if (this.hasBasisGramsTarget) this.basisGramsTarget.focus()
  }

  updateSaveNextVisibility() {
    if (!this.hasSaveNextButtonTarget) return

    if (this.hasNextNameTarget) {
      const nextName = this.nextNameTarget.value
      this.saveNextButtonTarget.hidden = false
      this.nextLabelTarget.textContent = `: ${nextName}`
    } else {
      this.saveNextButtonTarget.hidden = true
    }
  }

  async performSave(andNext) {
    const data = this.collectFormData()
    const errors = this.validateForm(data)

    if (errors.length > 0) {
      showErrors(this.errorsTarget, errors)
      return
    }

    const payload = andNext ? { ...data, save_and_next: true } : data
    this.disableSaveButtons("Saving\u2026")
    clearErrors(this.errorsTarget)
    this.saving = true

    try {
      const response = await fetch(this.nutritionUrl(this.currentIngredient), {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCsrfToken()
        },
        body: JSON.stringify(payload)
      })

      if (response.ok) {
        const result = await response.json()

        if (andNext && result.next_ingredient) {
          this.currentIngredient = result.next_ingredient
          this.titleTarget.textContent = `Edit ${result.next_ingredient}`
          clearErrors(this.errorsTarget)
          this.turboFrame.src = this.editUrlFor(result.next_ingredient)
        } else {
          this.dialogTarget.close()
          window.location.reload()
        }
      } else if (response.status === 422) {
        const result = await response.json()
        showErrors(this.errorsTarget, result.errors)
      } else {
        showErrors(this.errorsTarget, [`Server error (${response.status}). Please try again.`])
      }
    } catch {
      showErrors(this.errorsTarget, ["Network error. Please check your connection and try again."])
    } finally {
      this.saving = false
      this.enableSaveButtons()
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

  currentAisle() {
    if (!this.hasAisleSelectTarget) return null

    const val = this.aisleSelectTarget.value
    if (val === "__other__") return this.aisleInputTarget.value.trim() || null
    return val || null
  }

  nutritionUrl(name) {
    const slug = name.replace(/ /g, "-")
    return this.baseUrlValue.replace("__NAME__", encodeURIComponent(slug))
  }

  editUrlFor(name) {
    const slug = name.replace(/ /g, "-")
    return this.editUrlValue.replace("__NAME__", encodeURIComponent(slug))
  }

  disableSaveButtons(text) {
    this.saveButtonTarget.disabled = true
    this.saveButtonTarget.textContent = text
    if (this.hasSaveNextButtonTarget) this.saveNextButtonTarget.disabled = true
  }

  enableSaveButtons() {
    this.saveButtonTarget.disabled = false
    this.saveButtonTarget.textContent = "Save"
    if (this.hasSaveNextButtonTarget) this.saveNextButtonTarget.disabled = false
  }

  updateMeasuredAsUnitLabel(show) {
    const unitSpan = this.servingDensityGramsTarget.nextElementSibling
    if (unitSpan) unitSpan.textContent = show ? "g" : ""
  }
}

function parseFloatOrNull(value) {
  if (!value || value.trim() === "") return null

  const num = parseFloat(value)
  return Number.isNaN(num) ? null : num
}

function formatNumber(value) {
  if (Number.isInteger(value)) return String(value)
  return String(parseFloat(value.toFixed(4)))
}
