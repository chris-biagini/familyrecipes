import { Controller } from "@hotwired/stimulus"
import MealPlanSync from "utilities/meal_plan_sync"

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
