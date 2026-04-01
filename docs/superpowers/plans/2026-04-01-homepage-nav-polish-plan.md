# Homepage Navigation Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the homepage navigation area — smart tag decoration, relocated edit buttons, section dividers, and improved active tag state.

**Architecture:** All changes are in the homepage view layer (two ERB templates + CSS). The existing `SmartTagHelper` and `SmartTagRegistry` are reused unchanged. A new CSS token (`--tag-filter-active-bg`) and a reusable `section-rule` class handle the visual changes.

**Tech Stack:** Rails ERB views, CSS custom properties, Minitest integration tests.

---

### Task 1: Smart tag decoration on tag filter pills

**Files:**
- Modify: `app/views/homepage/_recipe_listings.html.erb:14-24`
- Test: `test/controllers/homepage_controller_test.rb`

- [ ] **Step 1: Write the failing test for decorated filter pills**

Add to `test/controllers/homepage_controller_test.rb`:

```ruby
test 'tag filter pills show smart decoration when decorate_tags enabled' do
  @kitchen.update!(decorate_tags: true)
  bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  create_recipe(
    "# Tagged\n\nCategory: Bread\nTags: vegetarian\n\n- Flour, 1 cup",
    category_name: 'Bread', kitchen: @kitchen
  )

  get kitchen_root_path(kitchen_slug: kitchen_slug)

  assert_select '.tag-filter-pill.tag-pill--green'
  assert_select '.tag-filter-pill .smart-icon', text: /🥕/
end

test 'tag filter pills are plain when decorate_tags disabled' do
  @kitchen.update!(decorate_tags: false)
  bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  create_recipe(
    "# Tagged\n\nCategory: Bread\nTags: vegetarian\n\n- Flour, 1 cup",
    category_name: 'Bread', kitchen: @kitchen
  )

  get kitchen_root_path(kitchen_slug: kitchen_slug)

  assert_select '.tag-filter-pill.tag-pill--green', count: 0
  assert_select '.tag-filter-pill .smart-icon', count: 0
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb -n /tag filter pills.*decorate/`
Expected: FAIL — no `.tag-pill--green` class or `.smart-icon` in the filter pills.

- [ ] **Step 3: Apply smart tag attrs to filter pills in the partial**

In `app/views/homepage/_recipe_listings.html.erb`, replace lines 14–24 (the tag filter pills section):

```erb
    <% if all_tags.any? %>
      <div class="index-nav-tags">
        <% all_tags.each do |tag| %>
          <% smart = smart_tag_pill_attrs(tag.name) %>
          <button type="button"
                  class="tag-filter-pill <%= smart.dig(:class)&.join(' ') %>"
                  data-recipe-filter-target="tag"
                  data-tag="<%= tag.name %>"
                  data-action="click->recipe-filter#toggle"><% if smart.dig(:data, :smart_emoji) %><span class="smart-icon<%= ' smart-icon--crossout' if smart.dig(:class)&.include?('tag-pill--crossout') %>"><%= smart.dig(:data, :smart_emoji) %></span><% end %><%= tag.name %></button>
        <% end %>
      </div>
    <% end %>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb -n /tag filter pills.*decorate/`
Expected: PASS

- [ ] **Step 5: Run full homepage test suite**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb`
Expected: All tests pass. The existing `tag filter bar renders when recipes have tags` test still passes since `.tag-filter-pill` class is preserved.

- [ ] **Step 6: Commit**

```bash
git add app/views/homepage/_recipe_listings.html.erb test/controllers/homepage_controller_test.rb
git commit -m "Decorate homepage tag filter pills with smart tag colors"
```

---

### Task 2: Smart tag decoration on recipe card tags

**Files:**
- Modify: `app/views/homepage/_recipe_listings.html.erb:44-49`
- Test: `test/controllers/homepage_controller_test.rb`

- [ ] **Step 1: Write the failing test for decorated card tags**

Add to `test/controllers/homepage_controller_test.rb`:

```ruby
test 'recipe card tags show smart decoration when decorate_tags enabled' do
  @kitchen.update!(decorate_tags: true)
  bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  create_recipe(
    "# Tagged\n\nCategory: Bread\nTags: vegetarian\n\n- Flour, 1 cup",
    category_name: 'Bread', kitchen: @kitchen
  )

  get kitchen_root_path(kitchen_slug: kitchen_slug)

  assert_select '.recipe-card .tag-pill.tag-pill--green'
  assert_select '.recipe-card .smart-icon', text: /🥕/
