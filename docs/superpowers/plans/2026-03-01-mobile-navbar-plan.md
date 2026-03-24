# Mobile Navbar Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add SVG icons to nav links (icon+text desktop, icon-only mobile) and rename "Home" to "Recipes" (#119).

**Architecture:** Inline SVG icons in the nav partial, CSS media query hides text at ≤600px. No new JS, no new controllers. Icons use `currentColor` to inherit existing hover/focus transitions.

**Tech Stack:** ERB partials, CSS media queries, inline SVG.

---

### Task 1: Add SVG icons and rename Home → Recipes in nav partial

**Files:**
- Modify: `app/views/shared/_nav.html.erb`

**Step 1: Update the nav partial**

Replace the full contents of `app/views/shared/_nav.html.erb` with:

```erb
  <nav>
    <div>
      <% if current_kitchen %>
        <%= link_to home_path, class: 'recipes', title: 'Recipes', aria: { label: 'Recipes' } do %>
          <svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 4c0-1 .5-2 2-2 1 0 7 .5 8 2 1-1.5 7-2 8-2 1.5 0 2 1 2 2v13c0 1-.5 1.5-1.5 1.5S14 17 12 18.5C10 17 4.5 18.5 3.5 18.5S2 18 2 17z"/><path d="M12 2v16.5"/></svg>
          <span>Recipes</span>
        <% end %>
        <% if logged_in? %>
          <%= link_to ingredients_path, class: 'ingredients', title: 'Ingredients', aria: { label: 'Ingredients' } do %>
            <svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6h12v1c0 1-.5 2-2 2H8c-1.5 0-2-1-2-2z"/><path d="M7 9c-.3 2-.5 5 0 8 .3 2 1.5 3 3 3h4c1.5 0 2.7-1 3-3 .5-3 .3-6 0-8"/><line x1="9" y1="13" x2="15" y2="13"/><line x1="9" y1="16" x2="13" y2="16"/></svg>
            <span>Ingredients</span>
          <% end %>
          <%= link_to menu_path, class: 'menu', title: 'Plan your meals', aria: { label: 'Menu' } do %>
            <svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="5" y="2" width="14" height="20" rx="1.5"/><line x1="9" y1="7" x2="16" y2="7"/><line x1="9" y1="11" x2="16" y2="11"/><line x1="9" y1="15" x2="14" y2="15"/><path d="M5 2v20" stroke-width="2"/></svg>
            <span>Menu</span>
          <% end %>
          <%= link_to groceries_path, class: 'groceries', title: 'Shopping list', aria: { label: 'Groceries' } do %>
            <svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="9" cy="20" r="1.5"/><circle cx="18" cy="20" r="1.5"/><path d="M3 3h2l1.5 9h12L20 6H7.5"/><path d="M6.5 12h12"/></svg>
            <span>Groceries</span>
          <% end %>
        <% end %>
      <% else %>
        <%= link_to root_path, class: 'recipes', title: 'Recipes', aria: { label: 'Recipes' } do %>
          <svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 4c0-1 .5-2 2-2 1 0 7 .5 8 2 1-1.5 7-2 8-2 1.5 0 2 1 2 2v13c0 1-.5 1.5-1.5 1.5S14 17 12 18.5C10 17 4.5 18.5 3.5 18.5S2 18 2 17z"/><path d="M12 2v16.5"/></svg>
          <span>Recipes</span>
        <% end %>
      <% end %>
    </div>
    <%= yield :extra_nav if content_for?(:extra_nav) %>
  </nav>
```

Key changes:
- `link_to` now uses block form so each link wraps an SVG icon + `<span>` text label.
- "Home" renamed to "Recipes" everywhere (text, title, class name `home` → `recipes`).
- Each link gets `aria: { label: 'LinkName' }` for accessibility when text is hidden on mobile.
- Each SVG has `aria-hidden="true"` and class `nav-icon`.

**Step 2: Commit**

```
git add app/views/shared/_nav.html.erb
git commit -m "feat: add SVG icons to nav links, rename Home to Recipes (#119)"
```

---

### Task 2: Update CSS for icon+text layout and mobile icon-only

