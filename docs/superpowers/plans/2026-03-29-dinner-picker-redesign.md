# Dinner Picker Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the dinner picker dialog into a single-page experience with a physics-based slot machine animation and faux-cylinder visual treatment.

**Architecture:** Extract spin physics and cylinder warp into a testable utility module (`spin_physics.js`). Rewrite the Stimulus controller to use a single-page layout (tags + drum + result details always visible). Replace setTimeout animation with requestAnimationFrame playback of pre-computed physics keyframes. Update CSS to replace the three-state layout with the new drum + result details structure.

**Tech Stack:** Stimulus, CSS custom properties, requestAnimationFrame, Euler physics simulation

**Spec:** `docs/superpowers/specs/2026-03-29-dinner-picker-redesign-design.md`

**Prototype reference:** `.superpowers/brainstorm/141793-1774831771/content/scroll-physics-v8.html`

---

### File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `app/javascript/utilities/spin_physics.js` | Create | Physics simulation, keyframe generation, cylinder warp, reel construction |
| `test/javascript/spin_physics_test.mjs` | Create | Unit tests for all spin_physics functions |
| `app/javascript/controllers/dinner_picker_controller.js` | Rewrite | Single-page layout, rAF animation playback, result reveal |
| `app/assets/stylesheets/menu.css` | Modify | Replace three-state CSS with drum + result details styles |
| `app/views/menu/show.html.erb` | Modify | Simplify dialog markup to single container |
| `app/javascript/utilities/dinner_picker_logic.js` | Unchanged | Weight computation stays as-is |
| `test/javascript/dinner_picker_test.mjs` | Unchanged | Existing weight tests still pass |

---

### Task 1: Create `spin_physics.js` — Physics Simulation

**Files:**
- Create: `app/javascript/utilities/spin_physics.js`
- Create: `test/javascript/spin_physics_test.mjs`

This task builds the pure-function physics engine. All functions are stateless and testable without DOM.

- [ ] **Step 1: Write tests for `simulateCurve`**

```javascript
// test/javascript/spin_physics_test.mjs
import assert from "node:assert/strict"
import { test } from "node:test"
import {
  simulateCurve,
  buildKeyframes,
  applyCylinderWarp,
  buildReelItems
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
    assert.ok(kf[i].pos >= kf[i - 1].pos,
      `Position decreased at index ${i}`)
  }
})

test("simulateCurve with pure constant friction", () => {
  const kf = simulateCurve(100, 50, 0)
  const last = kf[kf.length - 1]

  // v = v0 - a*t => t = v0/a = 100/50 = 2s
  assertCloseTo(last.t, 2.0, 0.1)
})
```

- [ ] **Step 2: Write tests for `buildKeyframes`**

```javascript
// Append to test/javascript/spin_physics_test.mjs

test("buildKeyframes lands exactly on target position", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  const last = result.keyframes[result.keyframes.length - 1]

  assertCloseTo(last.pos, result.targetPos, 0.01)
})

test("buildKeyframes target is a multiple of itemHeight", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)

  assert.equal(result.targetPos % 30, 0)
})

test("buildKeyframes ensures minimum travel", () => {
  // Very low force — should still travel at least 5 items
  const result = buildKeyframes(50, 275, 0.75, 30)

  assert.ok(result.targetItems >= 5,
    `Should travel at least 5 items, got ${result.targetItems}`)
})

test("buildKeyframes returns winnerIndex within reel bounds", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)

  assert.equal(result.winnerIndex, result.targetItems)
  assert.ok(result.winnerIndex > 0)
})
```

- [ ] **Step 3: Write tests for `buildReelItems`**

```javascript
// Append to test/javascript/spin_physics_test.mjs

test("buildReelItems places winner at winnerIndex", () => {
  const recipes = [
    { title: "A", slug: "a" },
    { title: "B", slug: "b" },
    { title: "C", slug: "c" }
  ]
  const winner = recipes[1]
  const items = buildReelItems(recipes, winner, 10, 15)

  assert.equal(items[10].title, "B")
  assert.equal(items.length, 15)
})

test("buildReelItems loops recipes to fill reel", () => {
  const recipes = [
    { title: "A", slug: "a" },
    { title: "B", slug: "b" }
  ]
  const winner = recipes[0]
  const items = buildReelItems(recipes, winner, 5, 8)

  // Items before winner should cycle through recipes
  assert.equal(items[0].title, "A")
  assert.equal(items[1].title, "B")
  assert.equal(items[2].title, "A")
  assert.equal(items[5].title, "A") // winner
})
```

