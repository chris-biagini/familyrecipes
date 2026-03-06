import { Controller } from "@hotwired/stimulus"
import {
  getCsrfToken, showErrors, clearErrors,
  closeWithConfirmation, saveRequest, guardBeforeUnload, handleSave
} from "utilities/editor_utils"
import {
  createItem, buildPayload, takeSnapshot, isModified, checkDuplicate,
  renderRows, startInlineRename, swapItems, animateSwap
} from "utilities/ordered_list_editor_utils"

/**
 * Rich list-based editor for kitchen aisle ordering. Replaces the generic
 * textarea editor for the Aisle Order dialog. Manages a staged changeset of
 * aisle rows with visual indicators for renames, deletes, and new additions.
 * List rendering, reorder animation, and inline rename are delegated to
 * ordered_list_editor_utils; this controller owns the dialog lifecycle,
 * server communication, and aisle-specific payload shape.
 *
 * - editor_utils: CSRF, error display, save request, beforeunload guard
 * - ordered_list_editor_utils: row rendering, swap animation, rename, payload
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

    this.guard = guardBeforeUnload(this.element, () => isModified(this.aisles, this.initialSnapshot))

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
    closeWithConfirmation(this.element, () => isModified(this.aisles, this.initialSnapshot), () => this.reset())
  }

  save() {
    this.guard.markSaving()
    handleSave(
      this.saveButtonTarget,
      this.errorsTarget,
      () => saveRequest(this.saveUrlValue, "PATCH", this.buildAislePayload()),
      () => {
        this.element.close()
        window.location.reload()
      }
    )
  }

  moveUp(index) {
    this.move(index, -1, "up")
  }

  moveDown(index) {
    this.move(index, 1, "down")
  }

  addAisle() {
    const name = this.newAisleNameTarget.value.trim()
    if (!name) return

    if (checkDuplicate(this.aisles, name)) {
      showErrors(this.errorsTarget, [`"${name}" already exists.`])
      return
    }

    clearErrors(this.errorsTarget)
    this.aisles.push(createItem(null, name))
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
    if (isModified(this.aisles, this.initialSnapshot)) {
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
        this.aisles = raw.split("\n").filter(Boolean).map(name => createItem(name))
        this.initialSnapshot = takeSnapshot(this.aisles)
        this.render()
        this.saveButtonTarget.disabled = false
      })
      .catch(() => {
        showErrors(this.errorsTarget, ["Failed to load aisle order. Close and try again."])
      })
  }

  render() {
    renderRows(this.listTarget, this.aisles, this.rowCallbacks())
  }

  rowCallbacks() {
    return {
      onMoveUp: (index) => this.moveUp(index),
      onMoveDown: (index) => this.moveDown(index),
      onDelete: (index) => { this.aisles[index].deleted = true; this.render() },
      onUndo: (index) => { this.aisles[index].deleted = false; this.render() },
      onRename: (index) => {
        const row = this.listTarget.children[index]
        const nameBtn = row.querySelector(".aisle-name")
        startInlineRename(nameBtn, this.aisles[index], () => this.render())
      }
    }
  }

  move(index, direction, label) {
    const liveIndices = this.liveIndices()
    const livePos = liveIndices.indexOf(index)
    const targetPos = livePos + direction
    if (livePos < 0 || targetPos < 0 || targetPos >= liveIndices.length) return

    const swapIndex = liveIndices[targetPos]
    const rows = this.listTarget.children

    animateSwap(rows[index], rows[swapIndex], () => {
      swapItems(this.aisles, index, swapIndex)
      this.render()
      this.focusMoveButton(swapIndex, label)
    })
  }

  liveIndices() {
    return this.aisles
      .map((a, i) => a.deleted ? null : i)
      .filter(i => i !== null)
  }

  focusMoveButton(newIndex, direction) {
    const selector = direction === "up" ? ".aisle-btn--up" : ".aisle-btn--down"
    const row = this.listTarget.children[newIndex]
    if (row) {
      const btn = row.querySelector(selector)
      if (btn) btn.focus()
    }
  }

  buildAislePayload() {
    const payload = buildPayload(this.aisles, "aisle_order")
    payload.aisle_order = payload.aisle_order.join("\n")
    return payload
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
}
