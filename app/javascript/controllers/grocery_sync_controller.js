import { Controller } from "@hotwired/stimulus"
import MealPlanSync from "utilities/meal_plan_sync"

/**
 * Thin sync wrapper for the groceries page. Delegates all ActionCable and state
 * management to MealPlanSync, then pipes state updates to the co-located
 * grocery_ui_controller (looked up via Stimulus' getControllerForElementAndIdentifier).
 * Exposes sendAction and urls so grocery_ui_controller can dispatch check-off
 * and custom item actions without its own sync logic.
 */
export default class extends Controller {
  connect() {
    const slug = this.element.dataset.kitchenSlug

    this.urls = {
      check: this.element.dataset.checkUrl,
      customItems: this.element.dataset.customItemsUrl
    }

    this.sync = new MealPlanSync({
      slug,
      stateUrl: this.element.dataset.stateUrl,
      cachePrefix: "grocery-state",
      onStateUpdate: (data) => this.applyStateToUI(data),
      remoteUpdateMessage: "Shopping list updated."
    })
  }

  disconnect() {
    if (this.sync) this.sync.disconnect()
  }

  get uiController() {
    return this.application.getControllerForElementAndIdentifier(this.element, "grocery-ui")
  }

  applyStateToUI(state) {
    const ui = this.uiController
    if (ui) ui.applyState(state)
  }

  sendAction(url, params) {
    return this.sync.sendAction(url, params)
  }
}
