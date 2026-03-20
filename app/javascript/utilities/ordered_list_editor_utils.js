/**
 * Shared utilities for ordered-list editor dialogs (aisles, categories, tags).
 * Provides changeset tracking, row rendering, inline rename, reorder
 * animations, and payload serialization. Each Stimulus controller owns
 * its dialog lifecycle and fetch calls; this module handles the list logic.
 * Supports an `orderable` flag to suppress up/down buttons for unordered lists.
 *
 * - ordered_list_editor_controller: unified controller for aisles, categories, tags
 * - icons.js: SVG icon builder (chevron, delete, undo)
 * - editor.css (.aisle-row, .btn-icon-round): shared row and button styles
 */

import { buildIcon } from './icons'

// --- Data / State ---

export function createItem(originalName, currentName = null) {
  return {
    originalName,
    currentName: currentName || originalName,
    deleted: false
  }
}

export function buildPayload(items, orderKey = "order") {
  const live = items.filter(i => !i.deleted)
  const order = live.map(i => i.currentName)

  const renames = {}
  items.forEach(i => {
    if (!i.deleted && i.originalName !== null && i.originalName !== i.currentName) {
      renames[i.originalName] = i.currentName
    }
  })

  const deletes = items
    .filter(i => i.deleted && i.originalName !== null)
    .map(i => i.originalName)

  return { [orderKey]: order, renames, deletes }
}

export function takeSnapshot(items) {
  return JSON.stringify(items)
}

export function isModified(items, initialSnapshot) {
  return JSON.stringify(items) !== initialSnapshot
}

export function checkDuplicate(items, name, excludeIndex = -1) {
  const lower = name.toLowerCase()
  return items.some((item, i) =>
    i !== excludeIndex && !item.deleted && item.currentName.toLowerCase() === lower
  )
}

// --- DOM / Rendering ---

export function buildRowElement(item, index, liveItems, callbacks, orderable = true) {
  const row = document.createElement("div")
  row.className = rowClassName(item)
  row.dataset.index = index
  row.dataset.name = item.currentName

  row.appendChild(buildNameArea(item, index, callbacks))
  row.appendChild(buildControls(item, index, liveItems, callbacks, orderable))

  return row
}

export function renderRows(container, items, callbacks, orderable = true) {
  const liveItems = items
    .map((item, i) => item.deleted ? null : i)
    .filter(i => i !== null)

  const rows = items.map((item, index) =>
    buildRowElement(item, index, liveItems, callbacks, orderable)
  )
  container.replaceChildren(...rows)
}

export function updateDisabledStates(container) {
  const rows = Array.from(container.children)
  const liveIndices = rows
    .map((row, i) => row.classList.contains("aisle-row--deleted") ? null : i)
    .filter(i => i !== null)

  rows.forEach((row, i) => {
    const livePos = liveIndices.indexOf(i)
    updateButtonStates(row, livePos, liveIndices.length - 1)
  })
}

export function updateButtonStates(row, livePos, lastLiveIndex) {
  const up = row.querySelector(".btn-move-up")
  const down = row.querySelector(".btn-move-down")
  if (up) up.disabled = livePos <= 0
  if (down) down.disabled = livePos < 0 || livePos >= lastLiveIndex
}

// --- Interaction ---

export function startInlineRename(nameButton, item, onDone) {
  const input = document.createElement("input")
  input.type = "text"
  input.className = "aisle-rename-input"
  input.value = item.currentName
  input.maxLength = 50
  input.setAttribute("aria-label", `Rename ${item.currentName}`)
  if (item.originalName) input.placeholder = item.originalName

  const finishRename = () => {
    const newName = input.value.trim()
    if (newName && newName !== item.currentName) {
      item.currentName = newName
    }
    onDone()
  }

  const cancelRename = () => onDone()

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

  nameButton.replaceWith(input)
  input.focus()
  input.select()
}

export function swapItems(items, indexA, indexB) {
  const temp = items[indexA]
  items[indexA] = items[indexB]
  items[indexB] = temp
}

export function animateSwap(rowA, rowB, onComplete) {
  if (!rowA || !rowB) { onComplete(); return }

  const rectA = rowA.getBoundingClientRect()
  const rectB = rowB.getBoundingClientRect()
  const deltaA = rectB.top - rectA.top
  const deltaB = rectA.top - rectB.top

  rowA.style.transition = "none"
  rowB.style.transition = "none"
  rowA.style.transform = "translateY(0)"
  rowB.style.transform = "translateY(0)"
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
      onComplete()
    }, { once: true })
  })
}

// --- Private helpers ---

function rowClassName(item) {
  if (item.deleted) return "aisle-row aisle-row--deleted"
  if (item.originalName === null) return "aisle-row aisle-row--new"
  if (item.originalName !== item.currentName) return "aisle-row aisle-row--renamed"
  return "aisle-row"
}

function buildNameArea(item, index, callbacks) {
  const area = document.createElement("div")
  area.className = "aisle-name-area"

  if (item.deleted) {
    const nameSpan = document.createElement("span")
    nameSpan.className = "aisle-name"
    nameSpan.textContent = item.currentName
    area.appendChild(nameSpan)
  } else {
    const nameBtn = document.createElement("button")
    nameBtn.type = "button"
    nameBtn.className = "aisle-name"
    nameBtn.textContent = item.currentName
    nameBtn.dataset.index = index
    nameBtn.addEventListener("click", () => callbacks.onRename(index))
    area.appendChild(nameBtn)
  }

  return area
}

function buildControls(item, index, liveItems, callbacks, orderable = true) {
  const controls = document.createElement("div")
  controls.className = "aisle-controls"

  const livePos = liveItems.indexOf(index)

  if (orderable) {
    const upBtn = buildIconButton(buildIcon('chevron', 14), "btn-move-up", "Move up", index)
    upBtn.addEventListener("click", () => callbacks.onMoveUp(index))
    if (item.deleted || livePos === 0) upBtn.disabled = true
    controls.appendChild(upBtn)

    const downSvg = buildIcon('chevron', 14)
    downSvg.classList.add('aisle-icon--flipped')
    const downBtn = buildIconButton(downSvg, "btn-move-down", "Move down", index)
    downBtn.addEventListener("click", () => callbacks.onMoveDown(index))
    if (item.deleted || livePos === liveItems.length - 1) downBtn.disabled = true
    controls.appendChild(downBtn)
  }

  const toggleBtn = item.deleted
    ? buildIconButton(buildIcon('undo', 14), "btn-primary", "Undo delete", index)
    : buildIconButton(buildIcon('delete', 14), "btn-danger", "Delete", index)
  toggleBtn.addEventListener("click", () => {
    if (item.deleted) {
      callbacks.onUndo(index)
    } else {
      callbacks.onDelete(index)
    }
  })

  controls.appendChild(toggleBtn)
  return controls
}

function buildIconButton(svgElement, className, label, index) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.className = `btn-icon-round ${className}`
  btn.setAttribute("aria-label", label)
  btn.dataset.index = index
  btn.appendChild(svgElement)
  return btn
}
