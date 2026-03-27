# Help Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add contextual "?" help icons throughout the app that link to the relevant section of the GitHub Pages help site.

**Architecture:** A `help_url` helper in `ApplicationHelper` builds absolute links from a base constant. Pages set their help path via `content_for(:help_path)` — the nav renders the link only when one is present. Editor dialogs receive an optional `help_path:` local and render a link in the header.

**Tech Stack:** Rails 8, ERB, Minitest, CSS custom properties

---

## File Map

| File | Change |
|---|---|
| `app/helpers/application_helper.rb` | Add `HELP_BASE_URL` constant + `help_url` method |
| `app/helpers/icon_helper.rb` | Add `:help` entry to `ICONS` hash |
| `config/html_safe_allowlist.yml` | Update line number after ICONS expansion shifts it |
| `app/assets/stylesheets/navigation.css` | Add `.nav-help-link` styles |
| `app/assets/stylesheets/editor.css` | Add `.editor-help-link` styles (note: `.editor-help` already exists as a text-copy style — use `.editor-help-link` for the button) |
| `app/views/shared/_nav.html.erb` | Add conditional help link after settings button |
| `app/views/shared/_editor_dialog.html.erb` | Add `help_path: nil` local; render link in header |
| `app/views/homepage/show.html.erb` | `content_for(:help_path)` + `help_path:` on 3 dialogs + manual link in AI import dialog |
| `app/views/recipes/show.html.erb` | `content_for(:help_path)` + `help_path:` on 2 dialogs |
| `app/views/menu/show.html.erb` | `content_for(:help_path)` + `help_path:` on QuickBites dialog |
| `app/views/groceries/show.html.erb` | `content_for(:help_path)` + `help_path:` on Aisles dialog |
| `app/views/ingredients/index.html.erb` | `content_for(:help_path)` + `help_path:` on nutrition dialog |
| `app/views/settings/_dialog.html.erb` | Add `help_path:` to editor_dialog call |
| `test/helpers/application_helper_test.rb` | Tests for `help_url` |
| `test/helpers/icon_helper_test.rb` | No changes needed — existing test at line 91 iterates `ICONS.each_key`, automatically covering `:help` |

---

## Task 1: Infrastructure — `help_url` helper + `:help` icon

**Files:**
- Modify: `app/helpers/application_helper.rb`
- Modify: `app/helpers/icon_helper.rb`
- Modify: `config/html_safe_allowlist.yml`
- Modify: `test/helpers/application_helper_test.rb`

- [ ] **Step 1: Write failing tests for `help_url`**

  Append to `test/helpers/application_helper_test.rb`:

  ```ruby
  test 'help_url prepends base URL to path' do
    assert_equal 'https://chris-biagini.github.io/familyrecipes/recipes/', help_url('/recipes/')
  end

  test 'help_url works with nested path' do
    assert_equal 'https://chris-biagini.github.io/familyrecipes/recipes/editing/', help_url('/recipes/editing/')
  end
  ```

- [ ] **Step 2: Run tests to confirm they fail**

  ```bash
  ruby -Itest test/helpers/application_helper_test.rb
  ```
  Expected: 2 failures — `undefined method 'help_url'`

- [ ] **Step 3: Add `HELP_BASE_URL` + `help_url` to `application_helper.rb`**

  ```ruby
  HELP_BASE_URL = 'https://chris-biagini.github.io/familyrecipes'.freeze

  def help_url(path)
    "#{HELP_BASE_URL}#{path}"
  end
  ```

  Add these after the `APP_VERSION` constant, before `format_numeric`.

- [ ] **Step 4: Run application helper tests — expect pass**

  ```bash
  ruby -Itest test/helpers/application_helper_test.rb
  ```
  Expected: All green.

- [ ] **Step 5: Add `:help` icon to `icon_helper.rb`**

  Add at the end of the `ICONS` hash, just before the closing `.tap` call (currently line 87):

  ```ruby
  help: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '1.8' },
          content: '<circle cx="12" cy="12" r="9"/>' \
                   '<path d="M9.5 9.5a2.5 2.5 0 0 1 5 0c0 2-2.5 2.5-2.5 4.5"/>' \
                   '<path d="M12 17.5h.01"/>' }
  ```

