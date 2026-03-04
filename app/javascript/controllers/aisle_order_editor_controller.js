import { Controller } from "@hotwired/stimulus"
import {
  getCsrfToken, showErrors, clearErrors,
  closeWithConfirmation, saveRequest, guardBeforeUnload, handleSave
} from "utilities/editor_utils"

/**
 * Rich list-based editor for kitchen aisle ordering. Replaces the generic
 * textarea editor for the Aisle Order dialog. Manages a staged changeset of
 * aisle rows — each tracked as { originalName, currentName, deleted } — with
 * visual indicators for renames (amber tint + "was" annotation) and deletes
 * (strikethrough + fade + undo button). Serializes { aisle_order, renames,
 * deletes } on save for server-side catalog cascading.
 *
 * - editor_utils: CSRF, error display, save request, beforeunload guard
 * - GroceriesController: load and save endpoints
 * - editor_controller: NOT used — this controller fully owns the dialog lifecycle
 */
export default class extends Controller {
  static targets = ["list", "saveButton", "errors", "newAisleName"]

  static values = {
    loadUrl: String,
    saveUrl: String
  }

  connect() {
    this.aisles = []
    this.initialSnapshot = null

    this.openButton = document.querySelector("#edit-aisle-order-button")
    if (this.openButton) {
      this.boundOpen = this.open.bind(this)
      this.openButton.addEventListener("click", this.boundOpen)
    }

    this.guard = guardBeforeUnload(this.element, () => this.isModified())

    this.boundCancel = this.handleCancel.bind(this)
    this.element.addEventListener("cancel", this.boundCancel)
  }

  disconnect() {
    if (this.openButton && this.boundOpen) {
      this.openButton.removeEventListener("click", this.boundOpen)
    }
    if (this.guard) this.guard.remove()
    this.element.removeEventListener("cancel", this.boundCancel)
  }

  open() {
    this.listTarget.replaceChildren()
    clearErrors(this.errorsTarget)
    this.resetSaveButton()
    if (this.hasNewAisleNameTarget) this.newAisleNameTarget.value = ""
    this.element.showModal()
    this.loadAisles()
  }

  close() {
    closeWithConfirmation(this.element, () => this.isModified(), () => this.reset())
  }

  save() {
    this.guard.markSaving()
    handleSave(
      this.saveButtonTarget,
      this.errorsTarget,
      () => saveRequest(this.saveUrlValue, "PATCH", this.buildPayload()),
      () => {
        this.element.close()
        window.location.reload()
      }
    )
  }

  moveUp(event) {
    const index = this.aisleIndex(event)
    const liveIndices = this.liveIndices()
    const livePos = liveIndices.indexOf(index)
    if (livePos <= 0) return

    const swapIndex = liveIndices[livePos - 1]
    this.swapAisles(index, swapIndex)
    this.render()
    this.focusMoveButton(swapIndex, "up")
  }

  moveDown(event) {
    const index = this.aisleIndex(event)
    const liveIndices = this.liveIndices()
    const livePos = liveIndices.indexOf(index)
    if (livePos < 0 || livePos >= liveIndices.length - 1) return

    const swapIndex = liveIndices[livePos + 1]
    this.swapAisles(index, swapIndex)
    this.render()
    this.focusMoveButton(swapIndex, "down")
  }

  deleteAisle(event) {
    this.aisles[this.aisleIndex(event)].deleted = true
    this.render()
  }

  undoDelete(event) {
    this.aisles[this.aisleIndex(event)].deleted = false
    this.render()
  }

