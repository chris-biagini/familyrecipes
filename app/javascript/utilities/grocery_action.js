/**
 * Builds the grocery section in the search overlay — a floating panel with
 * full-height ingredient rows that lets users quick-add items to their grocery
 * list without leaving the search dialog. The section positions above or below
 * recipe results based on match quality (tier-based positioning in the controller).
 *
 * Collaborators:
 *   - search_overlay_controller.js (renders, positions, and triggers actions)
 *   - GroceriesController#need (server endpoint for adding items)
 *   - editor_utils.js (CSRF token)
 */
import { getCsrfToken } from "./editor_utils"

export function buildGrocerySection(matches, query, { customItems = [] } = {}) {
  const ingredients = matches.length > 0 ? matches.slice(0, 4) : [query]

  const section = document.createElement("li")
  section.className = "grocery-section"

  const header = document.createElement("div")
  header.className = "grocery-section-header"
  header.textContent = "Add to grocery list"
  section.appendChild(header)

  const rows = []
  ingredients.forEach(name => {
    const row = document.createElement("div")
    row.className = "search-result grocery-item-row"
    row.setAttribute("role", "option")
    row.dataset.groceryAction = "true"
    row.dataset.ingredient = name

    const title = document.createElement("span")
    title.className = "search-result-title"
    title.textContent = name

    row.appendChild(title)

    const custom = customItems.find(c => c.name.toLowerCase() === name.toLowerCase())
    if (custom && custom.aisle && custom.aisle !== "Miscellaneous") {
      const aisle = document.createElement("span")
      aisle.className = "search-result-category"
      aisle.textContent = custom.aisle
      row.appendChild(aisle)
    }

    section.appendChild(row)
    rows.push(row)
  })

  return { section, rows }
}

export function buildAlreadyNeededRow(name) {
  const li = document.createElement("li")
  li.className = "search-result grocery-already-needed"
  li.setAttribute("role", "option")

  li.textContent = `\u2713 ${name} is already on your list`

  return li
}

export function postNeedAction(url, item, aisle) {
  return fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": getCsrfToken()
    },
    body: JSON.stringify({ item, aisle: aisle || "Miscellaneous" })
  }).then(r => r.json())
}

export function flashAndClose(row, status, closeCallback) {
  if (status === "already_needed") {
    row.textContent = "\u2713 Already on your list"
  } else {
    row.textContent = "\u2713 Added!"
  }
  row.classList.add("grocery-action-flash")

  setTimeout(() => closeCallback(), 500)
}
