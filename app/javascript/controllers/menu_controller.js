import { Controller } from "@hotwired/stimulus"
import { sendAction } from "utilities/turbo_fetch"

/**
 * Menu page recipe/quick-bite selection. Handles optimistic checkbox toggle,
 * select-all, and clear-all actions. All rendering (checkboxes, availability
 * dots) is server-side via Turbo Stream morphs.
 */
export default class extends Controller {
  connect() {
    this.element.addEventListener("change", (e) => {
      const cb = e.target.closest('#recipe-selector input[type="checkbox"]')
      if (!cb) return

      const slug = cb.dataset.slug
      const typeEl = cb.closest("[data-type]")
      const type = typeEl ? typeEl.dataset.type : "recipe"

      sendAction(this.element.dataset.selectUrl, { type, slug, selected: cb.checked })
    })
  }

  selectAll() {
    sendAction(this.element.dataset.selectAllUrl, {})
  }

  clear() {
    sendAction(this.element.dataset.clearUrl, {}, { method: "DELETE" })
  }
}
