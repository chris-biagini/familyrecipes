# Phone FAB Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the top navbar with a bottom-center floating action button on phones, expanding into a menu panel with a genie-style animation.

**Architecture:** A new Stimulus controller (`phone_fab_controller`) manages a FAB button, overlay, and panel that are hidden by default and shown via a CSS phone media query. The existing nav system (`nav_menu_controller`) is completely untouched — it's hidden on phones by the same media query. The shared `_nav_links` partial renders in both contexts to prevent drift.

**Tech Stack:** Stimulus, CSS animations (`transform`, `opacity`, `transition-delay`), CSS media queries (`pointer`, `hover`, `max-width`).

---

## Spec Deviations

**Icon buttons not extracted into a shared partial.** The spec proposed `_nav_icon_buttons.html.erb`, but the icon buttons need fundamentally different wiring in each context: the top nav uses `data-action="search-overlay#open"` and `id="settings-button"` (for the editor dialog system), while the FAB needs `data-action="phone-fab#openSearch"` / `phone-fab#openSettings` for the close-then-delegate pattern. Sharing the partial would require ugly conditionals that defeat the purpose. The drift risk is near-zero — these are standard icons (search, gear, help) that never change text or appearance. The `_nav_links` partial IS shared, which prevents the meaningful drift risk (link names, icons, routes).

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `app/views/shared/_phone_fab.html.erb` | Create | FAB markup: button, panel, overlay |
| `app/views/layouts/application.html.erb` | Modify | Render `_phone_fab` partial |
| `app/assets/stylesheets/navigation.css` | Modify | Phone media query, FAB/panel/overlay styles, animations |
| `app/assets/stylesheets/base.css` | Modify | Phone query: scroll-margin, gingham spacing, bottom padding |
| `app/javascript/controllers/phone_fab_controller.js` | Create | Open/close, stagger, search/settings dispatch, focus trap |
| `app/javascript/application.js` | Modify | Register `phone-fab` controller |
| `test/integration/phone_fab_test.rb` | Create | Verify FAB markup renders correctly |

---

### Task 1: Create phone FAB partial and add to layout

**Files:**
- Create: `app/views/shared/_phone_fab.html.erb`
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Create `_phone_fab.html.erb`**

```erb
<%# Phone FAB — bottom-center floating action button for phone-sized screens.
    Hidden by default via CSS; shown by the phone media query in navigation.css.
    Renders _nav_links (shared with top nav) to prevent content drift. Icon
    buttons are wired through phone_fab_controller for close-then-delegate.
    - Collaborators: phone_fab_controller.js, navigation.css (.phone-fab) %>
<div data-controller="phone-fab" class="phone-fab"
     data-action="keydown.esc@document->phone-fab#close turbo:before-visit@document->phone-fab#close">
  <div class="fab-overlay" data-phone-fab-target="overlay"
       data-action="click->phone-fab#close" hidden></div>
  <div class="fab-panel" data-phone-fab-target="panel"
       role="dialog" aria-label="Navigation" hidden>
    <div class="fab-nav-links">
      <%= render 'shared/nav_links' %>
    </div>
    <hr class="fab-divider">
    <div class="fab-icon-buttons">
      <% if current_kitchen %>
        <button type="button" class="nav-icon-btn"
                data-action="phone-fab#openSearch"
                title="Search recipes" aria-label="Search recipes">
          <%= icon(:search, class: 'nav-icon', size: nil) %>
        </button>
      <% end %>
      <% if logged_in? %>
        <button type="button" class="nav-icon-btn"
                data-action="phone-fab#openSettings"
                title="Settings" aria-label="Settings">
          <%= icon(:settings, class: 'nav-icon', size: nil) %>
        </button>
      <% end %>
      <% if content_for?(:help_path) %>
        <a href="<%= help_url(yield(:help_path)) %>" class="nav-icon-btn"
           data-action="phone-fab#closeOnNavigate"
           title="Help" aria-label="Help" target="_blank" rel="noopener noreferrer">
          <%= icon(:help, class: 'nav-icon', size: nil) %>
        </a>
      <% end %>
    </div>
  </div>
  <button type="button" class="fab-button" data-phone-fab-target="button"
          data-action="phone-fab#toggle" aria-label="Menu" aria-expanded="false">
    <svg class="hamburger-icon" viewBox="0 0 24 24" aria-hidden="true">
      <rect class="hamburger-top" x="3" y="11" width="18" height="2" rx="1" fill="currentColor"/>
      <rect class="hamburger-mid" x="3" y="11" width="18" height="2" rx="1" fill="currentColor"/>
      <rect class="hamburger-bot" x="3" y="11" width="18" height="2" rx="1" fill="currentColor"/>
    </svg>
  </button>
</div>
```

