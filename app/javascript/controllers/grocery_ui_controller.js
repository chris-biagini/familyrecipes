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

      const li = cb.closest("li[data-item]")
      const aisle = cb.closest(".aisle-group")

      if (cb.checked) {
        this.animateCheck(li, aisle)
      } else {
        this.animateUncheck(li, aisle)
      }

      this.updateItemCount()
      sendAction(this.element.dataset.checkUrl, { item: name, checked: cb.checked })
    })
  }

  updateItemCount() {
    const countEl = document.getElementById("item-count")
    if (!countEl) return

    const allItems = document.querySelectorAll("#shopping-list li[data-item]")
    const total = allItems.length
    const unchecked = Array.from(allItems).filter(li => {
      const cb = li.querySelector('input[type="checkbox"]')
      return cb && !cb.checked
    }).length

    if (total === 0) {
      countEl.textContent = ""
    } else if (unchecked === 0) {
      countEl.textContent = "\u2713 All done!"
    } else {
      countEl.textContent = `${unchecked} ${unchecked === 1 ? "item" : "items"} to buy`
    }
  }

  // --- Check/uncheck animations ---

  animateCheck(li, aisle) {
    if (!li || !aisle) return

    const timerId = setTimeout(() => {
      this.pendingTimers = this.pendingTimers.filter(id => id !== timerId)
      li.classList.add("item-checking")
      li.addEventListener("animationend", () => {
        this.moveToOnHand(li, aisle)
      }, { once: true })
    }, 400)
    this.pendingTimers.push(timerId)
  }

  moveToOnHand(li, aisle) {
    let onHandList = aisle.querySelector(".on-hand-items ul")
    let divider = aisle.querySelector(".on-hand-divider")

    if (!onHandList) {
      const toBuyList = aisle.querySelector(".to-buy-items")
      const idx = Array.from(document.querySelectorAll(".aisle-group")).indexOf(aisle)

      divider = document.createElement("button")
      divider.className = "on-hand-divider"
      divider.type = "button"
      divider.setAttribute("aria-expanded", "false")
      divider.setAttribute("aria-controls", `on-hand-${idx}`)

      const countSpan = document.createElement("span")
      countSpan.className = "on-hand-count"
      countSpan.textContent = "0 on hand"
      divider.appendChild(countSpan)

      const arrowSpan = document.createElement("span")
      arrowSpan.className = "on-hand-arrow"
      arrowSpan.textContent = "\u25B8"
      divider.appendChild(arrowSpan)

      const onHandDiv = document.createElement("div")
      onHandDiv.id = `on-hand-${idx}`
      onHandDiv.className = "on-hand-items"
      onHandDiv.hidden = true

      const ul = document.createElement("ul")
      onHandDiv.appendChild(ul)

      if (toBuyList) {
        toBuyList.after(divider, onHandDiv)
      } else {
        aisle.appendChild(divider)
        aisle.appendChild(onHandDiv)
      }
      onHandList = ul
    }

    li.classList.remove("item-checking")
    li.classList.add("item-appearing")
    onHandList.appendChild(li)
    li.addEventListener("animationend", () => {
      li.classList.remove("item-appearing")
    }, { once: true })

    this.updateOnHandCount(divider, aisle)

    const toBuyList = aisle.querySelector(".to-buy-items")
    if (toBuyList && toBuyList.children.length === 0) {
      this.collapseCompleteAisle(aisle)
    }
  }

  animateUncheck(li, aisle) {
    if (!li || !aisle) return

    let toBuyList = aisle.querySelector(".to-buy-items")

    if (!toBuyList) {
      const header = aisle.querySelector(".aisle-complete-header")
      const aisleName = aisle.dataset.aisle

      const h3 = document.createElement("h3")
      h3.className = "aisle-header"
      h3.textContent = aisleName

      toBuyList = document.createElement("ul")
      toBuyList.className = "to-buy-items"

      const divider = aisle.querySelector(".on-hand-divider")
      if (divider) {
        aisle.insertBefore(toBuyList, divider)
        aisle.insertBefore(h3, toBuyList)
      } else if (header) {
        header.after(h3, toBuyList)
      }
      aisle.classList.remove("aisle-complete")
    }

    li.classList.add("item-appearing")
    toBuyList.appendChild(li)
    li.addEventListener("animationend", () => {
      li.classList.remove("item-appearing")
    }, { once: true })

    const divider = aisle.querySelector(".on-hand-divider")
    this.updateOnHandCount(divider, aisle)

    const onHandList = aisle.querySelector(".on-hand-items ul")
    if (onHandList && onHandList.children.length === 0) {
      const onHandSection = aisle.querySelector(".on-hand-items")
      if (divider) divider.remove()
      if (onHandSection) onHandSection.remove()
    }
  }

  updateOnHandCount(divider, aisle) {
    if (!divider) return
    const count = aisle.querySelectorAll(".on-hand-items li[data-item]").length
    const countSpan = divider.querySelector(".on-hand-count")
    if (countSpan) countSpan.textContent = `${count} on hand`
  }

  collapseCompleteAisle(aisle) {
    aisle.classList.add("aisle-complete")
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

    this.element.querySelectorAll(".item-checking, .item-appearing").forEach(el => {
      el.classList.remove("item-checking", "item-appearing")
      el.style.animation = "none"
    })

    this.saveOnHandState()
    const originalRender = event.detail.render
    event.detail.render = async (...args) => {
      await originalRender(...args)
      this.restoreOnHandState()
    }
  }
}
