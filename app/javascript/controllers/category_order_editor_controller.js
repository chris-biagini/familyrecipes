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
 * Rich list editor for recipe categories. Provides inline rename, drag-free
 * reordering (up/down buttons), add/delete with undo, and visual state feedback.
 * Submits staged changes as a single PATCH. Uses ordered_list_editor_utils for
 * shared list logic; this controller owns the dialog lifecycle and fetch calls.
 *
 * - ordered_list_editor_utils: changeset, row rendering, animation, payload
 * - editor_utils: CSRF tokens, error display
 * - CategoriesController: backend for load/save
 */
export default class extends Controller {
  static targets = ["list", "saveButton", "errors", "newCategoryName"]

  static values = {
    loadUrl: String,
    saveUrl: String
  }

  connect() {
    this.categories = []
    this.initialSnapshot = null

    this.openButton = document.querySelector("#edit-categories-button")
    if (this.openButton) {
      this.boundOpen = this.open.bind(this)
      this.openButton.addEventListener("click", this.boundOpen)
    }

    this.guard = guardBeforeUnload(this.element, () => isModified(this.categories, this.initialSnapshot))

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
    if (this.hasNewCategoryNameTarget) this.newCategoryNameTarget.value = ""
    this.element.showModal()
    this.loadCategories()
  }

  close() {
    closeWithConfirmation(this.element, () => isModified(this.categories, this.initialSnapshot), () => this.reset())
  }

  save() {
    this.guard.markSaving()
    handleSave(
      this.saveButtonTarget,
      this.errorsTarget,
      () => saveRequest(this.saveUrlValue, "PATCH", this.buildCategoryPayload()),
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

  addCategory() {
    const name = this.newCategoryNameTarget.value.trim()
    if (!name) return

    if (checkDuplicate(this.categories, name)) {
      showErrors(this.errorsTarget, [`"${name}" already exists.`])
      return
    }

    clearErrors(this.errorsTarget)
    this.categories.push(createItem(null, name))
    this.newCategoryNameTarget.value = ""
    this.render()
    this.newCategoryNameTarget.focus()
  }

  addCategoryOnEnter(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.addCategory()
    }
  }

  // Private

  handleCancel(event) {
    if (isModified(this.categories, this.initialSnapshot)) {
      event.preventDefault()
      this.close()
    }
  }

  loadCategories() {
    this.saveButtonTarget.disabled = true

    fetch(this.loadUrlValue, {
      headers: { "Accept": "application/json", "X-CSRF-Token": getCsrfToken() }
    })
      .then(r => r.json())
      .then(data => {
        this.categories = (data.categories || []).map(c => createItem(c.name))
        this.initialSnapshot = takeSnapshot(this.categories)
        this.render()
        this.saveButtonTarget.disabled = false
      })
      .catch(() => {
        showErrors(this.errorsTarget, ["Failed to load categories. Close and try again."])
      })
  }

  render() {
    renderRows(this.listTarget, this.categories, this.rowCallbacks())
  }

  rowCallbacks() {
    return {
      onMoveUp: (index) => this.moveUp(index),
      onMoveDown: (index) => this.moveDown(index),
      onDelete: (index) => { this.categories[index].deleted = true; this.render() },
      onUndo: (index) => { this.categories[index].deleted = false; this.render() },
      onRename: (index) => {
        const row = this.listTarget.children[index]
        const nameBtn = row.querySelector(".aisle-name")
        startInlineRename(nameBtn, this.categories[index], () => this.render())
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
      swapItems(this.categories, index, swapIndex)
      this.render()
      this.focusMoveButton(swapIndex, label)
    })
  }

  liveIndices() {
    return this.categories
      .map((c, i) => c.deleted ? null : i)
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

  buildCategoryPayload() {
    return buildPayload(this.categories, "category_order")
  }

  reset() {
    this.categories = []
    this.initialSnapshot = null
    clearErrors(this.errorsTarget)
  }

  resetSaveButton() {
    this.saveButtonTarget.disabled = false
    this.saveButtonTarget.textContent = "Save"
  }
}