- [ ] **Step 2: Add FAB to layout**

In `app/views/layouts/application.html.erb`, add after the closing `</main>` tag and before the notifications div:

```erb
  </main>
  <%= render 'shared/phone_fab' %>
  <div id="notifications"></div>
```

- [ ] **Step 3: Run tests to verify no regression**

Run: `rake test`
Expected: All existing tests pass. The FAB markup is inert without CSS/JS.

- [ ] **Step 4: Commit**

```bash
git add app/views/shared/_phone_fab.html.erb app/views/layouts/application.html.erb
git commit -m "Add phone FAB partial and render in layout

Markup for the bottom-center floating action button. Hidden by default
(CSS phone media query controls visibility). Renders shared _nav_links
partial to prevent drift with top nav."
```

---

### Task 2: Phone FAB CSS

**Files:**
- Modify: `app/assets/stylesheets/navigation.css`

All new CSS goes in `navigation.css`. The phone media query scopes everything to actual phones.

- [ ] **Step 1: Extend hamburger animation selectors for FAB button**

In `navigation.css`, find the three `[aria-expanded="true"]` rules for the hamburger icon animation (around lines 189-199). Add `.fab-button` to each selector:

Before:
```css
.hamburger-btn[aria-expanded="true"] .hamburger-top {
  transform: translateY(0) rotate(45deg);
}

.hamburger-btn[aria-expanded="true"] .hamburger-mid {
  opacity: 0;
}

.hamburger-btn[aria-expanded="true"] .hamburger-bot {
  transform: translateY(0) rotate(-45deg);
}
```

After:
```css
.hamburger-btn[aria-expanded="true"] .hamburger-top,
.fab-button[aria-expanded="true"] .hamburger-top {
  transform: translateY(0) rotate(45deg);
}

.hamburger-btn[aria-expanded="true"] .hamburger-mid,
.fab-button[aria-expanded="true"] .hamburger-mid {
  opacity: 0;
}

.hamburger-btn[aria-expanded="true"] .hamburger-bot,
.fab-button[aria-expanded="true"] .hamburger-bot {
  transform: translateY(0) rotate(-45deg);
}
```

- [ ] **Step 2: Add the phone media query block with FAB structure and visibility**

At the end of `navigation.css` (after the existing dark mode media query), add the phone FAB styles. This is a single large block — add it all at once:

```css
/**********************/
/* Phone FAB          */
/**********************/

.phone-fab {
  display: none;
}

@media (pointer: coarse) and (hover: none) and (max-width: 600px) {
  nav[data-controller="nav-menu"] {
    display: none;
  }

  .phone-fab {
    display: block;
  }

  /* FAB button — fixed circle at bottom center */
  .fab-button {
    position: fixed;
    bottom: calc(0.75rem + env(safe-area-inset-bottom, 0px));
    left: 50%;
    transform: translateX(-50%);
    z-index: 20;
    width: 3rem;
    height: 3rem;
    border-radius: 50%;
    border: none;
    background-color: rgba(250, 248, 245, 0.82);
    backdrop-filter: blur(10px);
    -webkit-backdrop-filter: blur(10px);
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    color: var(--text);
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
    -webkit-tap-highlight-color: transparent;
    transition: color var(--duration-normal) ease;
  }

  .fab-button:focus-visible {
    outline: 2px solid var(--red);
    outline-offset: 2px;
  }

  .fab-button .hamburger-icon {
    width: 1.25rem;
    height: 1.25rem;
  }

  .fab-button[hidden] { display: none; }

  /* Overlay — dim backdrop behind panel */
  .fab-overlay {
    position: fixed;
    inset: 0;
    z-index: 18;
    background: rgba(0, 0, 0, 0.3);
    opacity: 0;
    transition: opacity var(--duration-slow) ease;
  }

  .fab-overlay.fab-open {
    opacity: 1;
  }

  .fab-overlay[hidden] { display: none; }

  /* Panel — frosted glass menu above FAB */
  .fab-panel {
    position: fixed;
    bottom: calc(4rem + env(safe-area-inset-bottom, 0px));
    left: 0;
    right: 0;
    margin: 0 auto;
    width: min(85vw, 18rem);
    z-index: 19;
    border-radius: 0.75rem;
    background-color: rgba(250, 248, 245, 0.82);
    backdrop-filter: blur(10px);
    -webkit-backdrop-filter: blur(10px);
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
    padding: 0.5rem;
    transform: scale(0.3) translateY(20px);
    opacity: 0;
    transform-origin: bottom center;
    transition: transform var(--duration-slow) cubic-bezier(0.16, 0.75, 0.40, 1),
                opacity var(--duration-normal) ease;
  }

  .fab-panel.fab-open {
    transform: scale(1) translateY(0);
    opacity: 1;
  }

  .fab-panel[hidden] { display: none; }

  /* Panel content: nav links stacked vertically */
  .fab-nav-links {
    display: flex;
    flex-direction: column;
  }

  /* Mirrors nav a styles — kept in sync manually (these rarely change) */
  .fab-nav-links a {
    font-family: var(--font-body);
    display: flex;
    align-items: center;
    gap: 0.35rem;
    text-decoration: none;
    font-weight: 600;
    font-size: 0.8rem;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    padding: 0.65rem 0.75rem;
    line-height: 1.5;
    color: var(--text);
    border-radius: 0.4rem;
    transition: color var(--duration-normal) ease,
                background-color var(--duration-slow) ease-out;
  }

  .fab-nav-links a:hover {
    color: var(--red);
    background-color: var(--hover-bg);
  }

  .fab-nav-links a[aria-current="page"] {
    color: var(--red);
    background-color: var(--hover-bg);
  }

  .fab-nav-links .nav-icon {
    width: 1.1rem;
    height: 1.1rem;
    flex-shrink: 0;
  }

  .fab-divider {
    border: none;
    border-top: 1px solid var(--rule);
    margin: 0.3rem 0.5rem;
  }

  /* Icon buttons row at bottom of panel */
  .fab-icon-buttons {
    display: flex;
    justify-content: center;
    gap: 0.5rem;
    padding: 0.25rem 0;
  }

  .fab-icon-buttons .nav-icon-btn {
    padding: 0.6rem 0.75rem;
  }

  /* Stagger fade-in for panel items */
  .fab-panel a,
  .fab-panel .nav-icon-btn {
    opacity: 0;
    transition: opacity 150ms ease,
                color var(--duration-normal) ease,
                background-color var(--duration-slow) ease-out;
    transition-delay: calc(var(--fab-stagger, 0) * 30ms);
  }

  .fab-panel.fab-open a,
  .fab-panel.fab-open .nav-icon-btn {
    opacity: 1;
  }
}

/* Dark mode FAB */
@media (pointer: coarse) and (hover: none) and (max-width: 600px) and (prefers-color-scheme: dark) {
  .fab-button {
    background-color: rgba(30, 27, 24, 0.82);
  }

  .fab-panel {
    background-color: rgba(30, 27, 24, 0.82);
  }
}

/* Reduced motion: zero stagger delays (global rule handles transition-duration) */
@media (pointer: coarse) and (hover: none) and (max-width: 600px) and (prefers-reduced-motion: reduce) {
  .fab-panel a,
  .fab-panel .nav-icon-btn {
    transition-delay: 0ms !important;
  }
}
```

- [ ] **Step 3: Verify CSS syntax**

