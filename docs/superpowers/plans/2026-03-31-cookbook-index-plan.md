# Cookbook Index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the homepage recipe listing from a flat link list into a browsable cookbook index with recipe cards, visible descriptions, tag pills, and client-side tag filtering.

**Architecture:** Replace the `_recipe_listings.html.erb` partial with a card-based grid layout. Add a Stimulus `recipe_filter_controller` for client-side tag filtering via CSS class toggling. Eager-load tags in the controller. No new models, endpoints, or server-side filtering.

**Tech Stack:** Rails ERB, Stimulus JS, CSS grid, existing Tag/RecipeTag models.

**Design spec:** `docs/superpowers/specs/2026-03-31-cookbook-index-design.md`

---

### Task 1: Eager-load tags in HomepageController

**Files:**
- Modify: `app/controllers/homepage_controller.rb:13` (the `show` action)
- Modify: `test/controllers/homepage_controller_test.rb`

- [ ] **Step 1: Write failing test for tag eager-loading**

Add to the test file, after the existing test cases:

```ruby
test 'recipe cards display tag pills' do
  recipe = create_recipe("# Tagged Recipe\n\nCategory: #{@category.name}\nTags: weeknight, italian\n\n- Flour, 1 cup", category_name: @category.name, kitchen: @kitchen)
  get kitchen_root_path(kitchen_slug)

  assert_select '.recipe-card .recipe-tag', count: 2
  assert_select '.recipe-card .recipe-tag', text: 'weeknight'
  assert_select '.recipe-card .recipe-tag', text: 'italian'
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb -n test_recipe_cards_display_tag_pills`
Expected: FAIL — `.recipe-card` selector does not exist yet.

- [ ] **Step 3: Update controller to eager-load tags**

In `app/controllers/homepage_controller.rb`, change the `show` method:

```ruby
def show
  @categories = current_kitchen.categories.with_recipes.ordered.includes(recipes: :tags)
end
```

- [ ] **Step 4: Verify controller change doesn't break existing tests**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb`
Expected: All existing tests pass. The new test still fails (view not updated yet).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/homepage_controller.rb test/controllers/homepage_controller_test.rb
git commit -m "Eager-load recipe tags in HomepageController#show"
```

---

### Task 2: Replace recipe listings partial with card layout

**Files:**
- Modify: `app/views/homepage/_recipe_listings.html.erb`
- Modify: `test/controllers/homepage_controller_test.rb`

- [ ] **Step 1: Write failing tests for the new card structure**

Add these tests to the test file:

```ruby
test 'recipe listings render as cards with descriptions' do
  create_recipe("# Tasty Pasta\n\nA simple weeknight meal.\n\nCategory: #{@category.name}\n\n- Pasta, 400 g", category_name: @category.name, kitchen: @kitchen)
  get kitchen_root_path(kitchen_slug)

  assert_select '.recipe-card' do |cards|
    assert cards.size >= 1
  end
  assert_select '.recipe-card .recipe-description', text: /simple weeknight/
end

test 'recipe cards omit description when blank' do
  create_recipe("# No Desc Recipe\n\nCategory: #{@category.name}\n\n- Flour, 1 cup", category_name: @category.name, kitchen: @kitchen)
  get kitchen_root_path(kitchen_slug)

  assert_select '.recipe-card .recipe-description', count: 0
end

test 'recipe cards carry data-tags attribute' do
  create_recipe("# Tagged\n\nCategory: #{@category.name}\nTags: weeknight, comfort-food\n\n- Flour, 1 cup", category_name: @category.name, kitchen: @kitchen)
  get kitchen_root_path(kitchen_slug)

  assert_select '.recipe-card[data-recipe-filter-target="card"][data-tags="comfort-food,weeknight"]'
end

test 'category sections have back-to-top link' do
  create_recipe("# Something\n\nCategory: #{@category.name}\n\n- Flour, 1 cup", category_name: @category.name, kitchen: @kitchen)
  get kitchen_root_path(kitchen_slug)

  assert_select 'section .back-to-top'
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb`
Expected: New tests fail — `.recipe-card` does not exist.

- [ ] **Step 3: Replace the partial**

Replace the full contents of `app/views/homepage/_recipe_listings.html.erb`:

```erb
<%# locals: (categories:) %>
<% all_tags = categories.flat_map { |c| c.recipes.flat_map(&:tags) }.uniq(&:name).sort_by(&:name) %>

