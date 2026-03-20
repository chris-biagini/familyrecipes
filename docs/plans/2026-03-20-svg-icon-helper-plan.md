# SVG Icon Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract ~20 inline SVG icons into a Ruby `IconHelper` module and a JS `icons.js` utility so each icon is defined once and referenced by name.

**Architecture:** A frozen `ICONS` hash in `IconHelper` maps symbol names to SVG definitions. A single `icon(name, size:, **attrs)` method builds inline `<svg>` tags. A parallel JS module handles the 3 programmatically-built icons. Templates replace raw SVG markup with `icon(:name)` calls.

**Tech Stack:** Rails helpers, ERB templates, vanilla JS (esbuild-bundled)

**Spec:** `docs/plans/2026-03-20-svg-icon-helper-design.md`

---

### Task 1: IconHelper — test and implementation

**Files:**
- Create: `app/helpers/icon_helper.rb`
- Create: `test/helpers/icon_helper_test.rb`
- Modify: `config/html_safe_allowlist.yml`

- [ ] **Step 1: Write failing tests**

Create `test/helpers/icon_helper_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class IconHelperTest < ActionView::TestCase
  test 'renders svg tag with default attributes' do
    result = icon(:edit, size: 12)

    assert_includes result, '<svg'
    assert_includes result, 'width="12"'
    assert_includes result, 'height="12"'
    assert_includes result, 'fill="none"'
    assert_includes result, 'stroke="currentColor"'
    assert_includes result, 'aria-hidden="true"'
    assert_includes result, '</svg>'
  end

  test 'uses per-icon viewBox' do
    result = icon(:edit, size: 12)

    assert_includes result, 'viewBox="0 0 32 32"'
  end

  test 'uses per-icon stroke-width' do
    edit_result = icon(:edit, size: 12)
    search_result = icon(:search, size: 12)

    assert_includes edit_result, 'stroke-width="2.5"'
    assert_includes search_result, 'stroke-width="1.8"'
  end

  test 'size nil omits width and height' do
    result = icon(:search, size: nil)

    assert_not_includes result, 'width='
    assert_not_includes result, 'height='
  end

  test 'merges custom class' do
    result = icon(:search, size: nil, class: 'nav-icon')

    assert_includes result, 'class="nav-icon"'
  end

  test 'nil value removes default attribute' do
    result = icon(:apple, size: 14, 'aria-hidden': nil, 'aria-label': 'Has nutrition')

    assert_not_includes result, 'aria-hidden'
    assert_includes result, 'aria-label="Has nutrition"'
  end

  test 'caller attrs override per-icon defaults' do
    result = icon(:edit, size: 12, 'stroke-width': '4')

    assert_includes result, 'stroke-width="4"'
    assert_not_includes result, 'stroke-width="2.5"'
  end

  test 'raises ArgumentError for unknown icon' do
    assert_raises(ArgumentError) { icon(:nonexistent) }
  end

  test 'returns html safe string' do
    assert_predicate icon(:edit, size: 12), :html_safe?
  end

  test 'contains expected svg content for each icon' do
    IconHelper::ICONS.each_key do |name|
      result = icon(name, size: 12)

      assert_includes result, '<svg', "#{name} should render an svg tag"
      assert_includes result, '</svg>', "#{name} should close the svg tag"
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/helpers/icon_helper_test.rb`
Expected: failures (IconHelper not defined)

- [ ] **Step 3: Implement IconHelper**

Create `app/helpers/icon_helper.rb` with an architectural header comment
(per CLAUDE.md convention — role, collaborators, constraints). The `ICONS`
hash stores each icon's `viewBox`, optional per-icon attribute overrides,
and SVG content. The public `icon` method should stay within the 5-line
method limit — extract private helpers (e.g. `build_svg_attrs` to merge
defaults/overrides/nil-removal, `svg_tag` to assemble the tag string).

Exact SVG content for each icon (copied from current inline markup):

- **edit** — viewBox `0 0 32 32`, stroke-width `2.5`:
  `<path d="M22 4l6 6-16 16H6v-6z"/><line x1="18" y1="8" x2="24" y2="14"/>`
- **plus** — viewBox `0 0 24 24`, stroke-width `2`:
  `<line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>`
- **search** — viewBox `0 0 24 24`, stroke-width `1.8`:
  `<circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>`
- **settings** — viewBox `0 0 24 24`, stroke-width `1.8`:
  `<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>`
