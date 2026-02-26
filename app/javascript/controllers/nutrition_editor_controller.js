import { Controller } from "@hotwired/stimulus"
import { getCsrfToken, clearErrors, saveRequest } from "utilities/editor_utils"

export default class extends Controller {
  static targets = ["textarea", "aisleSelect", "aisleInput"]

  connect() {
    this.currentIngredient = null
    this.originalContent = ""
    this.originalAisle = ""
    this.titleEl = this.element.querySelector(".editor-header h2")
    this.errorsEl = this.element.querySelector(".editor-errors")

    this.boundEditClick = (event) => this.openForIngredient(event)
    this.boundResetClick = (event) => this.resetIngredient(event)

    document.querySelectorAll(".nutrition-edit-btn").forEach(btn => {
      btn.addEventListener("click", this.boundEditClick)
    })

    document.querySelectorAll(".nutrition-reset-btn").forEach(btn => {
      btn.addEventListener("click", this.boundResetClick)
    })

    this.boundCollect = (e) => this.handleCollect(e)
    this.boundSave = (e) => this.handleSave(e)
    this.boundModified = (e) => this.handleModified(e)
    this.boundReset = (e) => this.handleReset(e)

    this.element.addEventListener("editor:collect", this.boundCollect)
    this.element.addEventListener("editor:save", this.boundSave)
    this.element.addEventListener("editor:modified", this.boundModified)
    this.element.addEventListener("editor:reset", this.boundReset)
  }

  disconnect() {
    document.querySelectorAll(".nutrition-edit-btn").forEach(btn => {
      btn.removeEventListener("click", this.boundEditClick)
    })

    document.querySelectorAll(".nutrition-reset-btn").forEach(btn => {
      btn.removeEventListener("click", this.boundResetClick)
    })

    this.element.removeEventListener("editor:collect", this.boundCollect)
    this.element.removeEventListener("editor:save", this.boundSave)
    this.element.removeEventListener("editor:modified", this.boundModified)
    this.element.removeEventListener("editor:reset", this.boundReset)
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

  openForIngredient(event) {
    const btn = event.currentTarget
    this.currentIngredient = btn.dataset.ingredient
    this.textareaTarget.value = btn.dataset.nutritionText
    this.originalContent = this.textareaTarget.value
    this.originalAisle = btn.dataset.aisle || ""

    this.aisleSelectTarget.value = this.originalAisle
    if (this.aisleSelectTarget.value !== this.originalAisle) this.aisleSelectTarget.value = ""

    this.aisleInputTarget.hidden = true
    this.aisleInputTarget.value = ""
    this.titleEl.textContent = this.currentIngredient
    clearErrors(this.errorsEl)
    this.element.showModal()
  }

  async resetIngredient(event) {
    const btn = event.currentTarget
    const name = btn.dataset.ingredient
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

  handleCollect(e) {
    e.detail.handled = true
    const nutritionChanged = this.textareaTarget.value !== this.originalContent
    e.detail.data = {
      label_text: nutritionChanged ? this.textareaTarget.value : "",
      aisle: this.currentAisle()
    }
  }

  handleSave(e) {
    e.detail.handled = true
    e.detail.saveFn = () => {
      return saveRequest(this.nutritionUrl(this.currentIngredient), "POST", e.detail.data)
    }
  }

  handleModified(e) {
    e.detail.handled = true
    e.detail.modified = this.textareaTarget.value !== this.originalContent ||
      this.currentAisle() !== this.originalAisle
  }

  handleReset(e) {
    e.detail.handled = true
    this.textareaTarget.value = this.originalContent
    this.aisleSelectTarget.value = this.originalAisle || ""
    this.aisleInputTarget.hidden = true
    this.aisleInputTarget.value = ""
  }

  currentAisle() {
    return this.aisleSelectTarget.value === "__other__"
      ? this.aisleInputTarget.value.trim()
      : this.aisleSelectTarget.value
  }

  nutritionUrl(name) {
    const slug = name.replace(/ /g, "-")
    const parts = window.location.pathname.split("/")
    const kitchensIdx = parts.indexOf("kitchens")
    const base = parts.slice(0, kitchensIdx + 2).join("/")
    return `${base}/nutrition/${encodeURIComponent(slug)}`
  }
}