- [ ] **Step 4: Write tests for `applyCylinderWarp`**

```javascript
// Append to test/javascript/spin_physics_test.mjs

test("applyCylinderWarp returns scaleY 1.0 at center", () => {
  const result = applyCylinderWarp(0, 76)

  assertCloseTo(result.scaleY, 1.0, 0.01)
  assertCloseTo(result.yShift, 0, 0.1)
})

test("applyCylinderWarp compresses at edges", () => {
  const result = applyCylinderWarp(1.0, 76)

  assert.ok(result.scaleY < 0.5,
    `scaleY at edge should be < 0.5, got ${result.scaleY}`)
})

test("applyCylinderWarp returns null for off-screen items", () => {
  const result = applyCylinderWarp(2.0, 76)

  assert.equal(result, null)
})

test("applyCylinderWarp foreshortening is gradual from center", () => {
  const center = applyCylinderWarp(0, 76)
  const nearby = applyCylinderWarp(0.2, 76)
  const mid = applyCylinderWarp(0.5, 76)

  // Should compress immediately — not stay flat near center
  assert.ok(nearby.scaleY < center.scaleY,
    "Items near center should already be slightly compressed")
  assert.ok(mid.scaleY < nearby.scaleY,
    "Compression should increase toward edges")
})
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `npm test`
Expected: FAIL — module `spin_physics.js` not found

- [ ] **Step 6: Create `spin_physics.js` with all functions**

```javascript
// app/javascript/utilities/spin_physics.js

/**
 * Physics simulation and visual effects for the dinner picker slot machine.
 * Pure functions — no DOM access, fully testable.
 *
 * - dinner_picker_controller.js: consumes these functions for animation
 * - dinner_picker_logic.js: weight computation (separate concern)
 * - test/javascript/spin_physics_test.mjs: unit tests
 */

const SIM_DT = 1 / 240

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

