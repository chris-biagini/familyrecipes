import { Controller } from "@hotwired/stimulus"
import MealPlanSync from "utilities/meal_plan_sync"

/**
 * Menu page recipe/quick-bite selection and availability display. Manages
 * checkboxes for recipe selection, select-all/clear actions, and availability
 * dots (colored indicators of how many ingredients are on hand). Delegates
 * sync to MealPlanSync. Availability dots show a popover with ingredient lists
 * on click.
 */
export default class extends Controller {
  connect() {
    const slug = this.element.dataset.kitchenSlug

    this.urls = {
      select: this.element.dataset.selectUrl,
      selectAll: this.element.dataset.selectAllUrl,
      clear: this.element.dataset.clearUrl
    }

    this.sync = new MealPlanSync({
      slug,
      stateUrl: this.element.dataset.stateUrl,
      cachePrefix: "menu-state",
      onStateUpdate: (data) => {
        this.syncCheckboxes(data)
        this.syncAvailability(data)
      },
      remoteUpdateMessage: "Menu updated."
    })

    this.bindRecipeCheckboxes()

    this.element.addEventListener('click', (e) => {
      const dot = e.target.closest('.availability-dot')
      if (dot) {
        e.preventDefault()
        e.stopPropagation()
        this.showPopover(dot)
      }
    })
  }

  disconnect() {
    this.hidePopover()
    if (this.sync) this.sync.disconnect()
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
    const state = this.sync.state
    const info = (state.availability || {})[slug]
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

  bindRecipeCheckboxes() {
    this.element.addEventListener("change", (e) => {
      const cb = e.target.closest('#recipe-selector input[type="checkbox"]')
      if (!cb) return

      const slug = cb.dataset.slug
      const typeEl = cb.closest("[data-type]")
      const type = typeEl ? typeEl.dataset.type : "recipe"

      this.sync.sendAction(this.urls.select, { type, slug, selected: cb.checked })
    })
  }

  selectAll() {
    this.sync.sendAction(this.urls.selectAll, {})
  }

  clear() {
    this.sync.sendAction(this.urls.clear, {}, "DELETE")
  }
}
