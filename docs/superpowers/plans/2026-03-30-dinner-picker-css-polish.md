# Dinner Picker CSS Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Elevate the dinner picker's 3D cylinder from functional to showcase with real geometry occlusion, metallic bezel, cosine lighting, and spin blur.

**Architecture:** Pure CSS + JS changes to two files. No new dependencies, no server-rendered markup changes. Cylinder wall panels provide 3D occlusion, per-frame Lambert shading replaces the flat vignette, and velocity-proportional blur adds motion feel.

**Tech Stack:** CSS 3D transforms, `color-mix()`, CSS custom properties, `requestAnimationFrame`, `filter: blur()`

**Spec:** `docs/superpowers/specs/2026-03-30-dinner-picker-css-polish-design.md`

---

### Task 1: Cylinder Wall Panels — CSS + JS

Add 12 panel elements to the cylinder for real 3D occlusion with alternating colors.

**Files:**
- Modify: `app/assets/stylesheets/menu.css:358-373`
- Modify: `app/javascript/controllers/dinner_picker_controller.js:105-124`

- [ ] **Step 1: Add panel CSS rules**

Add the panel class below the existing `.dinner-picker-reel` block (after line 356) in `menu.css`:

```css
.dinner-picker-reel-panel {
  position: absolute;
  width: 100%;
  height: 28px;
  top: 50%;
  left: 0;
  margin-top: -14px;
  --panel-color: var(--surface-alt);
  background-color: var(--panel-color);
  backface-visibility: hidden;
}

.dinner-picker-reel-panel.alt {
  --panel-color: var(--rule-faint);
}
```

- [ ] **Step 2: Update label translateZ in CSS**

In `.dinner-picker-reel-item`, the `backface-visibility` is already `visible`. No CSS change needed — the extra 1.5px translateZ offset is applied in JS (next step).

- [ ] **Step 3: Rewrite `populateCylinder()` to build panels + labels**

Replace the `populateCylinder()` method in `dinner_picker_controller.js`:

```javascript
populateCylinder() {
  this.slotRecipes = this.sampleRecipes(SLOT_COUNT)
  this.cylinderRadius = (ITEM_HEIGHT / 2) / Math.tan(Math.PI / SLOT_COUNT)

  const reel = this.reelTarget
  reel.textContent = ""

  for (let i = 0; i < SLOT_COUNT; i++) {
    const panel = document.createElement("div")
    panel.className = `dinner-picker-reel-panel${i % 2 ? " alt" : ""}`
    const panelAngle = i * SLOT_ANGLE + SLOT_ANGLE / 2
    panel.style.transform =
      `rotateX(${panelAngle}deg) translateZ(${this.cylinderRadius}px)`
    reel.appendChild(panel)

    const label = document.createElement("div")
    label.className = "dinner-picker-reel-item"
    label.textContent = this.slotRecipes[i].title
    const labelAngle = i * SLOT_ANGLE
    label.style.transform =
      `rotateX(${labelAngle}deg) translateZ(${this.cylinderRadius + 1.5}px)`
    reel.appendChild(label)
  }

  this.applyCylinderRotation(this.currentAngle)
  this.sizeDrum()
}
```

- [ ] **Step 4: Build JS and verify in browser**

Run: `npm run build`

Open http://rika:3030, navigate to the menu page, open the dinner picker dialog. Verify:
- Cylinder shows alternating cream panels behind the recipe labels
- Rear labels are no longer visible through the drum
- Idle scroll is smooth with no popping

- [ ] **Step 5: Commit**

```bash
git add app/assets/stylesheets/menu.css app/javascript/controllers/dinner_picker_controller.js
git commit -m "Add cylinder wall panels for real 3D occlusion

12 alternating-color panels form a solid barrel behind the recipe
labels. Panels use backface-visibility: hidden for natural front-half
occlusion. Labels float 1.5px above the panel surface."
```

---

### Task 2: Inset Metallic Bezel

Replace the flat drum border with a brushed-metal bezel and inner bevel highlight.

**Files:**
- Modify: `app/assets/stylesheets/menu.css:302-329`

- [ ] **Step 1: Replace drum container styles**

Replace the `.dinner-picker-drum` rule (lines 302–312):

