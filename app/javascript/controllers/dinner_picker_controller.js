import { Controller } from "@hotwired/stimulus"
import { computeFinalWeights, weightedRandomPick } from "../utilities/dinner_picker_logic"
import { buildKeyframes, positionAtTime, buildReelItems, applyCylinderWarp } from "../utilities/spin_physics"
import { loadSearchData, loadSmartTagData } from "../utilities/search_data"

/**
 * Single-page dinner picker with physics-based drum animation. Tags, drum,
 * result details, and action buttons are always visible — no state transitions.
 * Paired with editor_controller on the same <dialog> for open/close lifecycle.
 *
 * - spin_physics.js: physics simulation, keyframe generation, cylinder warp
 * - dinner_picker_logic.js: weight computation and random selection
 * - search_data.js: provides recipe and tag data
 * - editor_controller: dialog open/close, bloop animation
 * - menu_controller.js: handles checkbox change events for recipe selection
 */

const SPIN_FORCE = 1200
const TOTAL_FRICTION = 275
const DRAG_BLEND = 0.75
const ITEM_HEIGHT = 30
const CONTAINER_HEIGHT = 76
const CONTAINER_CENTER = CONTAINER_HEIGHT / 2
const REEL_PADDING_TOP = 22

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

const RESPIN_QUIPS = [
  "Spin again",
  "One more time",
  "Try my luck",
  "Double or nothing",
  "Let it ride",
  "Not feeling it"
]

export default class extends Controller {
  static targets = ["tagPills", "reel", "resultDetails", "resultDescription",
                     "resultLink", "spinBtn", "acceptBtn"]
  static values = { weights: Object, recipeBasePath: String }

  connect() {
    this.tagPreferences = {}
    this.declinePenalties = {}
    this.animFrame = null
    this.isSpinning = false
    this.currentWinner = null

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
    this.currentWinner = null
    this.isSpinning = false
    this.resultDetailsTarget.classList.remove("visible")
    this.acceptBtnTarget.hidden = true
    this.spinBtnTarget.textContent = this.randomQuip(QUIPS)
    this.buildTagPills()
  }

  reset() {
    this.cancelAnimation()
    this.tagPreferences = {}
    this.declinePenalties = {}
    this.currentWinner = null
  }

  cancelAnimation() {
    if (this.animFrame) {
      cancelAnimationFrame(this.animFrame)
      this.animFrame = null
    }
  }

  buildTagPills() {
    const container = this.tagPillsTarget
    container.textContent = ""
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
    if (this.isSpinning) return
    this.isSpinning = true

    if (this.currentWinner) {
      this.declinePenalties[this.currentWinner.slug] =
        (this.declinePenalties[this.currentWinner.slug] || 0) + 1
    }

    this.resultDetailsTarget.classList.remove("visible")
    this.acceptBtnTarget.hidden = true
    this.spinBtnTarget.textContent = "Spinning\u2026"

    const weights = computeFinalWeights(
      this.recipes, this.weightsValue, this.tagPreferences, this.declinePenalties
    )
    const pick = weightedRandomPick(weights)
    if (!pick) {
      this.isSpinning = false
      return
    }

    const winner = this.recipes.find(r => r.slug === pick)
    this.currentWinner = winner

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.showResult(winner)
      return
    }

    this.animateDrum(winner)
  }

  animateDrum(winner) {
    const { keyframes, targetPos, targetItems } =
      buildKeyframes(SPIN_FORCE, TOTAL_FRICTION, DRAG_BLEND, ITEM_HEIGHT)
    const totalTime = keyframes[keyframes.length - 1].t

    const reelItems = buildReelItems(
      this.recipes, winner, targetItems, targetItems + 5
    )

    const reel = this.reelTarget
    reel.textContent = ""
    for (const recipe of reelItems) {
      const div = document.createElement("div")
      div.className = "dinner-picker-reel-item"
      div.textContent = recipe.title
      reel.appendChild(div)
    }
    reel.style.transform = "translateY(0)"
    this.warpItems(0)

    let startTimestamp = null
    const frame = (timestamp) => {
      if (!startTimestamp) startTimestamp = timestamp

      const elapsed = (timestamp - startTimestamp) / 1000
      const state = positionAtTime(keyframes, elapsed)

      reel.style.transform = `translateY(-${state.pos}px)`
      this.warpItems(state.pos)

      if (elapsed >= totalTime) {
        reel.style.transform = `translateY(-${targetPos}px)`
        this.warpItems(targetPos)
        this.showResult(winner)
        return
      }

      this.animFrame = requestAnimationFrame(frame)
    }

    this.cancelAnimation()
    this.animFrame = requestAnimationFrame(frame)
  }

  warpItems(scrollPos) {
    const items = this.reelTarget.children
    for (let i = 0; i < items.length; i++) {
      const itemTop = REEL_PADDING_TOP + i * ITEM_HEIGHT - scrollPos
      const itemCenter = itemTop + ITEM_HEIGHT / 2
      const distFromCenter = (itemCenter - CONTAINER_CENTER) / CONTAINER_CENTER

      const warp = applyCylinderWarp(distFromCenter, ITEM_HEIGHT)
      if (!warp) {
        items[i].style.transform = ""
        continue
      }

      items[i].style.transform =
        `scaleY(${warp.scaleY.toFixed(3)}) translateY(${warp.yShift.toFixed(1)}px)`
    }
  }

  showResult(winner) {
    this.isSpinning = false
    this.spinBtnTarget.textContent = this.randomQuip(RESPIN_QUIPS)
    this.acceptBtnTarget.hidden = false

    this.resultDescriptionTarget.textContent = winner.description || ""
    this.resultLinkTarget.textContent = winner.title + " \u2192"
    this.resultLinkTarget.href =
      this.recipeBasePathValue + encodeURIComponent(winner.slug)
    this.resultDetailsTarget.classList.add("visible")
  }

  accept() {
    if (!this.currentWinner) return
    const checkbox = document.querySelector(
      `#recipe-selector input[type="checkbox"][data-slug="${CSS.escape(this.currentWinner.slug)}"]`
    )
    if (checkbox && !checkbox.checked) {
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    }
    this.element.close()
  }

  randomQuip(list) {
    return list[Math.floor(Math.random() * list.length)]
  }
}