- **book** — viewBox `0 0 24 24`, stroke-width `1.8`:
  `<path d="M2 17 V18.5 L12 19.5"/><path d="M22 17 V18.5 L12 19.5"/><path d="M2 4 C5 3.5 9 4 12 5.5 V18.5 C9 17 5 16.5 2 17 Z"/><path d="M22 4 C19 3.5 15 4 12 5.5 V18.5 C15 17 19 16.5 22 17 Z"/><path d="M12 5.5 V18.5"/><path d="M10.5 20 Q12 21.5 13.5 20"/>`
- **ingredients** — viewBox `0 0 24 24`, stroke-width `1.8`:
  `<path d="M2 10 L5.5 21 H18.5 L22 10"/><line x1="1" y1="10" x2="23" y2="10"/><line x1="9" y1="10" x2="16.5" y2="2.5"/><line x1="11.5" y1="10" x2="19" y2="2.5"/><path d="M16.5 2.5 C17 1 18.5 1 19 2.5"/>`
- **menu** — viewBox `0 0 24 24`, stroke-width `1.8`:
  `<rect x="4" y="1" width="16" height="22"/><line x1="8" y1="7" x2="16" y2="7"/><line x1="8" y1="11" x2="16" y2="11"/><line x1="8" y1="15" x2="16" y2="15"/><line x1="8" y1="19" x2="16" y2="19"/>`
- **cart** — viewBox `0 0 24 24`, stroke-width `1.8`:
  `<path d="M1 1h3.5l2 11h11l2.5-7H6"/><circle cx="8.5" cy="19" r="2"/><circle cx="16.5" cy="19" r="2"/><path d="M6.5 12h11"/>`
- **tag** — viewBox `0 0 24 24`, stroke-width `2`:
  `<path d="M12 2H2v10l9.29 9.29a1 1 0 0 0 1.42 0l6.58-6.58a1 1 0 0 0 0-1.42L12 2Z"/><path d="M7 7h.01"/>`
- **sparkle** — viewBox `0 0 24 24`, stroke-width `2`:
  `<path d="M12 3l1.5 4.5L18 9l-4.5 1.5L12 15l-1.5-4.5L6 9l4.5-1.5z"/><path d="M19 13l.75 2.25L22 16l-2.25.75L19 19l-.75-2.25L16 16l2.25-.75z"/>`
- **apple** — viewBox `0 0 32 32`, stroke-width `2.5`:
  `<line x1="16" y1="9" x2="16" y2="4"/><path d="M16 7c-2-2-5-2-6 0"/><path d="M16 9C13 7 7 8 5 12c-2 5 0 10 3 14 2 2 4 3 6 3 1 0 1.5-1 2-1s1 1 2 1c2 0 4-1 6-3 3-4 5-9 3-14-2-4-8-5-11-3z"/>`
- **scale** — viewBox `0 0 32 32`, stroke-width `2.5`:
  `<line x1="16" y1="3" x2="16" y2="26"/><line x1="4" y1="9" x2="28" y2="9"/><path d="M6 9L3 19h10L10 9"/><path d="M22 9l-3 10h10l-3-10"/><line x1="10" y1="26" x2="22" y2="26"/>`

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/helpers/icon_helper_test.rb`
Expected: all pass

- [ ] **Step 5: Add allowlist entry**

Add to `config/html_safe_allowlist.yml` under a new `# IconHelper` comment
section. The entry is `app/helpers/icon_helper.rb:<line>` where `<line>` is
the line number of the `.html_safe` call. Verify with `rake lint:html_safe`.

- [ ] **Step 6: Run lint**

Run: `bundle exec rubocop app/helpers/icon_helper.rb test/helpers/icon_helper_test.rb`
Expected: 0 offenses

- [ ] **Step 7: Commit**

```bash
git add app/helpers/icon_helper.rb test/helpers/icon_helper_test.rb config/html_safe_allowlist.yml
git commit -m "Add IconHelper with frozen icon registry and tests"
```

---

### Task 2: Replace inline SVGs in nav templates

**Files:**
- Modify: `app/views/shared/_nav.html.erb` (lines 29-32, 37-40)
- Modify: `app/views/shared/_nav_links.html.erb` (lines 4-11, 17-23, 28-34, 39-44, 51-58)

**Staying inline (not touched by this plan):**
- Hamburger SVG (`_nav.html.erb` lines 8-12) — CSS animation classes on individual rects
- Availability dots (`menu/_recipe_selector.html.erb`) — ERB conditional fill/stroke logic
- Download icon (`nutrition_editor_controller.js`) — single use, co-located

