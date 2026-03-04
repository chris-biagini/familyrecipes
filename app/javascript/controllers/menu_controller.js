import { Controller } from "@hotwired/stimulus"
import { sendAction } from "utilities/turbo_fetch"
import ListenerManager from "utilities/listener_manager"

/**
 * Menu page recipe/quick-bite selection. Handles optimistic checkbox toggle,
 * select-all, and clear-all actions. All rendering (checkboxes, availability
 * badges) is server-side via Turbo Stream morphs.
 */
export default class extends Controller {
  connect() {
    this.listeners = new ListenerManager()

    this.listeners.add(this.element, "change", (e) => {
      const cb = e.target.closest('#recipe-selector input[type="checkbox"]')
      if (!cb) return

      const slug = cb.dataset.slug
      const typeEl = cb.closest("[data-type]")
      const type = typeEl ? typeEl.dataset.type : "recipe"

      sendAction(this.element.dataset.selectUrl, { type, slug, selected: cb.checked })
    })
  }

  disconnect() {
    this.listeners.teardown()
  }

  selectAll() {
    sendAction(this.element.dataset.selectAllUrl, {})
  }

  clear() {
    sendAction(this.element.dataset.clearUrl, {}, { method: "DELETE" })
  }
}