<div id="recipe-listings" data-controller="recipe-filter">
  <% if all_tags.any? %>
    <div class="tag-filter-bar">
      <span class="tag-filter-label">Filter by tag:</span>
      <% all_tags.each do |tag| %>
        <button type="button"
                class="tag-filter-pill"
                data-recipe-filter-target="tag"
                data-tag="<%= tag.name %>"
                data-action="click->recipe-filter#toggle">
          <%= tag.name %>
        </button>
      <% end %>
    </div>
  <% end %>

  <div class="toc_nav" data-recipe-filter-target="toc">
    <ul>
      <% categories.each do |category| %>
        <li data-recipe-filter-target="tocLink" data-category="<%= category.slug %>">
          <%= link_to category.name, "##{category.slug}" %>
        </li>
      <% end %>
    </ul>
  </div>

  <% categories.each do |category| %>
    <section id="<%= category.slug %>" data-recipe-filter-target="category">
      <div class="category-heading">
        <h2><%= category.name %></h2>
        <a href="#recipe-listings" class="back-to-top">&uarr; top</a>
      </div>
      <div class="recipe-card-grid">
        <% category.recipes.sort_by(&:title).each do |recipe| %>
          <% sorted_tags = recipe.tags.sort_by(&:name) %>
          <div class="recipe-card"
               data-recipe-filter-target="card"
               data-tags="<%= sorted_tags.map(&:name).join(',') %>">
            <%= link_to recipe.title, recipe_path(recipe.slug), class: 'recipe-card-title' %>
            <% if recipe.description.present? %>
              <p class="recipe-description"><%= recipe.description %></p>
            <% end %>
            <% if sorted_tags.any? %>
              <div class="recipe-tag-list">
                <% sorted_tags.each do |tag| %>
                  <span class="recipe-tag"><%= tag.name %></span>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
      <p class="filter-empty-msg">No recipes match the current filter</p>
    </section>
  <% end %>
</div>
```

- [ ] **Step 4: Run tests**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb`
Expected: New card tests pass. Some existing tests may need selector updates (see next step).

- [ ] **Step 5: Fix any broken existing tests**

The existing tests assert on `section > ul li a` and `.toc_nav a` selectors. The TOC structure is preserved, so TOC tests should pass. Recipe link tests need updating from `section > ul li a` to `.recipe-card a` or `.recipe-card-title`. Update the broken assertions to match the new structure. For example, if a test does:

```ruby
assert_select 'section > ul li a', text: 'Oatmeal Cookies'
```

Change to:

```ruby
assert_select '.recipe-card-title', text: 'Oatmeal Cookies'
```

Walk through each failing assertion and update the selector.

- [ ] **Step 6: Run full test suite**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/views/homepage/_recipe_listings.html.erb test/controllers/homepage_controller_test.rb
git commit -m "Replace recipe listings with card layout showing descriptions and tags"
```

---

### Task 3: CSS for card grid, tag pills, and filter states

**Files:**
- Modify: `app/assets/stylesheets/base.css`

- [ ] **Step 1: Add card grid and tag filter CSS**

Add the following styles in `base.css` after the existing `section` and `.toc_nav` rules (after the `.homepage section h2` block, around line 930):

```css
/* Cookbook index: tag filter bar */
.tag-filter-bar {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-wrap: wrap;
  padding: 0.75rem 0;
  margin-bottom: 1rem;
  border-bottom: 1px solid var(--rule);
  position: sticky;
  top: var(--nav-height, 0px);
  z-index: 5;
  background: var(--content-card-bg);
}

.tag-filter-label {
  font-size: 0.8rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-light);
  font-weight: 500;
}

.tag-filter-pill {
  display: inline-block;
  padding: 0.25rem 0.75rem;
  border-radius: 1.25rem;
  font-size: 0.82rem;
  font-family: var(--font-body);
  background: var(--tag-bg);
  color: var(--tag-text);
  border: 2px solid transparent;
  cursor: pointer;
  transition: background var(--duration-fast), border-color var(--duration-fast);
}

.tag-filter-pill:hover {
  background: var(--hover-bg-strong);
}

.tag-filter-pill.active {
  background: var(--red);
  color: white;
  border-color: currentColor;
}

/* Cookbook index: category heading with back-to-top */
.category-heading {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  border-bottom: 2px solid var(--red);
  margin-bottom: 0.75rem;
}