- [ ] **Step 1: Replace search icon in `_nav.html.erb`**

Replace lines 29-32 (the `<svg>...</svg>` block inside the search button) with:
```erb
<%= icon(:search, class: 'nav-icon', size: nil) %>
```

- [ ] **Step 2: Replace settings icon in `_nav.html.erb`**

Replace lines 37-40 (the `<svg>...</svg>` block inside the settings button) with:
```erb
<%= icon(:settings, class: 'nav-icon', size: nil) %>
```

- [ ] **Step 3: Replace all nav link icons in `_nav_links.html.erb`**

Replace each multi-line `<svg>...</svg>` block:

- Lines 4-11 (authenticated book icon) → `<%= icon(:book, class: 'nav-icon', size: nil) %>`
- Lines 17-23 (ingredients icon) → `<%= icon(:ingredients, class: 'nav-icon', size: nil) %>`
- Lines 28-34 (menu icon) → `<%= icon(:menu, class: 'nav-icon', size: nil) %>`
- Lines 39-44 (cart icon) → `<%= icon(:cart, class: 'nav-icon', size: nil) %>`
- Lines 51-58 (unauthenticated book icon) → `<%= icon(:book, class: 'nav-icon', size: nil) %>`

- [ ] **Step 4: Run full test suite**

Run: `rake test`
Expected: all pass (nav icons are rendered in many controller tests)

- [ ] **Step 5: Commit**

```bash
git add app/views/shared/_nav.html.erb app/views/shared/_nav_links.html.erb
git commit -m "Replace inline SVGs in nav with icon helper calls"
```

---

### Task 3: Replace inline SVGs in homepage and recipe pages

**Files:**
- Modify: `app/views/homepage/show.html.erb` (lines 14, 19-24, 29, 35, 83-86, 116-119)
- Modify: `app/views/recipes/_recipe_content.html.erb` (line 39)
- Modify: `app/views/menu/show.html.erb` (line 21)

- [ ] **Step 1: Replace edit icon in `homepage/show.html.erb` line 14**

Replace the inline `<svg ...>...</svg>` with:
```erb
<%= icon(:edit, size: 12) %>
```

- [ ] **Step 2: Replace tag icon in `homepage/show.html.erb` lines 19-24**

Replace the multi-line `<svg>...</svg>` with:
```erb
<%= icon(:tag, size: 14) %>
```

- [ ] **Step 3: Replace plus icon in `homepage/show.html.erb` line 29**

Replace the inline `<svg ...>...</svg>` with:
```erb
<%= icon(:plus, size: 12, 'stroke-width': '2.5') %>
```

- [ ] **Step 4: Replace sparkle icon in `homepage/show.html.erb` line 35**

Replace the inline `<svg ...>...</svg>` with:
```erb
<%= icon(:sparkle, size: 14) %>
```

- [ ] **Step 5: Replace plus icons in editor dialog add buttons (lines 83-86 and 116-119)**

Each 4-line `<svg>...</svg>` block becomes:
```erb
<%= icon(:plus, size: 18) %>
```

- [ ] **Step 6: Replace edit icon in `_recipe_content.html.erb` line 39**

Replace the inline `<svg ...>...</svg>` with:
```erb
<%= icon(:edit, size: 12) %>
```

- [ ] **Step 7: Replace edit icon in `menu/show.html.erb` line 21**

Replace the inline `<svg ...>...</svg>` with:
```erb
<%= icon(:edit, size: 12) %>
```

- [ ] **Step 8: Run full test suite**

Run: `rake test`
Expected: all pass

- [ ] **Step 9: Commit**

```bash
git add app/views/homepage/show.html.erb app/views/recipes/_recipe_content.html.erb app/views/menu/show.html.erb
git commit -m "Replace inline SVGs in homepage, recipe, and menu with icon helper"
```

---

### Task 4: Replace inline SVGs in groceries and ingredients pages

**Files:**
- Modify: `app/views/groceries/show.html.erb` (lines 15, 62-65)
- Modify: `app/views/groceries/_custom_items.html.erb` (line 6)
- Modify: `app/views/ingredients/_table_row.html.erb` (lines 21, 24, 27)

- [ ] **Step 1: Replace edit icon in `groceries/show.html.erb` line 15**

Replace the inline `<svg ...>...</svg>` with:
```erb
<%= icon(:edit, size: 12) %>
```

