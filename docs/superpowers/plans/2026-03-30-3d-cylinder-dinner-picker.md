# 3D Cylinder Dinner Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the faux-3D dinner picker drum with a real CSS 3D spinning cylinder that pre-populates with weighted-random recipes on load and idles until spun.

**Architecture:** 12 recipe labels positioned around a CSS 3D cylinder via `rotateX`/`translateZ`. Physics simulation operates in angular space (degrees). Idle rotation on open; spin physics takes over from current angle. Winner determined by which slot the physics naturally lands on.

**Tech Stack:** CSS 3D transforms (`perspective`, `transform-style: preserve-3d`), Stimulus controller, requestAnimationFrame animation loop.

---

### Task 1: Rewrite spin_physics.js to angular space

Remove pixel-oriented helpers (`buildReelItems`, `applyCylinderWarp`) and
convert `buildKeyframes` to work in degrees with a slot-angle parameter.
`simulateCurve` is already unit-agnostic — no changes needed.

**Files:**
- Modify: `app/javascript/utilities/spin_physics.js`
- Modify: `test/javascript/spin_physics_test.mjs`

- [ ] **Step 1: Write failing tests for angular buildKeyframes**

Replace the existing test file contents with:

```javascript
import assert from "node:assert/strict"
import { test } from "node:test"
import {
  simulateCurve,
  buildKeyframes,
  positionAtTime
} from "../../app/javascript/utilities/spin_physics.js"

function assertCloseTo(actual, expected, delta) {
  assert.ok(Math.abs(actual - expected) <= delta,
    `Expected ${actual} to be within ${delta} of ${expected}`)
}

test("simulateCurve returns keyframes starting at zero", () => {
  const kf = simulateCurve(1200, 68.75, 0.515625)
  assert.equal(kf[0].t, 0)
  assert.equal(kf[0].pos, 0)
  assert.equal(kf[0].v, 1200)
})

test("simulateCurve ends with velocity near zero", () => {
  const kf = simulateCurve(1200, 68.75, 0.515625)
  const last = kf[kf.length - 1]
  assert.ok(last.v < 1, `Final velocity ${last.v} should be < 1`)
  assert.ok(last.pos > 0, "Should have traveled some distance")
  assert.ok(last.t > 0, "Should have taken some time")
})

test("simulateCurve positions are monotonically increasing", () => {
  const kf = simulateCurve(1200, 68.75, 0.515625)
  for (let i = 1; i < kf.length; i++) {
    assert.ok(kf[i].pos >= kf[i - 1].pos, `Position decreased at index ${i}`)
  }
})

test("simulateCurve with pure constant friction", () => {
  const kf = simulateCurve(100, 50, 0)
  const last = kf[kf.length - 1]
  assertCloseTo(last.t, 2.0, 0.1)
})

test("buildKeyframes lands exactly on a slot boundary", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  const last = result.keyframes[result.keyframes.length - 1]
  assertCloseTo(last.pos, result.targetAngle, 0.01)
  assert.equal(result.targetAngle % 30, 0)
})

test("buildKeyframes ensures minimum 720 degrees of travel", () => {
  const result = buildKeyframes(50, 275, 0.75, 30)
  assert.ok(result.targetAngle >= 720,
    `Should travel at least 720°, got ${result.targetAngle}`)
})

test("buildKeyframes returns winnerSlot as index into 12 slots", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  assert.ok(result.winnerSlot >= 0 && result.winnerSlot < 12,
    `winnerSlot should be 0-11, got ${result.winnerSlot}`)
})

test("buildKeyframes winnerSlot matches target angle", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  const expectedSlot = (result.targetAngle / 30) % 12
  assert.equal(result.winnerSlot, expectedSlot)
})

test("positionAtTime interpolates correctly at midpoint", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  const totalTime = result.keyframes[result.keyframes.length - 1].t
  const mid = positionAtTime(result.keyframes, totalTime / 2)
  assert.ok(mid.pos > 0, "Should have traveled some distance at midpoint")
  assert.ok(mid.pos < result.targetAngle, "Should not have reached target at midpoint")
})

test("positionAtTime returns last keyframe at end", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  const totalTime = result.keyframes[result.keyframes.length - 1].t
  const end = positionAtTime(result.keyframes, totalTime + 1)
  assertCloseTo(end.pos, result.targetAngle, 0.01)
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test test/javascript/spin_physics_test.mjs`
Expected: FAIL — `buildKeyframes` returns `targetPos`/`targetItems`/`winnerIndex`, not `targetAngle`/`winnerSlot`; `buildReelItems` and `applyCylinderWarp` imports missing.