.back-to-top {
  font-size: 0.75rem;
  color: var(--text-light);
  text-decoration: none;
  padding-bottom: 0.25rem;
}

.back-to-top:hover {
  color: var(--red);
}

/* Cookbook index: recipe card grid */
.recipe-card-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 0.5rem;
}

@media (max-width: 599px) {
  .recipe-card-grid {
    grid-template-columns: 1fr;
  }

  .tag-filter-bar {
    flex-wrap: nowrap;
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
  }
}

/* Cookbook index: recipe cards */
.recipe-card {
  padding: 0.625rem 0.75rem;
  border-left: 3px solid var(--red);
  background: var(--content-card-bg);
  border-radius: 0 4px 4px 0;
  transition: opacity var(--duration-normal);
}

.recipe-card-title {
  font-family: var(--font-display);
  font-size: 1.05rem;
  color: var(--red);
  text-decoration: none;
  transition: color var(--duration-normal);
}

.recipe-card-title:hover {
  color: var(--accent-hover);
}

.recipe-description {
  margin: 0.2rem 0 0.4rem;
  font-size: 0.84rem;
  color: var(--text-soft);
  line-height: 1.35;
}

.recipe-tag-list {
  display: flex;
  gap: 0.25rem;
  flex-wrap: wrap;
  margin-top: 0.25rem;
}

.recipe-tag {
  display: inline-block;
  padding: 0.06rem 0.44rem;
  border-radius: 0.625rem;
  font-size: 0.7rem;
  background: var(--rule-faint);
  color: var(--text-soft);
}

/* Cookbook index: filter states */
.recipe-card.filtered-out {
  opacity: 0.3;
  border-left-color: transparent;
}

section.filtered-empty {
  opacity: 0.3;
}

.filter-empty-msg {
  display: none;
  font-size: 0.85rem;
  color: var(--text-light);
  font-style: italic;
}

section.filtered-empty .filter-empty-msg {
  display: block;
}

section.filtered-empty .recipe-card-grid {
  display: none;
}

