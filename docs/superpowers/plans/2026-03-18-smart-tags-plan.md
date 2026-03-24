# Smart Tags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add colored emoji-decorated tag pills for curated tags, with a Kitchen-level toggle to disable.

**Architecture:** A frozen Ruby constant (`SmartTagRegistry`) maps tag names to emoji/color/style config. A helper converts this to CSS classes + data attributes. CSS `::before` renders emoji, `::after` renders crossout ✕. JS controllers read the registry from an embedded JSON blob.

**Tech Stack:** Rails 8, Stimulus, CSS custom properties, SQLite

**Spec:** `docs/plans/2026-03-18-smart-tags-design.md`

---

### Task 1: SmartTagRegistry Module

**Files:**
- Create: `lib/familyrecipes/smart_tag_registry.rb`
- Modify: `lib/familyrecipes.rb` (add require)
- Create: `test/smart_tag_registry_test.rb`

- [ ] **Step 1: Write the test file**

```ruby
# test/smart_tag_registry_test.rb
require 'minitest/autorun'
require_relative '../lib/familyrecipes'

class SmartTagRegistryTest < Minitest::Test
  def test_lookup_known_tag
    entry = FamilyRecipes::SmartTagRegistry.lookup("vegetarian")

    assert_equal "🌿", entry[:emoji]
    assert_equal :green, entry[:color]
  end

  def test_lookup_crossout_tag
    entry = FamilyRecipes::SmartTagRegistry.lookup("gluten-free")

    assert_equal :crossout, entry[:style]
    assert_equal :amber, entry[:color]
  end

  def test_lookup_cuisine_tag
    entry = FamilyRecipes::SmartTagRegistry.lookup("thai")

    assert_equal "🇹🇭", entry[:emoji]
    assert_equal :cuisine, entry[:color]
  end

  def test_lookup_unknown_tag_returns_nil
    assert_nil FamilyRecipes::SmartTagRegistry.lookup("unknown-tag")
  end

  def test_tags_frozen
    assert FamilyRecipes::SmartTagRegistry::TAGS.frozen?
  end

  def test_all_entries_have_required_keys
    FamilyRecipes::SmartTagRegistry::TAGS.each do |name, entry|
      assert entry.key?(:emoji), "#{name} missing :emoji"
      assert entry.key?(:color), "#{name} missing :color"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/smart_tag_registry_test.rb`
Expected: FAIL — `SmartTagRegistry` not defined

- [ ] **Step 3: Create the registry module**

Create `lib/familyrecipes/smart_tag_registry.rb` with the `TAGS` hash and
`self.lookup` method per the spec. Emoji choices are provisional — they'll be
curated in a dedicated session (Task 8).

Header comment:
```ruby
# Curated smart tag definitions — maps tag names to visual decorations
# (emoji, color group, optional crossout style). Purely presentational;
# tags not in this registry render as neutral pills.
#
# Collaborators:
# - SmartTagHelper: reads this to build CSS classes + data attributes
# - search_overlay_controller.js / tag_input_controller.js: consume JSON
#   version embedded in the layout
# - style.css: defines the .tag-pill--{color} and .tag-pill--crossout classes
```

- [ ] **Step 4: Add require to lib/familyrecipes.rb**

Add after the `usda_portion_classifier` require (line 106):

```ruby
require_relative 'familyrecipes/smart_tag_registry'
```

- [ ] **Step 5: Run test to verify it passes**

Run: `ruby -Itest test/smart_tag_registry_test.rb`
Expected: 6 tests, all PASS

- [ ] **Step 6: Add test to RuboCop exclusion**

This is a plain `Minitest::Test` file (not ActiveSupport). Add to the
`Rails/RefuteMethods` exclusion list in `.rubocop.yml` alongside the other
parser tests.

- [ ] **Step 7: Run lint**

Run: `bundle exec rubocop lib/familyrecipes/smart_tag_registry.rb test/smart_tag_registry_test.rb`
Expected: 0 offenses

- [ ] **Step 8: Commit**

