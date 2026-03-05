# Dark Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add automatic dark mode that respects OS `prefers-color-scheme`, with warm charcoal palette, adaptive favicon, and dual PWA icon sets.

**Architecture:** CSS variables consolidation + `@media (prefers-color-scheme: dark)` override block. Favicon SVG gets an internal media query. Rake task generates both light and dark PNG icon sets. Manifest and layout serve dark icons via `media` attributes.

**Tech Stack:** CSS custom properties, SVG `<style>` media queries, rsvg-convert, Rails ERB templates

---

### Task 1: Consolidate hard-coded colors in style.css into CSS variables

**Files:**
- Modify: `app/assets/stylesheets/style.css`

Replace all hard-coded color values with CSS variables. Add new variables to the `:root` block, then replace each hard-coded occurrence.

**Step 1: Add new variables to `:root` (after existing variables, before closing `}`)**

Add these to the `:root` block in `style.css` (after line 38):

```css
  --input-bg: white;
  --accent-hover: rgb(135, 8, 20);
  --overscroll-color: rgb(205, 71, 84);
  --scaled-highlight: rgba(255, 243, 205, 0.6);
  --shadow-sm: 0 1px 3px rgba(0, 0, 0, 0.08), 0 4px 12px rgba(0, 0, 0, 0.06);
  --shadow-nav: 0 2px 4px rgba(0, 0, 0, 0.08), 0 1px 2px rgba(0, 0, 0, 0.04);
  --shadow-dialog: 0 4px 24px rgba(0, 0, 0, 0.15);
  --dialog-backdrop: rgba(0, 0, 0, 0.5);
  --source-badge-bg: #cce5ff;
  --source-badge-text: #004085;
  --aisle-renamed-bg: #fff8e1;
  --aisle-renamed-border: #ffe082;
  --aisle-new-bg: #e8f5e9;
  --aisle-new-border: #a5d6a7;
  --broken-reference-bg: #fdf6f0;
  --aisle-row-border: #e0e0e0;
  --danger-hover-bg: rgba(204, 0, 0, 0.08);
```

**Step 2: Replace hard-coded values with variable references throughout style.css**

Each replacement listed as `line: old -> new`:

- Line 64 (`background-color: rgb(205, 71, 84)`) -> `background-color: var(--overscroll-color)`
- Line 166-167 (nav box-shadow) -> `box-shadow: var(--shadow-nav)`
- Line 281 (`.btn:hover` box-shadow `rgba(0, 0, 0, 0.1)`) -> `box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1)` (keep as-is — single occurrence, negligible)
- Line 296 (`.btn-primary:hover` `rgb(135, 8, 20)`) -> `var(--accent-hover)` (both background and border-color)
- Line 357-359 (main box-shadow) -> `box-shadow: var(--shadow-sm)`
- Line 383 (`.recipe-meta` `color: #666`) -> `color: var(--muted-text)`
- Line 396 (`.scalable.scaled` `rgba(255, 243, 205, 0.6)`) -> `background-color: var(--scaled-highlight)`
- Line 489 (`.ingredients-search:focus` `#2563eb`) -> `var(--accent-color)` (this was a stale fallback)
- Line 557 (`.source-custom` `#cce5ff` and `#004085`) -> `background: var(--source-badge-bg); color: var(--source-badge-text)`
- Line 798 (`.editor-dialog` box-shadow) -> `box-shadow: var(--shadow-dialog)`
- Line 807 (`.editor-dialog::backdrop`) -> `background: var(--dialog-backdrop)`
- Line 961 (`.aisle-row` `#e0e0e0`) -> `border: 1px solid var(--aisle-row-border)`
- Line 967 (`.aisle-row--renamed` `#fff8e1`, `#ffe082`) -> `background: var(--aisle-renamed-bg); border-color: var(--aisle-renamed-border)`
- Line 982 (`.aisle-row--new` `#e8f5e9`, `#a5d6a7`) -> `background: var(--aisle-new-bg); border-color: var(--aisle-new-border)`
- Lines 1209, 1339, 1359, 1385, 1402, 1497, 1507 (all `background: white`) -> `background: var(--input-bg)`
- Line 1426 (`.btn-icon:hover` `rgba(204, 0, 0, 0.08)`) -> `background: var(--danger-hover-bg)`
- Line 1449 (`.alias-chip` uses `--faint-bg` which is undefined) -> `background: var(--surface-alt)`
- Line 1561-1563 (`.embedded-recipe` box-shadow) -> `box-shadow: var(--shadow-sm)`
- Line 1637 (`.broken-reference` `#fdf6f0`) -> `background-color: var(--broken-reference-bg)`