.toc_nav li.filtered-empty a {
  opacity: 0.4;
}
```

- [ ] **Step 2: Verify the page renders correctly**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb`
Expected: All tests pass (CSS doesn't affect test assertions, but confirms nothing broke).

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/base.css
git commit -m "Add CSS for cookbook index cards, tag filter bar, and filter states"
```

---

### Task 4: Stimulus recipe_filter_controller

**Files:**
- Create: `app/javascript/controllers/recipe_filter_controller.js`
- Modify: `app/javascript/application.js`

- [ ] **Step 1: Create the controller**

Create `app/javascript/controllers/recipe_filter_controller.js`:

```javascript
/**
 * Client-side tag filtering for the cookbook index page.
 *
 * Mounted on `#recipe-listings`. Manages a set of active tag names and
 * toggles CSS classes on recipe cards, category sections, and TOC links
 * to show/hide based on tag matches.
 *
 * Collaborators:
 *   - `_recipe_listings.html.erb` provides targets and data-tags attributes
 *   - `base.css` defines `.filtered-out`, `.filtered-empty`, `.active` styles
 */
import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
  static targets = ['tag', 'card', 'category', 'tocLink']

  connect () {
    this.activeTags = new Set()
  }

  toggle (event) {
    const pill = event.currentTarget
    const name = pill.dataset.tag

    if (this.activeTags.has(name)) {
      this.activeTags.delete(name)
      pill.classList.remove('active')
    } else {
      this.activeTags.add(name)
      pill.classList.add('active')
    }

    this.apply()
  }

  apply () {
    const active = this.activeTags
    const filtering = active.size > 0

    this.cardTargets.forEach(card => {
      if (!filtering) {
        card.classList.remove('filtered-out')
        return
      }

      const cardTags = (card.dataset.tags || '').split(',').filter(Boolean)
      const matches = [...active].every(tag => cardTags.includes(tag))
      card.classList.toggle('filtered-out', !matches)
    })

    this.categoryTargets.forEach(section => {
      if (!filtering) {
        section.classList.remove('filtered-empty')
        return
      }

      const cards = section.querySelectorAll('[data-recipe-filter-target="card"]')
      const allHidden = [...cards].every(c => c.classList.contains('filtered-out'))
      section.classList.toggle('filtered-empty', allHidden)
    })

    this.tocLinkTargets.forEach(li => {
      if (!filtering) {
        li.classList.remove('filtered-empty')
        return
      }

      const slug = li.dataset.category
      const section = document.getElementById(slug)
      if (section) {
        li.classList.toggle('filtered-empty', section.classList.contains('filtered-empty'))
      }
    })
  }
}
```

- [ ] **Step 2: Register in application.js**

In `app/javascript/application.js`, add the import and registration alongside the existing controllers. Find the alphabetically correct spot (after `recipe_graphical` and `recipe_state`):

```javascript
import RecipeFilterController from './controllers/recipe_filter_controller'
```

And in the registration block:

```javascript
application.register('recipe-filter', RecipeFilterController)
```

- [ ] **Step 3: Build JS bundle**

Run: `npm run build`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Run full test suite to confirm nothing broke**

Run: `rake test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/recipe_filter_controller.js app/javascript/application.js
git commit -m "Add recipe_filter Stimulus controller for client-side tag filtering"
```

---

### Task 5: JS tests for recipe_filter_controller

**Files:**
- Create: `test/javascript/recipe_filter_controller_test.js`

- [ ] **Step 1: Check existing JS test structure**

Look at how other JS tests are structured in this project:

Run: `ls test/javascript/`

Follow the same pattern (likely uses a test framework already configured in `package.json`).

- [ ] **Step 2: Write JS tests**

Create `test/javascript/recipe_filter_controller_test.js`. The exact test framework depends on what the project uses (check `package.json` scripts). The tests should cover:

1. **Toggle activates/deactivates a tag** — clicking a pill adds `.active`, clicking again removes it.
2. **Filtering dims non-matching cards** — with "weeknight" active, a card with `data-tags="baking"` gets `.filtered-out`.
3. **AND logic** — with "weeknight" and "italian" active, a card with only `data-tags="weeknight"` gets `.filtered-out`.
4. **No filter shows all cards** — deactivating all tags removes `.filtered-out` from every card.
5. **Empty category gets `.filtered-empty`** — when all cards in a section are filtered out.
6. **TOC link mirrors category state** — `.filtered-empty` on TOC `li` matches section.
7. **Cards with no tags** — `data-tags=""` should be filtered out when any tag is active.

If the project uses a DOM-based test setup, write tests with that. If it uses simple unit tests (like the classifier tests), test the filtering logic by simulating the data structures. Adapt to whatever pattern exists.

- [ ] **Step 3: Run JS tests**

Run: `npm test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/javascript/recipe_filter_controller_test.js
git commit -m "Add JS tests for recipe filter controller"
```

---

### Task 6: Update html_safe_allowlist if needed

**Files:**
- Possibly modify: `config/html_safe_allowlist.yml`

- [ ] **Step 1: Run the html_safe audit**

Run: `rake lint:html_safe`

Check if any new `.html_safe` or `raw()` calls were introduced (there shouldn't be — the new partial uses standard ERB escaping).

- [ ] **Step 2: If the audit fails, update the allowlist**

If line-number shifts in other files caused allowlist mismatches, update `config/html_safe_allowlist.yml` with the correct line numbers.

- [ ] **Step 3: Run full lint and test suite**

Run: `rake`
Expected: All lint checks pass, all tests pass.

- [ ] **Step 4: Commit (only if changes were needed)**

```bash
git add config/html_safe_allowlist.yml
git commit -m "Update html_safe allowlist for shifted line numbers"
```

---

### Task 7: Manual smoke test

- [ ] **Step 1: Start the dev server**

Run: `bin/dev`

- [ ] **Step 2: Verify the homepage**

Open the homepage in a browser. Check:
- Recipe cards display with title, description (where present), and tag pills
- Two-column grid on desktop, one column on mobile (resize browser)
- Tag filter bar shows all tags alphabetically
- Clicking a tag highlights it (thick border, red fill)
- Non-matching recipes dim, matching recipes keep red left border
- Empty categories dim with "No recipes match" message
- TOC links dim for empty categories
- "↑ top" links scroll back to the TOC
- Clicking a recipe title navigates to the recipe page
- Admin actions (Add Recipe, Edit Categories, etc.) still work

- [ ] **Step 3: Verify no Bullet warnings**

Check the Rails log and page footer for N+1 query warnings. The eager-load should prevent any.

- [ ] **Step 4: Verify Brakeman passes**

Run: `rake security`
Expected: No new warnings.
