import { Controller } from "@hotwired/stimulus"
import { computeFinalWeights, weightedRandomPick } from "../utilities/dinner_picker_logic"
import ListenerManager from "../utilities/listener_manager"

/**
 * Dinner picker dialog: weighted random recipe suggestion with tag preferences,
 * slot machine animation, and re-roll with decline penalties. Opens from the
 * menu page, reads recipe data from SearchDataHelper JSON and recency weights
 * from a data attribute. Accept dispatches a checkbox change to menu_controller.
 *
 * - dinner_picker_logic.js: weight computation and random selection
 * - search_overlay_controller.js: provides searchData JSON (shared data source)
 * - menu_controller.js: handles checkbox change events for recipe selection
 * - ListenerManager: clean event listener teardown
 */

const QUIPS = [
  "I'm feeling lucky",
  "Baby needs new shoes",
  "Let it ride",
  "Fortune favors the bold",
  "Big money, no whammies",
  "Today's my lucky day",
  "This one's got my name on it",
  "Third time's the charm",
  "This is the one"
]

export default class extends Controller {
  static targets = ["dialog", "tagState", "slotDisplay", "resultArea"]
  static values = { weights: Object, recipeBasePath: String }

  connect() {
    this.listeners = new ListenerManager()
    this.tagPreferences = {}
    this.declinePenalties = {}
    this.animationTimer = null

    const searchData = this.loadSearchData()
    this.recipes = searchData.recipes || []
    this.allTags = searchData.all_tags || []

    const btn = document.getElementById("dinner-picker-button")
    if (btn) {
      this.listeners.add(btn, "click", () => this.open())
    }

    this.listeners.add(this.dialogTarget, "close", () => this.reset())
  }

  disconnect() {
    this.listeners.teardown()
  }

  open() {
    this.tagPreferences = {}
    this.declinePenalties = {}
    this.showTagState()
    this.dialogTarget.showModal()
  }

  reset() {
    this.cancelAnimation()
    this.tagPreferences = {}
    this.declinePenalties = {}
  }

  cancelAnimation() {
    if (this.animationTimer) {
      clearTimeout(this.animationTimer)
      this.animationTimer = null
    }
  }

  showTagState() {
    this.cancelAnimation()
    this.tagStateTarget.hidden = false
    this.slotDisplayTarget.hidden = true
    this.resultAreaTarget.hidden = true
    this.renderTagUI()
  }

  renderCloseButton(container) {
    const btn = document.createElement("button")
    btn.className = "dinner-picker-close"
    btn.textContent = "\u00D7"
    btn.setAttribute("aria-label", "Close")
    btn.addEventListener("click", () => this.dialogTarget.close())
    container.appendChild(btn)
  }

  renderTagUI() {
    const container = this.tagStateTarget
    container.textContent = ""

    this.renderCloseButton(container)

    const heading = document.createElement("h2")
    heading.textContent = "What are you in the mood for?"
    container.appendChild(heading)

    const subtitle = document.createElement("p")
    subtitle.className = "dinner-picker-subtitle"
    subtitle.textContent = "Tap tags to steer the pick, or just spin."
    container.appendChild(subtitle)

    const pills = document.createElement("div")
    pills.className = "dinner-picker-tag-pills"
    this.buildTagPills(pills)
    container.appendChild(pills)

    const btn = document.createElement("button")
    btn.className = "dinner-picker-spin-btn"
    btn.textContent = this.randomQuip()
    btn.addEventListener("click", () => this.spin())
    container.appendChild(btn)
  }

  buildTagPills(container) {
    const smartTags = this.loadSmartTagData()

    for (const tag of this.allTags) {
      const pill = document.createElement("button")
      pill.className = "dinner-picker-tag"
      pill.dataset.tag = tag
      this.applyTagState(pill, tag, smartTags)
      pill.addEventListener("click", () => this.cycleTag(pill, tag, smartTags))
      container.appendChild(pill)
    }
  }

  cycleTag(pill, tag, smartTags) {
    const current = this.tagPreferences[tag] ?? 1
    if (current === 1) this.tagPreferences[tag] = 2
    else if (current === 2) this.tagPreferences[tag] = 0.25
    else delete this.tagPreferences[tag]
    this.applyTagState(pill, tag, smartTags)
  }

  applyTagState(pill, tag, smartTags) {
    const pref = this.tagPreferences[tag] ?? 1
    pill.textContent = ""

    const prefixMap = { 2: "\u{1F44D} ", 0.25: "\u{1F44E} " }
    const prefix = prefixMap[pref] || ""

    const smart = smartTags[tag]
    const emoji = smart?.emoji ? smart.emoji + " " : ""
    pill.textContent = prefix + emoji + tag

    pill.classList.remove("tag-up", "tag-down", "tag-neutral")
    if (pref === 2) pill.classList.add("tag-up")
    else if (pref === 0.25) pill.classList.add("tag-down")
    else pill.classList.add("tag-neutral")
  }