end

test 'recipe card tags are plain when decorate_tags disabled' do
  @kitchen.update!(decorate_tags: false)
  bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  create_recipe(
    "# Tagged\n\nCategory: Bread\nTags: vegetarian\n\n- Flour, 1 cup",
    category_name: 'Bread', kitchen: @kitchen
  )

  get kitchen_root_path(kitchen_slug: kitchen_slug)

  assert_select '.recipe-card .tag-pill.tag-pill--green', count: 0
  assert_select '.recipe-card .recipe-tag', text: 'vegetarian'
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb -n /recipe card tags.*decorate/`
Expected: FAIL

- [ ] **Step 3: Apply smart tag attrs to recipe card tags**

In `app/views/homepage/_recipe_listings.html.erb`, replace the card tag rendering (lines 44–49):

```erb
            <% if sorted_tags.any? %>
              <div class="recipe-tag-list">
                <% sorted_tags.each do |tag| %>
                  <% smart = smart_tag_pill_attrs(tag.name) %>
                  <span class="recipe-tag tag-pill tag-pill--tag <%= smart.dig(:class)&.join(' ') %>"><% if smart.dig(:data, :smart_emoji) %><span class="smart-icon<%= ' smart-icon--crossout' if smart.dig(:class)&.include?('tag-pill--crossout') %>"><%= smart.dig(:data, :smart_emoji) %></span><% end %><%= tag.name %></span>
                <% end %>
              </div>
            <% end %>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb -n /recipe card tags.*decorate/`
Expected: PASS

- [ ] **Step 5: Run full homepage test suite**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb`
Expected: All pass. Existing `recipe cards display tag pills` test still passes since `.recipe-tag` class is preserved on the spans.

- [ ] **Step 6: Commit**

```bash
git add app/views/homepage/_recipe_listings.html.erb test/controllers/homepage_controller_test.rb
git commit -m "Decorate homepage recipe card tags with smart tag colors"
```

---

### Task 3: Relocate edit buttons to their sections

**Files:**
- Modify: `app/views/homepage/show.html.erb:12-36`
- Modify: `app/views/homepage/_recipe_listings.html.erb:5-26`
- Modify: `app/assets/stylesheets/base.css` (`.index-nav-categories`, `.index-nav-tags`)
- Test: `test/controllers/homepage_controller_test.rb`

- [ ] **Step 1: Write the failing test for button relocation**

Add to `test/controllers/homepage_controller_test.rb`:

```ruby
test 'Edit Categories button is inside index-nav-categories section' do
  log_in
  bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  create_recipe("# Bread\n\nCategory: Bread\n\n- Flour, 1 cup", category_name: 'Bread', kitchen: @kitchen)

  get kitchen_root_path(kitchen_slug: kitchen_slug)

  assert_select '.index-nav-categories #edit-categories-button'
end

test 'Edit Tags button is inside index-nav-tags section' do
  log_in
  bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  create_recipe(
    "# Tagged\n\nCategory: Bread\nTags: weeknight\n\n- Flour, 1 cup",
    category_name: 'Bread', kitchen: @kitchen
  )

  get kitchen_root_path(kitchen_slug: kitchen_slug)

  assert_select '.index-nav-tags #edit-tags-button'
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb -n /button is inside/`
Expected: FAIL — buttons are still in the header `.recipe-actions` div.

