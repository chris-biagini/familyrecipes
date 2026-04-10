import { Controller } from "@hotwired/stimulus"
import { saveRequest, getCsrfToken } from "../utilities/editor_utils"
import ListenerManager from "../utilities/listener_manager"

/**
 * Companion controller for the settings editor dialog. Hooks into editor
 * lifecycle events to manage a structured form (not a textarea). The Turbo
 * Frame delivers pre-populated fields; this controller snapshots originals
 * on content-loaded and provides collect/save/modified/reset handlers.
 *
 * Kitchen section: join code display + regenerate (owner-only).
 * Profile section: name/email saved alongside kitchen settings.
 *
 * - editor_controller: open/close/save lifecycle, dirty guards, frame readiness
 * - reveal_controller: API key show/hide toggle (nested)
 * - editor_utils: save requests, CSRF token
 * - ListenerManager: clean event listener teardown
 */
export default class extends Controller {
  static targets = [
    "siteTitle", "homepageHeading", "homepageSubtitle",
    "usdaApiKey", "anthropicApiKey", "showNutrition", "decorateTags",
    "joinCode", "regenerateButton",
    "profileName", "profileEmail"
  ]
  static values = { saveUrl: String, regenerateUrl: String, profileUrl: String }

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
    event.detail.data = this.#buildPayload()
  }

  provideSaveFn = (event) => {
    event.detail.handled = true
    event.detail.saveFn = async () => {
      if (this.#profileChanged()) {
        await saveRequest(this.profileUrlValue, "PATCH", this.#buildProfilePayload())
      }
      return saveRequest(this.saveUrlValue, "PATCH", this.#buildPayload())
    }
  }

  checkModified = (event) => {
    event.detail.handled = true
    event.detail.modified =
      this.siteTitleTarget.value !== this.originals.siteTitle ||
      this.homepageHeadingTarget.value !== this.originals.homepageHeading ||
      this.homepageSubtitleTarget.value !== this.originals.homepageSubtitle ||
      this.usdaApiKeyTarget.value.length > 0 ||
      this.anthropicApiKeyTarget.value.length > 0 ||
      this.showNutritionTarget.checked !== this.originals.showNutrition ||
      this.decorateTagsTarget.checked !== this.originals.decorateTags ||
      this.#profileChanged()
  }

  reset = (event) => {
    event.detail.handled = true
    this.siteTitleTarget.value = this.originals.siteTitle
    this.homepageHeadingTarget.value = this.originals.homepageHeading
    this.homepageSubtitleTarget.value = this.originals.homepageSubtitle
    this.usdaApiKeyTarget.value = ""
    this.anthropicApiKeyTarget.value = ""
    this.showNutritionTarget.checked = this.originals.showNutrition
    this.decorateTagsTarget.checked = this.originals.decorateTags
    if (this.hasProfileNameTarget) this.profileNameTarget.value = this.originals.profileName
    if (this.hasProfileEmailTarget) this.profileEmailTarget.value = this.originals.profileEmail
  }

  copyToClipboard(event) {
    const text = event.params.copyText
    navigator.clipboard.writeText(text)
  }

  async regenerateJoinCode() {
    const response = await fetch(this.regenerateUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": getCsrfToken()
      }
    })
    if (response.ok) {
      const data = await response.json()
      this.joinCodeTarget.value = data.join_code
    }
  }

  storeOriginals() {
    this.originals = {
      siteTitle: this.siteTitleTarget.value,
      homepageHeading: this.homepageHeadingTarget.value,
      homepageSubtitle: this.homepageSubtitleTarget.value,
      showNutrition: this.showNutritionTarget.checked,
      decorateTags: this.decorateTagsTarget.checked,
      profileName: this.hasProfileNameTarget ? this.profileNameTarget.value : "",
      profileEmail: this.hasProfileEmailTarget ? this.profileEmailTarget.value : ""
    }
  }

  #profileChanged() {
    if (!this.hasProfileNameTarget || !this.hasProfileEmailTarget) return false

    return this.profileNameTarget.value !== this.originals.profileName ||
      this.profileEmailTarget.value !== this.originals.profileEmail
  }

  #buildProfilePayload() {
    return {
      user: {
        name: this.profileNameTarget.value,
        email: this.profileEmailTarget.value
      }
    }
  }

  #buildPayload() {
    const kitchen = {
      site_title: this.siteTitleTarget.value,
      homepage_heading: this.homepageHeadingTarget.value,
      homepage_subtitle: this.homepageSubtitleTarget.value,
      usda_api_key: this.usdaApiKeyTarget.value,
      anthropic_api_key: this.anthropicApiKeyTarget.value,
      show_nutrition: this.showNutritionTarget.checked,
      decorate_tags: this.decorateTagsTarget.checked
    }
    return { kitchen }
  }
}
