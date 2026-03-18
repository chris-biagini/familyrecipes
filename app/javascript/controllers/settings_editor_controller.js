import { Controller } from "@hotwired/stimulus"
import { getCsrfToken, showErrors } from "../utilities/editor_utils"

/**
 * Companion controller for the settings editor dialog. Hooks into editor
 * lifecycle events to manage a structured form (not a textarea). Owns the
 * open flow: listens for #settings-button clicks, fetches current values,
 * populates fields, then delegates save/close/dirty-guard to the editor.
 *
 * - editor_controller: open/close/save lifecycle, dirty guards
 * - reveal_controller: API key show/hide toggle (nested)
 * - editor_utils: CSRF tokens, error display
 */
export default class extends Controller {
  static targets = ["siteTitle", "homepageHeading", "homepageSubtitle", "usdaApiKey", "anthropicApiKey", "showNutrition", "decorateTags"]
  static values = { loadUrl: String, saveUrl: String }

  connect() {
    this.originals = {}

    this.element.addEventListener("editor:collect", this.collect)
    this.element.addEventListener("editor:save", this.provideSaveFn)
    this.element.addEventListener("editor:modified", this.checkModified)
    this.element.addEventListener("editor:reset", this.reset)

    this.boundOpenClick = (e) => {
      if (e.target.closest('#settings-button')) this.openDialog()
    }
    document.addEventListener('click', this.boundOpenClick)
  }

  disconnect() {
    this.element.removeEventListener("editor:collect", this.collect)
    this.element.removeEventListener("editor:save", this.provideSaveFn)
    this.element.removeEventListener("editor:modified", this.checkModified)
    this.element.removeEventListener("editor:reset", this.reset)
    document.removeEventListener('click', this.boundOpenClick)
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
    event.detail.saveFn = () => fetch(this.saveUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": getCsrfToken()
      },
      body: JSON.stringify({
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
