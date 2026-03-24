# Recipe Search Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add a Spotlight-style search overlay for finding recipes by title, description, category, or ingredients.

**Architecture:** Client-side search over a JSON blob embedded in the layout. A `SearchDataHelper` builds the data, a `<dialog>` partial renders the overlay, and a `search_overlay_controller` Stimulus controller handles all interaction. No server-side search endpoint.

**Tech Stack:** Rails helper, ERB partial, Stimulus controller, CSS in `style.css`.

---

### Task 1: SearchDataHelper — build the JSON blob

**Files:**
- Create: `app/helpers/search_data_helper.rb`
- Test: `test/helpers/search_data_helper_test.rb`

**Step 1: Write the failing test**

```ruby
# test/helpers/search_data_helper_test.rb
# frozen_string_literal: true

require 'test_helper'

class SearchDataHelperTest < ActionView::TestCase
  setup do
    setup_test_kitchen
    setup_test_category(name: 'Baking')
  end

  test 'search_data_json returns JSON array of recipe objects' do
    markdown = "# Pancakes\n\nFluffy buttermilk pancakes.\n\n## Step 1\n\n- flour, 2 cups:\n- buttermilk, 1 cup:\n"
    MarkdownImporter.import(source: markdown, kitchen: @kitchen)

    data = JSON.parse(search_data_json)

    assert_equal 1, data.size
    entry = data.first
    assert_equal 'Pancakes', entry['title']
    assert_equal 'pancakes', entry['slug']
    assert_equal 'Fluffy buttermilk pancakes.', entry['description']
    assert_equal 'Baking', entry['category']
    assert_includes entry['ingredients'], 'flour'
    assert_includes entry['ingredients'], 'buttermilk'
  end

  test 'search_data_json deduplicates ingredients across steps' do
    markdown = "# Eggs\n\nSimple.\n\n## Step 1\n\n- eggs, 2:\n\n## Step 2\n\n- eggs, 1:\n"
    MarkdownImporter.import(source: markdown, kitchen: @kitchen)

    data = JSON.parse(search_data_json)
    assert_equal ['eggs'], data.first['ingredients']
  end

  test 'search_data_json returns empty array when no recipes' do
    assert_equal '[]', search_data_json
  end

  test 'search_data_json escapes HTML in titles' do
    markdown = "# Eggs & Toast\n\nSimple.\n\n## Step 1\n\n- eggs, 2:\n"
    MarkdownImporter.import(source: markdown, kitchen: @kitchen)

    json = search_data_json
    refute_includes json, '<'
    data = JSON.parse(json)
    assert_equal 'Eggs & Toast', data.first['title']
  end

  private

  def current_kitchen = @kitchen
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/helpers/search_data_helper_test.rb`
Expected: FAIL — `search_data_json` undefined.

**Step 3: Write the helper**

```ruby
# app/helpers/search_data_helper.rb
# frozen_string_literal: true

# Builds a JSON blob of searchable recipe data for the client-side search
# overlay. Rendered once per page in the application layout. The blob is small
# (well under 10KB even at 100 recipes) because it carries only the fields
# the search overlay needs: title, slug, description, category, ingredients.
#
# Collaborators:
# - ApplicationController (current_kitchen provides tenant scope)
# - search_overlay_controller.js (consumes the JSON in the browser)
module SearchDataHelper
  def search_data_json
    recipes = current_kitchen.recipes.includes(:category, :ingredients).alphabetical

    recipes.map { |recipe| search_entry_for(recipe) }.to_json
  end

  private

  def search_entry_for(recipe)
    {
      title: recipe.title,
      slug: recipe.slug,
      description: recipe.description.to_s,
      category: recipe.category.name,
      ingredients: recipe.ingredients.map(&:name).uniq
    }
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/helpers/search_data_helper_test.rb`
Expected: PASS

**Step 5: Lint**

Run: `bundle exec rubocop app/helpers/search_data_helper.rb test/helpers/search_data_helper_test.rb`

**Step 6: Commit**

```bash
git add app/helpers/search_data_helper.rb test/helpers/search_data_helper_test.rb
git commit -m "feat: SearchDataHelper builds JSON blob for client-side recipe search"
```

---

### Task 2: Search overlay partial and layout integration