Run: `rake lint`
Expected: 0 offenses (CSS isn't linted by RuboCop, but ensures no Ruby regressions).

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/navigation.css
git commit -m "Add phone FAB CSS: visibility, layout, genie animation

Phone media query (pointer: coarse + hover: none + max-width: 600px)
hides top nav and shows the FAB. Panel uses scale+translate origin
animation. Stagger fade-in via --fab-stagger custom property. Dark
mode and reduced-motion support included."
```

---

### Task 3: CSS adjustments for missing top nav

**Files:**
- Modify: `app/assets/stylesheets/base.css`

- [ ] **Step 1: Add phone media query for scroll-margin, gingham spacing, and FAB clearance**

In `base.css`, find the `/* small mobiles only */` comment (around line 1273). Add the phone FAB adjustments as a new query AFTER the existing `@media screen and (max-width: 720px)` block (which ends around line 1316):

```css
/* Phone FAB adjustments — no sticky nav to clear, need FAB clearance */
@media (pointer: coarse) and (hover: none) and (max-width: 600px) {
  main {
    padding-top: 2rem;
  }

  #recipe-listings,
  [data-recipe-filter-target="category"] {
    scroll-margin-top: 0.5rem;
  }

  body {
    padding-bottom: calc(4rem + env(safe-area-inset-bottom, 0px));
  }
}
```

- [ ] **Step 2: Run tests**

Run: `rake test`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/base.css
git commit -m "Adjust scroll-margin, gingham spacing, and bottom padding for phone FAB

Reduce scroll-margin-top (no sticky nav to clear), add top padding to
main (keep gingham visible), add body bottom padding for FAB clearance."
```

---

### Task 4: Phone FAB Stimulus controller

**Files:**
- Create: `app/javascript/controllers/phone_fab_controller.js`
- Modify: `app/javascript/application.js`

- [ ] **Step 1: Create `phone_fab_controller.js`**

```javascript
import { Controller } from "@hotwired/stimulus"

/**
 * Phone FAB — bottom-center floating action button for phone-sized screens.
 * Manages the panel open/close lifecycle, genie animation with staggered
 * item reveals, and cross-controller dispatch for search/settings.
 *
 * - Collaborators: _phone_fab.html.erb, navigation.css (.phone-fab),
 *   search_overlay_controller (dispatched via openSearch),
 *   editor_controller (settings button clicked programmatically)
 * - CSS phone media query controls visibility — this controller is inert
 *   on non-phone screens even though it connects to the DOM.
 * - Closes on: Escape, overlay click, Turbo navigation, orientation change
 */
export default class extends Controller {
  static targets = ["button", "panel", "overlay"]

  connect() {
    this.phoneQuery = window.matchMedia(
      "(pointer: coarse) and (hover: none) and (max-width: 600px)"
    )
    this.boundMediaChange = this.handleMediaChange.bind(this)
    this.phoneQuery.addEventListener("change", this.boundMediaChange)
  }

  disconnect() {
    this.phoneQuery.removeEventListener("change", this.boundMediaChange)
    clearTimeout(this.closeTimer)
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.overlayTarget.hidden = false
    this.panelTarget.hidden = false

    this.setStaggerDelays()

    requestAnimationFrame(() => {
      this.panelTarget.classList.add("fab-open")
      this.overlayTarget.classList.add("fab-open")
    })

    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.trapFocusListener = this.trapFocus.bind(this)
    this.element.addEventListener("keydown", this.trapFocusListener)

    this.firstFocusable?.focus()
  }

  close() {
    if (!this.isOpen) return

    this.resetStaggerDelays()
    this.panelTarget.classList.remove("fab-open")
    this.overlayTarget.classList.remove("fab-open")
    this.buttonTarget.setAttribute("aria-expanded", "false")

    this.element.removeEventListener("keydown", this.trapFocusListener)

    const cleanup = () => {
      clearTimeout(this.closeTimer)
      this.panelTarget.hidden = true
      this.overlayTarget.hidden = true
    }

    this.panelTarget.addEventListener("transitionend", (e) => {
      if (e.propertyName === "transform" || e.propertyName === "opacity") cleanup()
    }, { once: true })

    this.closeTimer = setTimeout(cleanup, 400)
    this.buttonTarget.focus()
  }

  instantClose() {
    if (!this.isOpen) return

    clearTimeout(this.closeTimer)
    this.panelTarget.classList.remove("fab-open")
    this.overlayTarget.classList.remove("fab-open")
    this.panelTarget.hidden = true
    this.overlayTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.element.removeEventListener("keydown", this.trapFocusListener)
  }

  openSearch() {
    this.instantClose()
    const overlay = this.application.getControllerForElementAndIdentifier(
      document.body, "search-overlay"
    )
    if (overlay) overlay.open()
  }

  openSettings() {
    this.instantClose()
    document.getElementById("settings-button")?.click()
  }

  closeOnNavigate() {
    this.instantClose()
  }

  // -- Private --

  get isOpen() {
    return this.buttonTarget.getAttribute("aria-expanded") === "true"
  }

  get focusableItems() {
    return [
      ...this.panelTarget.querySelectorAll("a:not([hidden]), button:not([hidden])"),
      this.buttonTarget
    ]
  }

  get firstFocusable() {
    return this.panelTarget.querySelector("a, button")
  }

  setStaggerDelays() {
    const items = this.panelTarget.querySelectorAll("a, .nav-icon-btn")
    items.forEach((el, i) => el.style.setProperty("--fab-stagger", i))
  }

  resetStaggerDelays() {
    const items = this.panelTarget.querySelectorAll("a, .nav-icon-btn")
    items.forEach(el => el.style.setProperty("--fab-stagger", "0"))
  }

  trapFocus(event) {
    if (event.key !== "Tab") return

    const items = this.focusableItems
    if (items.length === 0) return

    const first = items[0]
    const last = items[items.length - 1]

    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  handleMediaChange() {
    if (!this.phoneQuery.matches) this.instantClose()
  }
}
```

- [ ] **Step 2: Register controller in `application.js`**

In `app/javascript/application.js`, add the import alongside the other controllers (alphabetically after NavMenuController):

```javascript
import PhoneFabController from "./controllers/phone_fab_controller"
```

And the registration alongside the others:

```javascript
application.register("phone-fab", PhoneFabController)
```

- [ ] **Step 3: Build JavaScript**

Run: `npm run build`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Run full test suite**

Run: `rake test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/phone_fab_controller.js app/javascript/application.js
git commit -m "Add phone FAB Stimulus controller

Manages open/close lifecycle with genie animation, staggered item
reveals, focus trap, and cross-controller dispatch for search/settings.
Handles Escape, overlay click, Turbo navigation, and orientation change."
```

---

### Task 5: Integration tests

**Files:**
- Create: `test/integration/phone_fab_test.rb`

- [ ] **Step 1: Write integration tests**

```ruby
# frozen_string_literal: true

require 'test_helper'

class PhoneFabTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'phone FAB renders on homepage' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.phone-fab' do
      assert_select '.fab-button[aria-label="Menu"]'
      assert_select '.fab-panel[role="dialog"]'
      assert_select '.fab-overlay'
    end
  end

  test 'phone FAB panel contains nav links matching top nav' do
    log_in
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.fab-nav-links' do
      assert_select 'a.recipes'
      assert_select 'a.ingredients'
      assert_select 'a.menu'
      assert_select 'a.groceries'
    end
  end

  test 'phone FAB panel contains icon buttons' do
    log_in
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.fab-icon-buttons' do
      assert_select 'button[aria-label="Search recipes"]'
      assert_select 'button[aria-label="Settings"]'
    end
  end

  test 'phone FAB button starts closed' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.fab-button[aria-expanded="false"]'
    assert_select '.fab-panel[hidden]'
    assert_select '.fab-overlay[hidden]'
  end

  test 'top nav still renders alongside FAB' do
    log_in
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav[data-controller="nav-menu"]'
    assert_select '.phone-fab'
  end

  test 'phone FAB renders on recipe page' do
    recipe = ActsAsTenant.with_tenant(@kitchen) do
      Category.create!(name: 'Mains', kitchen: @kitchen)
              .recipes.create!(title: 'Test Recipe', kitchen: @kitchen)
    end

    get recipe_path(recipe, kitchen_slug: kitchen_slug)

    assert_select '.phone-fab .fab-button'
  end

  test 'phone FAB omits settings button when logged out' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.fab-icon-buttons button[aria-label="Settings"]', count: 0
  end
end
```

- [ ] **Step 2: Run tests**

Run: `ruby -Itest test/integration/phone_fab_test.rb`
Expected: All 7 tests pass.

- [ ] **Step 3: Run full suite**

Run: `rake`
Expected: 0 RuboCop offenses, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/integration/phone_fab_test.rb
git commit -m "Add integration tests for phone FAB menu

Verify FAB renders on homepage and recipe pages, contains nav links
and icon buttons, starts in closed state, coexists with top nav,
and respects login state for settings button."
```

---

### Task 6: Final verification and build

- [ ] **Step 1: Full lint and test**

Run: `rake`
Expected: 0 RuboCop offenses, all tests pass.

- [ ] **Step 2: Build JS**

Run: `npm run build`
Expected: Clean build, no warnings.

- [ ] **Step 3: Verify `html_safe` allowlist is current**

Run: `rake lint:html_safe`
Expected: No violations (no new `.html_safe` or `raw()` calls).

- [ ] **Step 4: Manual testing checklist**

Start the dev server (`bin/dev`) and test on a phone or using Chrome DevTools device emulation with **touch simulation enabled** (important — the `pointer: coarse` / `hover: none` queries require actual touch emulation, not just a narrow viewport):

1. Top nav is hidden on phone, visible on desktop
2. FAB circle visible at bottom center on phone
3. Tap FAB → hamburger animates to X, panel expands with genie animation, items stagger in
4. Tap FAB again → reverse animation, panel shrinks back
5. Tap overlay → menu closes
6. Tap a nav link → navigates to page, menu closes
7. Tap search → menu instantly closes, search overlay opens
8. Tap settings → menu instantly closes, settings dialog opens
9. Press Escape → menu closes
10. Rotate to landscape → menu closes, top nav appears
11. Dark mode: frosted glass has correct dark tones
12. Active page link highlighted (red) in FAB panel
13. Gingham visible above content (not abrupt start)
14. Back-to-top links scroll to correct position (no overshoot)
15. Content scrollable past FAB (bottom padding working)