- [ ] **Step 3: Remove edit buttons from the header**

In `app/views/homepage/show.html.erb`, replace lines 12–36 (the `current_member?` block in the header) with:

```erb
    <%- if current_member? -%>
    <div class="recipe-actions">
      <button type="button" id="new-recipe-button" class="btn-ghost">
        <%= icon(:plus, size: 12, 'stroke-width': '2.5') %>
        Add Recipe
      </button>
      <% if current_kitchen.anthropic_api_key.present? %>
        <span class="recipe-actions-dot">&middot;</span>
        <button type="button" id="ai-import-button" class="btn-ghost">
          <%= icon(:sparkle, size: 14) %>
          AI Import
        </button>
      <% end %>
    </div>
    <%- end -%>
```

- [ ] **Step 4: Add edit buttons into the listings partial sections**

In `app/views/homepage/_recipe_listings.html.erb`, update the categories and tags sections to include the edit buttons. The categories section becomes:

```erb
    <div class="index-nav-categories">
      <div>
        <% categories.each do |category| %>
          <span class="index-nav-link" data-recipe-filter-target="tocLink" data-category="<%= category.slug %>">
            <%= link_to category.name, "##{category.slug}" %>
          </span>
        <% end %>
      </div>
      <% if current_member? %>
        <button type="button" id="edit-categories-button" class="btn-ghost">
          <%= icon(:edit, size: 12) %>
          Edit Categories
        </button>
      <% end %>
    </div>
```

The tags section becomes:

```erb
    <% if all_tags.any? %>
      <div class="index-nav-tags">
        <div>
          <% all_tags.each do |tag| %>
            <% smart = smart_tag_pill_attrs(tag.name) %>
            <button type="button"
                    class="tag-filter-pill <%= smart.dig(:class)&.join(' ') %>"
                    data-recipe-filter-target="tag"
                    data-tag="<%= tag.name %>"
                    data-action="click->recipe-filter#toggle"><% if smart.dig(:data, :smart_emoji) %><span class="smart-icon<%= ' smart-icon--crossout' if smart.dig(:class)&.include?('tag-pill--crossout') %>"><%= smart.dig(:data, :smart_emoji) %></span><% end %><%= tag.name %></button>
          <% end %>
        </div>
        <% if current_member? %>
          <button type="button" id="edit-tags-button" class="btn-ghost">
            <%= icon(:tag, size: 14) %>
            Edit Tags
          </button>
        <% end %>
      </div>
    <% end %>
```

- [ ] **Step 5: Update CSS for the new section layout**

In `app/assets/stylesheets/base.css`, update `.index-nav-categories` and `.index-nav-tags` to use column layout so the edit button appears centered below the links/pills:

```css
.index-nav-categories {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.3rem;
}

.index-nav-categories > div {
  display: flex;
  align-items: baseline;
  gap: 0.4rem;
  flex-wrap: wrap;
  justify-content: center;
}

.index-nav-tags {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.3rem;
}

.index-nav-tags > div {
  display: flex;
  align-items: baseline;
  gap: 0.4rem;
  flex-wrap: wrap;
  justify-content: center;
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb`
Expected: All pass including the new button-location tests and the existing `homepage renders Edit Categories button for members` / `homepage does not render Edit Categories for non-members` tests.

- [ ] **Step 7: Commit**

```bash
git add app/views/homepage/show.html.erb app/views/homepage/_recipe_listings.html.erb app/assets/stylesheets/base.css
git commit -m "Move edit buttons next to their respective sections"
```

---

### Task 4: Decorative section dividers

**Files:**
- Modify: `app/assets/stylesheets/base.css`
- Modify: `app/views/homepage/_recipe_listings.html.erb`
- Test: `test/controllers/homepage_controller_test.rb`

- [ ] **Step 1: Write the failing test for section dividers**

