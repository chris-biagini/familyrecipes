import { Controller } from "@hotwired/stimulus"
import { getCsrfToken, saveRequest, showErrors } from "../utilities/editor_utils"
import ListenerManager from "../utilities/listener_manager"

/**
 * Companion controller for the settings editor dialog. Hooks into editor
 * lifecycle events to manage a structured form (not a textarea). Owns the
 * open flow: listens for #settings-button clicks, fetches current values,
 * populates fields, then delegates save/close/dirty-guard to the editor.
 *
 * - editor_controller: open/close/save lifecycle, dirty guards
 * - reveal_controller: API key show/hide toggle (nested)
 * - editor_utils: CSRF tokens, error display
 * - ListenerManager: clean event listener teardown
 */
export default class extends Controller {
  static targets = ["siteTitle", "homepageHeading", "homepageSubtitle", "usdaApiKey", "anthropicApiKey", "showNutrition", "decorateTags"]
  static values = { loadUrl: String, saveUrl: String }

  connect() {
    this.originals = {}
    this.listeners = new ListenerManager()

    this.listeners.add(this.element, "editor:collect", this.collect)
    this.listeners.add(this.element, "editor:save", this.provideSaveFn)
    this.listeners.add(this.element, "editor:modified", this.checkModified)
    this.listeners.add(this.element, "editor:reset", this.reset)
    this.listeners.add(document, 'click', (e) => {
      if (e.target.closest('#settings-button')) this.openDialog()
    })
  }

  disconnect() {
    this.listeners.teardown()
  }

  openDialog() {
    const editor = this.application.getControllerForElementAndIdentifier(this.element, "editor")
    editor.clearErrorDisplay()
    editor.resetSaveButton()
    this.disableFields(true)
    this.element.showModal()

    fetch(this.loadUrlValue, {
      headers: { "Accept": "application/json", "X-CSRF-Token": getCsrfToken() }
    })
      .then(r => r.json())
      .then(data => {
        this.siteTitleTarget.value = data.site_title || ""
        this.homepageHeadingTarget.value = data.homepage_heading || ""
        this.homepageSubtitleTarget.value = data.homepage_subtitle || ""
        this.usdaApiKeyTarget.value = data.usda_api_key || ""
        this.anthropicApiKeyTarget.value = data.anthropic_api_key || ""
        this.showNutritionTarget.checked = !!data.show_nutrition
        this.decorateTagsTarget.checked = !!data.decorate_tags
        this.storeOriginals()
        this.disableFields(false)
        this.siteTitleTarget.focus()
      })
      .catch(() => {
        this.disableFields(false)
        showErrors(editor.errorsTarget, ["Failed to load settings. Close and try again."])
      })
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

  disableFields(disabled) {
    ;[this.siteTitleTarget, this.homepageHeadingTarget,
      this.homepageSubtitleTarget, this.usdaApiKeyTarget,
      this.anthropicApiKeyTarget, this.showNutritionTarget,
      this.decorateTagsTarget].forEach(f => f.disabled = disabled)
  }
}