```
git add lib/familyrecipes/smart_tag_registry.rb lib/familyrecipes.rb \
  test/smart_tag_registry_test.rb .rubocop.yml
git commit -m "Add SmartTagRegistry with curated tag decorations (#252)"
```

---

### Task 2: Migration + Settings Toggle

**Files:**
- Create: `db/migrate/011_add_decorate_tags_to_kitchens.rb`
- Modify: `app/controllers/settings_controller.rb`
- Modify: `app/views/settings/_dialog.html.erb`
- Modify: `app/javascript/controllers/settings_editor_controller.js`
- Create: `test/controllers/settings_decorate_tags_test.rb`

- [ ] **Step 1: Write the test**

```ruby
# test/controllers/settings_decorate_tags_test.rb
require "test_helper"

class SettingsDecorateTagsTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    log_in
  end

  test "show includes decorate_tags" do
    get settings_path(kitchen_slug:), headers: { "Accept" => "application/json" }

    data = JSON.parse(response.body)

    assert data.key?("decorate_tags")
    assert_equal true, data["decorate_tags"]
  end

  test "update decorate_tags" do
    patch settings_path(kitchen_slug:),
          params: { kitchen: { decorate_tags: false } },
          headers: { "Content-Type" => "application/json", "Accept" => "application/json" },
          as: :json

    assert_response :success
    assert_equal false, @kitchen.reload.decorate_tags
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/settings_decorate_tags_test.rb`
Expected: FAIL — `decorate_tags` column doesn't exist

- [ ] **Step 3: Create migration**

```ruby
# db/migrate/011_add_decorate_tags_to_kitchens.rb
class AddDecorateTagsToKitchens < ActiveRecord::Migration[8.0]
  def change
    add_column :kitchens, :decorate_tags, :boolean, default: true, null: false
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 4: Update SettingsController**

In `app/controllers/settings_controller.rb`:

Add `decorate_tags: current_kitchen.decorate_tags` to the `show` JSON hash
(after `show_nutrition` on line 19).

Add `:decorate_tags` to the `params.expect` array in `settings_params`
(line 35-36).

- [ ] **Step 5: Update settings dialog HTML**

In `app/views/settings/_dialog.html.erb`, add a new checkbox after the
`show_nutrition` field (after line 44, before the `</fieldset>`):

```erb
<div class="settings-field">
  <label class="settings-checkbox-label">
    <input type="checkbox" id="settings-decorate-tags"
           data-settings-editor-target="decorateTags">
    Decorate special tags
  </label>
  <span class="settings-field-hint">Show emoji and colors for dietary, cuisine, and other recognized tags</span>
</div>
```

- [ ] **Step 6: Update settings_editor_controller.js**

In `app/javascript/controllers/settings_editor_controller.js`:

Add `"decorateTags"` to the `static targets` array (line 15).

Then add `decorateTags` handling to all six methods that reference
`showNutrition`, following the exact same pattern:

- `openDialog` (line 57): `this.decorateTagsTarget.checked = !!data.decorate_tags`
- `collect` (line 77): `decorate_tags: this.decorateTagsTarget.checked`
- `provideSaveFn` (line 97): `decorate_tags: this.decorateTagsTarget.checked`
- `checkModified` (line 111): `|| this.decorateTagsTarget.checked !== this.originals.decorateTags`
- `reset` (line 121): `this.decorateTagsTarget.checked = this.originals.decorateTags`
- `storeOriginals` (line 131): `decorateTags: this.decorateTagsTarget.checked`
- `disableFields` (line 138): add `this.decorateTagsTarget` to the array

- [ ] **Step 7: Run tests**

Run: `ruby -Itest test/controllers/settings_decorate_tags_test.rb`
Expected: PASS

- [ ] **Step 8: Run full test suite and lint**

Run: `bundle exec rubocop && rake test`
Expected: 0 offenses, all tests pass

- [ ] **Step 9: Commit**

```
git add db/migrate/011_add_decorate_tags_to_kitchens.rb \
  app/controllers/settings_controller.rb \
  app/views/settings/_dialog.html.erb \
  app/javascript/controllers/settings_editor_controller.js \
  test/controllers/settings_decorate_tags_test.rb
