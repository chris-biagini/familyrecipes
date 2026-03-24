# ActionCable Sync DRY Extraction — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Extract shared ActionCable sync logic from `menu_controller.js` and `grocery_sync_controller.js` into a standalone `MealPlanSync` utility class.

**Architecture:** A new `MealPlanSync` class in `app/javascript/utilities/meal_plan_sync.js` owns the transport layer (ActionCable subscription, version-based polling, heartbeat, localStorage cache, offline queue, Turbo Stream interception). Controllers create an instance and pass an `onStateUpdate` callback for UI work. `sendAction` accepts an explicit HTTP method parameter (defaults to `PATCH`). Both controllers gain offline queue support.

**Tech Stack:** Vanilla ES modules, ActionCable, Stimulus, importmap-rails (no build step)

**Design doc:** `docs/plans/2026-02-28-actioncable-sync-dry-design.md`

---

### Task 1: Create `MealPlanSync` utility class

**Files:**
- Create: `app/javascript/utilities/meal_plan_sync.js`

**Step 1: Create the utility file with full implementation**

```js
import { createConsumer } from "@rails/actioncable"
import { getCsrfToken } from "utilities/editor_utils"
import { show as notifyShow } from "utilities/notify"

export default class MealPlanSync {
  constructor({ slug, stateUrl, cachePrefix, onStateUpdate, remoteUpdateMessage }) {
    this.stateUrl = stateUrl
    this.cachePrefix = cachePrefix
    this.onStateUpdate = onStateUpdate
    this.remoteUpdateMessage = remoteUpdateMessage

    this.storageKey = `${cachePrefix}-${slug}`
    this.pendingKey = `${cachePrefix}-pending-${slug}`
    this.version = 0
    this.state = {}
    this.pending = []
    this.awaitingOwnAction = false
    this.initialFetch = true

    this.loadCache()
    this.loadPending()

    if (this.state && Object.keys(this.state).length > 0) {
      this.onStateUpdate(this.state)
    }

    this.fetchState()
    this.subscribe(slug)
    this.startHeartbeat()
    this.flushPending()

    this.boundHandleStreamRender = this.handleStreamRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this.boundHandleStreamRender)
  }

  disconnect() {
    if (this.fetchController) this.fetchController.abort()
    if (this.heartbeatId) {
      clearInterval(this.heartbeatId)
      this.heartbeatId = null
    }
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    if (this.consumer) {
      this.consumer.disconnect()
      this.consumer = null
    }
    if (this.boundHandleStreamRender) {
      document.removeEventListener("turbo:before-stream-render", this.boundHandleStreamRender)
    }
  }

  sendAction(url, params, method = "PATCH") {
    this.awaitingOwnAction = true

    return fetch(url, {
      method,
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": getCsrfToken() || ""
      },
      body: JSON.stringify(params)
    })
      .then(response => {
        if (!response.ok) {
          const err = new Error("action failed")
          err.status = response.status
          throw err
        }
        return response.json()
      })
      .then(() => {
        this.fetchState()
      })
      .catch(err => {
        this.awaitingOwnAction = false
        if (!err.status) {
          this.pending.push({ url, params, method })
          this.savePending()
        }
      })
  }

  // --- private ---

  fetchState() {
    if (this.fetchController) this.fetchController.abort()
    this.fetchController = new AbortController()

    fetch(this.stateUrl, {
      headers: { "Accept": "application/json" },
      signal: this.fetchController.signal
    })
      .then(response => {
        if (!response.ok) throw new Error("fetch failed")
        return response.json()
      })
      .then(data => {
        if (data.version >= this.version) {
          const isRemoteUpdate = data.version > this.version
            && this.version > 0
            && !this.awaitingOwnAction
            && !this.initialFetch
          this.awaitingOwnAction = false
          this.initialFetch = false
          this.version = data.version
          this.state = data
          this.saveCache()
          this.onStateUpdate(data)
          if (isRemoteUpdate) {
            notifyShow(this.remoteUpdateMessage)
          }
        }
      })
      .catch(() => {})
  }

  fetchStateWithNotification() {
    if (this.fetchController) this.fetchController.abort()
    this.fetchController = new AbortController()

    fetch(this.stateUrl, {
      headers: { "Accept": "application/json" },
      signal: this.fetchController.signal
    })
      .then(response => {
        if (!response.ok) throw new Error("fetch failed")
        return response.json()
      })
      .then(data => {
        this.version = data.version
        this.state = data
        this.saveCache()
        this.onStateUpdate(data)
        notifyShow(this.remoteUpdateMessage)
      })
      .catch(() => {})
  }

  subscribe(slug) {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "MealPlanChannel", kitchen_slug: slug },
      {
        received: (data) => {
          if (data.type === 'content_changed') {
            this.fetchStateWithNotification()
            return
          }
          if (data.version && data.version > this.version && !this.awaitingOwnAction) {
            this.fetchState()
          }
        },
        connected: () => {
          this.flushPending()
        }
      }
    )
  }

  startHeartbeat() {
    this.heartbeatId = setInterval(() => this.fetchState(), 30000)
  }

  flushPending() {
    if (this.pending.length === 0) return

    const queue = this.pending.slice()
    this.pending = []
    this.savePending()

    queue.forEach(entry => {
      this.sendAction(entry.url, entry.params, entry.method)
    })
  }

  handleStreamRender(event) {
    const originalRender = event.detail.render
    event.detail.render = async (streamElement) => {
      await originalRender(streamElement)
      if (this.state && Object.keys(this.state).length > 0) {
        this.onStateUpdate(this.state)
      }
    }
  }

  saveCache() {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify({
        version: this.version,
        state: this.state
      }))
    } catch { /* localStorage full or unavailable */ }
  }

  loadCache() {
    try {
      const raw = localStorage.getItem(this.storageKey)
      if (!raw) return
      const cached = JSON.parse(raw)
      if (cached && cached.version) {
        this.version = cached.version
        this.state = cached.state || {}
      }
    } catch { /* corrupted cache */ }
  }

  savePending() {
    try {
      if (this.pending.length > 0) {
        localStorage.setItem(this.pendingKey, JSON.stringify(this.pending))
      } else {
        localStorage.removeItem(this.pendingKey)
      }
    } catch { /* localStorage full or unavailable */ }
  }

  loadPending() {
    try {
      const raw = localStorage.getItem(this.pendingKey)
      if (raw) {
        this.pending = JSON.parse(raw) || []
      }
    } catch {
      this.pending = []
    }
  }
}
```

