/**
 * Shared utilities for ordered-list editor dialogs (aisles, categories, tags).
 * Provides changeset tracking, row rendering, inline rename, reorder
 * animations, and payload serialization. Each Stimulus controller owns
 * its dialog lifecycle and fetch calls; this module handles the list logic.
 * Supports an `orderable` flag to suppress up/down buttons for unordered lists.
 *
 * - ordered_list_editor_controller: unified controller for aisles, categories, tags
 * - style.css (.aisle-row, .aisle-btn): shared row and button styles
 */

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
  const up = row.querySelector(".aisle-btn--up")
  const down = row.querySelector(".aisle-btn--down")
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
    const upBtn = buildIconButton(chevronSvg(), "aisle-btn--up", "Move up", index)
    upBtn.addEventListener("click", () => callbacks.onMoveUp(index))
    if (item.deleted || livePos === 0) upBtn.disabled = true
    controls.appendChild(upBtn)

    const downBtn = buildIconButton(chevronSvg(true), "aisle-btn--down", "Move down", index)
    downBtn.addEventListener("click", () => callbacks.onMoveDown(index))
    if (item.deleted || livePos === liveItems.length - 1) downBtn.disabled = true
    controls.appendChild(downBtn)
  }

  const toggleBtn = item.deleted
    ? buildIconButton(undoSvg(), "aisle-btn--undo", "Undo delete", index)
    : buildIconButton(deleteSvg(), "aisle-btn--delete", "Delete", index)
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
  btn.className = `aisle-btn ${className}`
  btn.setAttribute("aria-label", label)
  btn.dataset.index = index
  btn.appendChild(svgElement)
  return btn
}

function chevronSvg(flipped = false) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  svg.setAttribute("viewBox", "0 0 24 24")
  svg.setAttribute("width", "14")
  svg.setAttribute("height", "14")
  svg.setAttribute("fill", "none")
  if (flipped) svg.classList.add("aisle-icon--flipped")
  const path = document.createElementNS("http://www.w3.org/2000/svg", "polyline")
  path.setAttribute("points", "6 15 12 9 18 15")
  path.setAttribute("stroke", "currentColor")
  path.setAttribute("stroke-width", "2")
  path.setAttribute("stroke-linecap", "round")
  path.setAttribute("stroke-linejoin", "round")
  svg.appendChild(path)
  return svg
}

function deleteSvg() {
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

function undoSvg() {
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