  spin() {
    const weights = computeFinalWeights(
      this.recipes, this.weightsValue, this.tagPreferences, this.declinePenalties
    )
    const pick = weightedRandomPick(weights)
    if (!pick) return

    const recipe = this.recipes.find(r => r.slug === pick)
    this.animateSlotMachine(recipe, Object.keys(this.declinePenalties).length > 0)
  }

  animateSlotMachine(winner, isReroll) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.showResult(winner)
      return
    }

    this.tagStateTarget.hidden = true
    this.slotDisplayTarget.hidden = false
    this.resultAreaTarget.hidden = true

    const display = this.slotDisplayTarget
    display.textContent = ""

    const emoji = document.createElement("div")
    emoji.className = "slot-emoji"
    emoji.textContent = "\u{1F3B0}"
    display.appendChild(emoji)

    const slotWindow = document.createElement("div")
    slotWindow.className = "slot-window"
    display.appendChild(slotWindow)

    const nameEl = document.createElement("div")
    nameEl.className = "slot-name"
    slotWindow.appendChild(nameEl)

    const cycles = isReroll ? 8 : 15
    let i = 0
    const animate = () => {
      if (i < cycles) {
        const randomRecipe = i < cycles - 1
          ? this.recipes[Math.floor(Math.random() * this.recipes.length)]
          : winner
        nameEl.textContent = randomRecipe.title
        i++
        this.animationTimer = setTimeout(animate, 80 + i * (isReroll ? 20 : 15))
      } else {
        nameEl.textContent = winner.title
        nameEl.classList.add("slot-landed")
        emoji.textContent = "\u{1F389}"
        this.animationTimer = setTimeout(() => this.showResult(winner), 400)
      }
    }
    animate()
  }

  showResult(recipe) {
    this.tagStateTarget.hidden = true
    this.slotDisplayTarget.hidden = true
    this.resultAreaTarget.hidden = false

    const container = this.resultAreaTarget
    container.textContent = ""

    this.renderCloseButton(container)

    const label = document.createElement("div")
    label.className = "result-label"
    label.textContent = "Tonight's Pick"
    container.appendChild(label)

    const title = document.createElement("h2")
    title.className = "result-title"
    title.textContent = recipe.title
    container.appendChild(title)

    if (recipe.description) {
      const desc = document.createElement("p")
      desc.className = "result-description"
      desc.textContent = recipe.description
      container.appendChild(desc)
    }

    if (recipe.tags.length > 0) {
      const tags = document.createElement("div")
      tags.className = "result-tags"
      for (const tag of recipe.tags) {
        const pill = document.createElement("span")
        pill.className = "result-tag-pill"
        pill.textContent = tag
        tags.appendChild(pill)
      }
      container.appendChild(tags)
    }

    const actions = document.createElement("div")
    actions.className = "result-actions"

    const acceptBtn = document.createElement("button")
    acceptBtn.className = "result-accept-btn"
    acceptBtn.textContent = "\u2713 Add to Menu"
    acceptBtn.addEventListener("click", () => this.accept(recipe))
    actions.appendChild(acceptBtn)

    const retryBtn = document.createElement("button")
    retryBtn.className = "result-retry-btn"
    retryBtn.textContent = "Try again"
    retryBtn.addEventListener("click", () => this.retry(recipe))
    actions.appendChild(retryBtn)

    container.appendChild(actions)

    const viewLink = document.createElement("a")
    viewLink.className = "result-view-link"
    viewLink.href = this.recipeBasePathValue + recipe.slug
    viewLink.textContent = "View Recipe"
    container.appendChild(viewLink)
  }

  accept(recipe) {
    const checkbox = document.querySelector(
      `#recipe-selector input[type="checkbox"][data-slug="${CSS.escape(recipe.slug)}"]`
    )
    if (checkbox && !checkbox.checked) {
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    }
    this.dialogTarget.close()
  }

  retry(recipe) {
    this.declinePenalties[recipe.slug] = (this.declinePenalties[recipe.slug] || 0) + 1
    this.showTagState()
  }

  randomQuip() {
    return "\u{1F3B0} " + QUIPS[Math.floor(Math.random() * QUIPS.length)]
  }

  loadSearchData() {
    const el = document.querySelector("[data-search-overlay-target='data']")
    if (!el) return {}
    try { return JSON.parse(el.textContent || "{}") } catch { return {} }
  }

  loadSmartTagData() {
    const el = document.querySelector("[data-smart-tags]")
    if (!el) return {}
    try { return JSON.parse(el.textContent || "{}") } catch { return {} }
  }
}