  startRename(event) {
    const index = this.aisleIndex(event)
    const aisle = this.aisles[index]
    const btn = event.currentTarget

    const input = document.createElement("input")
    input.type = "text"
    input.className = "aisle-rename-input"
    input.value = aisle.currentName
    input.setAttribute("aria-label", `Rename ${aisle.currentName}`)

    const finishRename = () => {
      const newName = input.value.trim()
      if (newName && newName !== aisle.currentName) {
        aisle.currentName = newName
      }
      this.render()
    }

    const cancelRename = () => this.render()

    input.addEventListener("blur", finishRename)
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault()
        input.removeEventListener("blur", finishRename)
        finishRename()
      } else if (e.key === "Escape") {
        e.preventDefault()
        input.removeEventListener("blur", finishRename)
        cancelRename()
      }
    })

    btn.replaceWith(input)
    input.focus()
    input.select()
  }

  addAisle() {
    const name = this.newAisleNameTarget.value.trim()
    if (!name) return

    const duplicate = this.aisles.some(a =>
      !a.deleted && a.currentName.toLowerCase() === name.toLowerCase()
    )
    if (duplicate) {
      showErrors(this.errorsTarget, [`"${name}" already exists.`])
      return
    }

    clearErrors(this.errorsTarget)
    this.aisles.push({ originalName: null, currentName: name, deleted: false })
    this.newAisleNameTarget.value = ""
    this.render()
    this.newAisleNameTarget.focus()
  }

  addAisleOnEnter(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.addAisle()
    }
  }

  // Private

  handleCancel(event) {
    if (this.isModified()) {
      event.preventDefault()
      this.close()
    }
  }

  loadAisles() {
    this.saveButtonTarget.disabled = true

    fetch(this.loadUrlValue, {
      headers: { "Accept": "application/json", "X-CSRF-Token": getCsrfToken() }
    })
      .then(r => r.json())
      .then(data => {
        const raw = data.aisle_order || ""
        this.aisles = raw.split("\n").filter(Boolean).map(name => ({
          originalName: name,
          currentName: name,
          deleted: false
        }))
        this.initialSnapshot = JSON.stringify(this.aisles)
        this.render()
        this.saveButtonTarget.disabled = false
      })
      .catch(() => {
        showErrors(this.errorsTarget, ["Failed to load aisle order. Close and try again."])
      })
  }

  render() {
    const rows = this.aisles.map((aisle, index) => this.buildRow(aisle, index))
    this.listTarget.replaceChildren(...rows)
  }

  buildRow(aisle, index) {
    const row = document.createElement("div")
    row.className = this.rowClassName(aisle)

    if (aisle.deleted) {
      row.appendChild(this.buildDeletedContent(aisle, index))
    } else {
      row.appendChild(this.buildNameArea(aisle, index))
      row.appendChild(this.buildControls(aisle, index))
    }

    return row
  }

  rowClassName(aisle) {
    if (aisle.deleted) return "aisle-row aisle-row--deleted"
    if (aisle.originalName === null) return "aisle-row aisle-row--new"
    if (aisle.originalName !== aisle.currentName) return "aisle-row aisle-row--renamed"
    return "aisle-row"
  }

  buildNameArea(aisle, index) {
    const area = document.createElement("div")
    area.className = "aisle-name-area"

    const nameBtn = document.createElement("button")
    nameBtn.type = "button"
    nameBtn.className = "aisle-name"
    nameBtn.textContent = aisle.currentName
    nameBtn.dataset.aisleIndex = index
    nameBtn.dataset.action = "click->aisle-order-editor#startRename"
    area.appendChild(nameBtn)

    if (this.isRenamed(aisle)) {
      const was = document.createElement("span")
      was.className = "aisle-was"
      was.textContent = `\u2190 was ${aisle.originalName}`
      area.appendChild(was)
    }

    return area
  }

  buildControls(aisle, index) {
    const controls = document.createElement("div")
    controls.className = "aisle-controls"

    const live = this.liveIndices()
    const livePos = live.indexOf(index)

    const upBtn = this.buildCircleButton("\u2303", "aisle-btn--up", "Move up", index)
    upBtn.dataset.action = "click->aisle-order-editor#moveUp"
    if (livePos === 0) upBtn.disabled = true

    const downBtn = this.buildCircleButton("\u2304", "aisle-btn--down", "Move down", index)
    downBtn.dataset.action = "click->aisle-order-editor#moveDown"
    if (livePos === live.length - 1) downBtn.disabled = true

    const deleteBtn = this.buildCircleButton("\u00d7", "aisle-btn--delete", "Delete", index)
    deleteBtn.dataset.action = "click->aisle-order-editor#deleteAisle"

    controls.appendChild(upBtn)
    controls.appendChild(downBtn)
    controls.appendChild(deleteBtn)
    return controls
  }

  buildDeletedContent(aisle, index) {
    const wrapper = document.createElement("div")
    wrapper.className = "aisle-row-deleted-content"

    const nameArea = document.createElement("div")
    nameArea.className = "aisle-name-area"
    const nameSpan = document.createElement("span")
    nameSpan.className = "aisle-name"
    nameSpan.textContent = aisle.currentName
    nameArea.appendChild(nameSpan)
    wrapper.appendChild(nameArea)

    const controls = document.createElement("div")
    controls.className = "aisle-controls"
    const undoBtn = this.buildCircleButton("\u21a9", "aisle-btn--undo", "Undo delete", index)
    undoBtn.dataset.action = "click->aisle-order-editor#undoDelete"
    controls.appendChild(undoBtn)
    wrapper.appendChild(controls)

    return wrapper
  }

  buildCircleButton(symbol, className, label, index) {
    const btn = document.createElement("button")
    btn.type = "button"
    btn.className = `aisle-btn ${className}`
    btn.textContent = symbol
    btn.setAttribute("aria-label", label)
    btn.dataset.aisleIndex = index
    return btn
  }

  buildPayload() {
    const liveAisles = this.aisles.filter(a => !a.deleted)
    const aisleOrder = liveAisles.map(a => a.currentName).join("\n")

    const renames = {}
    this.aisles.forEach(a => {
      if (!a.deleted && a.originalName !== null && a.originalName !== a.currentName) {
        renames[a.originalName] = a.currentName
      }
    })

    const deletes = this.aisles
      .filter(a => a.deleted && a.originalName !== null)
      .map(a => a.originalName)

    return { aisle_order: aisleOrder, renames, deletes }
  }

  isModified() {
    return JSON.stringify(this.aisles) !== this.initialSnapshot
  }

  isRenamed(aisle) {
    return aisle.originalName !== null && aisle.originalName !== aisle.currentName
  }

  liveIndices() {
    return this.aisles
      .map((a, i) => a.deleted ? null : i)
      .filter(i => i !== null)
  }

  swapAisles(indexA, indexB) {
    const temp = this.aisles[indexA]
    this.aisles[indexA] = this.aisles[indexB]
    this.aisles[indexB] = temp
  }

  focusMoveButton(newIndex, direction) {
    const selector = direction === "up" ? ".aisle-btn--up" : ".aisle-btn--down"
    const rows = this.listTarget.children
    if (rows[newIndex]) {
      const btn = rows[newIndex].querySelector(selector)
      if (btn) btn.focus()
    }
  }

  reset() {
    this.aisles = []
    this.initialSnapshot = null
    clearErrors(this.errorsTarget)
  }

  resetSaveButton() {
    this.saveButtonTarget.disabled = false
    this.saveButtonTarget.textContent = "Save"
  }

  aisleIndex(event) {
    return parseInt(event.currentTarget.dataset.aisleIndex, 10)
  }
}
