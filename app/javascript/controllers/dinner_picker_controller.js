import { Controller } from "@hotwired/stimulus"
import { computeFinalWeights, weightedRandomPick } from "../utilities/dinner_picker_logic"
import { buildKeyframes, positionAtTime } from "../utilities/spin_physics"
import { loadSearchData } from "../utilities/search_data"

/**
 * Single-page dinner picker with a real CSS 3D spinning cylinder. 12 recipe
 * labels positioned around a cylinder via rotateX/translateZ. Idle rotation on
 * open; physics-based spin on demand. Recency weighting deprioritizes recently
 * cooked recipes; declining a pick penalizes it for the session.
 *
 * - spin_physics.js: angular physics simulation and keyframe generation
 * - dinner_picker_logic.js: weight computation and random selection
 * - search_data.js: provides recipe data
 * - editor_controller: dialog open/close, bloop animation
 * - menu_controller.js: handles checkbox change events for recipe selection
 */

const SLOT_COUNT = 12
const SLOT_ANGLE = 30
const ITEM_HEIGHT = 26
const SPIN_FORCE = 1200
const TOTAL_FRICTION = 275
const DRAG_BLEND = 0.75
const IDLE_SPEED = 0.06
const DRUM_PADDING = 56

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
  static targets = ["reel", "resultDetails", "resultDescription",
                     "resultLink", "spinBtn", "acceptBtn"]
  static values = { weights: Object, recipeBasePath: String }

  connect() {
    this.declinePenalties = {}
    this.animFrame = null
    this.isSpinning = false
    this.currentWinner = null
    this.currentAngle = 0
    this.slotRecipes = []
    this.cylinderRadius = 0

    const data = loadSearchData()
    this.recipes = data.recipes || []

    this.element.addEventListener("close", () => this.reset())
  }

  disconnect() {
    this.cancelAnimation()
  }

  onOpen() {
    this.declinePenalties = {}
    this.currentWinner = null
    this.isSpinning = false
    this.currentAngle = 0
    this.resultDetailsTarget.classList.remove("visible")
    this.acceptBtnTarget.hidden = true
    this.spinBtnTarget.textContent = this.randomQuip(QUIPS)
    this.populateCylinder()
    this.startIdle()
  }

  reset() {
    this.cancelAnimation()
    this.declinePenalties = {}
    this.currentWinner = null
  }

  cancelAnimation() {
    if (this.animFrame) {
      cancelAnimationFrame(this.animFrame)
      this.animFrame = null
    }
  }

  // -- Cylinder DOM --

  populateCylinder() {
    this.slotRecipes = this.sampleRecipes(SLOT_COUNT)
    this.cylinderRadius = (ITEM_HEIGHT / 2) / Math.tan(Math.PI / SLOT_COUNT)

    const reel = this.reelTarget
    reel.textContent = ""

    for (let i = 0; i < SLOT_COUNT; i++) {
      const div = document.createElement("div")
      div.className = "dinner-picker-reel-item"
      div.textContent = this.slotRecipes[i].title
      const angle = i * SLOT_ANGLE
      div.style.transform =
        `rotateX(${angle}deg) translateZ(${this.cylinderRadius}px)`
      reel.appendChild(div)
    }

    this.applyCylinderRotation(this.currentAngle)
    this.sizeDrum()
  }

  sizeDrum() {
    const drum = this.reelTarget.parentElement
    const titles = this.slotRecipes.map(r => r.title)
    const canvas = document.createElement("canvas").getContext("2d")
    const item = this.reelTarget.firstElementChild
    canvas.font = getComputedStyle(item).font
    const maxWidth = Math.max(...titles.map(t => canvas.measureText(t).width))
    drum.style.width = `${Math.ceil(maxWidth) + DRUM_PADDING}px`
  }

  applyCylinderRotation(angle) {
    this.reelTarget.style.transform = `rotateX(${-angle}deg)`
  }

  sampleRecipes(count) {
    if (this.recipes.length === 0) return []

    const weights = computeFinalWeights(
      this.recipes, this.weightsValue, this.declinePenalties
    )

    const picked = []
    const remaining = { ...weights }

    for (let i = 0; i < count; i++) {
      let slug = weightedRandomPick(remaining)
      if (!slug) {
        Object.assign(remaining, weights)
        slug = weightedRandomPick(remaining)
      }
      picked.push(this.recipes.find(r => r.slug === slug))
      delete remaining[slug]
    }

    return picked
  }

  // -- Idle rotation --

  startIdle() {
    this.cancelAnimation()
    let lastTimestamp = null

    const frame = (timestamp) => {
      if (!lastTimestamp) lastTimestamp = timestamp
      const dt = (timestamp - lastTimestamp) / 1000
      lastTimestamp = timestamp

      this.currentAngle += IDLE_SPEED * dt * 360
      this.applyCylinderRotation(this.currentAngle)
      this.animFrame = requestAnimationFrame(frame)
    }

    this.animFrame = requestAnimationFrame(frame)
  }

  // -- Spin --

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

    this.currentAngle = 0
    this.populateCylinder()

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      const winner = this.slotRecipes[0]
      this.currentWinner = winner
      this.showResult(winner)
      return
    }

    this.animateSpin()
  }

  animateSpin() {
    this.cancelAnimation()

    const startAngle = this.currentAngle
    const { keyframes, targetAngle, winnerSlot } =
      buildKeyframes(SPIN_FORCE, TOTAL_FRICTION, DRAG_BLEND, SLOT_ANGLE)
    const totalTime = keyframes[keyframes.length - 1].t

    const winner = this.slotRecipes[winnerSlot]
    this.currentWinner = winner

    let startTimestamp = null
    const frame = (timestamp) => {
      if (!startTimestamp) startTimestamp = timestamp

      const elapsed = (timestamp - startTimestamp) / 1000
      const state = positionAtTime(keyframes, elapsed)

      this.currentAngle = startAngle + state.pos
      this.applyCylinderRotation(this.currentAngle)

      if (elapsed >= totalTime) {
        this.currentAngle = startAngle + targetAngle
        this.applyCylinderRotation(this.currentAngle)
        this.showResult(winner)
        return
      }

      this.animFrame = requestAnimationFrame(frame)
    }

    this.animFrame = requestAnimationFrame(frame)
  }

  // -- Result --

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