```css
.dinner-picker-drum {
  border-radius: 8px;
  height: 76px;
  overflow: hidden;
  position: relative;
  margin: 0 auto 0.8rem;
  background: linear-gradient(to bottom, #d8d4d0 0%, #c8c4c0 50%, #b8b4b0 100%);
  border: 1px solid #a8a4a0;
  box-shadow:
    inset 0 2px 6px rgba(0, 0, 0, 0.25),
    inset 0 -1px 3px rgba(0, 0, 0, 0.1),
    0 1px 2px rgba(0, 0, 0, 0.1);
  perspective: 150px;
  width: fit-content;
}
```

- [ ] **Step 2: Replace the `::before` vignette with inner bevel**

Replace the `.dinner-picker-drum::before` rule (lines 314–329):

```css
.dinner-picker-drum::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 2;
  pointer-events: none;
  border-radius: 7px;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.3);
}
```

- [ ] **Step 3: Add dark mode overrides**

Add inside the existing `@media (prefers-color-scheme: dark)` block in `menu.css` (find the appropriate location — there may not be one yet for dinner picker styles, so add at the end of the dark mode block or after the light-mode dinner picker rules):

```css
@media (prefers-color-scheme: dark) {
  .dinner-picker-drum {
    background: linear-gradient(to bottom, #4a4540 0%, #3a3530 50%, #2a2724 100%);
    border-color: #1e1b18;
    box-shadow:
      inset 0 2px 6px rgba(0, 0, 0, 0.4),
      inset 0 -1px 3px rgba(0, 0, 0, 0.2),
      0 1px 2px rgba(0, 0, 0, 0.2);
  }

  .dinner-picker-drum::before {
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.1);
  }
}
```

- [ ] **Step 4: Verify in browser**

Open http://rika:3030, open the dinner picker. Verify:
- Drum has a subtle brushed-metal gradient (lighter top, darker bottom)
- Inset shadow makes the viewport feel recessed
- Top edge has a thin highlight "lip"
- Toggle dark mode (OS setting or browser devtools) and verify dark variant

- [ ] **Step 5: Commit**

```bash
git add app/assets/stylesheets/menu.css
git commit -m "Replace flat drum border with inset metallic bezel

Brushed-metal gradient with inset shadows creates a recessed slot-machine
window. Inner bevel highlight on the top edge. Dark mode variant included."
```

---

### Task 3: Bezel-Mounted Engraved Chevrons

Move chevrons to the bezel surface with an engraved/debossed look.

**Files:**
- Modify: `app/assets/stylesheets/menu.css:331-349`

- [ ] **Step 1: Update chevron base styles**

Replace the `.dinner-picker-chevron` rule:

```css
.dinner-picker-chevron {
  position: absolute;
  top: 50%;
  transform: translateY(-50%);
  z-index: 4;
  pointer-events: none;
  color: #8a8580;
  font-size: 0.7rem;
  line-height: 1;
  text-shadow:
    0 1px 0 rgba(255, 255, 255, 0.4),
    0 -1px 0 rgba(0, 0, 0, 0.2);
}
```

Key changes from current: `z-index` 3→4 (above bevel), `opacity: 0.6` removed, `color` changed from `var(--red)` to `#8a8580` (warm gray matching metal), engraved `text-shadow` added.

- [ ] **Step 2: Add dark mode chevron override**