git commit -m "Add decorate_tags Kitchen setting (#252)"
```

---

### Task 3: CSS Smart Tag Styles

**Files:**
- Modify: `app/assets/stylesheets/style.css`

- [ ] **Step 1: Add light-mode custom properties**

In `style.css`, add inside the `:root` block (after the `--cat-text` variable
at line 52):

```css
/* Smart tag color groups */
--smart-green-bg: #d4edda;    --smart-green-text: #1b5e20;
--smart-amber-bg: #fff3cd;    --smart-amber-text: #7a5d00;
--smart-blue-bg: #d6eaf8;     --smart-blue-text: #1a4a6e;
--smart-purple-bg: #e8daf5;   --smart-purple-text: #4a2080;
--smart-cuisine-bg: #f5ddd0;  --smart-cuisine-text: #6e3a22;
```

- [ ] **Step 2: Add dark-mode custom properties**

In the `@media (prefers-color-scheme: dark) { :root { ... } }` block, add
after `--cat-text` (line 99):

```css
/* Smart tag color groups */
--smart-green-bg: #1a3a1e;    --smart-green-text: #a8d8a0;
--smart-amber-bg: #3a3018;    --smart-amber-text: #d8c070;
--smart-blue-bg: #1a2e3e;     --smart-blue-text: #90c0e0;
--smart-purple-bg: #2a1e3a;   --smart-purple-text: #c0a8e0;
--smart-cuisine-bg: #3a2820;  --smart-cuisine-text: #d8b0a0;
```

- [ ] **Step 3: Add smart tag pill classes**

After the existing `.tag-pill--category` rule (around line 1506), add:

```css
/* Smart tag color variants + --pill-bg for crossout halo */
.tag-pill--green   { background: var(--smart-green-bg);   color: var(--smart-green-text);   --pill-bg: var(--smart-green-bg); }
.tag-pill--amber   { background: var(--smart-amber-bg);   color: var(--smart-amber-text);   --pill-bg: var(--smart-amber-bg); }
.tag-pill--blue    { background: var(--smart-blue-bg);     color: var(--smart-blue-text);    --pill-bg: var(--smart-blue-bg); }
.tag-pill--purple  { background: var(--smart-purple-bg);   color: var(--smart-purple-text);  --pill-bg: var(--smart-purple-bg); }
.tag-pill--cuisine { background: var(--smart-cuisine-bg);  color: var(--smart-cuisine-text); --pill-bg: var(--smart-cuisine-bg); }

/* Emoji prefix via data attribute */
.tag-pill[data-smart-emoji]::before {
  content: attr(data-smart-emoji);
  margin-right: 0.3em;
  font-size: 0.85em;
}

/* Crossout ✕ badge */
.tag-pill--crossout { position: relative; }
.tag-pill--crossout::after {
  content: "✕";
  position: absolute;
  bottom: -0.15em;
  right: -0.3em;
  font-size: 0.7em;
  font-weight: 900;
  color: #c44;
  line-height: 1;
  text-shadow:
    -1px -1px 0 var(--pill-bg),
     1px -1px 0 var(--pill-bg),
    -1px  1px 0 var(--pill-bg),
     1px  1px 0 var(--pill-bg);
}
```

- [ ] **Step 4: Add settings field hint style**

Add after the `.settings-checkbox-label` rule:

```css
.settings-field-hint {
  display: block;
  font-size: 0.72rem;
  color: var(--text-soft);
  margin-top: 0.1rem;
  padding-left: 1.45rem;
}
```

- [ ] **Step 5: Verify visually**

Start dev server (`bin/dev`), open a recipe with tags. Tags should still
render with neutral styling (no smart tag helper wired up yet). The CSS is
ready for when we wire it up.

- [ ] **Step 6: Commit**

```
git add app/assets/stylesheets/style.css
git commit -m "Add smart tag CSS: color variants, emoji prefix, crossout badge (#252)"
```

---

### Task 4: SmartTagHelper + Server-Side Rendering

**Files:**
- Create: `app/helpers/smart_tag_helper.rb`
- Modify: `app/views/recipes/_recipe_content.html.erb`
- Create: `test/helpers/smart_tag_helper_test.rb`
- Modify: `test/integration/recipe_tags_display_test.rb` (or create new)

- [ ] **Step 1: Write helper test**

```ruby
# test/helpers/smart_tag_helper_test.rb
require "test_helper"