**Step 2: Verify the file is picked up by importmap**

No config change needed — `pin_all_from 'app/javascript/utilities'` in `config/importmap.rb` already covers all files in that directory.

**Step 3: Commit**

```bash
git add app/javascript/utilities/meal_plan_sync.js
git commit -m "feat: add MealPlanSync utility class (#116)"
```

---

### Task 2: Rewrite `grocery_sync_controller.js` to use `MealPlanSync`

**Files:**
- Modify: `app/javascript/controllers/grocery_sync_controller.js` (full rewrite — 245 lines → ~30)

**Step 1: Replace the entire file**

```js
import { Controller } from "@hotwired/stimulus"
import MealPlanSync from "utilities/meal_plan_sync"

export default class extends Controller {
  connect() {
    const slug = this.element.dataset.kitchenSlug

    this.urls = {
      check: this.element.dataset.checkUrl,
      customItems: this.element.dataset.customItemsUrl
    }

    this.sync = new MealPlanSync({
      slug,
      stateUrl: this.element.dataset.stateUrl,
      cachePrefix: "grocery-state",
      onStateUpdate: (data) => this.applyStateToUI(data),
      remoteUpdateMessage: "Shopping list updated."
    })
  }

  disconnect() {
    if (this.sync) this.sync.disconnect()
  }

  get uiController() {
    return this.application.getControllerForElementAndIdentifier(this.element, "grocery-ui")
  }

  applyStateToUI(state) {
    const ui = this.uiController
    if (ui) ui.applyState(state)
  }

  sendAction(url, params) {
    return this.sync.sendAction(url, params)
  }
}
```

Note: `sendAction` is still exposed because `grocery_ui_controller.js` calls `this.syncController.sendAction(...)` directly. The thin wrapper delegates to the utility.

**Step 2: Run the existing test suite**

```bash
rake test
```

Expected: All tests pass. No Ruby changes, but controller tests exercise the server endpoints that these JS controllers hit.

**Step 3: Commit**

```bash
git add app/javascript/controllers/grocery_sync_controller.js
git commit -m "refactor: rewrite grocery_sync_controller to use MealPlanSync (#116)"
```

---

