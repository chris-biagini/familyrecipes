# SVG Paper Texture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the PNG paper texture with a procedural SVG feTurbulence filter.

**Architecture:** An inline `<svg>` filter definition in the layout generates
fractal noise passed through diffuse lighting. The `main::before` pseudo-element
applies the filter instead of tiling a PNG. CSS custom properties control opacity.

**Tech Stack:** SVG filters (feTurbulence, feDiffuseLighting), CSS custom properties

**Spec:** `docs/plans/2026-03-20-svg-paper-texture-design.md`

---

### Task 1: Add SVG filter definition to application layout

**Files:**
- Modify: `app/views/layouts/application.html.erb:36`

- [ ] **Step 1: Add inline SVG after `</main>`**

Insert between `</main>` (line 36) and `<div id="notifications">` (line 37):

```erb
  <svg width="0" height="0" aria-hidden="true">
    <filter id="paper-texture">
      <feTurbulence type="fractalNoise" baseFrequency="0.5"
                    numOctaves="4" stitchTiles="stitch" />
      <feDiffuseLighting lighting-color="white" surfaceScale="1.2">
        <feDistantLight azimuth="45" elevation="55" />
      </feDiffuseLighting>
    </filter>
  </svg>
```

- [ ] **Step 2: Verify the layout renders without errors**

Run: `bin/rails runner "puts 'ok'"`

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "Add inline SVG paper-texture filter to layout"
```

---

### Task 2: Replace PNG texture with SVG filter in CSS

**Files:**
- Modify: `app/assets/stylesheets/base.css:73,133,550-558`

- [ ] **Step 1: Add `--paper-opacity` token to `:root`**

After `--content-card-bg: rgb(255, 252, 249);` (line 73), add:

```css
  --paper-opacity: 0.08;
```

- [ ] **Step 2: Add dark-mode `--paper-opacity` override**

After `--content-card-bg: rgb(30, 27, 24);` (line 133), add:

```css
    --paper-opacity: 0.04;
```

- [ ] **Step 3: Replace `main::before` styles**

Replace the existing `main::before` block (lines 550-558):

```css
/* Before (delete this): */
main::before {
  content: "";
  position: absolute;
  inset: 0;
  background-image: url("paper-noise.png");
  background-size: 200px 200px;
  opacity: 0.05;
  pointer-events: none;
}

/* After: */
main::before {
  content: "";
  position: absolute;
  inset: 0;
  filter: url(#paper-texture);
  opacity: var(--paper-opacity);
  pointer-events: none;
}
```

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/base.css
git commit -m "Replace PNG paper texture with SVG feTurbulence filter"
```

---

### Task 3: Suppress texture overlay in print stylesheet

**Files:**
- Modify: `app/assets/stylesheets/print.css:36-43`

- [ ] **Step 1: Add `main::before` suppression**

After the existing `main { ... }` block (lines 36-43), add:

```css
  main::before {
    display: none;
  }
```

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/print.css
git commit -m "Suppress paper texture overlay in print styles"
```

---

### Task 4: Delete unused image assets

**Files:**
- Delete: `app/assets/images/paper-noise.png`
- Delete: `app/assets/images/fabric-weave.png`

- [ ] **Step 1: Delete both files**

```bash
rm app/assets/images/paper-noise.png app/assets/images/fabric-weave.png
```

- [ ] **Step 2: Verify no remaining references**

```bash
grep -r "paper-noise\|fabric-weave" app/ --include="*.css" --include="*.erb" --include="*.js"
```

Expected: no output (base.css reference was already replaced in Task 2).

- [ ] **Step 3: Run lint to confirm no breakage**

```bash
bundle exec rubocop
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Delete unused paper-noise.png and fabric-weave.png"
```
