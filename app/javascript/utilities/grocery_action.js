/**
 * Builds and manages the grocery action row in the search overlay — the "Need X?"
 * prompt that lets users quick-add ingredients to their grocery list without
 * leaving the search dialog. Handles DOM construction, alternate suggestions,
 * POST submission, and flash-and-close confirmation animation.
 *
 * Collaborators:
 *   - search_overlay_controller.js (renders and triggers actions)
 *   - GroceriesController#need (server endpoint for adding items)
 *   - editor_utils.js (CSRF token)
 */
import { getCsrfToken } from "./editor_utils"

export function buildGroceryActionRow(topMatch, alternates, { customItems = [] } = {}) {
  const items = []

  const li = document.createElement("li")
  li.className = "search-result grocery-action-row"
  li.setAttribute("role", "option")
  li.dataset.groceryAction = "true"
  li.dataset.ingredient = topMatch

  const left = document.createElement("span")
  left.className = "grocery-action-left"

  const label = document.createDocumentFragment()
  label.appendChild(document.createTextNode("\uD83D\uDED2 Need "))
  const strong = document.createElement("strong")
  strong.textContent = topMatch
  label.appendChild(strong)
  label.appendChild(document.createTextNode("?"))

  left.appendChild(label)

  const custom = customItems.find(c => c.name.toLowerCase() === topMatch.toLowerCase())
  if (custom && custom.aisle && custom.aisle !== "Miscellaneous") {
    const aisle = document.createElement("span")
    aisle.className = "grocery-action-aisle"
    aisle.textContent = custom.aisle
    left.appendChild(aisle)
  }

  const hint = document.createElement("span")
  hint.className = "grocery-action-hint"
  hint.textContent = "\u21B5"

  li.appendChild(left)
  li.appendChild(hint)
  items.push(li)

  if (alternates && alternates.length > 0) {
    const altLi = document.createElement("li")
    altLi.className = "grocery-alternates"
    altLi.appendChild(document.createTextNode("also: "))

    alternates.forEach((alt, i) => {
      if (i > 0) altLi.appendChild(document.createTextNode(", "))
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "grocery-alternate-btn"
      btn.textContent = alt
      btn.dataset.ingredient = alt
      altLi.appendChild(btn)
    })

    items.push(altLi)
  }

  return items
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
