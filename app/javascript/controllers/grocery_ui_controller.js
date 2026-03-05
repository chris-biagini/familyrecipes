import { Controller } from "@hotwired/stimulus"
import { sendAction } from "utilities/turbo_fetch"
import ListenerManager from "utilities/listener_manager"

/**
 * Groceries page interaction — optimistic checkbox toggle, custom item input,
 * aisle collapse persistence. All rendering is server-side via Turbo page-refresh
 * morphs; this controller only handles user interactions and preserves local
 * state (aisle collapse) across morphs.
 */
export default class extends Controller {
  connect() {
    this.aisleCollapseKey = `grocery-aisles-${this.element.dataset.kitchenSlug}`
    this.listeners = new ListenerManager()

    this.bindShoppingListEvents()
    this.bindCustomItemInput()
    this.restoreAisleCollapse()

    this.listeners.add(document, "turbo:before-render", (e) => this.preserveAisleStateOnRefresh(e))
  }

  disconnect() {
    this.listeners.teardown()
  }

  // --- Shopping list ---

  bindShoppingListEvents() {
    const shoppingList = document.getElementById("shopping-list")

    this.listeners.add(shoppingList, "change", (e) => {
      const cb = e.target
      if (!cb.matches('.check-off input[type="checkbox"]')) return

      const name = cb.dataset.item
      if (!name) return

      this.updateAisleCount(cb.closest(".aisle-group"))
      this.updateItemCount()

      sendAction(this.element.dataset.checkUrl, { item: name, checked: cb.checked })
    })

    this.listeners.add(shoppingList, "toggle", (e) => {
      if (e.target.matches("details.aisle")) this.saveAisleCollapse()
    }, true)
  }

  updateAisleCount(details) {
    if (!details) return
    const checkboxes = details.querySelectorAll('li[data-item] input[type="checkbox"]')
    const total = checkboxes.length
    const checked = Array.from(checkboxes).filter(cb => cb.checked).length
    const remaining = total - checked

    const countSpan = details.querySelector(".aisle-count")
    if (!countSpan) return

    if (remaining === 0 && total > 0) {
      countSpan.textContent = "\u2713"
      countSpan.classList.add("aisle-done")
    } else {
      countSpan.textContent = `(${remaining})`
      countSpan.classList.remove("aisle-done")
    }
  }

  updateItemCount() {
    const countEl = document.getElementById("item-count")
    if (!countEl) return

    const items = document.querySelectorAll("#shopping-list li[data-item]")
    const total = items.length
    const checked = Array.from(items).filter(li => {
      const cb = li.querySelector('input[type="checkbox"]')
      return cb && cb.checked
    }).length
    const remaining = total - checked

    if (total === 0) {
      countEl.textContent = ""
    } else if (remaining === 0) {
      countEl.textContent = "\u2713 All done!"
    } else if (checked > 0) {
      countEl.textContent = `${remaining} of ${total} items needed`
    } else {
      countEl.textContent = `${total} ${total === 1 ? "item" : "items"}`
    }
  }

  // --- Custom items (delegated from controller root to survive morphs) ---

  bindCustomItemInput() {
    const url = this.element.dataset.customItemsUrl

    this.listeners.add(this.element, "click", (e) => {
      if (e.target.closest("#custom-add")) {
        this.addCustomItem(url)
      } else {
        const btn = e.target.closest(".custom-item-remove")
        if (btn) sendAction(url, { item: btn.dataset.item, action_type: "remove" })
      }
    })

    this.listeners.add(this.element, "keydown", (e) => {
      if (e.target.id === "custom-input" && e.key === "Enter") {
        e.preventDefault()
        this.addCustomItem(url)
      }
    })
  }

  addCustomItem(url) {
    const input = document.getElementById("custom-input")
    if (!input) return

    const text = input.value.trim()
    if (!text) return

    sendAction(url, { item: text, action_type: "add" })
    input.value = ""
    input.focus()
  }

  // --- Aisle collapse ---

  saveAisleCollapse() {
    const collapsed = Array.from(document.querySelectorAll("#shopping-list details.aisle"))
      .filter(d => !d.open)
      .map(d => d.dataset.aisle)

    try {
      localStorage.setItem(this.aisleCollapseKey, JSON.stringify(collapsed))
    } catch { /* localStorage full */ }
  }

  restoreAisleCollapse() {
    const collapsed = this.loadCollapsedAisles()
    collapsed.forEach(aisle => {
      const details = document.querySelector(`#shopping-list details.aisle[data-aisle="${CSS.escape(aisle)}"]`)
      if (details) details.open = false
    })
  }

  loadCollapsedAisles() {
    try {
      const raw = localStorage.getItem(this.aisleCollapseKey)
      return raw ? JSON.parse(raw) : []
    } catch {
      return []
    }
  }

  preserveAisleStateOnRefresh(event) {
    if (!event.detail.render) return
    this.saveAisleCollapse()
    const originalRender = event.detail.render
    event.detail.render = async (...args) => {
      await originalRender(...args)
      this.restoreAisleCollapse()
    }
  }
}
