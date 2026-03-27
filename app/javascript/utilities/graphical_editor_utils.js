/**
 * Shared utilities for graphical list editors. Pure functions for accordion
 * behavior, collection management, and card DOM construction. Used by both
 * recipe_graphical_controller and quickbites_graphical_controller to avoid
 * duplicating identical DOM-building and list-manipulation patterns.
 *
 * - recipe_graphical_controller: recipe step/ingredient editing
 * - quickbites_graphical_controller: category/item editing
 * - dom_builders: low-level element factories (buildIconButton, buildPillButton, buildInput)
 * - ordered_list_editor_utils: animateSwap/swapItems for move animations
 */

import { buildIconButton, buildPillButton } from "./dom_builders"
import { animateSwap, swapItems } from "./ordered_list_editor_utils"

// --- Accordion helpers ---

export function collapseAll(container) {
  container.querySelectorAll("details.collapse-header[open]").forEach(d => { d.open = false })
}

export function expandItem(container, index) {
  collapseAll(container)
  const card = container.children[index]
  if (!card) return
  const details = card.querySelector("details.collapse-header")
  if (details) details.open = true
}

export function toggleItem(container, index) {
  const card = container.children[index]
  if (!card) return
  const details = card.querySelector("details.collapse-header")
  if (details) details.open = !details.open
}

// --- Collection management ---

export function removeFromList(list, index, rebuildFn) {
  list.splice(index, 1)
  rebuildFn()
}

export function moveInList(list, index, direction, container, rebuildFn) {
  const target = index + direction
  if (target < 0 || target >= list.length) return

  if (container) {
    collapseAll(container)
    const rowA = container.children[index]
    const rowB = container.children[target]
    animateSwap(rowA, rowB, () => {
      swapItems(list, index, target)
      rebuildFn()
    })
  } else {
    swapItems(list, index, target)
    rebuildFn()
  }
}

export function rebuildContainer(container, items, buildFn) {
  container.replaceChildren()
  items.forEach((item, i) => container.appendChild(buildFn(i, item)))
}

// --- Card DOM builders ---

export function buildCardShell(detailsEl, bodyEl) {
  const card = document.createElement("div")
  card.className = "graphical-step-card"
  card.appendChild(detailsEl)
  card.appendChild(bodyEl)
  return card
}

export function buildCardDetails(titleEl, summaryEl, actionsEl) {
  const details = document.createElement("details")
  details.className = "collapse-header"

  const summary = document.createElement("summary")
  summary.className = "graphical-step-header"

  const titleArea = document.createElement("span")
  titleArea.className = "graphical-step-title-area"
  titleArea.appendChild(titleEl)
  titleArea.appendChild(summaryEl)
  summary.appendChild(titleArea)

  summary.appendChild(actionsEl)

  details.appendChild(summary)
  return details
}

export function buildCardTitle(text, fallback) {
  const span = document.createElement("span")
  span.className = "graphical-step-title"
  span.textContent = text || fallback
  return span
}

export function buildCountSummary(count, singular, plural) {
  const span = document.createElement("span")
  span.className = "graphical-ingredient-summary"
  span.textContent = count === 0 ? "" : `${count} ${count === 1 ? singular : plural}`
  return span
}

export function buildCardActions(index, onMove, onRemove, { total = 0 } = {}) {
  const actions = document.createElement("div")
  actions.className = "graphical-step-actions"

  const upBtn = buildIconButton("chevron", () => onMove(index, -1), { className: "btn-move-up", label: "Move up" })
  if (index === 0) upBtn.disabled = true
  actions.appendChild(upBtn)

  const downBtn = buildIconButton("chevron", () => onMove(index, 1), { className: "aisle-icon--flipped btn-move-down", label: "Move down" })
  if (total > 0 && index >= total - 1) downBtn.disabled = true
  actions.appendChild(downBtn)

  actions.appendChild(buildIconButton("delete", () => onRemove(index), { className: "btn-danger", label: "Remove" }))
  return actions
}

export function buildCollapseBody(contentFn) {
  const wrapper = document.createElement("div")
  wrapper.className = "collapse-body"

  const inner = document.createElement("div")
  inner.className = "collapse-inner graphical-step-body"
  contentFn(inner)

  wrapper.appendChild(inner)
  return wrapper
}

export function buildRowsSection(label, items, onAdd, buildRowFn, containerAttrs) {
  const section = document.createElement("div")
  section.className = "graphical-ingredients-section"

  const headerRow = document.createElement("div")
  headerRow.className = "graphical-ingredients-header"

  const labelEl = document.createElement("span")
  labelEl.textContent = label
  headerRow.appendChild(labelEl)

  section.appendChild(headerRow)

  const rowsContainer = document.createElement("div")
  rowsContainer.className = "graphical-ingredient-rows"
  if (containerAttrs) {
    Object.entries(containerAttrs).forEach(([key, value]) => {
      rowsContainer.dataset[key] = value
    })
  }
  items.forEach((item, i) => rowsContainer.appendChild(buildRowFn(i, item)))
  section.appendChild(rowsContainer)

  section.appendChild(buildPillButton("+ Add", onAdd))

  return section
}

export function updateMoveButtons(container) {
  const children = Array.from(container.children)
  const last = children.length - 1
  children.forEach((el, i) => {
    const up = el.querySelector(".btn-move-up")
    const down = el.querySelector(".btn-move-down")
    if (up) up.disabled = i === 0
    if (down) down.disabled = i >= last
  })
}

export function updateTitleDisplay(container, index, text, fallback) {
  const card = container.children[index]
  if (!card) return
  const titleEl = card.querySelector(".graphical-step-title")
  if (titleEl) titleEl.textContent = text || fallback
}