- [ ] **Step 6: Run icon helper tests**

  The existing test at line 91 (`'contains expected svg content for each icon'`) iterates `ICONS.each_key`, so `:help` is automatically tested. Run:

  ```bash
  ruby -Itest test/helpers/icon_helper_test.rb
  ```
  Expected: All green.

- [ ] **Step 7: Update `html_safe_allowlist.yml`**

  Adding `:help` shifts `svg_tag`'s `.html_safe` call off its current line. Run:

  ```bash
  bundle exec rake lint:html_safe
  ```

  If it reports a line-number mismatch for `app/helpers/icon_helper.rb`, update the line number in `config/html_safe_allowlist.yml`. The entry looks like:

  ```yaml
  - "app/helpers/icon_helper.rb:113"
  ```

  Replace `113` with whatever line the lint task reports.

- [ ] **Step 8: Run full lint + tests**

  ```bash
  bundle exec rake lint && rake test
  ```
  Expected: 0 offenses, all tests pass.

- [ ] **Step 9: Commit**

  ```bash
  git add app/helpers/application_helper.rb app/helpers/icon_helper.rb \
          config/html_safe_allowlist.yml \
          test/helpers/application_helper_test.rb
  git commit -m "Add help_url helper and :help SVG icon"
  ```

---

## Task 2: Nav CSS + partial

**Files:**
- Modify: `app/assets/stylesheets/navigation.css`
- Modify: `app/views/shared/_nav.html.erb`

- [ ] **Step 1: Add `.nav-help-link` to `navigation.css`**

  Add immediately after the `.nav-settings-link` block (currently ends ~line 121):

  ```css
  .nav-help-link {
    background: none;
    border: none;
    cursor: pointer;
    color: var(--text);
    padding: 0.5rem 0.6rem;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    text-decoration: none;
    border-radius: 0.4rem;
    transition: color var(--duration-normal) ease, background-color var(--duration-slow) ease-out;
  }

  .nav-help-link:hover {
    color: var(--red);
    background-color: var(--hover-bg);
  }

  .nav-help-link .nav-icon {
    width: 1.1rem;
    height: 1.1rem;
  }
  ```

- [ ] **Step 2: Add help link to `_nav.html.erb`**

  After the settings button block (the `<% if logged_in? %>` block that ends at line 36), add:

  ```erb
  <% if content_for?(:help_path) %>
    <a href="<%= help_url(yield(:help_path)) %>"
       class="nav-help-link"
       title="Help"
       aria-label="Help"
       target="_blank"
       rel="noopener noreferrer">
      <%= icon(:help, class: 'nav-icon', size: nil) %>
    </a>
  <% end %>
  ```

- [ ] **Step 3: Run full test suite**

  ```bash
  rake test
  ```
  Expected: All green.

- [ ] **Step 4: Commit**

  ```bash
  git add app/assets/stylesheets/navigation.css app/views/shared/_nav.html.erb
  git commit -m "Add help icon to nav bar"
  ```

---

## Task 3: Editor dialog partial + CSS

**Files:**
- Modify: `app/assets/stylesheets/editor.css`
- Modify: `app/views/shared/_editor_dialog.html.erb`

- [ ] **Step 1: Add `.editor-help-link` to `editor.css`**

  Add after the `.editor-mode-toggle:focus-visible` block (around line 895):

  ```css
  .editor-help-link {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 4px 6px;
    color: var(--text-soft);
    text-decoration: none;
    border-radius: 4px;
    transition: color var(--duration-fast) ease;
  }

  .editor-help-link:hover {
    color: var(--red);
  }

  .editor-help-link svg {
    width: 1rem;
    height: 1rem;
  }
  ```

