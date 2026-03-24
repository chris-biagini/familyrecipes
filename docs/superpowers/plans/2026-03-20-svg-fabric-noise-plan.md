# SVG Fabric Noise Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add organic grain to the gingham tablecloth background using a flat grayscale SVG noise filter.

**Architecture:** A second inline SVG filter (`#fabric-texture`) in the layout generates desaturated fractal noise. A new `body::after` pseudo-element applies the filter over the gingham gradients on `body::before`. CSS custom properties control opacity per color scheme.

**Tech Stack:** SVG filters (feTurbulence, feColorMatrix), CSS custom properties

**Spec:** `docs/plans/2026-03-20-svg-fabric-noise-design.md`

---

### Task 1: Add SVG filter definition to application layout

**Files:**
- Modify: `app/views/layouts/application.html.erb:44`
- Modify: `config/html_safe_allowlist.yml:34`

- [ ] **Step 1: Add `#fabric-texture` filter inside the existing `<svg>` block**

Insert after `</filter>` (line 44), before `</svg>` (line 45):

```erb
    <filter id="fabric-texture">
      <feTurbulence type="fractalNoise" baseFrequency="0.65"
                    numOctaves="4" stitchTiles="stitch" />
      <feColorMatrix type="saturate" values="0" />
    </filter>
```

The `<svg>` block should now contain both `#paper-texture` and `#fabric-texture`.

- [ ] **Step 2: Update html_safe_allowlist.yml**

The 4-line insertion shifts `smart_tags_json.html_safe` from line 50 to line 54. Update the allowlist:

```yaml
# application.html.erb — smart_tags_json returns JSON from a frozen Ruby constant (no user content)
- "app/views/layouts/application.html.erb:54"
```

- [ ] **Step 3: Verify the layout renders without errors**

Run: `bin/rails runner "puts 'ok'"`

- [ ] **Step 4: Verify lint passes**

Run: `bundle exec rake lint:html_safe`

- [ ] **Step 5: Commit**

```bash
git add app/views/layouts/application.html.erb config/html_safe_allowlist.yml
git commit -m "Add inline SVG fabric-texture filter to layout"
```

---

### Task 2: Add noise overlay CSS and custom property

**Files:**
- Modify: `app/assets/stylesheets/base.css:74,135,187`

- [ ] **Step 1: Add `--gingham-noise-opacity` token to `:root`**

After `--paper-opacity: 0.08;` (line 74), add:

```css
  --gingham-noise-opacity: 0.07;
```

- [ ] **Step 2: Add dark-mode `--gingham-noise-opacity` override**

After `--paper-opacity: 0.04;` (line 135), add:

```css
    --gingham-noise-opacity: 0.04;
```

- [ ] **Step 3: Add `body::after` rule**

After the `body::before` closing brace (line 187), add:

```css
body::after {
  content: '';
  position: fixed;
  inset: 0;
  z-index: -1;
  pointer-events: none;
  filter: url(#fabric-texture);
  opacity: var(--gingham-noise-opacity);
}
```

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/base.css
git commit -m "Add fabric noise overlay to gingham background"
```

---

### Task 3: Suppress noise overlay in print stylesheet

**Files:**
- Modify: `app/assets/stylesheets/print.css:47`

- [ ] **Step 1: Add `body::after` suppression**

After the existing `main::before` block (lines 45-47), add:

```css
  body::after {
    display: none;
  }
```

- [ ] **Step 2: Run lint to confirm no breakage**

```bash
bundle exec rubocop
```

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/print.css
git commit -m "Suppress fabric noise overlay in print styles"
```
