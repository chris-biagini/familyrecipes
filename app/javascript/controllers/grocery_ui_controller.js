import { Controller } from "@hotwired/stimulus"
import { sendAction } from "../utilities/turbo_fetch"
import ListenerManager from "../utilities/listener_manager"

/**
 * Groceries page interaction — optimistic checkbox toggle, inventory check
 * buttons (Have It / Need It), custom item input, on-hand section collapse
 * persistence. All rendering is server-side via Turbo page-refresh morphs;
 * this controller handles user interactions and preserves local state
 * (on-hand expand/collapse) across morphs.
 *
 * Three zones: Inventory Check (unknown items), To Buy (confirmed needed),
 * On Hand (confirmed in stock). Have It / Need It buttons resolve items out
 * of the Inventory Check zone; checkbox toggle moves between To Buy and On Hand.
 *
 * Item zone movement is handled by server morphs after button/checkbox clicks.
 * CSS transitions provide immediate visual feedback. The counter updates
 * optimistically before the morph arrives.
 *
 * - turbo_fetch (sendAction): fire-and-forget mutations with retry and error toast
 * - ListenerManager: tracks event listeners for clean teardown on disconnect
 */
export default class extends Controller {
  connect() {
    this.onHandKey = `grocery-on-hand-${this.element.dataset.kitchenSlug}`
    this.listeners = new ListenerManager()

    this.cleanupOldStorage()
    this.bindShoppingListEvents()
    this.bindInventoryCheckButtons()
    this.bindCustomItemInput()
    this.bindOnHandToggle()
    this.restoreOnHandState()
    this.applyInCartState()

    this.listeners.add(document, "turbo:before-render", (e) => this.preserveOnHandStateOnRefresh(e))
  }

  disconnect() {
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

      if (cb.checked) {
        this.addToCart(name)
      } else {
        this.removeFromCart(name)
      }
    })
  }

  updateItemCount() {
    const countEl = document.getElementById("item-count")
    if (!countEl) return

    const toBuyItems = document.querySelectorAll("#shopping-list .to-buy-items li[data-item]")
    const unchecked = Array.from(toBuyItems).filter(li => {
      const cb = li.querySelector('input[type="checkbox"]')
      return cb && !cb.checked
    }).length

    if (toBuyItems.length === 0) {
      countEl.textContent = ""
    } else if (unchecked === 0) {
      countEl.textContent = "\u2713 All done!"
    } else {
      countEl.textContent = `${unchecked} ${unchecked === 1 ? "item" : "items"} to buy`
    }
  }

  // --- Inventory check (Have It / Need It) ---

  bindInventoryCheckButtons() {
    this.listeners.add(this.element, "click", (e) => {
      const btn = e.target.closest("[data-grocery-action='have-it'], [data-grocery-action='need-it']")
      if (!btn) return

      const name = btn.dataset.item
      const action = btn.dataset.groceryAction
      const url = action === "have-it"
        ? this.element.dataset.haveItUrl
        : this.element.dataset.needItUrl

      sendAction(url, { item: name })

      const li = btn.closest("li")
      if (li) li.remove()

      this.hideEmptyInventoryCheck()
      this.updateItemCount()
    })
  }

  hideEmptyInventoryCheck() {
    const section = this.element.querySelector(".inventory-check-section")
    if (!section) return

    const remaining = section.querySelectorAll(".inventory-check-items li")
    if (remaining.length === 0) section.remove()
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
    this.listeners.add(this.element, "toggle", (e) => {
      if (!e.target.matches("details.on-hand-section")) return

      this.saveOnHandState()
    }, true)
  }

  saveOnHandState() {
    const expanded = {}
    this.element.querySelectorAll("details.on-hand-section").forEach(details => {
      const aisle = details.closest(".aisle-group")?.dataset.aisle
      if (aisle) expanded[aisle] = details.open
    })

    try {
      localStorage.setItem(this.onHandKey, JSON.stringify(expanded))
    } catch { /* localStorage full */ }
  }

  restoreOnHandState() {
    const state = this.loadOnHandState()
    this.element.querySelectorAll("details.on-hand-section").forEach(details => {
      const aisle = details.closest(".aisle-group")?.dataset.aisle
      if (!aisle || !state[aisle]) return

      details.open = true
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
      this.applyInCartState()
    }
  }

  // --- In cart (shopping trip boundary) ---

  get cartKey() {
    return `grocery-in-cart-${this.element.dataset.kitchenSlug}`
  }

  loadCart() {
    try {
      const raw = sessionStorage.getItem(this.cartKey)
      if (!raw) return new Set()

      const parsed = JSON.parse(raw)
      if (Array.isArray(parsed)) return this.clearCart()

      const fourHours = 4 * 60 * 60 * 1000
      if (Date.now() - parsed.ts > fourHours) return this.clearCart()

      return new Set(parsed.items)
    } catch {
      return new Set()
    }
  }

  saveCart(cart) {
    try {
      sessionStorage.setItem(this.cartKey, JSON.stringify({ items: [...cart], ts: Date.now() }))
    } catch { /* sessionStorage full */ }
  }

  clearCart() {
    sessionStorage.removeItem(this.cartKey)
    return new Set()
  }

  addToCart(name) {
    const cart = this.loadCart()
    cart.add(name)
    this.saveCart(cart)
  }

  removeFromCart(name) {
    const cart = this.loadCart()
    cart.delete(name)
    this.saveCart(cart)
  }

  applyInCartState() {
    const cart = this.loadCart()
    if (cart.size === 0) return

    cart.forEach(name => {
      const onHandItem = this.element.querySelector(
        `.on-hand-items li[data-item="${CSS.escape(name)}"]`
      )
      if (!onHandItem) return

      const aisle = onHandItem.closest('.aisle-group')
      if (!aisle) return

      const toBuyList = aisle.querySelector('.to-buy-items')
      if (!toBuyList) return

      onHandItem.classList.add('in-cart')
      const cb = onHandItem.querySelector('input[type="checkbox"]')
      if (cb) cb.checked = true
      toBuyList.appendChild(onHandItem)
    })

    this.updateItemCount()
  }
}
