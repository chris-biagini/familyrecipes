import { Controller } from "@hotwired/stimulus"
import { showErrors, clearErrors, saveRequest } from "../utilities/editor_utils"
import {
  createItem, buildPayload, takeSnapshot, isModified, checkDuplicate,
  renderRows, startInlineRename, swapItems, animateSwap, updateButtonStates
} from "../utilities/ordered_list_editor_utils"
import ListenerManager from "../utilities/listener_manager"

/**
 * Companion controller for ordered-list editor dialogs (aisles, categories,
 * tags). Lives on the same element as editor_controller via extra_controllers.
 * Responds to editor lifecycle events to manage list state: reads server-
 * rendered rows on content-loaded, provides save/modified/reset handlers.
 * The `orderable` value suppresses up/down reorder buttons for unordered
 * lists like tags.
 *
 * - editor_controller: open/close/save lifecycle, dirty guards, frame readiness
 * - ordered_list_editor_utils: changeset, row rendering, animation, payload
 * - editor_utils: save requests, error display
 * - ListenerManager: clean event listener teardown
 */
export default class extends Controller {
  static targets = ["list", "newItemName"]

  static values = {
    saveUrl: String,
    payloadKey: { type: String, default: "order" },
    joinWith: String,
    orderable: { type: Boolean, default: true }
  }

  connect() {
    this.items = []
    this.initialSnapshot = null
    this.listeners = new ListenerManager()

    this.listeners.add(this.element, "editor:content-loaded", this.handleContentLoaded)
    this.listeners.add(this.element, "editor:collect", this.handleCollect)
    this.listeners.add(this.element, "editor:save", this.handleSave)
    this.listeners.add(this.element, "editor:modified", this.handleModified)
    this.listeners.add(this.element, "editor:reset", this.handleReset)
  }

  disconnect() {
    this.listeners.teardown()
  }

  handleContentLoaded = () => {
    const rows = this.listTarget.querySelectorAll(".aisle-row")
    this.items = Array.from(rows).map(row => createItem(row.dataset.name))
    this.initialSnapshot = takeSnapshot(this.items)
    this.render()
  }

  handleCollect = (event) => {
    event.detail.handled = true
    event.detail.data = this.buildItemPayload()
  }

  handleSave = (event) => {
    event.detail.handled = true
    event.detail.saveFn = () => saveRequest(this.saveUrlValue, "PATCH", this.buildItemPayload())
  }

  handleModified = (event) => {
    event.detail.handled = true
    event.detail.modified = isModified(this.items, this.initialSnapshot)
  }

  handleReset = (event) => {
    event.detail.handled = true
    this.items = []
    this.initialSnapshot = null
  }

  addItem() {
    const name = this.newItemNameTarget.value.trim()
    if (!name) return

    const errorsEl = this.element.querySelector("[data-editor-target='errors']")
    if (checkDuplicate(this.items, name)) {
      if (errorsEl) showErrors(errorsEl, [`"${name}" already exists.`])
      return
    }

    if (errorsEl) clearErrors(errorsEl)
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

  moveUp(index) {
    this.move(index, -1, "up")
  }

  moveDown(index) {
    this.move(index, 1, "down")
  }

  // Private

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
}
