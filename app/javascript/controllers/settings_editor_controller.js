import { Controller } from "@hotwired/stimulus"
import { saveRequest } from "../utilities/editor_utils"
import ListenerManager from "../utilities/listener_manager"

/**
 * Companion controller for the settings editor dialog. Hooks into editor
 * lifecycle events to manage a structured form (not a textarea). The Turbo
 * Frame delivers pre-populated fields; this controller snapshots originals
 * on content-loaded and provides collect/save/modified/reset handlers.
 *
 * - editor_controller: open/close/save lifecycle, dirty guards, frame readiness
 * - reveal_controller: API key show/hide toggle (nested)
 * - editor_utils: save requests
 * - ListenerManager: clean event listener teardown
 */
export default class extends Controller {
  static targets = ["siteTitle", "homepageHeading", "homepageSubtitle", "usdaApiKey", "anthropicApiKey", "showNutrition", "decorateTags"]
  static values = { saveUrl: String }

  connect() {
    this.originals = {}
    this.listeners = new ListenerManager()

    this.listeners.add(this.element, "editor:content-loaded", this.handleContentLoaded)
    this.listeners.add(this.element, "editor:collect", this.collect)
    this.listeners.add(this.element, "editor:save", this.provideSaveFn)
    this.listeners.add(this.element, "editor:modified", this.checkModified)
    this.listeners.add(this.element, "editor:reset", this.reset)
  }

  disconnect() {
    this.listeners.teardown()
  }

  handleContentLoaded = () => {
    this.storeOriginals()
  }

  collect = (event) => {
    event.detail.handled = true
    event.detail.data = {
      kitchen: {
        site_title: this.siteTitleTarget.value,
        homepage_heading: this.homepageHeadingTarget.value,
        homepage_subtitle: this.homepageSubtitleTarget.value,
        usda_api_key: this.usdaApiKeyTarget.value,
        anthropic_api_key: this.anthropicApiKeyTarget.value,
        show_nutrition: this.showNutritionTarget.checked,
        decorate_tags: this.decorateTagsTarget.checked
      }
    }
  }

  provideSaveFn = (event) => {
    event.detail.handled = true
    event.detail.saveFn = () => saveRequest(this.saveUrlValue, "PATCH", {
      kitchen: {
        site_title: this.siteTitleTarget.value,
        homepage_heading: this.homepageHeadingTarget.value,
        homepage_subtitle: this.homepageSubtitleTarget.value,
        usda_api_key: this.usdaApiKeyTarget.value,
        anthropic_api_key: this.anthropicApiKeyTarget.value,
        show_nutrition: this.showNutritionTarget.checked,
        decorate_tags: this.decorateTagsTarget.checked
      }
    })
  }

  checkModified = (event) => {
    event.detail.handled = true
    event.detail.modified =
      this.siteTitleTarget.value !== this.originals.siteTitle ||
      this.homepageHeadingTarget.value !== this.originals.homepageHeading ||
      this.homepageSubtitleTarget.value !== this.originals.homepageSubtitle ||
      this.usdaApiKeyTarget.value !== this.originals.usdaApiKey ||
      this.anthropicApiKeyTarget.value !== this.originals.anthropicApiKey ||
      this.showNutritionTarget.checked !== this.originals.showNutrition ||
      this.decorateTagsTarget.checked !== this.originals.decorateTags
  }

  reset = (event) => {
    event.detail.handled = true
    this.siteTitleTarget.value = this.originals.siteTitle
    this.homepageHeadingTarget.value = this.originals.homepageHeading
    this.homepageSubtitleTarget.value = this.originals.homepageSubtitle
    this.usdaApiKeyTarget.value = this.originals.usdaApiKey
    this.anthropicApiKeyTarget.value = this.originals.anthropicApiKey
    this.showNutritionTarget.checked = this.originals.showNutrition
    this.decorateTagsTarget.checked = this.originals.decorateTags
  }

  storeOriginals() {
    this.originals = {
      siteTitle: this.siteTitleTarget.value,
      homepageHeading: this.homepageHeadingTarget.value,
      homepageSubtitle: this.homepageSubtitleTarget.value,
      usdaApiKey: this.usdaApiKeyTarget.value,
      anthropicApiKey: this.anthropicApiKeyTarget.value,
      showNutrition: this.showNutritionTarget.checked,
      decorateTags: this.decorateTagsTarget.checked
    }
  }
}