Add inside the `@media (prefers-color-scheme: dark)` block created in Task 2 step 3 (don't create a second media query — append to the existing one):

```css
  .dinner-picker-chevron {
    color: #5a5550;
    text-shadow:
      0 1px 0 rgba(255, 255, 255, 0.15),
      0 -1px 0 rgba(0, 0, 0, 0.4);
  }
```

- [ ] **Step 3: Verify in browser**

Open http://rika:3030, open dinner picker. Verify:
- Chevrons appear stamped/engraved into the metallic bezel
- They sit visually on the faceplate, not floating over the cylinder
- Light/dark mode both look right

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/menu.css
git commit -m "Move chevrons to bezel surface with engraved look

Chevrons now read as stamped into the metallic faceplate rather than
floating over the cylinder. Dual text-shadow creates debossed effect."
```

---

### Task 4: Cosine Edge Shading (Lambert Lighting)

Per-panel shading that follows 3D geometry, called each animation frame.

**Files:**
- Modify: `app/javascript/controllers/dinner_picker_controller.js:136-180`
- Modify: `app/assets/stylesheets/menu.css` (panel and label rules)

- [ ] **Step 1: Add shade-driven CSS for panels**

Update the `.dinner-picker-reel-panel` rule (created in Task 1) to use `--shade`:

```css
.dinner-picker-reel-panel {
  position: absolute;
  width: 100%;
  height: 28px;
  top: 50%;
  left: 0;
  margin-top: -14px;
  --panel-color: var(--surface-alt);
  --shade: 0;
  background-color: color-mix(in srgb, var(--panel-color), black calc(var(--shade) * 35%));
  backface-visibility: hidden;
}
```

- [ ] **Step 2: Add shade-driven CSS for labels**

Update `.dinner-picker-reel-item` to add the `--shade` property and opacity calc:

```css
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
  backface-visibility: visible;
  --shade: 0;
  opacity: calc(1 - var(--shade) * 0.6);
}
```

- [ ] **Step 3: Add `updateShading()` method to the controller**

Add this method to `dinner_picker_controller.js`, after `applyCylinderRotation()`:

```javascript
updateShading() {
  const panels = this.reelTarget.querySelectorAll(".dinner-picker-reel-panel")
  const labels = this.reelTarget.querySelectorAll(".dinner-picker-reel-item")

  panels.forEach((panel, i) => {
    const deg = (i * SLOT_ANGLE + SLOT_ANGLE / 2 + this.currentAngle) % 360
    const shade = 1 - Math.abs(Math.cos(deg * Math.PI / 180))
    panel.style.setProperty("--shade", shade.toFixed(3))
  })

  labels.forEach((label, i) => {
    const deg = (i * SLOT_ANGLE + this.currentAngle) % 360
    const shade = 1 - Math.abs(Math.cos(deg * Math.PI / 180))
    label.style.setProperty("--shade", shade.toFixed(3))
  })
}
```

- [ ] **Step 4: Call `updateShading()` in the idle animation loop**

Update the `startIdle()` method — add `this.updateShading()` after `this.applyCylinderRotation()`:

```javascript
startIdle() {
  this.cancelAnimation()
  let lastTimestamp = null

  const frame = (timestamp) => {
    if (!lastTimestamp) lastTimestamp = timestamp
    const dt = (timestamp - lastTimestamp) / 1000
    lastTimestamp = timestamp

    this.currentAngle += IDLE_SPEED * dt * 360
    this.applyCylinderRotation(this.currentAngle)
    this.updateShading()
    this.animFrame = requestAnimationFrame(frame)
  }

  this.animFrame = requestAnimationFrame(frame)
}
```

- [ ] **Step 5: Call `updateShading()` in the spin animation loop**

Update the `animateSpin()` method — add `this.updateShading()` after each `this.applyCylinderRotation()` call. The frame callback becomes:

```javascript
const frame = (timestamp) => {
  if (!startTimestamp) startTimestamp = timestamp

  const elapsed = (timestamp - startTimestamp) / 1000
  const state = positionAtTime(keyframes, elapsed)

  this.currentAngle = startAngle + state.pos
  this.applyCylinderRotation(this.currentAngle)
  this.updateShading()

  if (elapsed >= totalTime) {
    this.currentAngle = startAngle + targetAngle
    this.applyCylinderRotation(this.currentAngle)
    this.updateShading()
    this.showResult(winner)
    return
  }

  this.animFrame = requestAnimationFrame(frame)
}
```

- [ ] **Step 6: Call `updateShading()` after `populateCylinder()`**

In `populateCylinder()`, add `this.updateShading()` after `this.sizeDrum()` so panels get initial shade values:

```javascript
  this.applyCylinderRotation(this.currentAngle)
  this.sizeDrum()
  this.updateShading()
}
```

- [ ] **Step 7: Build and verify in browser**

Run: `npm run build`

Open http://rika:3030, open dinner picker. Verify:
- Panels near the top/bottom edges are visibly darker than the front-facing panel
- Labels near the edges fade in opacity
- The shading transitions smoothly during idle scroll — no flickering or stepping
- The shading updates correctly during a spin

- [ ] **Step 8: Commit**

```bash
git add app/assets/stylesheets/menu.css app/javascript/controllers/dinner_picker_controller.js
git commit -m "Add cosine edge shading to cylinder panels and labels