- [ ] **Step 2: Update `_editor_dialog.html.erb`**

  Change the locals comment at line 1 from:

  ```erb
  <%# locals: (title:, id:, dialog_data: {}, footer_extra: nil, extra_data: {}, mode_toggle: false) %>
  ```

  To:

  ```erb
  <%# locals: (title:, id:, dialog_data: {}, footer_extra: nil, extra_data: {}, mode_toggle: false, help_path: nil) %>
  ```

  In the `editor-header-actions` div (currently lines 14-25), add the help link between the mode toggle block and the close button:

  ```erb
  <% if help_path %>
    <a href="<%= help_url(help_path) %>"
       class="editor-help-link"
       title="Help"
       aria-label="Help"
       target="_blank"
       rel="noopener noreferrer">
      <%= icon(:help, size: 14) %>
    </a>
  <% end %>
  ```

  Place it after the `<% if mode_toggle %>` block and before the close button. The full `editor-header-actions` div should look like:

  ```erb
  <div class="editor-header-actions">
    <% if mode_toggle %>
      <% toggle_controller = dialog_data[:extra_controllers] %>
      <button type="button" class="btn editor-mode-toggle"
              data-action="click-><%= toggle_controller %>#toggleMode"
              data-<%= toggle_controller %>-target="modeToggle"
              title="Switch editor mode">&lt;/&gt;</button>
    <% end %>
    <% if help_path %>
      <a href="<%= help_url(help_path) %>"
         class="editor-help-link"
         title="Help"
         aria-label="Help"
         target="_blank"
         rel="noopener noreferrer">
        <%= icon(:help, size: 14) %>
      </a>
    <% end %>
    <button type="button" class="btn editor-close" data-editor-target="closeButton"
            data-action="click->editor#close" aria-label="Close">&times;</button>
  </div>
  ```

- [ ] **Step 3: Run full test suite**

  ```bash
  rake test
  ```
  Expected: All green.

- [ ] **Step 4: Commit**

  ```bash
  git add app/assets/stylesheets/editor.css app/views/shared/_editor_dialog.html.erb
  git commit -m "Add help link to editor dialog header"
  ```

---

## Task 4: Homepage + AI import

**Files:**
- Modify: `app/views/homepage/show.html.erb`

- [ ] **Step 1: Add `content_for(:help_path)` near the top of `homepage/show.html.erb`**

  Add at the very top of the file (before any HTML):

  ```erb
  <% content_for :help_path, '/recipes/' %>
  ```

- [ ] **Step 2: Add `help_path:` to the Categories dialog call**

  Find the `render layout: 'shared/editor_dialog'` call with `title: 'Categories'` (~line 54).
  Add `help_path: '/recipes/tags-and-categories/'` to its `locals:` hash.

- [ ] **Step 3: Add `help_path:` to the Tags dialog call**

  Find the call with `title: 'Tags'` (~line 84).
  Add `help_path: '/recipes/tags-and-categories/'` to its `locals:` hash.

- [ ] **Step 4: Add `help_path:` to the New Recipe dialog call**

  Find the call with `title: 'New Recipe'` (~line 116).
  Add `help_path: '/recipes/editing/'` to its `locals:` hash.

- [ ] **Step 5: Add a manual help link to the AI import dialog**

  The AI import dialog is a custom `<dialog>` (around line 166) that does not use `_editor_dialog`. Its header currently has only a close button. Add a help link inside the header actions div, left of the close button:

  Find this pattern:

  ```erb
  <dialog id="ai-import-editor" class="editor-dialog"
  ```

  Locate its header — it contains an `aria-label="Close"` button. Before that close button, add:

  ```erb
  <a href="<%= help_url('/import-export/ai-import/') %>"
     class="editor-help-link"
     title="Help"
     aria-label="Help"
     target="_blank"
     rel="noopener noreferrer">
    <%= icon(:help, size: 14) %>
  </a>
  ```

- [ ] **Step 6: Run full test suite**

  ```bash
  rake test
  ```
  Expected: All green.

- [ ] **Step 7: Commit**

  ```bash
  git add app/views/homepage/show.html.erb
  git commit -m "Add help links to homepage page and dialogs"
  ```

---

## Task 5: Recipe show

**Files:**
- Modify: `app/views/recipes/show.html.erb`

- [ ] **Step 1: Add `content_for(:help_path)` at top of `recipes/show.html.erb`**

  ```erb
  <% content_for :help_path, '/recipes/' %>
  ```

