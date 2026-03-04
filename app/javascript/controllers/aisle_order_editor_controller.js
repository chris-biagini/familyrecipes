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
    this.animateSwap(index, swapIndex, () => {
      this.swapAisles(index, swapIndex)
      this.render()
      this.focusMoveButton(swapIndex, "up")
    })
  }

  moveDown(event) {
    const index = this.aisleIndex(event)
    const liveIndices = this.liveIndices()
    const livePos = liveIndices.indexOf(index)
    if (livePos < 0 || livePos >= liveIndices.length - 1) return

    const swapIndex = liveIndices[livePos + 1]
    this.animateSwap(index, swapIndex, () => {
      this.swapAisles(index, swapIndex)
      this.render()
      this.focusMoveButton(swapIndex, "down")
    })
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
    input.maxLength = 50
    input.setAttribute("aria-label", `Rename ${aisle.currentName}`)
    if (aisle.originalName) input.placeholder = aisle.originalName

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
    row.dataset.aisleIndex = index

    row.appendChild(this.buildNameArea(aisle, index))
    row.appendChild(this.buildControls(aisle, index))

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

    if (aisle.deleted) {
      const nameSpan = document.createElement("span")
      nameSpan.className = "aisle-name"
      nameSpan.textContent = aisle.currentName
      area.appendChild(nameSpan)
    } else {
      const nameBtn = document.createElement("button")
      nameBtn.type = "button"
      nameBtn.className = "aisle-name"
      nameBtn.textContent = aisle.currentName
      nameBtn.dataset.aisleIndex = index
      nameBtn.dataset.action = "click->aisle-order-editor#startRename"
      area.appendChild(nameBtn)
    }

    return area
  }

  buildControls(aisle, index) {
    const controls = document.createElement("div")
    controls.className = "aisle-controls"

    const live = this.liveIndices()
    const livePos = live.indexOf(index)

    const upBtn = this.buildIconButton(this.chevronSvg(), "aisle-btn--up", "Move up", index)
    upBtn.dataset.action = "click->aisle-order-editor#moveUp"
    if (aisle.deleted || livePos === 0) upBtn.disabled = true

    const downBtn = this.buildIconButton(this.chevronSvg(true), "aisle-btn--down", "Move down", index)
    downBtn.dataset.action = "click->aisle-order-editor#moveDown"
    if (aisle.deleted || livePos === live.length - 1) downBtn.disabled = true

    const toggleBtn = aisle.deleted
      ? this.buildIconButton(this.undoSvg(), "aisle-btn--undo", "Undo delete", index)
      : this.buildIconButton(this.deleteSvg(), "aisle-btn--delete", "Delete", index)
    toggleBtn.dataset.action = aisle.deleted
      ? "click->aisle-order-editor#undoDelete"
      : "click->aisle-order-editor#deleteAisle"

    controls.appendChild(upBtn)
    controls.appendChild(downBtn)
    controls.appendChild(toggleBtn)
    return controls
  }

  buildIconButton(svgElement, className, label, index) {
    const btn = document.createElement("button")
    btn.type = "button"
    btn.className = `aisle-btn ${className}`
    btn.setAttribute("aria-label", label)
    btn.dataset.aisleIndex = index
    btn.appendChild(svgElement)
    return btn
  }

  chevronSvg(flipped = false) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    svg.setAttribute("viewBox", "0 0 24 24")
    svg.setAttribute("width", "14")
    svg.setAttribute("height", "14")
    svg.setAttribute("fill", "none")
    if (flipped) svg.style.transform = "scaleY(-1)"
    const path = document.createElementNS("http://www.w3.org/2000/svg", "polyline")
    path.setAttribute("points", "6 15 12 9 18 15")
    path.setAttribute("stroke", "currentColor")
    path.setAttribute("stroke-width", "2")
    path.setAttribute("stroke-linecap", "round")
    path.setAttribute("stroke-linejoin", "round")
    svg.appendChild(path)
    return svg
  }

  deleteSvg() {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    svg.setAttribute("viewBox", "0 0 24 24")
    svg.setAttribute("width", "14")
    svg.setAttribute("height", "14")
    svg.setAttribute("fill", "none")
    const l1 = document.createElementNS("http://www.w3.org/2000/svg", "line")
    l1.setAttribute("x1", "6"); l1.setAttribute("y1", "6")
    l1.setAttribute("x2", "18"); l1.setAttribute("y2", "18")
    l1.setAttribute("stroke", "currentColor")
    l1.setAttribute("stroke-width", "2")
    l1.setAttribute("stroke-linecap", "round")
    const l2 = document.createElementNS("http://www.w3.org/2000/svg", "line")
    l2.setAttribute("x1", "18"); l2.setAttribute("y1", "6")
    l2.setAttribute("x2", "6"); l2.setAttribute("y2", "18")
    l2.setAttribute("stroke", "currentColor")
    l2.setAttribute("stroke-width", "2")
    l2.setAttribute("stroke-linecap", "round")
    svg.appendChild(l1)
    svg.appendChild(l2)
    return svg
  }

  undoSvg() {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    svg.setAttribute("viewBox", "0 0 24 24")
    svg.setAttribute("width", "14")
    svg.setAttribute("height", "14")
    svg.setAttribute("fill", "none")
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
    path.setAttribute("d", "M4 9h11a4 4 0 0 1 0 8H11")
    path.setAttribute("stroke", "currentColor")
    path.setAttribute("stroke-width", "2")
    path.setAttribute("stroke-linecap", "round")
    path.setAttribute("stroke-linejoin", "round")
    const arrow = document.createElementNS("http://www.w3.org/2000/svg", "polyline")
    arrow.setAttribute("points", "7 5 4 9 7 13")
    arrow.setAttribute("stroke", "currentColor")
    arrow.setAttribute("stroke-width", "2")
    arrow.setAttribute("stroke-linecap", "round")
    arrow.setAttribute("stroke-linejoin", "round")
    svg.appendChild(path)
    svg.appendChild(arrow)
    return svg
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

  animateSwap(indexA, indexB, callback) {
    const rows = this.listTarget.children
    const rowA = rows[indexA]
    const rowB = rows[indexB]
    if (!rowA || !rowB) { callback(); return }

    this.updateDisabledStatesAfterSwap(indexA, indexB)

    const rectA = rowA.getBoundingClientRect()
    const rectB = rowB.getBoundingClientRect()
    const deltaA = rectB.top - rectA.top
    const deltaB = rectA.top - rectB.top

    rowA.style.transition = "none"
    rowB.style.transition = "none"
    rowA.style.transform = `translateY(0)`
    rowB.style.transform = `translateY(0)`
    rowA.style.zIndex = "1"
    rowB.style.zIndex = "0"

    requestAnimationFrame(() => {
      rowA.style.transition = "transform 150ms ease"
      rowB.style.transition = "transform 150ms ease"
      rowA.style.transform = `translateY(${deltaA}px)`
      rowB.style.transform = `translateY(${deltaB}px)`

      rowA.addEventListener("transitionend", () => {
        rowA.style.transition = ""
        rowA.style.transform = ""
        rowA.style.zIndex = ""
        rowB.style.transition = ""
        rowB.style.transform = ""
        rowB.style.zIndex = ""
        callback()
      }, { once: true })
    })
  }

  updateDisabledStatesAfterSwap(indexA, indexB) {
    const live = this.liveIndices()
    const posA = live.indexOf(indexA)
    const posB = live.indexOf(indexB)
    const newPosA = posB
    const newPosB = posA
    const last = live.length - 1
    const rows = this.listTarget.children

    this.setMoveDisabled(rows[indexA], newPosA === 0, newPosA === last)
    this.setMoveDisabled(rows[indexB], newPosB === 0, newPosB === last)
  }

  setMoveDisabled(row, atTop, atBottom) {
    if (!row) return
    const up = row.querySelector(".aisle-btn--up")
    const down = row.querySelector(".aisle-btn--down")
    if (up) up.disabled = atTop
    if (down) down.disabled = atBottom
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