Per-frame Lambert shading replaces the flat vignette gradient. Each panel
and label gets a --shade custom property updated via requestAnimationFrame,
driving color-mix darkening on panels and opacity reduction on labels."
```

---

### Task 5: Spin Blur

Velocity-proportional `filter: blur()` during spin animation.

**Files:**
- Modify: `app/javascript/controllers/dinner_picker_controller.js:249-281`

- [ ] **Step 1: Add blur to the spin animation loop**

Update the `animateSpin()` frame callback to apply blur based on velocity. The `state` object from `positionAtTime()` has a `.v` property (degrees/second). Update the frame function (building on Task 4's version):

```javascript
const frame = (timestamp) => {
  if (!startTimestamp) startTimestamp = timestamp

  const elapsed = (timestamp - startTimestamp) / 1000
  const state = positionAtTime(keyframes, elapsed)

  this.currentAngle = startAngle + state.pos
  this.applyCylinderRotation(this.currentAngle)
  this.updateShading()

  const blurPx = Math.min(state.v / 300, 4)
  this.reelTarget.style.filter = blurPx > 0.3
    ? `blur(${blurPx.toFixed(1)}px)` : "none"

  if (elapsed >= totalTime) {
    this.currentAngle = startAngle + targetAngle
    this.applyCylinderRotation(this.currentAngle)
    this.updateShading()
    this.reelTarget.style.filter = "none"
    this.showResult(winner)
    return
  }

  this.animFrame = requestAnimationFrame(frame)
}
```

- [ ] **Step 2: Build and verify in browser**

Run: `npm run build`

Open http://rika:3030, open dinner picker and click spin. Verify:
- Labels blur into color bands at peak velocity
- Blur decreases smoothly as the cylinder decelerates
- Labels are fully crisp when the spin lands
- Idle scroll has no blur

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/dinner_picker_controller.js
git commit -m "Add velocity-proportional spin blur to cylinder

filter: blur() scales with angular velocity during spin, peaking at
4px at launch speed and clearing to sharp as the cylinder decelerates.
No blur during idle rotation."
```

---

### Task 6: Final Polish and Verification

End-to-end check and any cleanup.

**Files:**
- Possibly: `app/assets/stylesheets/menu.css`, `app/javascript/controllers/dinner_picker_controller.js`

- [ ] **Step 1: Run JS tests**

Run: `npm test`

Expected: All existing dinner_picker and spin_physics tests pass. No new tests needed — the changes are purely visual (CSS + DOM construction) with no new logic functions.

- [ ] **Step 2: Run Ruby tests**

Run: `bundle exec rake test`

Expected: All tests pass. No Ruby files were changed.

- [ ] **Step 3: Run linter**

Run: `bundle exec rubocop`

Expected: No offenses. No Ruby files were changed, but verify nothing was accidentally touched.

- [ ] **Step 4: Full browser walkthrough**

Open http://rika:3030, test the complete flow:
1. Open dinner picker — verify idle scroll with alternating panels, edge shading, metallic bezel, engraved chevrons
2. Click spin — verify blur ramps up, shading continues, blur clears on landing
3. Click re-spin — verify same behavior with new recipes
4. Accept a recipe — verify dialog closes cleanly
5. Re-open — verify idle scroll restarts from clean state
6. Toggle dark mode — verify all elements adapt (bezel gradient, chevron colors, panel colors)

- [ ] **Step 5: Check `prefers-reduced-motion`**

In browser devtools, enable "prefers-reduced-motion: reduce". Open picker and spin. Verify:
- Result appears immediately with no animation
- No blur applied

- [ ] **Step 6: Commit any final tweaks**

If any visual adjustments were needed during verification, commit them:

```bash
git add -u
git commit -m "Polish dinner picker CSS: [describe tweaks]"
```

If no tweaks needed, skip this step.
