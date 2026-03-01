import { Controller } from "@hotwired/stimulus"

function formatNumber(val) {
  const num = typeof val === "string" ? parseFloat(val) : val
  return parseFloat(num.toFixed(2)).toString()
}

function formatAmounts(amounts) {
  if (!amounts || amounts.length === 0) return ""

  const parts = amounts.map(([value, unit]) => {
    const formatted = formatNumber(value)
    return unit ? `${formatted}\u00a0${unit}` : formatted
  })
  return `(${parts.join(" + ")})`
}

export default class extends Controller {
  connect() {
    this.element.classList.remove("hidden-until-js")
    this.aisleCollapseKey = `grocery-aisles-${this.element.dataset.kitchenSlug}`
    this.boundHandlers = new Map()

    this.bindCustomItemInput()
    this.bindShoppingListEvents()
  }

  disconnect() {
    for (const [node, handlers] of this.boundHandlers) {
      for (const [event, handler] of handlers) {
        node.removeEventListener(event, handler)
      }
    }
    this.boundHandlers.clear()
  }

  addListener(node, event, handler) {
    node.addEventListener(event, handler)
    if (!this.boundHandlers.has(node)) this.boundHandlers.set(node, [])
    this.boundHandlers.get(node).push([event, handler])
  }

  get syncController() {
    return this.application.getControllerForElementAndIdentifier(this.element, "grocery-sync")
  }

  applyState(state) {
    this.renderShoppingList(state.shopping_list || {})
    this.renderCustomItems(state.custom_items || [])
    this.syncCheckedOff(state.checked_off || [])
    this.renderItemCount()
  }

  renderShoppingList(shoppingList) {
    const container = document.getElementById("shopping-list")
    const aisles = Object.keys(shoppingList)
    const collapsed = this.loadAisleCollapse()

    container.textContent = ""

    const header = document.createElement("div")
    header.className = "shopping-list-header"
    const h2 = document.createElement("h2")
    h2.textContent = "Shopping List"
    const countEl = document.createElement("span")
    countEl.id = "item-count"
    header.appendChild(h2)
    header.appendChild(countEl)
    container.appendChild(header)

    if (aisles.length === 0) {
      const emptyMsg = document.createElement("p")
      emptyMsg.id = "grocery-preview-empty"
      emptyMsg.textContent = "No items yet."
      container.appendChild(emptyMsg)
      return
    }

    for (const aisle of aisles) {
      const items = shoppingList[aisle]
      const isCollapsed = collapsed.indexOf(aisle) !== -1

      const details = document.createElement("details")
      details.className = "aisle"
      details.dataset.aisle = aisle
      if (!isCollapsed) details.open = true

      const summary = document.createElement("summary")
      summary.appendChild(document.createTextNode(`${aisle} `))
      const aisleCount = document.createElement("span")
      aisleCount.className = "aisle-count"
      summary.appendChild(aisleCount)
      details.appendChild(summary)

      const ul = document.createElement("ul")

      for (const item of items) {
        const amountStr = formatAmounts(item.amounts)

        const li = document.createElement("li")
        li.dataset.item = item.name

        const label = document.createElement("label")
        label.className = "check-off"

        const checkbox = document.createElement("input")
        checkbox.type = "checkbox"
        checkbox.dataset.item = item.name

        const textSpan = document.createElement("span")
        textSpan.className = "item-text"
        textSpan.textContent = amountStr ? `${item.name} ` : item.name

        if (amountStr) {
          const amountNode = document.createElement("span")
          amountNode.className = "item-amount"
          amountNode.textContent = amountStr
          textSpan.appendChild(amountNode)
        }

        label.appendChild(checkbox)
        label.appendChild(textSpan)

        li.appendChild(label)

        if (item.sources && item.sources.length > 0) {
          li.title = `Needed for: ${item.sources.join(', ')}`
        }

        ul.appendChild(li)
      }

      details.appendChild(ul)
      container.appendChild(details)

      const toggleHandler = () => this.saveAisleCollapse()
      this.addListener(details, "toggle", toggleHandler)
    }
  }