- [ ] **Step 2: Add `help_path:` to the Edit Nutrition dialog**

  Find the call with `title: 'Edit Nutrition'` (~line 15).
  Add `help_path: '/recipes/nutrition/'` to its `locals:` hash.

- [ ] **Step 3: Add `help_path:` to the Edit Recipe dialog**

  Find the call with `title: "Editing: #{@recipe.title}"` (~line 33).
  Add `help_path: '/recipes/editing/'` to its `locals:` hash.

- [ ] **Step 4: Run full test suite**

  ```bash
  rake test
  ```
  Expected: All green.

- [ ] **Step 5: Commit**

  ```bash
  git add app/views/recipes/show.html.erb
  git commit -m "Add help links to recipe page and editors"
  ```

---

## Task 6: Menu, Groceries, Ingredients, Settings

**Files:**
- Modify: `app/views/menu/show.html.erb`
- Modify: `app/views/groceries/show.html.erb`
- Modify: `app/views/ingredients/index.html.erb`
- Modify: `app/views/settings/_dialog.html.erb`

- [ ] **Step 1: Menu page — `content_for` + QuickBites dialog**

  In `menu/show.html.erb`, add at the top:

  ```erb
  <% content_for :help_path, '/menu/' %>
  ```

  Find the `render layout: 'shared/editor_dialog'` call with `title: 'Edit QuickBites'` (~line 39).
  Add `help_path: '/menu/quickbites/'` to its `locals:` hash.

- [ ] **Step 2: Groceries page — `content_for` + Aisles dialog**

  In `groceries/show.html.erb`, add at the top:

  ```erb
  <% content_for :help_path, '/groceries/' %>
  ```

  Find the call with `title: 'Aisles'` (~line 41).
  Add `help_path: '/groceries/aisles/'` to its `locals:` hash.

- [ ] **Step 3: Ingredients page — `content_for` + nutrition dialog**

  In `ingredients/index.html.erb`, add at the top:

  ```erb
  <% content_for :help_path, '/ingredients/' %>
  ```

  Find the `render layout: 'shared/editor_dialog'` call with `title: 'Edit Nutrition'` (~line 29).
  Add `help_path: '/ingredients/nutrition-data/'` to its `locals:` hash.

- [ ] **Step 4: Settings dialog**

  In `settings/_dialog.html.erb`, find the `render layout: 'shared/editor_dialog'` call with `title: 'Settings'` (~line 2).
  Add `help_path: '/settings/'` to its `locals:` hash.

- [ ] **Step 5: Run full test suite + lint**

  ```bash
  bundle exec rake lint && rake test
  ```
  Expected: 0 offenses, all tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add app/views/menu/show.html.erb app/views/groceries/show.html.erb \
          app/views/ingredients/index.html.erb app/views/settings/_dialog.html.erb
  git commit -m "Add help links to menu, groceries, ingredients, and settings"
  ```

---

## Verification Checklist

After all tasks complete:

- [ ] `rake test` — all green
- [ ] `bundle exec rake lint` — 0 offenses
- [ ] `bundle exec rake lint:html_safe` — no violations
- [ ] Manual check: navigate to Recipes page — confirm `?` appears in nav, links to `https://chris-biagini.github.io/familyrecipes/recipes/`
- [ ] Manual check: open recipe editor — confirm `?` appears in dialog header, links to `.../recipes/editing/`
- [ ] Manual check: navigate to Menu, Groceries, Ingredients — confirm `?` appears and links correctly
- [ ] Manual check: open Settings dialog — confirm `?` in header links to `.../settings/`
- [ ] Manual check: open AI import dialog — confirm `?` in header links to `.../import-export/ai-import/`
- [ ] Spot-check all 9 dialog help URLs resolve by opening each in a browser: `recipes/editing/`, `recipes/nutrition/`, `recipes/tags-and-categories/`, `menu/quickbites/`, `groceries/aisles/`, `ingredients/nutrition-data/`, `settings/`, `import-export/ai-import/` — all prefixed with `https://chris-biagini.github.io/familyrecipes/`
