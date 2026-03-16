import { Controller } from "@hotwired/stimulus"
import {
  getCsrfToken, showErrors, clearErrors,
  closeWithConfirmation, saveRequest, guardBeforeUnload, handleSave
} from "../utilities/editor_utils"
import {
  createItem, buildPayload, takeSnapshot, isModified, checkDuplicate,
  renderRows, startInlineRename, swapItems, animateSwap, updateButtonStates
} from "../utilities/ordered_list_editor_utils"

/**
 * Generic ordered-list editor dialog for managing named items with reorder,
 * rename, add, and delete. Parameterized via Stimulus values so one controller
 * handles grocery aisles, recipe categories, and tags. The `orderable` value
 * suppresses up/down reorder buttons for unordered lists like tags.
 *
 * - ordered_list_editor_utils: changeset, row rendering, animation, payload
 * - editor_utils: CSRF tokens, error display, save/close helpers
 * - GroceriesController / CategoriesController / TagsController: backend endpoints
 */
export default class extends Controller {
  static targets = ["list", "saveButton", "errors", "newItemName"]

  static values = {
    loadUrl: String,
    saveUrl: String,
    payloadKey: { type: String, default: "order" },
    joinWith: String,
    loadKey: { type: String, default: "items" },
    openSelector: String,
    orderable: { type: Boolean, default: true }
  }

  connect() {
    this.items = []
    this.initialSnapshot = null

    if (this.hasOpenSelectorValue) {
      this.openButton = document.querySelector(this.openSelectorValue)
      if (this.openButton) {
        this.boundOpen = this.open.bind(this)
        this.openButton.addEventListener("click", this.boundOpen)
      }
    }

    this.guard = guardBeforeUnload(this.element, () => isModified(this.items, this.initialSnapshot))

    this.boundCancel = this.handleCancel.bind(this)
    this.element.addEventListener("cancel", this.boundCancel)

    this.boundBeforeVisit = this.handleBeforeVisit.bind(this)
    document.addEventListener("turbo:before-visit", this.boundBeforeVisit)
  }

  disconnect() {
    if (this.openButton && this.boundOpen) {
      this.openButton.removeEventListener("click", this.boundOpen)
    }
    if (this.guard) this.guard.remove()
    this.element.removeEventListener("cancel", this.boundCancel)
    if (this.boundBeforeVisit) document.removeEventListener("turbo:before-visit", this.boundBeforeVisit)
  }

  open() {
    this.listTarget.replaceChildren()
    clearErrors(this.errorsTarget)
    this.resetSaveButton()
    if (this.hasNewItemNameTarget) this.newItemNameTarget.value = ""
    this.element.showModal()
    this.loadItems()
  }

  close() {
    closeWithConfirmation(this.element, () => isModified(this.items, this.initialSnapshot), () => this.reset())
  }

  save() {
    this.guard.markSaving()
    handleSave(
      this.saveButtonTarget,
      this.errorsTarget,
      () => saveRequest(this.saveUrlValue, "PATCH", this.buildItemPayload()),
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

  addItem() {
    const name = this.newItemNameTarget.value.trim()
    if (!name) return

    if (checkDuplicate(this.items, name)) {
      showErrors(this.errorsTarget, [`"${name}" already exists.`])
      return
    }

    clearErrors(this.errorsTarget)
    this.items.push(createItem(null, name))
    this.newItemNameTarget.value = ""
    this.render()
    this.newItemNameTarget.focus()
  }

  addItemOnEnter(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.addItem()
    }
  }

  // Private

  handleCancel(event) {
    if (isModified(this.items, this.initialSnapshot)) {
      event.preventDefault()
      this.close()
    }
  }

  handleBeforeVisit(event) {
    if (!this.element.open) return
    if (isModified(this.items, this.initialSnapshot)) {
      event.preventDefault()
      this.close()
    } else {
      this.element.close()
    }
  }

  loadItems() {
    this.saveButtonTarget.disabled = true

    fetch(this.loadUrlValue, {
      headers: { "Accept": "application/json", "X-CSRF-Token": getCsrfToken() }
    })
      .then(r => r.json())
      .then(data => {
        this.items = this.parseLoadedItems(data)
        this.initialSnapshot = takeSnapshot(this.items)
        this.render()
        this.saveButtonTarget.disabled = false
      })
      .catch(() => {
        showErrors(this.errorsTarget, ["Failed to load items. Close and try again."])
      })
  }

  parseLoadedItems(data) {
    const raw = data[this.loadKeyValue]
    if (Array.isArray(raw)) return raw.map(item => createItem(item.name))
    if (typeof raw === "string") return raw.split("\n").filter(Boolean).map(name => createItem(name))
    return []
  }

  render() {
    renderRows(this.listTarget, this.items, this.rowCallbacks(), this.orderableValue)
  }

  rowCallbacks() {
    return {
      onMoveUp: (index) => this.moveUp(index),
      onMoveDown: (index) => this.moveDown(index),
      onDelete: (index) => { this.items[index].deleted = true; this.render() },
      onUndo: (index) => { this.items[index].deleted = false; this.render() },
      onRename: (index) => {
        const row = this.listTarget.children[index]
        const nameBtn = row.querySelector(".aisle-name")
        startInlineRename(nameBtn, this.items[index], () => this.render())
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
    const lastLive = liveIndices.length - 1

    updateButtonStates(rows[index], targetPos, lastLive)
    updateButtonStates(rows[swapIndex], livePos, lastLive)

    animateSwap(rows[index], rows[swapIndex], () => {
      swapItems(this.items, index, swapIndex)
      this.render()
      this.focusMoveButton(swapIndex, label)
    })
  }

  liveIndices() {
    return this.items
      .map((item, i) => item.deleted ? null : i)
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

  buildItemPayload() {
    const payload = buildPayload(this.items, this.payloadKeyValue)
    if (this.hasJoinWithValue) {
      payload[this.payloadKeyValue] = payload[this.payloadKeyValue].join(this.joinWithValue)
    }
    return payload
  }

  reset() {
    this.items = []
    this.initialSnapshot = null
    clearErrors(this.errorsTarget)
  }

  resetSaveButton() {
    this.saveButtonTarget.disabled = false
    this.saveButtonTarget.textContent = "Save"
  }
}