  renderCustomItems(items) {
    const container = document.getElementById("custom-items-list")
    container.textContent = ""

    for (const name of items) {
      const li = document.createElement("li")

      const span = document.createElement("span")
      span.textContent = name

      const btn = document.createElement("button")
      btn.className = "custom-item-remove"
      btn.type = "button"
      btn.textContent = "\u00d7"
      btn.setAttribute("aria-label", `Remove ${name}`)
      btn.dataset.item = name

      li.appendChild(span)
      li.appendChild(btn)
      container.appendChild(li)
    }
  }

  syncCheckedOff(checkedOff) {
    document.querySelectorAll('#shopping-list input[type="checkbox"][data-item]').forEach(cb => {
      cb.checked = checkedOff.indexOf(cb.dataset.item) !== -1
    })
  }

  renderItemCount() {
    this.updateAisleCounts()

    const countEl = document.getElementById("item-count")
    if (!countEl) return

    let total = 0
    let checked = 0

    document.querySelectorAll("#shopping-list li[data-item]").forEach(li => {
      total++
      const cb = li.querySelector('input[type="checkbox"]')
      if (cb && cb.checked) checked++
    })

    const remaining = total - checked

    if (total === 0) {
      countEl.textContent = ""
    } else if (remaining === 0) {
      countEl.textContent = "\u2713 All done!"
      countEl.classList.add("all-done")
    } else {
      countEl.classList.remove("all-done")
      if (checked > 0) {
        countEl.textContent = `${remaining} of ${total} items needed`
      } else {
        countEl.textContent = `${total} ${total === 1 ? "item" : "items"}`
      }
    }
  }

  updateAisleCounts() {
    document.querySelectorAll("#shopping-list details.aisle").forEach(details => {
      let total = 0
      let checked = 0

      details.querySelectorAll("li[data-item]").forEach(li => {
        total++
        const cb = li.querySelector('input[type="checkbox"]')
        if (cb && cb.checked) checked++
      })

      const countSpan = details.querySelector(".aisle-count")
      if (!countSpan) return

      const remaining = total - checked
      if (remaining === 0 && total > 0) {
        countSpan.textContent = "\u2713"
        countSpan.classList.add("aisle-done")
      } else {
        countSpan.textContent = `(${remaining})`
        countSpan.classList.remove("aisle-done")
      }
    })
  }

  saveAisleCollapse() {
    const collapsed = []
    document.querySelectorAll("#shopping-list details.aisle").forEach(details => {
      if (!details.open) collapsed.push(details.dataset.aisle)
    })

    try {
      localStorage.setItem(this.aisleCollapseKey, JSON.stringify(collapsed))
    } catch { /* localStorage full or unavailable */ }
  }

  loadAisleCollapse() {
    try {
      const raw = localStorage.getItem(this.aisleCollapseKey)
      return raw ? JSON.parse(raw) : []
    } catch {
      return []
    }
  }

  bindCustomItemInput() {
    const input = document.getElementById("custom-input")
    const addBtn = document.getElementById("custom-add")
    const customList = document.getElementById("custom-items-list")

    const addItem = () => {
      const text = input.value.trim()
      if (!text) return

      this.syncController.sendAction(this.syncController.urls.customItems, {
        item: text,
        action_type: "add"
      })

      input.value = ""
      input.focus()
    }

    this.addListener(addBtn, "click", addItem)

    this.addListener(input, "keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault()
        addItem()
      }
    })

    this.addListener(customList, "click", (e) => {
      const btn = e.target.closest(".custom-item-remove")
      if (!btn) return

      this.syncController.sendAction(this.syncController.urls.customItems, {
        item: btn.dataset.item,
        action_type: "remove"
      })
    })
  }

  bindShoppingListEvents() {
    const shoppingList = document.getElementById("shopping-list")

    this.addListener(shoppingList, "change", (e) => {
      const cb = e.target
      if (!cb.matches('.check-off input[type="checkbox"]')) return

      const name = cb.dataset.item
      if (!name) return

      this.syncController.sendAction(this.syncController.urls.check, {
        item: name,
        checked: cb.checked
      })

      this.renderItemCount()
    })
  }
}