### Task 3: Rewrite `menu_controller.js` to use `MealPlanSync`

**Files:**
- Modify: `app/javascript/controllers/menu_controller.js` (352 lines → ~200)

**Step 1: Replace the file contents**

The controller keeps all UI methods (`syncCheckboxes`, `syncAvailability`, `showPopover`, `hidePopover`, `bindRecipeCheckboxes`, `selectAll`, `clear`) and replaces the transport layer with `MealPlanSync`.

```js
import { Controller } from "@hotwired/stimulus"
import MealPlanSync from "utilities/meal_plan_sync"

export default class extends Controller {
  connect() {
    const slug = this.element.dataset.kitchenSlug

    this.urls = {
      select: this.element.dataset.selectUrl,
      selectAll: this.element.dataset.selectAllUrl,
      clear: this.element.dataset.clearUrl
    }

    this.sync = new MealPlanSync({
      slug,
      stateUrl: this.element.dataset.stateUrl,
      cachePrefix: "menu-state",
      onStateUpdate: (data) => {
        this.syncCheckboxes(data)
        this.syncAvailability(data)
      },
      remoteUpdateMessage: "Menu updated."
    })

    this.bindRecipeCheckboxes()

    this.element.addEventListener('click', (e) => {
      const dot = e.target.closest('.availability-dot')
      if (dot) {
        e.preventDefault()
        e.stopPropagation()
        this.showPopover(dot)
      }
    })
  }

  disconnect() {
    this.hidePopover()
    if (this.sync) this.sync.disconnect()
  }

  syncCheckboxes(state) {
    this.element.classList.remove("hidden-until-js")

    const selectedRecipes = state.selected_recipes || []
    const selectedQuickBites = state.selected_quick_bites || []

    this.element.querySelectorAll('#recipe-selector input[type="checkbox"]').forEach(cb => {
      const slug = cb.dataset.slug
      const typeEl = cb.closest("[data-type]")
      if (!typeEl || !slug) return

      if (typeEl.dataset.type === "quick_bite") {
        cb.checked = selectedQuickBites.indexOf(slug) !== -1
      } else {
        cb.checked = selectedRecipes.indexOf(slug) !== -1
      }
    })
  }

  syncAvailability(state) {
    const availability = state.availability || {}

    this.element.querySelectorAll('#recipe-selector input[type="checkbox"]').forEach(cb => {
      const slug = cb.dataset.slug
      if (!slug) return

      const li = cb.closest('li')
      if (!li) return

      let dot = li.querySelector('.availability-dot')
      const info = availability[slug]

      if (!info) {
        if (dot) dot.remove()
        return
      }

      if (!dot) {
        dot = document.createElement('span')
        dot.className = 'availability-dot'
        dot.dataset.slug = slug
        cb.after(dot)
      }

      const missing = info.missing
      const isQuickBite = cb.closest('[data-type="quick_bite"]')
      dot.dataset.missing = isQuickBite
        ? (missing === 0 ? '0' : '3+')
        : (missing > 2 ? '3+' : String(missing))

      const label = missing === 0
        ? 'All ingredients on hand'
        : `Missing ${missing}: ${info.missing_names.join(', ')}`
      dot.setAttribute('aria-label', label)
    })
  }

  showPopover(dot) {
    const slug = dot.dataset.slug
    const state = this.sync.state
    const info = (state.availability || {})[slug]
    if (!info) return

    let popover = document.getElementById('ingredient-popover')
    if (!popover) {
      popover = document.createElement('div')
      popover.id = 'ingredient-popover'
      popover.setAttribute('role', 'tooltip')
      document.body.appendChild(popover)
    }

    if (this.activePopoverDot === dot) {
      this.hidePopover()
      return
    }

    popover.textContent = ''

    const ingredientsList = document.createElement('p')
    ingredientsList.className = 'popover-ingredients'
    ingredientsList.textContent = info.ingredients.join(', ')
    popover.appendChild(ingredientsList)

    if (info.missing_names.length > 0) {
      const missingEl = document.createElement('p')
      missingEl.className = 'popover-missing'
      missingEl.textContent = `Missing: ${info.missing_names.join(', ')}`
      popover.appendChild(missingEl)
    }

    popover.classList.add('visible')

    const rect = dot.getBoundingClientRect()
    popover.style.top = ''
    popover.style.left = ''

    const popoverRect = popover.getBoundingClientRect()
    let top = rect.bottom + 6
    let left = rect.left

    if (top + popoverRect.height > window.innerHeight) {
      top = rect.top - popoverRect.height - 6
    }
    if (left + popoverRect.width > window.innerWidth) {
      left = window.innerWidth - popoverRect.width - 8
    }
    if (left < 8) left = 8

    popover.style.top = (top + window.scrollY) + 'px'
    popover.style.left = (left + window.scrollX) + 'px'

    this.activePopoverDot = dot
    dot.setAttribute('aria-expanded', 'true')
    dot.setAttribute('aria-describedby', 'ingredient-popover')

    setTimeout(() => {
      this.boundHideOnClickOutside = (e) => {
        if (!popover.contains(e.target) && e.target !== dot) {
          this.hidePopover()
        }
      }
      this.boundHideOnEscape = (e) => {
        if (e.key === 'Escape') {
          this.hidePopover()
          dot.focus()
        }
      }
      document.addEventListener('click', this.boundHideOnClickOutside)
      document.addEventListener('keydown', this.boundHideOnEscape)
    }, 0)
  }

  hidePopover() {
    const popover = document.getElementById('ingredient-popover')
    if (popover) popover.classList.remove('visible')

    if (this.activePopoverDot) {
      this.activePopoverDot.setAttribute('aria-expanded', 'false')
      this.activePopoverDot.removeAttribute('aria-describedby')
      this.activePopoverDot = null
    }

    if (this.boundHideOnClickOutside) {
      document.removeEventListener('click', this.boundHideOnClickOutside)
      this.boundHideOnClickOutside = null
    }
    if (this.boundHideOnEscape) {
      document.removeEventListener('keydown', this.boundHideOnEscape)
      this.boundHideOnEscape = null
    }
  }

  bindRecipeCheckboxes() {
    this.element.addEventListener("change", (e) => {
      const cb = e.target.closest('#recipe-selector input[type="checkbox"]')
      if (!cb) return

      const slug = cb.dataset.slug
      const typeEl = cb.closest("[data-type]")
      const type = typeEl ? typeEl.dataset.type : "recipe"

      this.sync.sendAction(this.urls.select, { type, slug, selected: cb.checked })
    })
  }

  selectAll() {
    this.sync.sendAction(this.urls.selectAll, {})
  }

  clear() {
    this.sync.sendAction(this.urls.clear, {}, "DELETE")
  }
}
```