- [ ] **Step 3: Rewrite spin_physics.js**

Replace the full file contents with:

```javascript
/**
 * Physics simulation for the dinner picker cylinder. Pure functions — no DOM
 * access, fully testable. Operates in angular space (degrees).
 *
 * - dinner_picker_controller.js: consumes these functions for animation
 * - dinner_picker_logic.js: weight computation (separate concern)
 * - test/javascript/spin_physics_test.mjs: unit tests
 */

const SIM_DT = 1 / 240
const SLOT_COUNT = 12
const MIN_TRAVEL = 720

export function simulateCurve(v0, constFric, dragCoeff) {
  let v = v0
  let pos = 0
  let t = 0
  const keyframes = [{ t: 0, pos: 0, v: v0 }]

  while (v > 0.5 && t < 30) {
    const decel = constFric + dragCoeff * v
    v = Math.max(0, v - decel * SIM_DT)
    pos += v * SIM_DT
    t += SIM_DT
    keyframes.push({ t, pos, v })
  }

  return keyframes
}

export function buildKeyframes(spinForce, totalFriction, dragBlend, slotAngle) {
  const constFric = totalFriction * (1 - dragBlend)
  const dragCoeff = totalFriction * dragBlend / spinForce * 3

  const raw = simulateCurve(spinForce, constFric, dragCoeff)
  const naturalDist = raw[raw.length - 1].pos

  let targetSlots = Math.round(naturalDist / slotAngle)
  const minSlots = Math.ceil(MIN_TRAVEL / slotAngle)
  if (targetSlots < minSlots) targetSlots = minSlots

  const targetAngle = targetSlots * slotAngle
  const scale = targetAngle / raw[raw.length - 1].pos

  const keyframes = raw.map(kf => ({
    t: kf.t,
    pos: kf.pos * scale,
    v: kf.v * scale
  }))

  const winnerSlot = targetSlots % SLOT_COUNT

  return { keyframes, targetAngle, winnerSlot }
}

export function positionAtTime(keyframes, t) {
  if (t <= 0) return keyframes[0]
  if (t >= keyframes[keyframes.length - 1].t) return keyframes[keyframes.length - 1]

  let lo = 0
  let hi = keyframes.length - 1
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1
    if (keyframes[mid].t <= t) lo = mid
    else hi = mid
  }

  const a = keyframes[lo]
  const b = keyframes[hi]
  const frac = (t - a.t) / (b.t - a.t)
  return {
    t,
    pos: a.pos + (b.pos - a.pos) * frac,
    v: a.v + (b.v - a.v) * frac
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test test/javascript/spin_physics_test.mjs`
Expected: All 10 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/utilities/spin_physics.js test/javascript/spin_physics_test.mjs
git commit -m "Rewrite spin_physics to angular space for 3D cylinder"
```

---

### Task 2: Replace drum CSS with 3D cylinder styles

Delete the faux-warp styles (scaleY reel, `::after` indicator lines) and add
CSS 3D perspective, cylinder wrapper, item positioning, and red chevron markers.

**Files:**
- Modify: `app/assets/stylesheets/menu.css` (lines 300–415)

- [ ] **Step 1: Replace drum CSS block**

Replace the `/* -- Drum (faux-cylinder slot window) -- */` section (from line
300 through line 362, ending after `.dinner-picker-reel-item`) with:

```css
/* -- Drum (3D cylinder slot window) -- */

.dinner-picker-drum {
  border-radius: 8px;
  height: 76px;
  overflow: hidden;
  position: relative;
  margin-bottom: 0.8rem;
  border: 1px solid var(--rule);
  background: var(--surface-alt);
  perspective: 300px;
}