**Files:**
- Modify: `app/assets/stylesheets/style.css` (lines 150–196 and 701–714)

**Step 1: Update nav link styles for icon+text layout**

In `style.css`, replace the `nav a` block (lines 150–163) with:

```css
nav a {
  font-family: "Futura", sans-serif;
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  text-decoration: none;
  font-weight: 600;
  font-size: 0.8rem;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  padding: 0.5rem 0.9rem;
  line-height: 1.5;
  color: var(--text-color);
  transition: color 0.2s ease;
  position: relative;
}
```

Changes: `display: inline-block` → `display: inline-flex` with `align-items: center` and `gap: 0.35rem` for icon+text side by side.

**Step 2: Add nav-icon sizing**

After the `nav a:focus-visible` block (after line 281), add:

```css
.nav-icon {
  width: 1rem;
  height: 1rem;
  flex-shrink: 0;
}
```

**Step 3: Remove mid-dot separators**

Delete the `nav > div:first-child a + a::before` block (lines 187–196):

```css
nav > div:first-child a + a::before {
  content: "\00b7";
  position: absolute;
  left: 0;
  top: 50%;
  transform: translate(-50%, -50%);
  color: var(--border-muted);
  font-size: 1rem;
  letter-spacing: 0;
}
```

**Step 4: Update mobile breakpoint for icon-only**

In the `@media screen and (max-width: 600px)` block, replace the `nav a` rules (lines 706–709) with:

```css
  nav a {
    padding: 0.5rem 0.6rem;
  }

  nav a span {
    display: none;
  }

  .nav-icon {
    width: 1.25rem;
    height: 1.25rem;
  }
```

This hides the text labels and bumps up icon size slightly for better tap targets on mobile. The `font-size: 0.7rem` rule is no longer needed (text is hidden).

Also delete the mobile `nav a::after` adjustment (lines 711–714) — the underline animation doesn't work well with icon-only links:

```css
  nav a::after {
    left: 0.5rem;
    right: 0.5rem;
  }
```

**Step 5: Commit**

```
git add app/assets/stylesheets/style.css
git commit -m "style: icon+text nav on desktop, icon-only on mobile (#119)"
```

---

### Task 3: Update tests for Home → Recipes rename

**Files:**
- Modify: `test/integration/end_to_end_test.rb` (lines 83, 92)

**Step 1: Update test assertions**

On line 83, change:
```ruby
    assert_select 'nav a.home', 'Home'
```
to:
```ruby
    assert_select 'nav a.recipes', 'Recipes'
```

On line 92, change:
```ruby
    assert_select 'nav a.home', 'Home'
```
to:
```ruby
    assert_select 'nav a.recipes', 'Recipes'
```

**Step 2: Run the tests**

```
ruby -Itest test/integration/end_to_end_test.rb
```

Expected: All tests pass.

**Step 3: Run full test suite**

```
rake test
```

Expected: All tests pass.

**Step 4: Commit**

```
git add test/integration/end_to_end_test.rb
git commit -m "test: update nav assertions for Home → Recipes rename (#119)"
```

---

### Task 4: Visual verification

**Step 1: Start the dev server**

```
bin/dev
```

**Step 2: Verify desktop view**

Open `http://localhost:3030` in the browser. Confirm:
- Each nav link shows an SVG icon + text label side by side.
- "Recipes" replaces "Home" in the first nav link.
- No mid-dot separators between links.
- Hover underline animation still works.
- Action buttons (+ New, Edit, Scale, etc.) display correctly on the right.

**Step 3: Verify mobile view**

Resize browser to ≤600px width. Confirm:
- Nav links show icons only — text labels are hidden.
- Icons are large enough for comfortable tapping.
- Action buttons still visible and not cramped.

**Step 4: Verify icon distinguishability**

Confirm the open book (landscape, two-page spread) and folded menu card (portrait, left-fold spine) are visually distinct at nav icon size.

**Step 5: Check RuboCop**

```
rake lint
```

Expected: 0 offenses.

**Step 6: Run html_safe audit**

```
rake lint:html_safe
```

Expected: No new violations (no `.html_safe` or `raw()` added).
