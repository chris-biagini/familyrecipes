import { Controller } from "@hotwired/stimulus"
import { sendAction } from "../utilities/turbo_fetch"
import ListenerManager from "../utilities/listener_manager"

/**
 * Groceries page interaction — optimistic checkbox toggle, custom item input,
 * on-hand section collapse persistence. All rendering is server-side via Turbo
 * page-refresh morphs; this controller handles user interactions and preserves
 * local state (on-hand expand/collapse) across morphs.
 *
 * - turbo_fetch (sendAction): fire-and-forget mutations with retry and error toast
 * - ListenerManager: tracks event listeners for clean teardown on disconnect
 */
export default class extends Controller {
  connect() {
    this.onHandKey = `grocery-on-hand-${this.element.dataset.kitchenSlug}`
    this.listeners = new ListenerManager()
    this.pendingTimers = []

    this.cleanupOldStorage()
    this.bindShoppingListEvents()
    this.bindCustomItemInput()
    this.bindOnHandToggle()
    this.restoreOnHandState()

    this.listeners.add(document, "turbo:before-render", (e) => this.preserveOnHandStateOnRefresh(e))
  }

  disconnect() {
    this.pendingTimers.forEach(id => clearTimeout(id))
    this.pendingTimers = []
    this.listeners.teardown()
  }

  // --- Shopping list ---

  bindShoppingListEvents() {
    this.listeners.add(this.element, "change", (e) => {
      const cb = e.target
      if (!cb.matches('#shopping-list .check-off input[type="checkbox"]')) return

      const name = cb.dataset.item
      if (!name) return

      this.updateItemCount()

      sendAction(this.element.dataset.checkUrl, { item: name, checked: cb.checked })
    })
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

  // --- On-hand section collapse ---

  cleanupOldStorage() {
    try {
      localStorage.removeItem(`grocery-aisles-${this.element.dataset.kitchenSlug}`)
    } catch { /* ignore */ }
  }

  bindOnHandToggle() {
    this.listeners.add(this.element, "click", (e) => {
      const btn = e.target.closest(".on-hand-divider, .aisle-complete-header")
      if (!btn) return

      const targetId = btn.getAttribute("aria-controls")
      const target = document.getElementById(targetId)
      if (!target) return

      const expanding = target.hidden
      target.hidden = !expanding
      btn.setAttribute("aria-expanded", String(expanding))

      this.saveOnHandState()
    })
  }

  saveOnHandState() {
    const expanded = {}
    this.element.querySelectorAll("[aria-controls^='on-hand-']").forEach(btn => {
      const aisle = btn.closest(".aisle-group")?.dataset.aisle
      if (aisle) expanded[aisle] = btn.getAttribute("aria-expanded") === "true"
    })

    try {
      localStorage.setItem(this.onHandKey, JSON.stringify(expanded))
    } catch { /* localStorage full */ }
  }

  restoreOnHandState() {
    const state = this.loadOnHandState()
    this.element.querySelectorAll("[aria-controls^='on-hand-']").forEach(btn => {
      const aisle = btn.closest(".aisle-group")?.dataset.aisle
      if (!aisle || !state[aisle]) return

      const targetId = btn.getAttribute("aria-controls")
      const target = document.getElementById(targetId)
      if (!target) return

      target.hidden = false
      btn.setAttribute("aria-expanded", "true")
    })
  }

  loadOnHandState() {
    try {
      const raw = localStorage.getItem(this.onHandKey)
      return raw ? JSON.parse(raw) : {}
    } catch {
      return {}
    }
  }

  preserveOnHandStateOnRefresh(event) {
    if (!event.detail.render) return
    this.saveOnHandState()
    const originalRender = event.detail.render
    event.detail.render = async (...args) => {
      await originalRender(...args)
      this.restoreOnHandState()
    }
  }
}