Key changes:
- `this.state` references in `showPopover` become `this.sync.state` (the utility exposes state as a public property)
- `sendAction` calls delegate to `this.sync.sendAction` with explicit method
- `clear()` now passes `"DELETE"` as the third argument instead of deriving from URL comparison
- Menu now gains offline queue support via the shared utility

**Step 2: Run the test suite**

```bash
rake test
```

Expected: All tests pass.

**Step 3: Commit**

```bash
git add app/javascript/controllers/menu_controller.js
git commit -m "refactor: rewrite menu_controller to use MealPlanSync (#116)"
```

---

### Task 4: Manual smoke test and final commit

**Step 1: Start the dev server**

```bash
bin/dev
```

**Step 2: Smoke test the menu page**

Open the menu page in two browser tabs. In tab 1:
- Select/deselect recipes — verify checkboxes toggle
- Click "Select All" — verify all recipes check
- Click "Clear" — verify all recipes uncheck
- Verify tab 2 reflects changes (toast notification appears)
- Check that availability dots still render and popovers work

**Step 3: Smoke test the groceries page**

Open the groceries page in two browser tabs. In tab 1:
- Check off items — verify checkbox persists on page reload (localStorage cache)
- Add a custom item — verify it appears
- Remove a custom item — verify it disappears
- Verify tab 2 reflects changes (toast notification appears)

**Step 4: Verify `content_changed` behavior**

Both menu and groceries should show notification toasts when underlying content changes (recipe CRUD, quick bite edits). This is now unified — both use `fetchStateWithNotification` from the utility.

**Step 5: Run lint + tests one final time**

```bash
rake
```

Expected: 0 RuboCop offenses, all tests pass.

**Step 6: Squash or final commit closing the issue**

If all three prior commits are clean, no additional commit needed. The final commit message in Task 3 can be amended to include `Closes #116` if desired, or add a closing commit:

```bash
git commit --allow-empty -m "closes #116"
```
