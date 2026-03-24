import { Controller } from "@hotwired/stimulus"
import { sendAction } from "../utilities/turbo_fetch"
import ListenerManager from "../utilities/listener_manager"

/**
 * Groceries page — three zones (Inventory Check, To Buy, On Hand), optimistic
 * zone transitions, custom item input, and collapse persistence. Server-side
 * Turbo morphs are authoritative; this controller provides instant UI feedback.
 *
 * On Hand splits by recency: today items have checkboxes (undo purchase),
 * older items have "Need It" buttons (SM-2 blending). After exit animation,
 * buildOptimisticItem inserts a minimal <li> in the destination zone so the
 * subsequent morph is a near-no-op.
 *
 * - turbo_fetch (sendAction): fire-and-forget mutations with retry and error toast
 * - ListenerManager: tracks event listeners for clean teardown on disconnect
 */
export default class extends Controller {
  connect() {
    this.onHandKey = `grocery-on-hand-${this.element.dataset.kitchenSlug}`
    this.listeners = new ListenerManager()
    this.pendingMoves = new Set()

    this.cleanupOldStorage()
    this.cleanupCartStorage()
    this.bindShoppingListEvents()
    this.bindInventoryCheckButtons()
    this.bindCustomItemInput()
    this.bindCollapseToggle()
    this.restoreCollapseWithoutTransition()

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

      const li = cb.closest("li")
      if (li) {
        this.pendingMoves.add(name)
        const aisleGroup = li.closest(".aisle-group")
        const destZone = cb.checked ? "on-hand" : "to-buy"

        this.animateExit(li)
        setTimeout(() => this.insertOptimisticItem(name, destZone, aisleGroup), 260)
      }

      this.updateItemCount()
      sendAction(this.element.dataset.checkUrl, { item: name, checked: cb.checked })
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

  animateExit(li) {
    li.style.display = "grid"
    li.style.gridTemplateRows = "1fr"
    li.style.overflow = "hidden"
    li.firstElementChild.style.minHeight = "0"
    li.offsetHeight // force reflow so browser computes 1fr before transition
    li.classList.add("check-off-exit")
  }

  // --- Inventory check (Have It / Need It) ---

  bindInventoryCheckButtons() {
    this.listeners.add(this.element, "click", (e) => {
      if (e.target.closest("[data-grocery-action='confirm-all']")) {
        this.bulkIcAction(this.element.dataset.confirmAllUrl)
        return
      }

      if (e.target.closest("[data-grocery-action='deplete-all']")) {
        this.bulkIcAction(this.element.dataset.depleteAllUrl)
        return
      }

      const btn = e.target.closest("[data-grocery-action='have-it'], [data-grocery-action='need-it']")
      if (!btn) return

      const name = btn.dataset.item
      const action = btn.dataset.groceryAction
      const url = action === "have-it"
        ? this.element.dataset.haveItUrl
        : this.element.dataset.needItUrl

      sendAction(url, { item: name })

      this.pendingMoves.add(name)
      const li = btn.closest("li")
      const aisleGroup = li?.closest(".aisle-group")
      if (li) li.remove()

      if (aisleGroup) {
        const destZone = action === "have-it" ? "on-hand" : "to-buy"
        this.insertOptimisticItem(name, destZone, aisleGroup)
      }

      this.hideEmptyInventoryCheck()
      this.updateItemCount()
    })
  }

  bulkIcAction(url) {
    const lis = this.element.querySelectorAll(".inventory-check-items li")
    const items = Array.from(lis).map(li => li.dataset.item).filter(Boolean)
    if (items.length === 0) return

    sendAction(url, { items })

    items.forEach(name => this.pendingMoves.add(name))
    lis.forEach(li => li.remove())
    this.hideEmptyInventoryCheck()
    this.updateItemCount()
  }

  hideEmptyInventoryCheck() {
    const wrapper = this.element.querySelector(".inventory-check-wrapper")
    if (!wrapper) return

    const remaining = wrapper.querySelectorAll(".inventory-check-items li")
    if (remaining.length === 0) wrapper.remove()
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

    const { name, aisle } = this.parseCustomItemText(text)
    sendAction(url, { item: name, aisle: aisle || "Miscellaneous", action_type: "add" })
    input.value = ""
    input.focus()
  }

  parseCustomItemText(text) {
    const idx = text.lastIndexOf("@")
    if (idx < 0) return { name: text.trim(), aisle: null }

    const hint = text.slice(idx + 1).trim()
    if (!hint) return { name: text.slice(0, idx).trim(), aisle: null }

    return { name: text.slice(0, idx).trim(), aisle: hint }
  }

  // --- Collapse persistence ---

  cleanupOldStorage() {
    try {
      localStorage.removeItem(`grocery-aisles-${this.element.dataset.kitchenSlug}`)
    } catch { /* ignore */ }
  }

  bindCollapseToggle() {
    this.listeners.add(this.element, "toggle", (e) => {
      if (!e.target.matches("details.to-buy-section, details.on-hand-section, details.inventory-check-section")) return

      this.saveCollapseState()
    }, true)
  }

  saveCollapseState() {
    const state = {}

    const invCheck = this.element.querySelector("details.inventory-check-section")
    if (invCheck) state._inventory_check = invCheck.open

    this.element.querySelectorAll(".aisle-group").forEach(group => {
      const aisle = group.dataset.aisle
      if (!aisle) return

      const toBuy = group.querySelector("details.to-buy-section")
      const onHand = group.querySelector("details.on-hand-section")

      state[aisle] = {
        to_buy: toBuy ? toBuy.open : true,
        on_hand: onHand ? onHand.open : true
      }
    })

    try {
      localStorage.setItem(this.onHandKey, JSON.stringify(state))
    } catch { /* localStorage full */ }
  }

  restoreCollapseWithoutTransition() {
    this.element.style.setProperty("transition", "none", "important")
    this.element.querySelectorAll(".collapse-body").forEach(el => {
      el.style.setProperty("transition", "none", "important")
    })

    this.restoreCollapseState()

    this.element.offsetHeight
    this.element.style.removeProperty("transition")
    this.element.querySelectorAll(".collapse-body").forEach(el => {
      el.style.removeProperty("transition")
    })
  }

  restoreCollapseState() {
    const state = this.loadCollapseState()

    const invCheck = this.element.querySelector("details.inventory-check-section")
    if (invCheck && state._inventory_check === false) invCheck.open = false

    this.element.querySelectorAll(".aisle-group").forEach(group => {
      const aisle = group.dataset.aisle
      if (!aisle) return

      let entry = state[aisle]
      if (typeof entry === "boolean") {
        entry = { to_buy: true, on_hand: entry }
      }

      const toBuy = group.querySelector("details.to-buy-section")
      const onHand = group.querySelector("details.on-hand-section")

      if (toBuy && entry?.to_buy === false) toBuy.open = false
      if (onHand && entry?.on_hand === false) onHand.open = false
    })
  }

  loadCollapseState() {
    try {
      const raw = localStorage.getItem(this.onHandKey)
      return raw ? JSON.parse(raw) : {}
    } catch {
      return {}
    }
  }

  preserveOnHandStateOnRefresh(event) {
    if (!event.detail.render) return

    this.saveCollapseState()
    const originalRender = event.detail.render
    event.detail.render = async (...args) => {
      await originalRender(...args)
      this.restoreCollapseState()
      this.applyPendingMoves()
    }
  }

  cleanupCartStorage() {
    try {
      sessionStorage.removeItem(`grocery-in-cart-${this.element.dataset.kitchenSlug}`)
    } catch { /* ignore */ }
  }

  // --- Zone transition animations ---

  applyPendingMoves() {
    if (this.pendingMoves.size === 0) return

    this.pendingMoves.forEach(name => {
      const li = this.element.querySelector(
        `li[data-item="${CSS.escape(name)}"]`
      )
      if (!li) return

      this.animateEntry(li)
    })

    this.pendingMoves.clear()
  }

  animateEntry(li) {
    li.classList.add("check-off-enter")
    li.addEventListener("animationend", () => {
      li.classList.remove("check-off-enter")
    }, { once: true })
  }

  buildOptimisticItem(name, zone) {
    const li = document.createElement("li")
    li.dataset.item = name

    const label = document.createElement("label")
    label.className = "check-off"
    const cb = document.createElement("input")
    cb.className = "custom-checkbox"
    cb.type = "checkbox"
    cb.dataset.item = name
    if (zone === "on-hand") cb.checked = true
    const span = document.createElement("span")
    span.className = "item-text"
    span.textContent = name
    label.append(cb, span)
    li.append(label)

    return li
  }

  insertOptimisticItem(name, zone, aisleGroup) {
    if (!aisleGroup) return

    const selector = zone === "on-hand" ? ".on-hand-items" : ".to-buy-items"
    const ul = aisleGroup.querySelector(selector)
    if (!ul) return

    const li = this.buildOptimisticItem(name, zone)
    ul.appendChild(li)
    this.pendingMoves.delete(name)

    this.animateEntry(li)
  }
}