class SmartTagHelperTest < ActionView::TestCase
  include SmartTagHelper

  setup do
    @kitchen = Kitchen.new(decorate_tags: true)
  end

  test "returns color class and emoji data for known tag" do
    attrs = smart_tag_pill_attrs("vegetarian", kitchen: @kitchen)

    assert_includes attrs[:class], "tag-pill--green"
    assert_equal "🌿", attrs[:data][:smart_emoji]
  end

  test "returns crossout class for crossout tag" do
    attrs = smart_tag_pill_attrs("gluten-free", kitchen: @kitchen)

    assert_includes attrs[:class], "tag-pill--amber"
    assert_includes attrs[:class], "tag-pill--crossout"
  end

  test "returns empty hash for unknown tag" do
    attrs = smart_tag_pill_attrs("random-tag", kitchen: @kitchen)

    assert_equal({}, attrs)
  end

  test "returns empty hash when decorations disabled" do
    @kitchen.decorate_tags = false
    attrs = smart_tag_pill_attrs("vegetarian", kitchen: @kitchen)

    assert_equal({}, attrs)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/helpers/smart_tag_helper_test.rb`
Expected: FAIL — `SmartTagHelper` not found

- [ ] **Step 3: Create the helper**

```ruby
# app/helpers/smart_tag_helper.rb
# frozen_string_literal: true

# Bridges SmartTagRegistry to views — returns CSS classes and data attributes
# for tag pills based on the curated registry. Returns empty hash for unknown
# tags or when decorations are disabled.
#
# Collaborators:
# - FamilyRecipes::SmartTagRegistry: the curated tag definitions
# - Kitchen#decorate_tags: per-kitchen toggle
# - _recipe_content.html.erb: server-rendered tag pills
module SmartTagHelper
  def smart_tag_pill_attrs(tag_name, kitchen: current_kitchen)
    return {} unless kitchen.decorate_tags

    entry = FamilyRecipes::SmartTagRegistry.lookup(tag_name)
    return {} unless entry

    classes = ["tag-pill--#{entry[:color]}"]
    classes << "tag-pill--crossout" if entry[:style] == :crossout

    { class: classes, data: { smart_emoji: entry[:emoji] } }
  end
end
```

- [ ] **Step 4: Run helper test**

Run: `ruby -Itest test/helpers/smart_tag_helper_test.rb`
Expected: PASS

- [ ] **Step 5: Update recipe content view**

In `app/views/recipes/_recipe_content.html.erb`, replace the tag pill button
(lines 18-22):

Before:
```erb
<% recipe.tags.sort_by(&:name).each do |tag| %>
  <button type="button" class="recipe-tag-pill tag-pill tag-pill--tag"
          data-action="click->recipe-state#searchTag"
          data-tag="<%= tag.name %>"><%= tag.name %></button>
<% end %>
```

After:
```erb
<% recipe.tags.sort_by(&:name).each do |tag| %>
  <% smart = smart_tag_pill_attrs(tag.name) %>
  <button type="button"
          class="recipe-tag-pill tag-pill tag-pill--tag <%= smart.dig(:class)&.join(' ') %>"
          data-action="click->recipe-state#searchTag"
          data-tag="<%= tag.name %>"
          <%= "data-smart-emoji=\"#{smart.dig(:data, :smart_emoji)}\"" if smart.dig(:data, :smart_emoji) %>><%= tag.name %></button>
<% end %>
```

- [ ] **Step 6: Write integration test**

```ruby
# test/integration/smart_tags_display_test.rb
require "test_helper"

class SmartTagsDisplayTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test "recipe page renders smart tag classes when enabled" do
    recipe = RecipeWriteService.create(kitchen: @kitchen, markdown: "# Test\n\nStep 1", tags: ["vegetarian"])

    get recipe_path(recipe, kitchen_slug:)

    assert_select "button.tag-pill--green[data-smart-emoji='🌿']", text: "vegetarian"
  end

  test "recipe page renders neutral pills when decorations disabled" do
    @kitchen.update!(decorate_tags: false)
    recipe = RecipeWriteService.create(kitchen: @kitchen, markdown: "# Test\n\nStep 1", tags: ["vegetarian"])

    get recipe_path(recipe, kitchen_slug:)

    assert_select "button.tag-pill--green", count: 0
    assert_select "button.tag-pill--tag", text: "vegetarian"
  end
end
```

- [ ] **Step 7: Run tests**

Run: `ruby -Itest test/helpers/smart_tag_helper_test.rb test/integration/smart_tags_display_test.rb`
Expected: PASS

- [ ] **Step 8: Run full suite and lint**

Run: `bundle exec rubocop app/helpers/smart_tag_helper.rb && rake test`
Expected: 0 offenses, all tests pass

- [ ] **Step 9: Commit**

```
git add app/helpers/smart_tag_helper.rb app/views/recipes/_recipe_content.html.erb \
  test/helpers/smart_tag_helper_test.rb test/integration/smart_tags_display_test.rb
git commit -m "Wire SmartTagHelper into recipe tag pills (#252)"
```

---

### Task 5: JS Registry Embed + Search Overlay

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/helpers/smart_tag_helper.rb` (add `smart_tags_json` method)
- Modify: `app/javascript/controllers/search_overlay_controller.js`
- Modify: `config/html_safe_allowlist.yml`

- [ ] **Step 1: Add JSON embed helper**

Add to `app/helpers/smart_tag_helper.rb`:

```ruby
def smart_tags_json
  FamilyRecipes::SmartTagRegistry::TAGS.to_json
end
```

- [ ] **Step 2: Add JSON script tag to layout**

In `app/views/layouts/application.html.erb`, add after the search overlay
render (line 34), before settings:

```erb
<% if current_kitchen&.decorate_tags %>
  <script type="application/json" nonce="<%= content_security_policy_nonce %>" data-smart-tags><%= smart_tags_json.html_safe %></script>
<% end %>
```

- [ ] **Step 3: Update html_safe_allowlist.yml**

Add the new `.html_safe` call to `config/html_safe_allowlist.yml` with the
correct `file:line_number` key. The comment should note it's a hardcoded
constant with no user content.

- [ ] **Step 4: Update search overlay controller**

In `app/javascript/controllers/search_overlay_controller.js`:

Add a method to load the smart tag registry:

```javascript
loadSmartTags() {
  const el = document.querySelector('script[data-smart-tags]')
  this.smartTags = el ? JSON.parse(el.textContent) : null
}
```

Call `this.loadSmartTags()` in the `connect()` method.

Update `renderPills()` to apply smart tag styling. After creating the span
(line 162), add:

```javascript
if (this.smartTags && pill.type === "tag") {
  const entry = this.smartTags[pill.text]
  if (entry) {
    span.classList.add(`tag-pill--${entry.color}`)
    if (entry.style === "crossout") span.classList.add("tag-pill--crossout")
    span.dataset.smartEmoji = entry.emoji
  }
}
```

- [ ] **Step 5: Run lint and tests**

Run: `rake lint:html_safe && rake test`
Expected: PASS

- [ ] **Step 6: Commit**

```
git add app/helpers/smart_tag_helper.rb app/views/layouts/application.html.erb \
  app/javascript/controllers/search_overlay_controller.js \
  config/html_safe_allowlist.yml
git commit -m "Embed smart tag registry in layout, apply in search overlay (#252)"
```

---

### Task 6: Tag Input Controller

**Files:**
- Modify: `app/javascript/controllers/tag_input_controller.js`