export function buildKeyframes(spinForce, totalFriction, dragBlend, itemHeight) {
  const constFric = totalFriction * (1 - dragBlend)
  const dragCoeff = totalFriction * dragBlend / spinForce * 3

  const raw = simulateCurve(spinForce, constFric, dragCoeff)
  const naturalDist = raw[raw.length - 1].pos

  let targetItems = Math.round(naturalDist / itemHeight)
  if (targetItems < 5) targetItems = 5
  const targetPos = targetItems * itemHeight

  const scale = targetPos / raw[raw.length - 1].pos
  const keyframes = raw.map(kf => ({
    t: kf.t,
    pos: kf.pos * scale,
    v: kf.v * scale
  }))

  return { keyframes, targetPos, targetItems, winnerIndex: targetItems }
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

export function buildReelItems(recipes, winner, winnerIndex, totalItems) {
  const items = []
  for (let i = 0; i < totalItems; i++) {
    if (i === winnerIndex) {
      items.push(winner)
    } else {
      items.push(recipes[i % recipes.length])
    }
  }
  return items
}

export function applyCylinderWarp(distFromCenter, containerHeight) {
  const absDist = Math.abs(distFromCenter)
  if (absDist > 1.5) return null

  const foreshorten = Math.max(0, 1 - Math.pow(absDist, 1.3))
  const scaleY = 0.15 + 0.85 * foreshorten
  const itemHeight = 30
  const yShift = distFromCenter * (1 - scaleY) * itemHeight * 0.5

  return { scaleY, yShift }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `npm test`
Expected: All spin_physics tests PASS, all existing dinner_picker_logic tests PASS

- [ ] **Step 8: Commit**

```bash
git add app/javascript/utilities/spin_physics.js test/javascript/spin_physics_test.mjs
git commit -m "Add spin_physics.js: physics simulation for dinner picker drum"
```

---

### Task 2: Update Dialog Markup

**Files:**
- Modify: `app/views/menu/show.html.erb:64-78`

Replace the three-target dialog structure with a single-page layout.

- [ ] **Step 1: Update dialog markup**

Replace lines 64–78 of `app/views/menu/show.html.erb` with:

```erb
<dialog id="dinner-picker-dialog" class="editor-dialog"
        data-controller="editor dinner-picker"
        data-editor-open-selector-value="#dinner-picker-button"
        data-editor-on-success-value="close"
        data-action="editor:opened->dinner-picker#onOpen"
        data-dinner-picker-weights-value="<%= @cook_weights.to_json %>"
        data-dinner-picker-recipe-base-path-value="<%= recipes_path %>/">
  <div class="dinner-picker-content">
    <button type="button" class="dinner-picker-close"
            data-action="click->editor#close" aria-label="Close">&times;</button>
    <h2 class="dinner-picker-heading">What's for Dinner?</h2>
    <p class="dinner-picker-subtitle">Tap tags to steer the pick, or just spin.</p>
    <div data-dinner-picker-target="tagPills" class="dinner-picker-tag-pills"></div>
    <div class="dinner-picker-drum">
      <div data-dinner-picker-target="reel" class="dinner-picker-reel">
        <div class="dinner-picker-reel-item">&mdash;</div>
      </div>
    </div>
    <div data-dinner-picker-target="resultDetails" class="dinner-picker-result-details">
      <p data-dinner-picker-target="resultDescription" class="dinner-picker-result-description"></p>
      <a data-dinner-picker-target="resultLink" class="dinner-picker-result-link" href="#"></a>
    </div>
    <div class="dinner-picker-actions">
      <button data-dinner-picker-target="spinBtn"
              data-action="click->dinner-picker#spin"
              class="btn btn-primary dinner-picker-spin-btn">I'm feeling lucky</button>
      <button data-dinner-picker-target="acceptBtn"
              data-action="click->dinner-picker#accept"
              class="btn btn-primary" hidden>Add to Menu</button>
    </div>
  </div>
</dialog>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/menu/show.html.erb
git commit -m "Simplify dinner picker dialog to single-page layout"
```

---

### Task 3: Replace CSS Styles

**Files:**
- Modify: `app/assets/stylesheets/menu.css:222-397`

Replace all dinner picker CSS with the new drum-based styles.

- [ ] **Step 1: Replace dinner picker CSS block**

Replace everything from `/* -- Dinner Picker -- */` (line 222) through the `prefers-reduced-motion` media query (line 397) with:

```css
/* -- Dinner Picker -- */

#dinner-picker-dialog.editor-dialog,
#dinner-picker-dialog.editor-dialog[open] {
  max-width: 28rem;
  width: 90vw;
  height: fit-content;
  max-height: 90vh;
  padding: 1.5rem;
  overflow: visible;
}

.dinner-picker-close {
  position: absolute;
  top: 0.75rem;
  right: 0.75rem;
  background: none;
  border: none;
  font-size: 1.5rem;
  line-height: 1;
  color: var(--text-light);
  cursor: pointer;
  padding: 0.25rem 0.5rem;
  z-index: 1;
}

.dinner-picker-close:hover {
  color: var(--text);
}

.dinner-picker-heading {
  text-align: center;
  margin: 0;
}

.dinner-picker-subtitle {
  color: var(--text-soft);
  font-size: 0.85rem;
  margin: 0.3rem 0 1rem;
  text-align: center;
}

.dinner-picker-tag-pills {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  justify-content: center;
  margin-bottom: 1.2rem;
}

.dinner-picker-tag {
  padding: 0.3rem 0.6rem;
  border-radius: 12px;
  font-size: 0.8rem;
  cursor: pointer;
  border: 1px solid transparent;
  transition: background var(--duration-fast), color var(--duration-fast);
}

.dinner-picker-tag.tag-neutral {
  background: var(--surface-alt);
  color: var(--text-soft);
}

.dinner-picker-tag.tag-up {
  background: var(--smart-green-bg);
  color: var(--smart-green-text);
}

.dinner-picker-tag.tag-down {
  background: var(--red-light);
  color: var(--red);
}

.dinner-picker-spin-btn {
  min-width: 180px;
}

/* -- Drum (faux-cylinder slot window) -- */

.dinner-picker-drum {
  border-radius: 8px;
  height: 76px;
  overflow: hidden;
  position: relative;
  margin-bottom: 0.8rem;
  border: 1px solid var(--rule);
  background: var(--surface-alt);
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

.dinner-picker-drum::after {
  content: '';
  position: absolute;
  left: 0;
  right: 0;
  top: 50%;
  transform: translateY(-50%);
  height: 30px;
  z-index: 3;
  pointer-events: none;
  border-top: 1px solid rgba(179, 58, 58, 0.2);
  border-bottom: 1px solid rgba(179, 58, 58, 0.2);
}

.dinner-picker-reel {
  display: flex;
  flex-direction: column;
  align-items: center;
  will-change: transform;
  padding-top: 22px;
}

.dinner-picker-reel-item {
  height: 30px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1rem;
  font-weight: 600;
  color: var(--red);
  white-space: nowrap;
  flex-shrink: 0;
  padding: 0 1rem;
}

/* -- Result details (slides in below drum) -- */

.dinner-picker-result-details {
  text-align: center;
  max-height: 0;
  overflow: hidden;
  transition: max-height 0.4s ease, opacity 0.3s ease;
  opacity: 0;
}

.dinner-picker-result-details.visible {
  max-height: 200px;
  opacity: 1;
}

.dinner-picker-result-description {
  color: var(--text-soft);
  font-size: 0.85rem;
  margin-bottom: 0.6rem;
  line-height: 1.4;
}

.dinner-picker-result-link {
  display: block;
  text-align: center;
  color: var(--text-soft);
  font-size: 0.8rem;
  margin-bottom: 0.2rem;
}

.dinner-picker-actions {
  display: flex;
  gap: 0.5rem;
  justify-content: center;
  margin-top: 0.8rem;
}

.dinner-picker-actions [hidden] {
  display: none;
}

@media (max-width: 720px) {
  #dinner-picker-dialog.editor-dialog {
    width: 90vw;
    height: fit-content;
    max-width: 28rem;
    max-height: 90vh;
    border-radius: 0.25rem;
    border: 1px solid var(--text);
    padding: 1.5rem;
  }
}
```

- [ ] **Step 2: Verify the `html_safe_allowlist.yml` doesn't reference deleted lines**

Run: `grep -n "menu.css" config/html_safe_allowlist.yml`

If any entries reference `menu.css`, check whether they still apply. The dinner picker CSS doesn't use `.html_safe` so this is unlikely.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/menu.css
git commit -m "Replace dinner picker CSS with drum-based single-page styles"
```

---

### Task 4: Rewrite `dinner_picker_controller.js`

**Files:**
- Rewrite: `app/javascript/controllers/dinner_picker_controller.js`

This is the main task — rewrite the controller to use the single-page layout, physics-based animation, and cylinder warp effect.

- [ ] **Step 1: Rewrite the controller**

```javascript
// app/javascript/controllers/dinner_picker_controller.js

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

      const warp = applyCylinderWarp(distFromCenter, CONTAINER_HEIGHT)
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
```

- [ ] **Step 2: Run the full test suite**

Run: `npm test && bundle exec rake test`

Expected: All JS tests pass. All Rails tests pass (the dialog structure changed but controller tests exercise the server-side menu action, not JS behavior).

- [ ] **Step 3: Run linting**

Run: `bundle exec rubocop && npm run build`

Expected: No lint offenses. JS builds without errors.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/dinner_picker_controller.js
git commit -m "Rewrite dinner picker: single-page layout with physics drum animation"
```

---

### Task 5: Verify and Polish

**Files:** None created — this is a verification and cleanup pass.

- [ ] **Step 1: Run the full test suite**

Run: `npm test && bundle exec rake`

Expected: All tests pass, no lint offenses.

- [ ] **Step 2: Check `html_safe_allowlist.yml` line numbers**

Run: `rake lint:html_safe`

If any entries in `config/html_safe_allowlist.yml` reference `menu.css` or `show.html.erb` with shifted line numbers, update them.

- [ ] **Step 3: Build JS bundle**

Run: `npm run build`

Expected: Clean build, no warnings.

- [ ] **Step 4: Manual smoke test**

Start the dev server with `bin/dev` and verify:
1. Open the dinner picker dialog from the menu page
2. Tag pills render and toggle through 3 states
3. Click spin — drum animates with physics deceleration and cylinder warp
4. Result details slide in below the drum after landing
5. "Add to Menu" button appears after landing
6. Clicking spin again re-spins without leaving the page
7. Decline penalties apply (previously shown recipes appear less often)
8. "Add to Menu" checks the recipe checkbox and closes the dialog
9. Dialog resets cleanly on close and reopen

- [ ] **Step 5: Commit any fixes from smoke test**

Only if needed. Use descriptive commit messages for each fix.
