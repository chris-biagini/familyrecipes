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
  static targets = ["popover"]

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
        this.showIngredientPopover(dot)
      }
    })

    this.popoverTarget.addEventListener('toggle', (e) => {
      if (e.newState !== 'closed' || !this.activePopoverDot) return
      if (this.popoverTarget.matches(':popover-open')) return

      this.activePopoverDot.removeAttribute('aria-expanded')
      this.activePopoverDot.removeAttribute('aria-describedby')
      this.activePopoverDot = null
    })
  }

  disconnect() {
    if (this.popoverTarget.matches(':popover-open')) this.popoverTarget.hidePopover()
    if (this.sync) this.sync.disconnect()
  }

  syncCheckboxes(state) {
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

  showIngredientPopover(dot) {
    const popover = this.popoverTarget

    if (this.activePopoverDot) {
      this.activePopoverDot.removeAttribute('aria-expanded')
      this.activePopoverDot.removeAttribute('aria-describedby')
    }

    if (this.activePopoverDot === dot && popover.matches(':popover-open')) {
      popover.hidePopover()
      this.activePopoverDot = null
      return
    }

    const info = (this.sync.state.availability || {})[dot.dataset.slug]
    if (!info) return

    this.populatePopover(info)

    if (popover.matches(':popover-open')) popover.hidePopover()

    this.activePopoverDot = dot
    dot.setAttribute('aria-expanded', 'true')
    dot.setAttribute('aria-describedby', 'ingredient-popover')

    popover.showPopover()
    this.positionPopover(dot)
  }

  populatePopover(info) {
    const popover = this.popoverTarget
    popover.querySelector('.popover-ingredients').textContent = info.ingredients.join(', ')

    const missingEl = popover.querySelector('.popover-missing')
    if (info.missing_names.length > 0) {
      missingEl.textContent = `Missing: ${info.missing_names.join(', ')}`
      missingEl.hidden = false
    } else {
      missingEl.hidden = true
    }
  }

  positionPopover(dot) {
    const popover = this.popoverTarget
    const rect = dot.getBoundingClientRect()

    popover.style.top = ''
    popover.style.left = ''

    const popoverRect = popover.getBoundingClientRect()
    let top = rect.bottom + 6
    let left = rect.left

    if (top + popoverRect.height > window.innerHeight) top = rect.top - popoverRect.height - 6
    if (left + popoverRect.width > window.innerWidth) left = window.innerWidth - popoverRect.width - 8
    if (left < 8) left = 8

    popover.style.top = top + 'px'
    popover.style.left = left + 'px'
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
