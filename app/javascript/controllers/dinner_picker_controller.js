import { Controller } from "@hotwired/stimulus"
import { computeFinalWeights, weightedRandomPick } from "../utilities/dinner_picker_logic"
import { loadSearchData, loadSmartTagData } from "../utilities/search_data"

/**
 * Dinner picker dialog: weighted random recipe suggestion with tag preferences,
 * slot machine animation, and re-roll with decline penalties. Paired with
 * editor_controller on the same <dialog> element — editor handles open/close
 * lifecycle, this controller handles picker UI and logic.
 *
 * - dinner_picker_logic.js: weight computation and random selection
 * - search_data.js: provides searchData JSON (shared data source)
 * - editor_controller: dialog open/close, bloop animation
 * - menu_controller.js: handles checkbox change events for recipe selection
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
  static targets = ["tagState", "slotDisplay", "resultArea"]
  static values = { weightsUrl: String, recipeBasePath: String }

  connect() {
    this.tagPreferences = {}
    this.declinePenalties = {}
    this.animationTimer = null
    this.weights = null

    const data = loadSearchData()
    this.recipes = data.recipes || []
    this.allTags = data.all_tags || []

    this.element.addEventListener("close", () => this.reset())
  }

  disconnect() {
    this.cancelAnimation()
  }

  onOpen() {
    this.tagPreferences = {}
    this.declinePenalties = {}
    this.showTagState()
  }

  reset() {
    this.cancelAnimation()
    this.tagPreferences = {}
    this.declinePenalties = {}
    this.weights = null
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

  renderTagUI() {
    const container = this.tagStateTarget
    container.textContent = ""

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
    btn.className = "btn btn-primary dinner-picker-spin-btn"
    btn.textContent = this.randomQuip()
    btn.addEventListener("click", () => this.spin())
    container.appendChild(btn)
  }

  buildTagPills(container) {
    const smartTags = loadSmartTagData()

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

  async loadWeights() {
    if (this.weights) return this.weights

    const response = await fetch(this.weightsUrlValue, {
      headers: { "Accept": "application/json" }
    })
    this.weights = await response.json()
    return this.weights
  }

  async spin() {
    const weights = computeFinalWeights(
      this.recipes, await this.loadWeights(), this.tagPreferences, this.declinePenalties
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

    const retryBtn = document.createElement("button")
    retryBtn.className = "btn"
    retryBtn.textContent = "Try again"
    retryBtn.addEventListener("click", () => this.retry(recipe))
    actions.appendChild(retryBtn)

    const acceptBtn = document.createElement("button")
    acceptBtn.className = "btn btn-primary"
    acceptBtn.textContent = "Add to Menu"
    acceptBtn.addEventListener("click", () => this.accept(recipe))
    actions.appendChild(acceptBtn)

    container.appendChild(actions)

    const viewLink = document.createElement("a")
    viewLink.className = "result-view-link"
    viewLink.href = this.recipeBasePathValue + encodeURIComponent(recipe.slug)
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
    this.element.close()
  }

  retry(recipe) {
    this.declinePenalties[recipe.slug] = (this.declinePenalties[recipe.slug] || 0) + 1
    this.showTagState()
  }

  randomQuip() {
    return QUIPS[Math.floor(Math.random() * QUIPS.length)]
  }
}