- [ ] **Step 2: Replace plus icon in `groceries/show.html.erb` lines 62-65**

Replace the 4-line `<svg>...</svg>` with:
```erb
<%= icon(:plus, size: 18) %>
```

- [ ] **Step 3: Replace plus icon in `_custom_items.html.erb` line 6**

Replace the inline `<svg ...>...</svg>` inside the add button with:
```erb
<%= icon(:plus, size: 18) %>
```

- [ ] **Step 4: Replace ingredient status icons in `_table_row.html.erb`**

Line 21 (edit/custom entry icon):
```erb
<%= icon(:edit, size: 14, class: 'ingredient-icon', 'aria-label': 'Custom entry', 'aria-hidden': nil) %>
```

Line 24 (apple/nutrition icon):
```erb
<%= icon(:apple, size: 14, class: 'ingredient-icon', 'aria-label': 'Has nutrition', 'aria-hidden': nil) %>
```

Line 27 (scale/density icon):
```erb
<%= icon(:scale, size: 14, class: 'ingredient-icon', 'aria-label': 'Has density', 'aria-hidden': nil) %>
```

- [ ] **Step 5: Run full test suite**

Run: `rake test`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add app/views/groceries/show.html.erb app/views/groceries/_custom_items.html.erb app/views/ingredients/_table_row.html.erb
git commit -m "Replace inline SVGs in groceries and ingredients with icon helper"
```

---

### Task 5: JS icons utility and ordered list editor refactor

**Files:**
- Create: `app/javascript/utilities/icons.js`
- Modify: `app/javascript/utilities/ordered_list_editor_utils.js` (lines 214-312)

- [ ] **Step 1: Create `icons.js`**

Create `app/javascript/utilities/icons.js` with header comment, an `ICONS`
object containing definitions for `chevron`, `delete`, and `undo`, and an
exported `buildIcon(name, size)` function.

Each icon entry has: `viewBox`, and an array of child element specs
(`{ tag, attrs }`) describing the SVG children.

`buildIcon` creates the SVG element via `createElementNS`, sets `viewBox`,
`width`, `height`, and `fill="none"`, then iterates child specs to build
and append each child element with its attributes (including
`stroke="currentColor"`, `stroke-width="2"`, `stroke-linecap="round"`,
`stroke-linejoin="round"`).

Icon definitions (from current `ordered_list_editor_utils.js`):

- **chevron**: `{ tag: 'polyline', attrs: { points: '6 15 12 9 18 15' } }`
- **delete**: two `line` elements: `(6,6)→(18,18)` and `(18,6)→(6,18)`,
  stroke-linejoin not needed (lines)
- **undo**: `path` with `d="M4 9h11a4 4 0 0 1 0 8H11"` + `polyline`
  with `points="7 5 4 9 7 13"`

- [ ] **Step 2: Update `ordered_list_editor_utils.js`**

Add import at top of file:
```js
import { buildIcon } from './icons'
```

In `buildControls` (around lines 214-228), replace:
- `chevronSvg()` → `buildIcon('chevron', 14)`
- `chevronSvg(true)` → the same call, then `svg.classList.add('aisle-icon--flipped')` — extract into a local helper or inline the class addition after the call
- `deleteSvg()` → `buildIcon('delete', 14)`
- `undoSvg()` → `buildIcon('undo', 14)`

Delete the three functions `chevronSvg`, `deleteSvg`, `undoSvg` (lines 251-312).

- [ ] **Step 3: Build JS**

Run: `npm run build`
Expected: successful build, no errors

- [ ] **Step 4: Run JS tests**

Run: `npm test`
Expected: all pass

- [ ] **Step 5: Run full test suite**

Run: `rake test`
Expected: all pass (ordered list editors are covered by integration tests)

- [ ] **Step 6: Commit**

```bash
git add app/javascript/utilities/icons.js app/javascript/utilities/ordered_list_editor_utils.js
git commit -m "Extract JS icon builders into shared icons.js utility"
```

---

### Task 6: Final lint pass

**Files:**
- All modified files

- [ ] **Step 1: Run full lint**

Run: `rake lint`
Expected: 0 offenses

- [ ] **Step 2: Run html_safe audit**

Run: `rake lint:html_safe`
Expected: pass (allowlist updated in Task 1)

- [ ] **Step 3: Run full test suite**

Run: `rake test`
Expected: all pass

- [ ] **Step 4: Run JS build and tests**

Run: `npm run build && npm test`
Expected: all pass
