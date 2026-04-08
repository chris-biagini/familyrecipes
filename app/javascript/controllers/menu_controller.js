import { Controller } from "@hotwired/stimulus"
import { sendAction } from "../utilities/turbo_fetch"
import ListenerManager from "../utilities/listener_manager"

/**
 * Menu page recipe/quick-bite selection. Handles optimistic checkbox toggle.
 * All rendering (checkboxes, availability badges) is server-side via Turbo
 * Stream morphs. Preserves expanded availability details across morph refreshes.
 *
 * - turbo_fetch (sendAction): fire-and-forget mutations with retry and error toast
 * - ListenerManager: tracks event listeners for clean teardown on disconnect
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

    this.listeners.add(document, "turbo:before-render", (e) => this.preserveOpenDetails(e))
  }

  disconnect() {
    this.listeners.teardown()
  }

  preserveOpenDetails(event) {
    if (!event.detail.render) return

    const openSummaries = Array.from(this.element.querySelectorAll(
      "details.availability-ready[open] summary, details.availability-close[open] summary, details.availability-far[open] summary"
    )).map(s => s.closest("details").getAttribute("aria-label"))

    if (!openSummaries.length) return

    const originalRender = event.detail.render
    event.detail.render = async (...args) => {
      await originalRender(...args)
      openSummaries.forEach(label => {
        const details = this.element.querySelector(`details[aria-label="${CSS.escape(label)}"]`)
        if (details) details.open = true
      })
    }
  }

}