- [ ] **Step 1: Load smart tags in tag input controller**

In `app/javascript/controllers/tag_input_controller.js`, add a
`loadSmartTags()` method (same pattern as search overlay):

```javascript
loadSmartTags() {
  const el = document.querySelector('script[data-smart-tags]')
  this.smartTags = el ? JSON.parse(el.textContent) : null
}
```

Call `this.loadSmartTags()` in the `connect()` method.

- [ ] **Step 2: Update renderPills to apply smart styling**

In the `renderPills()` method (line 115-131), after setting
`pill.className = "tag-pill tag-pill--tag"` (line 119), add:

```javascript
if (this.smartTags) {
  const entry = this.smartTags[name]
  if (entry) {
    pill.classList.add(`tag-pill--${entry.color}`)
    if (entry.style === "crossout") pill.classList.add("tag-pill--crossout")
    pill.dataset.smartEmoji = entry.emoji
  }
}
```

- [ ] **Step 3: Optionally add emoji to autocomplete dropdown**

In the `showAutocomplete()` method (line 145+), when building `nameSpan`,
prepend the emoji if available:

```javascript
if (this.smartTags) {
  const entry = this.smartTags[tag]
  if (entry) nameSpan.textContent = `${entry.emoji} ${tag}`
}
```

- [ ] **Step 4: Test manually**

Start dev server, open recipe editor, verify:
- Tag pills in editor show emoji + colors
- Autocomplete dropdown shows emoji
- Tags still add/remove correctly

- [ ] **Step 5: Commit**

```
git add app/javascript/controllers/tag_input_controller.js
git commit -m "Apply smart tag styling in tag input editor (#252)"
```

---

### Task 7: Integration Tests + Cleanup

**Files:**
- Create: `test/integration/smart_tags_search_test.rb`

- [ ] **Step 1: Write search overlay integration test**

```ruby
# test/integration/smart_tags_search_test.rb
require "test_helper"

class SmartTagsSearchTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test "layout embeds smart tags JSON when enabled" do
    RecipeWriteService.create(kitchen: @kitchen, markdown: "# Test\n\nStep 1")

    get home_path(kitchen_slug:)

    assert_select 'script[data-smart-tags]'
  end

  test "layout omits smart tags JSON when disabled" do
    @kitchen.update!(decorate_tags: false)
    RecipeWriteService.create(kitchen: @kitchen, markdown: "# Test\n\nStep 1")

    get home_path(kitchen_slug:)

    assert_select 'script[data-smart-tags]', count: 0
  end
end
```

- [ ] **Step 2: Run all tests**

Run: `rake test`
Expected: All pass

- [ ] **Step 3: Run full lint**

Run: `rake lint`
Expected: 0 offenses

- [ ] **Step 4: Commit**

```
git add test/integration/smart_tags_search_test.rb
git commit -m "Add smart tags integration tests (#252)"
```

---

### Task 8: Emoji Curation Session

This is a collaborative session with the user using the visual companion. The
registry from Task 1 has provisional emoji — this task is where we finalize
the full tag list and emoji choices.

**Files:**
- Modify: `lib/familyrecipes/smart_tag_registry.rb`

- [ ] **Step 1: Present full registry in visual companion**

Build an HTML mockup showing all current smart tag entries rendered as styled
pills (using the actual CSS from Task 3). Group by color category.

- [ ] **Step 2: Iterate with user on emoji choices**

Walk through each category. Consider:
- Does the emoji read well at small sizes?
- Is it funny/playful where appropriate?
- Do the "-free" crossouts look right with these specific emoji?
- Any tags to add or remove from the curated list?
- Any new cuisines, dietary restrictions, or categories?

- [ ] **Step 3: Update registry and commit**

Update `lib/familyrecipes/smart_tag_registry.rb` with final choices.

Run: `ruby -Itest test/smart_tag_registry_test.rb && rake test`

```
git add lib/familyrecipes/smart_tag_registry.rb
git commit -m "Finalize smart tag emoji curation (#252)

Resolves #252"
```