**Files:**
- Create: `app/views/shared/_search_overlay.html.erb`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/views/shared/_nav.html.erb`
- Modify: `config/html_safe_allowlist.yml`

**Step 1: Create the search overlay partial**

The dialog uses `showModal()` for focus trapping. The Stimulus controller
will handle opening it. JSON inside `<script type="application/json">` is
safe — the JSON encoder escapes `</` sequences.

```erb
<%# app/views/shared/_search_overlay.html.erb %>
<% if current_kitchen %>
  <script type="application/json" data-search-overlay-target="data"><%= search_data_json.html_safe %></script>
  <dialog class="search-overlay" data-search-overlay-target="dialog" data-action="click->search-overlay#backdropClick">
    <div class="search-panel">
      <div class="search-input-wrap">
        <svg class="search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <circle cx="11" cy="11" r="8"/>
          <line x1="21" y1="21" x2="16.65" y2="16.65"/>
        </svg>
        <input type="text"
               class="search-input"
               placeholder="Search recipes…"
               autocomplete="off"
               spellcheck="false"
               data-search-overlay-target="input"
               data-action="input->search-overlay#search keydown->search-overlay#keydown">
      </div>
      <ul class="search-results" data-search-overlay-target="results" role="listbox"></ul>
    </div>
  </dialog>
<% end %>
```

Note: add the `.html_safe` call to `config/html_safe_allowlist.yml` after
determining the exact line number.

**Step 2: Add the overlay to the application layout**

In `app/views/layouts/application.html.erb`, add the Stimulus controller to
`<body>` and render the partial.

Change:
```erb
<body <%= yield :body_attrs %>>
```
To:
```erb
<body data-controller="search-overlay"
      data-search-overlay-base-path="<%= params[:kitchen_slug] ? "/kitchens/#{params[:kitchen_slug]}" : '' %>"
      <%= yield :body_attrs %>>
```

And before `</body>`:
```erb
  <%= render 'shared/search_overlay' %>
```

**Step 3: Add the search trigger button to the nav**

In `app/views/shared/_nav.html.erb`, add a search button before the
`<% if logged_in? %>` settings block:

```erb
  <% if current_kitchen %>
    <button type="button" class="nav-search-btn"
            data-action="search-overlay#open"
            title="Search recipes (press /)"
            aria-label="Search recipes">
      <svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <circle cx="11" cy="11" r="8"/>
        <line x1="21" y1="21" x2="16.65" y2="16.65"/>
      </svg>
    </button>
  <% end %>
```

**Step 4: Update html_safe_allowlist.yml**

After creating the partial, check the line number of the `.html_safe` call
and add it to `config/html_safe_allowlist.yml`.

**Step 5: Commit**

```bash
git add app/views/shared/_search_overlay.html.erb app/views/layouts/application.html.erb app/views/shared/_nav.html.erb config/html_safe_allowlist.yml
git commit -m "feat: search overlay partial and layout integration"
```

---

### Task 3: Stimulus controller — search_overlay_controller.js

**Files:**
- Create: `app/javascript/controllers/search_overlay_controller.js`

**Step 1: Write the controller**

All DOM construction uses `createElement`/`textContent` — no `innerHTML`
with user content (strict CSP). The one use of `textContent = ""` on the
results list is for clearing (safe, empty string). Use `replaceChildren()`
instead for clarity.

```javascript
// app/javascript/controllers/search_overlay_controller.js
import { Controller } from "@hotwired/stimulus"

/**
 * Spotlight-style recipe search overlay. Opens on "/" keypress or nav button
 * click, searches a pre-embedded JSON blob client-side, and navigates to the
 * selected recipe on Enter/click. All DOM construction uses createElement/
 * textContent (no innerHTML) for CSP compliance.
 *
 * Collaborators:
 * - SearchDataHelper (server-side, provides the JSON data blob)
 * - shared/_search_overlay.html.erb (dialog markup and data script tag)
 * - application.js (turbo:before-cache closes open dialogs)
 */
export default class extends Controller {
  static targets = ["dialog", "input", "results", "data"]