Add to `test/controllers/homepage_controller_test.rb`:

```ruby
test 'categories and tags sections have section-rule class' do
  bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  create_recipe(
    "# Tagged\n\nCategory: Bread\nTags: weeknight\n\n- Flour, 1 cup",
    category_name: 'Bread', kitchen: @kitchen
  )

  get kitchen_root_path(kitchen_slug: kitchen_slug)

  assert_select '.index-nav-categories.section-rule'
  assert_select '.index-nav-tags.section-rule'
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb -n /section-rule/`
Expected: FAIL

- [ ] **Step 3: Add section-rule CSS class**

In `app/assets/stylesheets/base.css`, add the `.section-rule` class near the `header::after` rule (after line 839):

```css
.section-rule::after {
  content: "";
  display: block;
  width: 40px;
  height: 1px;
  background: var(--red);
  margin: 0.6rem auto 0;
}
```

Note: The margin is smaller than `header::after` (`0.6rem` vs `1.5rem`) since these sections are closer together.

- [ ] **Step 4: Add section-rule class to the section wrappers**

In `app/views/homepage/_recipe_listings.html.erb`, add `section-rule` to both container divs:

Change `<div class="index-nav-categories">` to `<div class="index-nav-categories section-rule">`

Change `<div class="index-nav-tags">` to `<div class="index-nav-tags section-rule">`

- [ ] **Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add app/assets/stylesheets/base.css app/views/homepage/_recipe_listings.html.erb test/controllers/homepage_controller_test.rb
git commit -m "Add decorative red rules between navigation sections"
```

---

### Task 5: Fix tag filter active state

**Files:**
- Modify: `app/assets/stylesheets/base.css:974-978`

- [ ] **Step 1: Add the active background token**

In `app/assets/stylesheets/base.css`, add a new token for the active filter pill background. In the light-mode `:root` block (near line 18, after `--red-light`):

```css
  --tag-filter-active-bg: rgba(179, 58, 58, 0.15);
```

In the dark-mode `@media (prefers-color-scheme: dark)` `:root` block (near line 85, after `--red-light`):

```css
  --tag-filter-active-bg: rgba(200, 80, 80, 0.2);
```

- [ ] **Step 2: Update the .tag-filter-pill.active rule**

In `app/assets/stylesheets/base.css`, replace the `.tag-filter-pill.active` block (lines 974–978):

```css
.tag-filter-pill.active {
  background: var(--tag-filter-active-bg);
  color: var(--red);
  border-color: var(--red);
}
```

- [ ] **Step 3: Verify visually**

Run: `bin/dev`
Navigate to the homepage, click a tag filter pill. Confirm:
- Light mode: light red/pink background with red border and red text
- The tag's smart color is replaced by the active state (active wins)
- Clicking again removes the active state, restoring the smart color

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/base.css
git commit -m "Fix tag filter active state: light red bg with red border"
```

---

### Task 6: Final verification

- [ ] **Step 1: Run full test suite**

Run: `rake test`
Expected: All tests pass.

- [ ] **Step 2: Run linter**

Run: `bundle exec rubocop`
Expected: No new offenses.

- [ ] **Step 3: Run html_safe audit**

Run: `rake lint:html_safe`
Expected: Clean — no new `.html_safe` or `raw()` calls introduced.

- [ ] **Step 4: Visual smoke test**

Run `bin/dev` and check:
1. Homepage with `decorate_tags: true` — filter pills and card tags show colors/emoji
2. Homepage with `decorate_tags: false` — filter pills and card tags are plain
3. Edit Categories button appears centered below category links (members only)
4. Edit Tags button appears centered below tag pills (members only)
5. Short red decorative rules appear between categories, tags, and content
6. Clicking a filter pill shows light red bg + red border active state
7. Both edit buttons still open their respective dialogs
8. Non-member view has no edit buttons, but categories/tags/rules still render