.dinner-picker-drum::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 2;
  pointer-events: none;
  background:
    linear-gradient(to bottom,
      rgba(45, 42, 38, 0.35) 0%,
      rgba(45, 42, 38, 0.08) 20%,
      transparent 38%,
      transparent 62%,
      rgba(45, 42, 38, 0.08) 80%,
      rgba(45, 42, 38, 0.35) 100%
    );
}

.dinner-picker-chevron {
  position: absolute;
  top: 50%;
  transform: translateY(-50%);
  z-index: 3;
  pointer-events: none;
  color: var(--red);
  font-size: 0.7rem;
  opacity: 0.6;
  line-height: 1;
}

.dinner-picker-chevron-left {
  left: 4px;
}

.dinner-picker-chevron-right {
  right: 4px;
}

.dinner-picker-reel {
  position: absolute;
  width: 100%;
  height: 100%;
  transform-style: preserve-3d;
  will-change: transform;
}

.dinner-picker-reel-item {
  position: absolute;
  width: 100%;
  height: 26px;
  top: 50%;
  left: 0;
  margin-top: -13px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.95rem;
  font-weight: 600;
  color: var(--red);
  white-space: nowrap;
  backface-visibility: hidden;
  padding: 0 2rem;
}
```

Note: each item is 26px tall (fitting comfortably inside the 76px viewport at
~3 visible). The cylinder radius is computed in JS from the slot count and item
height.

- [ ] **Step 2: Verify no syntax errors**

Run: `npm run build`
Expected: esbuild succeeds (CSS is served by Propshaft, not esbuild, but this
confirms JS still bundles). Visually verify the CSS is valid by scanning it.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/menu.css
git commit -m "Replace drum CSS with 3D cylinder styles and chevron markers"
```

---

### Task 3: Remove placeholder from show.html.erb

The cylinder is built entirely in JS — remove the static placeholder `<div>`.

**Files:**
- Modify: `app/views/menu/show.html.erb` (lines 77–81)

- [ ] **Step 1: Replace the drum div contents**

Replace:
```erb
    <div class="dinner-picker-drum">
      <div data-dinner-picker-target="reel" class="dinner-picker-reel">
        <div class="dinner-picker-reel-item">&mdash;</div>
      </div>
    </div>
```

With:
```erb
    <div class="dinner-picker-drum">
      <span class="dinner-picker-chevron dinner-picker-chevron-left">&#9654;</span>
      <span class="dinner-picker-chevron dinner-picker-chevron-right">&#9664;</span>
      <div data-dinner-picker-target="reel" class="dinner-picker-reel"></div>
    </div>
```

The chevrons (▶ ◀) are static markers on the drum frame. The reel div starts
empty — the controller populates it with 12 recipe items on open.

- [ ] **Step 2: Commit**

```bash
git add app/views/menu/show.html.erb
git commit -m "Remove placeholder reel item, add chevron markers to drum"
```

---

### Task 4: Rewrite dinner_picker_controller.js

Major rewrite: build 3D cylinder DOM, idle rotation, spin-from-current-angle,
weighted slot population. Delete `warpItems`. Keep all existing targets, values,
quips, tag pill logic, accept logic, and reduced-motion handling.

**Files:**
- Modify: `app/javascript/controllers/dinner_picker_controller.js`

- [ ] **Step 1: Rewrite the controller**

Replace the full file contents with:

```javascript
import { Controller } from "@hotwired/stimulus"
import { computeFinalWeights, weightedRandomPick } from "../utilities/dinner_picker_logic"
import { buildKeyframes, positionAtTime } from "../utilities/spin_physics"
import { loadSearchData, loadSmartTagData } from "../utilities/search_data"

/**
 * Single-page dinner picker with a real CSS 3D spinning cylinder. 12 recipe
 * labels positioned around a cylinder via rotateX/translateZ. Idle rotation on
 * open; physics-based spin on demand. Tags, drum, result details, and action
 * buttons are always visible.
 *
 * - spin_physics.js: angular physics simulation and keyframe generation
 * - dinner_picker_logic.js: weight computation and random selection
 * - search_data.js: provides recipe and tag data
 * - editor_controller: dialog open/close, bloop animation
 * - menu_controller.js: handles checkbox change events for recipe selection
 */

const SLOT_COUNT = 12
const SLOT_ANGLE = 30
const ITEM_HEIGHT = 26
const SPIN_FORCE = 1200
const TOTAL_FRICTION = 275
const DRAG_BLEND = 0.75
const IDLE_SPEED = 0.3

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
    this.currentAngle = 0
    this.slotRecipes = []
    this.cylinderRadius = 0

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
    this.currentAngle = 0
    this.resultDetailsTarget.classList.remove("visible")
    this.acceptBtnTarget.hidden = true
    this.spinBtnTarget.textContent = this.randomQuip(QUIPS)
    this.buildTagPills()
    this.populateCylinder()
    this.startIdle()
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
  }

  applyCylinderRotation(angle) {
    this.reelTarget.style.transform = `rotateX(${-angle}deg)`
  }

  sampleRecipes(count) {
    if (this.recipes.length === 0) return []

    const weights = computeFinalWeights(
      this.recipes, this.weightsValue, this.tagPreferences, this.declinePenalties
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

  // -- Tag pills --

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
```

- [ ] **Step 2: Build JS to verify no syntax errors**

Run: `npm run build`
Expected: esbuild succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/dinner_picker_controller.js
git commit -m "Rewrite dinner picker controller for 3D cylinder"
```

---

### Task 5: Manual smoke test and tuning

The 3D cylinder is now wired up. Verify it works end-to-end in a real browser
and tune the visual parameters (perspective, radius, idle speed) if needed.

**Files:**
- Possibly modify: `app/assets/stylesheets/menu.css` (perspective value)
- Possibly modify: `app/javascript/controllers/dinner_picker_controller.js` (IDLE_SPEED, ITEM_HEIGHT)

- [ ] **Step 1: Start the dev server**

Run: `bin/dev`
Open the menu page and click "What Should We Make?" to open the dinner picker
dialog.

- [ ] **Step 2: Verify idle rotation**

Confirm:
- The cylinder shows 12 recipe names arranged in 3D
- It slowly rotates toward the viewer on open
- ~3 items are visible at a time through the viewport
- Red chevrons (▶ ◀) are visible on left and right edges
- The vignette gradient darkens items at top/bottom edges
- No "—" placeholder visible

- [ ] **Step 3: Verify spin**

Click the Spin button. Confirm:
- The cylinder re-populates with fresh recipes (labels change)
- It spins at least 2 full rotations
- Deceleration looks natural — no visible snap at the end
- Winner lands centered in the viewport
- Result details (description, link) appear below the drum
- "Add to Menu" button appears
- Spin button shows a respin quip

- [ ] **Step 4: Verify tag interaction**

Tap tag pills to boost/suppress tags, then spin again. Confirm the cylinder
re-populates with recipes weighted toward the selected tags.

- [ ] **Step 5: Verify accept**

Click "Add to Menu" and confirm the recipe checkbox gets checked and the dialog
closes.

- [ ] **Step 6: Tune parameters if needed**

If the cylinder looks too flat or too distorted, adjust:
- `perspective: 300px` in `.dinner-picker-drum` (lower = more dramatic 3D)
- `ITEM_HEIGHT = 26` / item CSS `height: 26px` (must match)
- `IDLE_SPEED = 0.3` (full rotations per second — ~3.3s per revolution)

Commit any tuning changes:
```bash
git add -A
git commit -m "Tune 3D cylinder visual parameters"
```

- [ ] **Step 7: Run full test suite**

Run: `rake test` and `npm test`
Expected: All tests pass. No server-side changes were made, so Rails tests
should be unaffected. JS tests updated in Task 1 should pass.

- [ ] **Step 8: Run lint**

Run: `bundle exec rubocop` (only needed if any Ruby files were touched during
tuning — unlikely but verify).

- [ ] **Step 9: Final commit if any tuning was done**

If any additional changes were made during tuning, commit them.
