import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { show as notifyShow } from "utilities/notify"

export default class extends Controller {
  connect() {
    const slug = this.element.dataset.kitchenSlug

    this.storageKey = `menu-state-${slug}`
    this.version = 0
    this.state = {}
    this.awaitingOwnAction = false
    this.initialFetch = true

    this.urls = {
      state: this.element.dataset.stateUrl,
      select: this.element.dataset.selectUrl,
      selectAll: this.element.dataset.selectAllUrl,
      clear: this.element.dataset.clearUrl
    }

    this.loadCache()
    if (this.state && Object.keys(this.state).length > 0) {
      this.syncCheckboxes(this.state)
      this.syncAvailability(this.state)
    }

    this.fetchState()
    this.subscribe(slug)
    this.startHeartbeat()

    this.bindRecipeCheckboxes()

    this.element.addEventListener('click', (e) => {
      const dot = e.target.closest('.availability-dot')
      if (dot) {
        e.preventDefault()
        e.stopPropagation()
        this.showPopover(dot)
      }
    })

    this.boundHandleStreamRender = this.handleStreamRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this.boundHandleStreamRender)
  }

  disconnect() {
    this.hidePopover()
    if (this.fetchController) this.fetchController.abort()
    if (this.heartbeatId) {
      clearInterval(this.heartbeatId)
      this.heartbeatId = null
    }
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    if (this.consumer) {
      this.consumer.disconnect()
      this.consumer = null
    }
    if (this.boundHandleStreamRender) {
      document.removeEventListener("turbo:before-stream-render", this.boundHandleStreamRender)
    }
  }

  handleStreamRender(event) {
    const originalRender = event.detail.render
    event.detail.render = async (streamElement) => {
      await originalRender(streamElement)
      if (this.state && Object.keys(this.state).length > 0) {
        this.syncCheckboxes(this.state)
        this.syncAvailability(this.state)
      }
    }
  }

  fetchState() {
    if (this.fetchController) this.fetchController.abort()
    this.fetchController = new AbortController()

    fetch(this.urls.state, {
      headers: { "Accept": "application/json" },
      signal: this.fetchController.signal
    })
      .then(response => {
        if (!response.ok) throw new Error("fetch failed")
        return response.json()
      })
      .then(data => {
        if (data.version >= this.version) {
          const isRemoteUpdate = data.version > this.version
            && this.version > 0
            && !this.awaitingOwnAction
            && !this.initialFetch
          this.awaitingOwnAction = false
          this.initialFetch = false
          this.version = data.version
          this.state = data
          this.saveCache()
          this.syncCheckboxes(data)
          this.syncAvailability(data)
          if (isRemoteUpdate) {
            notifyShow("Menu updated.")
          }
        }
      })
      .catch(() => {})
  }

  syncCheckboxes(state) {
    this.element.classList.remove("hidden-until-js")

    const selectedRecipes = state.selected_recipes || []
    const selectedQuickBites = state.selected_quick_bites || []

    this.element.querySelectorAll('#recipe-selector input[type="checkbox"]').forEach(cb => {
      const slug = cb.dataset.slug
      const typeEl = cb.closest("[data-type]")
      if (!typeEl || !slug) return

      if (typeEl.dataset.type === "quick_bite") {
        cb.checked = selectedQuickBites.indexOf(slug) !== -1
      } else {
        cb.checked = selectedRecipes.indexOf(slug) !== -1
      }
    })
  }

  syncAvailability(state) {
    const availability = state.availability || {}

    this.element.querySelectorAll('#recipe-selector input[type="checkbox"]').forEach(cb => {
      const slug = cb.dataset.slug
      if (!slug) return

      const li = cb.closest('li')
      if (!li) return

      let dot = li.querySelector('.availability-dot')
      const info = availability[slug]

      if (!info) {
        if (dot) dot.remove()
        return
      }

      if (!dot) {
        dot = document.createElement('span')
        dot.className = 'availability-dot'
        dot.dataset.slug = slug
        cb.after(dot)
      }

      const missing = info.missing
      const isQuickBite = cb.closest('[data-type="quick_bite"]')
      dot.dataset.missing = isQuickBite
        ? (missing === 0 ? '0' : '3+')
        : (missing > 2 ? '3+' : String(missing))

      const label = missing === 0
        ? 'All ingredients on hand'
        : `Missing ${missing}: ${info.missing_names.join(', ')}`
      dot.setAttribute('aria-label', label)
    })
  }

  showPopover(dot) {
    const slug = dot.dataset.slug
    const info = (this.state.availability || {})[slug]
    if (!info) return

    let popover = document.getElementById('ingredient-popover')
    if (!popover) {
      popover = document.createElement('div')
      popover.id = 'ingredient-popover'
      popover.setAttribute('role', 'tooltip')
      document.body.appendChild(popover)
    }

    if (this.activePopoverDot === dot) {
      this.hidePopover()
      return
    }

    popover.textContent = ''

    const ingredientsList = document.createElement('p')
    ingredientsList.className = 'popover-ingredients'
    ingredientsList.textContent = info.ingredients.join(', ')
    popover.appendChild(ingredientsList)

    if (info.missing_names.length > 0) {
      const missingEl = document.createElement('p')
      missingEl.className = 'popover-missing'
      missingEl.textContent = `Missing: ${info.missing_names.join(', ')}`
      popover.appendChild(missingEl)
    }

    popover.classList.add('visible')

    const rect = dot.getBoundingClientRect()
    popover.style.top = ''
    popover.style.left = ''

    const popoverRect = popover.getBoundingClientRect()
    let top = rect.bottom + 6
    let left = rect.left

    if (top + popoverRect.height > window.innerHeight) {
      top = rect.top - popoverRect.height - 6
    }
    if (left + popoverRect.width > window.innerWidth) {
      left = window.innerWidth - popoverRect.width - 8
    }
    if (left < 8) left = 8

    popover.style.top = (top + window.scrollY) + 'px'
    popover.style.left = (left + window.scrollX) + 'px'

    this.activePopoverDot = dot
    dot.setAttribute('aria-expanded', 'true')
    dot.setAttribute('aria-describedby', 'ingredient-popover')

    setTimeout(() => {
      this.boundHideOnClickOutside = (e) => {
        if (!popover.contains(e.target) && e.target !== dot) {
          this.hidePopover()
        }
      }
      this.boundHideOnEscape = (e) => {
        if (e.key === 'Escape') {
          this.hidePopover()
          dot.focus()
        }
      }
      document.addEventListener('click', this.boundHideOnClickOutside)
      document.addEventListener('keydown', this.boundHideOnEscape)
    }, 0)
  }

  hidePopover() {
    const popover = document.getElementById('ingredient-popover')
    if (popover) popover.classList.remove('visible')

    if (this.activePopoverDot) {
      this.activePopoverDot.setAttribute('aria-expanded', 'false')
      this.activePopoverDot.removeAttribute('aria-describedby')
      this.activePopoverDot = null
    }

    if (this.boundHideOnClickOutside) {
      document.removeEventListener('click', this.boundHideOnClickOutside)
      this.boundHideOnClickOutside = null
    }
    if (this.boundHideOnEscape) {
      document.removeEventListener('keydown', this.boundHideOnEscape)
      this.boundHideOnEscape = null
    }
  }

  sendAction(url, params) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')
    const method = url === this.urls.clear ? "DELETE" : "PATCH"

    this.awaitingOwnAction = true

    return fetch(url, {
      method,
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken ? csrfToken.content : ""
      },
      body: JSON.stringify(params)
    })
      .then(response => {
        if (!response.ok) throw new Error("action failed")
        return response.json()
      })
      .then(() => {
        this.fetchState()
      })
      .catch(() => {
        this.awaitingOwnAction = false
      })
  }

  subscribe(slug) {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "MealPlanChannel", kitchen_slug: slug },
      {
        received: (data) => {
          if (data.type === 'content_changed') {
            this.fetchState()
            return
          }
          if (data.version && data.version > this.version && !this.awaitingOwnAction) {
            this.fetchState()
          }
        }
      }
    )
  }

  startHeartbeat() {
    this.heartbeatId = setInterval(() => this.fetchState(), 30000)
  }

  bindRecipeCheckboxes() {
    this.element.addEventListener("change", (e) => {
      const cb = e.target.closest('#recipe-selector input[type="checkbox"]')
      if (!cb) return

      const slug = cb.dataset.slug
      const typeEl = cb.closest("[data-type]")
      const type = typeEl ? typeEl.dataset.type : "recipe"

      this.sendAction(this.urls.select, { type, slug, selected: cb.checked })
    })
  }

  selectAll() {
    this.sendAction(this.urls.selectAll, {})
  }

  clear() {
    this.sendAction(this.urls.clear, {})
  }

  saveCache() {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify({
        version: this.version,
        state: this.state
      }))
    } catch { /* localStorage full or unavailable */ }
  }

  loadCache() {
    try {
      const raw = localStorage.getItem(this.storageKey)
      if (!raw) return
      const cached = JSON.parse(raw)
      if (cached && cached.version) {
        this.version = cached.version
        this.state = cached.state || {}
      }
    } catch { /* corrupted cache */ }
  }
}