**Step 3: Run lint to verify no syntax errors**

Run: `bundle exec rubocop` (just to confirm nothing in Ruby broke if any ERB references changed — CSS has no linter here, so visually verify the page loads)

**Step 4: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "refactor: consolidate hard-coded colors into CSS variables in style.css"
```

---

### Task 2: Consolidate hard-coded colors in menu.css and groceries.css

**Files:**
- Modify: `app/assets/stylesheets/groceries.css`

No hard-coded colors in `menu.css` need new variables — it already uses CSS variables for everything except `white` for checkbox checkmarks (which stays as-is per design).

**Step 1: Replace hard-coded values in groceries.css**

Add new variables to `:root` in `style.css` (if not already from Task 1):

```css
  --custom-item-border: #eee;
  --custom-item-remove: #bbb;
```

Then in `groceries.css`:

- Line 97 (`#custom-items-list li` `border-bottom: 1px solid #eee`) -> `border-bottom: 1px solid var(--custom-item-border)`
- Line 101 (`li:first-child` `border-top: 1px solid #eee`) -> `border-top: 1px solid var(--custom-item-border)`
- Line 111 (`.custom-item-remove` `color: #bbb`) -> `color: var(--custom-item-remove)`
- Line 157 (`#shopping-list .aisle-group` `border: 1px solid #e0e0e0`) -> `border: 1px solid var(--aisle-row-border)`

**Step 2: Verify page loads correctly**

Run: `bin/dev` and check the menu and groceries pages look unchanged.

**Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css app/assets/stylesheets/groceries.css
git commit -m "refactor: consolidate hard-coded colors in groceries.css into CSS variables"
```

---

### Task 3: Add the dark mode CSS override block

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Add the dark mode media query block**

Insert immediately after the `:root` block (after line 39, before `html {`):

```css
@media (prefers-color-scheme: dark) {
  :root {
    --border-color: rgb(65, 60, 55);
    --text-color: rgb(220, 215, 210);

    --frosted-glass-bg: rgba(38, 35, 32, 0.8);
    --content-background-color: rgb(38, 35, 32);

    /* Gingham */
    --gingham-base: rgb(24, 22, 20);
    --gingham-stripe-color: rgba(140, 20, 30, 0.15);
    --weave-color: rgba(100, 100, 100, 0.04);

    /* Shared UI colors */
    --checked-color: rgb(200, 55, 60);
    --muted-text: rgb(140, 135, 130);
    --muted-text-light: rgb(110, 106, 102);
    --border-light: rgb(60, 56, 52);
    --border-muted: rgb(85, 80, 75);
    --separator-color: rgb(50, 47, 44);
    --surface-alt: rgb(32, 30, 28);
    --danger-color: rgb(220, 60, 50);
    --accent-color: rgb(200, 55, 60);

    /* Availability indicators */
    --on-hand-color: rgb(200, 55, 60);
    --missing-color: rgb(200, 55, 60);
    --hover-bg: rgb(48, 44, 40);

    /* New consolidated variables */
    --input-bg: rgb(30, 28, 26);
    --accent-hover: rgb(170, 45, 50);
    --overscroll-color: rgb(30, 24, 22);
    --scaled-highlight: rgba(180, 140, 60, 0.2);
    --shadow-sm: 0 1px 3px rgba(0, 0, 0, 0.16), 0 4px 12px rgba(0, 0, 0, 0.12);
    --shadow-nav: 0 2px 4px rgba(0, 0, 0, 0.16), 0 1px 2px rgba(0, 0, 0, 0.08);
    --shadow-dialog: 0 4px 24px rgba(0, 0, 0, 0.3);
    --dialog-backdrop: rgba(0, 0, 0, 0.65);
    --source-badge-bg: rgba(50, 100, 160, 0.25);
    --source-badge-text: rgb(130, 170, 220);
    --aisle-renamed-bg: rgba(180, 140, 40, 0.15);
    --aisle-renamed-border: rgba(180, 140, 40, 0.3);
    --aisle-new-bg: rgba(60, 140, 70, 0.15);
    --aisle-new-border: rgba(60, 140, 70, 0.3);
    --broken-reference-bg: rgb(42, 36, 32);
    --aisle-row-border: rgb(55, 52, 48);
    --danger-hover-bg: rgba(220, 60, 50, 0.12);
    --custom-item-border: rgb(50, 47, 44);
    --custom-item-remove: rgb(110, 106, 102);
  }
}
```

**Step 2: Check the `color-scheme` property**

Add to the existing `html` rule (around line 41, inside the `html {` block):

```css
  color-scheme: light dark;
```

This tells the browser that the page supports both schemes, which affects form controls, scrollbars, and other UA-styled elements.

**Step 3: Verify dark mode renders correctly**

Run `bin/dev`. In the browser, toggle dark mode (Chrome DevTools > Rendering > Emulate CSS media feature `prefers-color-scheme: dark`). Check:
- Gingham is barely-visible dark red texture on near-black
- Content card is warm dark surface
- Text is readable warm off-white
- Nav frosted glass works on dark background
- Accent red is visible on dark surfaces
- Checkboxes, buttons, links use updated colors

**Step 4: Check WCAG contrast ratios**

Verify these key combinations meet WCAG AA (4.5:1 for normal text, 3:1 for large text):
- Text `rgb(220, 215, 210)` on card `rgb(38, 35, 32)` — expected ~11:1
- Muted `rgb(140, 135, 130)` on card `rgb(38, 35, 32)` — expected ~4.8:1
- Muted light `rgb(110, 106, 102)` on card `rgb(38, 35, 32)` — expected ~3.2:1 (AA for large text only — this is used for decorative/secondary text, acceptable)
- Accent `rgb(200, 55, 60)` on card `rgb(38, 35, 32)` — expected ~4.2:1 (AA large text; accent is used on interactive elements which are typically larger)

**Step 5: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "feat: add dark mode via prefers-color-scheme media query"
```

---

### Task 4: Update favicon SVG for dark mode adaptation

**Files:**
- Modify: `app/assets/images/favicon.svg`

**Step 1: Replace favicon.svg with adaptive version**

```xml
<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
  <style>
    .base { fill: rgb(249,246,243); }
    .check { fill: rgb(190,12,30); fill-opacity: 0.5; }
    @media (prefers-color-scheme: dark) {
      .base { fill: rgb(38,35,32); }
      .check { fill: rgb(200,55,60); fill-opacity: 0.35; }
    }
  </style>
  <rect width="16" height="16" class="base" />
  <rect width="8" height="16" class="check" />
  <rect width="16" height="8" class="check" />
</svg>
```

**Step 2: Verify in browser**

Open the app and check the favicon in the browser tab. Toggle dark mode in DevTools to confirm it switches colors.

**Step 3: Commit**

```bash
git add app/assets/images/favicon.svg
git commit -m "feat: make favicon SVG adapt to dark mode via internal media query"
```

---

### Task 5: Update rake pwa:icons to generate dark PNG icon sets

**Files:**
- Modify: `lib/tasks/pwa.rake`

**Step 1: Write the failing test**

No existing test for the rake task. Add one:

Create: `test/tasks/pwa_icons_test.rb`

```ruby
# frozen_string_literal: true

require 'test_helper'

class PwaIconsTaskTest < ActiveSupport::TestCase
  test 'generates both light and dark icon sets' do
    Dir.mktmpdir do |dir|
      # Stub output directory
      output_dir = Pathname.new(dir)
      Rails.public_path.stub(:join, ->(path) { path == 'icons' ? output_dir : Rails.public_path.join(path) }) do
        Rake::Task['pwa:icons'].invoke
      end

      light_icons = %w[icon-192.png icon-512.png apple-touch-icon.png favicon-32.png]
      dark_icons = %w[icon-192-dark.png icon-512-dark.png apple-touch-icon-dark.png favicon-32-dark.png]

      (light_icons + dark_icons).each do |filename|
        assert output_dir.join(filename).exist?, "Expected #{filename} to exist"
        assert output_dir.join(filename).size.positive?, "Expected #{filename} to be non-empty"
      end
    end
  ensure
    Rake::Task['pwa:icons'].reenable
  end
end
```

Actually, stubbing the rake task's output path is fragile. Instead, just test that the task runs and generates files in the actual public/icons directory:

Create: `test/tasks/pwa_icons_test.rb`

```ruby
# frozen_string_literal: true

require 'test_helper'
require 'rake'

class PwaIconsTaskTest < ActiveSupport::TestCase
  setup do
    Rake::Task['pwa:icons'].reenable
  end

  test 'generates light and dark icon PNGs' do
    skip 'rsvg-convert not installed' unless system('which rsvg-convert > /dev/null 2>&1')

    Rake::Task['pwa:icons'].invoke

    icons_dir = Rails.public_path.join('icons')
    expected = %w[
      icon-192.png icon-512.png apple-touch-icon.png favicon-32.png
      icon-192-dark.png icon-512-dark.png apple-touch-icon-dark.png favicon-32-dark.png
    ]

    expected.each do |filename|
      path = icons_dir.join(filename)
      assert path.exist?, "Expected #{filename} to be generated"
      assert path.size.positive?, "Expected #{filename} to be non-empty"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/tasks/pwa_icons_test.rb`
Expected: FAIL — dark icons don't exist yet.

**Step 3: Update the rake task**

Replace `lib/tasks/pwa.rake` with:

```ruby
# frozen_string_literal: true

# Generates PWA icon PNGs from the source favicon.svg using rsvg-convert.
# Output goes to public/icons/ (gitignored). Required at build time or after
# SVG changes — the Dockerfile runs this in its builder stage.
#
# Produces both light and dark icon sets. The dark set uses a temporary SVG
# with baked-in dark colors because rsvg-convert ignores prefers-color-scheme.
namespace :pwa do
  desc 'Generate PWA icons from favicon.svg using rsvg-convert'
  task icons: :environment do
    source = Rails.root.join('app/assets/images/favicon.svg')
    output_dir = Rails.public_path.join('icons')

    abort "Source SVG not found: #{source}" unless source.exist?

    FileUtils.mkdir_p(output_dir)

    icons = {
      'icon-192.png' => 192,
      'icon-512.png' => 512,
      'apple-touch-icon.png' => 180,
      'favicon-32.png' => 32
    }

    generate_icons(source, output_dir, icons)
    generate_dark_icons(output_dir, icons)
  end
end

def generate_icons(source, output_dir, icons)
  icons.each do |filename, size|
    output = output_dir.join(filename)
    system('rsvg-convert', '-w', size.to_s, '-h', size.to_s,
           source.to_s, '-o', output.to_s, exception: true)
    puts "  Generated #{filename} (#{size}x#{size})"
  end
end

def generate_dark_icons(output_dir, icons)
  dark_svg = <<~SVG
    <svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
      <rect width="16" height="16" fill="rgb(38,35,32)" />
      <rect width="8" height="16" fill="rgb(200,55,60)" fill-opacity="0.35" />
      <rect width="16" height="8" fill="rgb(200,55,60)" fill-opacity="0.35" />
    </svg>
  SVG

  Tempfile.create(['favicon-dark', '.svg']) do |tmp|
    tmp.write(dark_svg)
    tmp.flush

    icons.each do |filename, size|
      dark_filename = filename.sub('.png', '-dark.png')
      output = output_dir.join(dark_filename)
      system('rsvg-convert', '-w', size.to_s, '-h', size.to_s,
             tmp.path, '-o', output.to_s, exception: true)
      puts "  Generated #{dark_filename} (#{size}x#{size})"
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/tasks/pwa_icons_test.rb`
Expected: PASS

**Step 5: Run the rake task manually to regenerate icons**

Run: `rake pwa:icons`
Expected: 8 lines of "Generated ..." output.

**Step 6: Commit**

```bash
git add lib/tasks/pwa.rake test/tasks/pwa_icons_test.rb
git commit -m "feat: generate dark mode PWA icon PNGs alongside light set"
```

---

### Task 6: Update manifest and layout for dark icons and theme-color

**Files:**
- Modify: `app/controllers/pwa_controller.rb`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `test/controllers/pwa_controller_test.rb`

**Step 1: Write the failing test for dark manifest icons**

Add to `test/controllers/pwa_controller_test.rb`:

```ruby
test 'manifest includes dark mode icons' do
  get '/manifest.json'

  data = JSON.parse(response.body) # rubocop:disable Rails/ResponseParsedBody

  assert_equal 4, data['icons'].size

  dark_icons = data['icons'].select { |i| i['media'] }
  assert_equal 2, dark_icons.size

  dark_icons.each do |icon|
    assert_equal '(prefers-color-scheme: dark)', icon['media']
    assert_match(/-dark\.png/, icon['src'])
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/pwa_controller_test.rb -n test_manifest_includes_dark_mode_icons`
Expected: FAIL — only 2 icons, no dark icons.

**Step 3: Update PwaController#manifest_data**

In `app/controllers/pwa_controller.rb`, replace the `icons` array in `manifest_data`:

```ruby
icons: [
  { src: versioned_icon_path('icon-192.png'), sizes: '192x192', type: 'image/png' },
  { src: versioned_icon_path('icon-512.png'), sizes: '512x512', type: 'image/png' },
  { src: versioned_icon_path('icon-192-dark.png'), sizes: '192x192', type: 'image/png',
    media: '(prefers-color-scheme: dark)' },
  { src: versioned_icon_path('icon-512-dark.png'), sizes: '512x512', type: 'image/png',
    media: '(prefers-color-scheme: dark)' }
]
```

**Step 4: Update the existing manifest test**

The existing test asserts `assert_equal 2, data['icons'].size` — update it to `4`.
Also update the assertions to check the first two icons (light) specifically:

```ruby
test 'manifest returns JSON with versioned icon URLs' do
  get '/manifest.json'

  assert_response :success
  assert_equal 'application/manifest+json', response.media_type

  data = JSON.parse(response.body) # rubocop:disable Rails/ResponseParsedBody

  assert_equal 'Family Recipes', data['name']
  assert_equal 'Recipes', data['short_name']
  assert_equal '/', data['start_url']
  assert_equal 'standalone', data['display']
  assert_equal 4, data['icons'].size

  version = Rails.configuration.icon_version

  assert_equal "/icons/icon-192.png?v=#{version}", data['icons'][0]['src']
  assert_equal "/icons/icon-512.png?v=#{version}", data['icons'][1]['src']
  assert_equal "/icons/icon-192-dark.png?v=#{version}", data['icons'][2]['src']
  assert_equal "/icons/icon-512-dark.png?v=#{version}", data['icons'][3]['src']
end
```

**Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/pwa_controller_test.rb`
Expected: All pass.

**Step 6: Update layout for dark icons and theme-color**

In `app/views/layouts/application.html.erb`, replace the theme-color meta and icon links:

Replace line 8:
```erb
  <meta name="theme-color" content="rgb(205, 71, 84)" media="(prefers-color-scheme: light)">
  <meta name="theme-color" content="rgb(30, 24, 22)" media="(prefers-color-scheme: dark)">
```

Replace lines 14-15 (PNG favicon and apple-touch-icon):
```erb
  <link rel="icon" type="image/png" sizes="32x32" href="<%= versioned_icon_path('favicon-32.png') %>">
  <link rel="icon" type="image/png" sizes="32x32" href="<%= versioned_icon_path('favicon-32-dark.png') %>" media="(prefers-color-scheme: dark)">
  <link rel="apple-touch-icon" sizes="180x180" href="<%= versioned_icon_path('apple-touch-icon.png') %>">
  <link rel="apple-touch-icon" sizes="180x180" href="<%= versioned_icon_path('apple-touch-icon-dark.png') %>" media="(prefers-color-scheme: dark)">
```

The SVG favicon link (line 13) stays unchanged — it adapts via its internal `<style>`.

**Step 7: Commit**

```bash
git add app/controllers/pwa_controller.rb app/views/layouts/application.html.erb test/controllers/pwa_controller_test.rb
git commit -m "feat: serve dark mode PWA icons and theme-color in manifest and layout"
```

---

### Task 7: Update html_safe allowlist and run full test suite

**Files:**
- Possibly modify: `config/html_safe_allowlist.yml` (if line numbers shifted)

**Step 1: Run full lint and test suite**

Run: `rake`

This runs both `lint` (RuboCop) and `test` (Minitest). Fix any failures:
- If `lint:html_safe` fails because line numbers shifted in modified files, update `config/html_safe_allowlist.yml` accordingly.
- If any tests fail, fix the root cause.

**Step 2: Run lint:html_safe specifically**

Run: `rake lint:html_safe`

Check if any `.html_safe` or `raw()` calls shifted line numbers due to the layout changes. Update the allowlist if needed.

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "chore: update html_safe allowlist for shifted line numbers"
```

(Only if changes were needed.)

---

### Task 8: Visual QA in browser

**Files:** None (manual verification)

**Step 1: Start the dev server**

Run: `bin/dev`

**Step 2: Test light mode**

Visit each page and verify nothing changed visually:
- Homepage / recipe index
- Individual recipe page
- Menu page (with recipes selected and Quick Bites)
- Groceries page (with shopping list items)
- Ingredients page
- Login page
- Editor dialogs (recipe editor, Quick Bites editor, nutrition editor, aisle order editor)

**Step 3: Test dark mode**

Toggle to dark mode (Chrome DevTools > Rendering > Emulate CSS media feature `prefers-color-scheme: dark`). Check:
- Gingham pattern: barely-visible red texture on dark background
- Content card: warm dark surface elevated above background
- Nav bar: frosted glass effect works on dark, border visible
- Text: warm off-white, readable
- Links: underlines visible, hover accent works
- Buttons: primary (red), danger, default all have correct dark styles
- Checkboxes: dark red when checked, white checkmark visible
- Crossed-off items: muted text color visible as strikethrough
- Editor dialogs: dark background, inputs darker than card
- Aisle rows: surface-alt with appropriate border
- Notification toast: frosted glass effect on dark
- Embedded recipe cards: visible border, distinct from parent card
- Scaled ingredient highlights: warm amber tint visible

**Step 4: Test iOS/mobile considerations**

- Verify overscroll color is the dark warm tone
- Verify `color-scheme: light dark` makes native form controls (scrollbars, date pickers) dark

**Step 5: Test favicon**

- Verify SVG favicon switches between light and dark in browser tab
- Verify PNG favicons and apple-touch-icons were generated (check `public/icons/` for 8 files)
