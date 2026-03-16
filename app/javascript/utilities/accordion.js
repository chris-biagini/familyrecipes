/**
 * Accordion collapse/expand behavior for graphical editor cards.
 * Operates on a container element whose direct children are cards,
 * each containing `.graphical-step-body` (collapsible) and
 * `.graphical-step-toggle-icon` (▶/▼ indicator). Pure DOM
 * manipulation, no Stimulus coupling.
 *
 * - recipe_graphical_controller: step cards
 * - quickbites_graphical_controller: category cards
 */

export function toggleAccordionItem(container, index) {
  const card = container.children[index]
  if (!card) return
  const body = card.querySelector(".graphical-step-body")
  const icon = card.querySelector(".graphical-step-toggle-icon")
  if (!body) return

  const isHidden = body.hidden
  body.hidden = !isHidden
  if (icon) icon.textContent = isHidden ? "\u25BC" : "\u25B6"
}

export function expandAccordionItem(container, index) {
  collapseAllAccordionItems(container)
  toggleAccordionItem(container, index)
}

export function collapseAllAccordionItems(container) {
  const cards = container.children
  for (let i = 0; i < cards.length; i++) {
    const body = cards[i].querySelector(".graphical-step-body")
    const icon = cards[i].querySelector(".graphical-step-toggle-icon")
    if (body) body.hidden = true
    if (icon) icon.textContent = "\u25B6"
  }
}

export function buildToggleButton(onToggle) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.className = "graphical-step-toggle"
  const icon = document.createElement("span")
  icon.className = "graphical-step-toggle-icon"
  icon.textContent = "\u25B6"
  btn.appendChild(icon)
  btn.addEventListener("click", onToggle)
  return btn
}