  connect() {
    this.recipes = this.hasDataTarget
      ? JSON.parse(this.dataTarget.textContent || "[]")
      : []
    this.selectedIndex = -1
    this.boundKeydown = this.globalKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  open() {
    if (!this.hasDialogTarget || this.dialogTarget.open) return
    this.dialogTarget.showModal()
    this.inputTarget.value = ""
    this.clearResults()
    this.inputTarget.focus()
  }

  close() {
    this.dialogTarget.close()
  }

  backdropClick(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  search() {
    const query = this.inputTarget.value.trim().toLowerCase()
    if (query.length < 2) {
      this.clearResults()
      return
    }

    const matches = this.rankResults(query)
    this.selectedIndex = -1
    this.renderResults(matches)
  }

  keydown(event) {
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.moveSelection(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.moveSelection(-1)
        break
      case "Enter":
        event.preventDefault()
        this.selectCurrent()
        break
    }
  }

  // Private

  globalKeydown(event) {
    if (event.key !== "/") return
    if (this.hasDialogTarget && this.dialogTarget.open) return
    if (this.insideInput(event.target)) return
    if (document.querySelector("dialog[open]")) return

    event.preventDefault()
    this.open()
  }

  insideInput(element) {
    const tag = element.tagName
    return tag === "INPUT" || tag === "TEXTAREA" || element.isContentEditable
  }

  rankResults(query) {
    const scored = []

    for (const recipe of this.recipes) {
      const tier = this.matchTier(recipe, query)
      if (tier < 4) scored.push({ recipe, tier })
    }

    scored.sort((a, b) => {
      if (a.tier !== b.tier) return a.tier - b.tier
      return a.recipe.title.localeCompare(b.recipe.title)
    })

    return scored.map(s => s.recipe)
  }

  matchTier(recipe, query) {
    if (recipe.title.toLowerCase().includes(query)) return 0
    if (recipe.description.toLowerCase().includes(query)) return 1
    if (recipe.category.toLowerCase().includes(query)) return 2
    if (recipe.ingredients.some(i => i.toLowerCase().includes(query))) return 3
    return 4
  }

  renderResults(recipes) {
    this.clearResults()
    const list = this.resultsTarget

    if (recipes.length === 0) {
      const li = document.createElement("li")
      li.className = "search-no-results"
      li.textContent = "No matches"
      li.setAttribute("role", "option")
      list.appendChild(li)
      return
    }

    recipes.forEach((recipe, index) => {
      const li = document.createElement("li")
      li.className = "search-result"
      li.setAttribute("role", "option")
      li.dataset.index = index
      li.dataset.slug = recipe.slug

      const title = document.createElement("span")
      title.className = "search-result-title"
      title.textContent = recipe.title

      const category = document.createElement("span")
      category.className = "search-result-category"
      category.textContent = recipe.category

      li.appendChild(title)
      li.appendChild(category)
      li.addEventListener("click", () => this.navigateTo(recipe.slug))
      list.appendChild(li)
    })
  }

  clearResults() {
    this.resultsTarget.replaceChildren()
    this.selectedIndex = -1
  }

  moveSelection(delta) {
    const items = this.resultsTarget.querySelectorAll(".search-result")
    if (items.length === 0) return

    if (this.selectedIndex >= 0 && this.selectedIndex < items.length) {
      items[this.selectedIndex].classList.remove("selected")
    }

    this.selectedIndex += delta
    if (this.selectedIndex < 0) this.selectedIndex = items.length - 1
    if (this.selectedIndex >= items.length) this.selectedIndex = 0

    items[this.selectedIndex].classList.add("selected")
    items[this.selectedIndex].scrollIntoView({ block: "nearest" })
  }

  selectCurrent() {
    const items = this.resultsTarget.querySelectorAll(".search-result")
    const index = this.selectedIndex >= 0 ? this.selectedIndex : 0
    if (items.length === 0) return

    this.navigateTo(items[index].dataset.slug)
  }

  navigateTo(slug) {
    this.close()
    const base = this.element.dataset.searchOverlayBasePath || ""
    Turbo.visit(`${base}/recipes/${slug}`)
  }
}
```

**Step 2: Verify auto-registration**

Stimulus auto-registers controllers via `pin_all_from` in
`config/importmap.rb`. No changes needed.

**Step 3: Commit**

```bash
git add app/javascript/controllers/search_overlay_controller.js
git commit -m "feat: Stimulus search overlay controller with keyboard nav"
```

---

### Task 4: CSS — search overlay styles

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Add search overlay styles**

Add a new section after the Editor Dialog section (~line 1185). The panel
uses `backdrop-filter: blur()` for frosted glass, with a dimmed `::backdrop`
matching existing editor dialogs.

```css
/************************/
/* Search Overlay       */
/************************/

.search-overlay {
  border: none;
  background: transparent;
  padding: 0;
  width: min(90vw, 32rem);
  margin: 0 auto;
  margin-top: 15vh;
  overflow: visible;
}

.search-overlay[open] {
  display: flex;
  flex-direction: column;
}

.search-overlay::backdrop {
  background: var(--dialog-backdrop);
}

.search-panel {
  background: var(--frosted-glass-bg);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border: 1px solid var(--border-light);
  border-radius: 0.75rem;
  box-shadow: var(--shadow-dialog);
  overflow: hidden;
}

.search-input-wrap {
  display: flex;
  align-items: center;
  padding: 0.75rem 1rem;
  gap: 0.75rem;
  border-bottom: 1px solid var(--separator-color);
}

.search-icon {
  width: 1.25rem;
  height: 1.25rem;
  flex-shrink: 0;
  color: var(--muted-text);
}

.search-input {
  flex: 1;
  border: none;
  background: transparent;
  font-size: 1.1rem;
  color: var(--text-color);
  outline: none;
  font-family: inherit;
}

.search-input::placeholder {
  color: var(--muted-text-light);
}

.search-results {
  list-style: none;
  margin: 0;
  padding: 0;
  max-height: 24rem;
  overflow-y: auto;
}

.search-results:empty {
  display: none;
}

.search-result {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.6rem 1rem;
  cursor: pointer;
}

.search-result:hover,
.search-result.selected {
  background: var(--hover-bg);
}

.search-result-title {
  color: var(--text-color);
}

.search-result-category {
  font-size: 0.8rem;
  color: var(--muted-text);
}

.search-no-results {
  padding: 1rem;
  text-align: center;
  color: var(--muted-text);
}

/* Nav search button */

.nav-search-btn {
  background: none;
  border: none;
  cursor: pointer;
  padding: 0.25rem;
  color: var(--text-color);
  display: flex;
  align-items: center;
}
```

**Step 2: Add responsive adjustments**

In the mobile breakpoint section, add:

```css
.search-overlay {
  width: min(95vw, 32rem);
  margin-top: 10vh;
}
```

**Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "style: search overlay frosted glass panel and result list"
```

---

### Task 5: Integration test

**Files:**
- Create: `test/integration/search_overlay_test.rb`

**Step 1: Write integration tests**

```ruby
# test/integration/search_overlay_test.rb
# frozen_string_literal: true

require 'test_helper'

class SearchOverlayTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    setup_test_category(name: 'Baking')
    markdown = "# Pancakes\n\nFluffy buttermilk pancakes.\n\n## Step 1\n\n- flour, 2 cups:\n"
    MarkdownImporter.import(source: markdown, kitchen: @kitchen)
  end

  test 'homepage includes search data JSON and dialog' do
    get root_path

    assert_response :success
    assert_select 'script[type="application/json"][data-search-overlay-target="data"]'
    assert_select 'dialog.search-overlay'
  end

  test 'recipe page includes search data JSON' do
    get recipe_path('pancakes')

    assert_response :success
    assert_select 'script[type="application/json"][data-search-overlay-target="data"]'
  end

  test 'search data contains recipe with expected fields' do
    get root_path

    json_tag = css_select('script[data-search-overlay-target="data"]').first
    data = JSON.parse(json_tag.text)

    assert_equal 1, data.size
    assert_equal 'Pancakes', data.first['title']
    assert_equal 'pancakes', data.first['slug']
    assert_includes data.first['ingredients'], 'flour'
  end

  test 'nav includes search button' do
    get root_path

    assert_select 'button.nav-search-btn'
  end
end
```

**Step 2: Run tests**

Run: `ruby -Itest test/integration/search_overlay_test.rb`
Expected: PASS

**Step 3: Run full suite and lint**

Run: `rake`
Expected: all green, 0 offenses

**Step 4: Commit**

```bash
git add test/integration/search_overlay_test.rb
git commit -m "test: integration tests for search overlay data and markup"
```

---

### Task 6: Manual testing and polish

**Step 1: Start the dev server**

Run: `bin/dev`

**Step 2: Manual test checklist**

- [ ] Press `/` on homepage — overlay opens
- [ ] Press `/` while typing in another input — overlay does NOT open
- [ ] Press `/` while an editor dialog is open — overlay does NOT open
- [ ] Type "pan" — Pancakes appears
- [ ] Type a single character — no results shown (min 2 chars)
- [ ] Arrow down/up navigates results, wraps around
- [ ] Enter on selected result navigates to recipe page
- [ ] Click a result navigates to recipe page
- [ ] Escape closes overlay
- [ ] Click backdrop closes overlay
- [ ] Overlay works on recipe pages, menu, groceries (not just homepage)
- [ ] Light mode and dark mode both look correct
- [ ] Frosted glass effect visible on panel
- [ ] Nav search button opens overlay
- [ ] Results show title + category label

**Step 3: Fix any issues found**

**Step 4: Final commit if any polish needed**
