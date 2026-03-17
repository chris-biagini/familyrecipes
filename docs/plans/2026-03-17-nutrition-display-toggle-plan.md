# Nutrition Display Toggle Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a kitchen-level setting to show/hide the Nutrition Facts label on recipe pages.

**Architecture:** Boolean `show_nutrition` column on Kitchen (default `false`). Toggle lives in the existing Settings dialog. The view guard is a single `current_kitchen.show_nutrition` check prepended to the existing nutrition conditional. All nutrition computation (jobs, cascades) stays untouched.

**Tech Stack:** Rails 8, SQLite, Stimulus, Minitest

**Spec:** `docs/plans/2026-03-17-nutrition-display-toggle-design.md`

---

## Chunk 1: Database + Backend

### Task 1: Migration

**Files:**
- Create: `db/migrate/008_add_show_nutrition_to_kitchens.rb`

- [ ] **Step 1: Write the migration**

```ruby
# frozen_string_literal: true

class AddShowNutritionToKitchens < ActiveRecord::Migration[8.0]
  def change
    add_column :kitchens, :show_nutrition, :boolean, default: false, null: false
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `cd /home/claude/familyrecipes && bin/rails db:migrate`
Expected: column added, `db/schema.rb` updated with `show_nutrition`

- [ ] **Step 3: Commit**

```bash
git add db/migrate/008_add_show_nutrition_to_kitchens.rb db/schema.rb
git commit -m "Add show_nutrition boolean to kitchens table"
```

### Task 2: Settings controller — test and implementation

**Files:**
- Modify: `app/controllers/settings_controller.rb:12-17` (show action JSON)
- Modify: `app/controllers/settings_controller.rb:32-33` (settings_params)
- Modify: `test/controllers/settings_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Add two tests to `test/controllers/settings_controller_test.rb`:

```ruby
test 'show returns show_nutrition setting' do
  log_in
  get settings_path(kitchen_slug: kitchen_slug), as: :json

  data = response.parsed_body

  assert_equal false, data['show_nutrition']
end

test 'updates show_nutrition via JSON' do
  log_in
  patch settings_path(kitchen_slug: kitchen_slug),
        params: { kitchen: { show_nutrition: true } }, as: :json

  assert_response :success
  @kitchen.reload

  assert @kitchen.show_nutrition
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/settings_controller_test.rb -n /show_nutrition/`
Expected: first test fails (key not present in JSON), second fails (param not permitted)

- [ ] **Step 3: Update SettingsController**

In `app/controllers/settings_controller.rb`:

1. Add `show_nutrition` to the `show` action JSON hash:

```ruby
def show
  render json: {
    site_title: current_kitchen.site_title,
    homepage_heading: current_kitchen.homepage_heading,
    homepage_subtitle: current_kitchen.homepage_subtitle,
    usda_api_key: current_kitchen.usda_api_key,
    show_nutrition: current_kitchen.show_nutrition
  }
end
```

2. Add `show_nutrition` to `settings_params`:

```ruby
def settings_params
  params.expect(kitchen: %i[site_title homepage_heading homepage_subtitle usda_api_key show_nutrition])
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/settings_controller_test.rb`
Expected: all tests pass (including existing ones)

- [ ] **Step 5: Commit**

```bash
git add app/controllers/settings_controller.rb test/controllers/settings_controller_test.rb
git commit -m "Add show_nutrition to settings controller JSON and params"
```

### Task 3: Recipe view — test and implementation

**Files:**
- Modify: `app/views/recipes/_recipe_content.html.erb:66`
- Modify: `test/controllers/recipes_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Add two tests to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'hides nutrition table when show_nutrition is false' do
  recipe = @kitchen.recipes.find_by!(slug: 'focaccia')
  recipe.update_column(:nutrition_data, {
    'totals' => { 'calories' => 200 },
    'per_serving' => { 'calories' => 25 }
  })

  get recipe_path('focaccia', kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select '.nutrition-label', count: 0
end

test 'shows nutrition table when show_nutrition is true' do
  @kitchen.update!(show_nutrition: true)
  recipe = @kitchen.recipes.find_by!(slug: 'focaccia')
  recipe.update_column(:nutrition_data, {
    'totals' => { 'calories' => 200 },
    'per_serving' => { 'calories' => 25 }
  })

  get recipe_path('focaccia', kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select '.nutrition-label'
end
```

- [ ] **Step 2: Run tests to verify the "hides" test fails**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /nutrition_table/`
Expected: "hides" test FAILS (no guard yet, so nutrition renders regardless of `show_nutrition`). "shows" test passes (nutrition renders because there's no guard blocking it).

- [ ] **Step 3: Add show_nutrition guard to the view**

In `app/views/recipes/_recipe_content.html.erb`, change line 66 from:

```erb
<%- if nutrition && nutrition['totals']&.values&.any? { |v| v.to_f > 0 } -%>
```

to:

```erb
<%- if current_kitchen.show_nutrition && nutrition && nutrition['totals']&.values&.any? { |v| v.to_f > 0 } -%>
```

- [ ] **Step 4: Run tests to verify both pass**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /nutrition_table/`
Expected: both tests pass

- [ ] **Step 5: Commit**

```bash
git add app/views/recipes/_recipe_content.html.erb test/controllers/recipes_controller_test.rb
git commit -m "Guard nutrition table display with kitchen.show_nutrition"
```

## Chunk 2: Settings Dialog Frontend

### Task 4: Settings dialog HTML

**Files:**
- Modify: `app/views/settings/_dialog.html.erb`

- [ ] **Step 1: Add Recipes fieldset to the dialog**

In `app/views/settings/_dialog.html.erb`, insert a new fieldset between the closing `</fieldset>` of the "Site" section (line 34) and the opening `<fieldset>` of the "API Keys" section (line 36):

```erb
      <fieldset class="editor-section">
        <legend class="editor-section-title">Recipes</legend>
        <div class="settings-field">
          <label class="settings-checkbox-label">
            <input type="checkbox" id="settings-show-nutrition"
                   data-settings-editor-target="showNutrition">
            Display nutrition information under recipes
          </label>
        </div>
      </fieldset>
```

- [ ] **Step 2: Add CSS for the checkbox label**

In `app/assets/stylesheets/style.css`, after the `.settings-field label` block (around line 1009), add:

```css
.settings-checkbox-label {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-weight: normal;
  cursor: pointer;
}
```

This overrides the `.settings-field label` rule (which uses `display: block` and `font-weight: 600` for labels above text inputs) to properly align the checkbox inline with its text.

- [ ] **Step 3: Commit**

```bash
git add app/views/settings/_dialog.html.erb app/assets/stylesheets/style.css
git commit -m "Add nutrition toggle checkbox to settings dialog"
```

### Task 5: Stimulus controller wiring

**Files:**
- Modify: `app/javascript/controllers/settings_editor_controller.js`

- [ ] **Step 1: Add showNutrition to static targets**

Change line 15 from:

```javascript
static targets = ["siteTitle", "homepageHeading", "homepageSubtitle", "usdaApiKey"]
```

to:

```javascript
static targets = ["siteTitle", "homepageHeading", "homepageSubtitle", "usdaApiKey", "showNutrition"]
```

- [ ] **Step 2: Update openDialog fetch handler**

After line 55 (`this.usdaApiKeyTarget.value = data.usda_api_key || ""`), add:

```javascript
        this.showNutritionTarget.checked = !!data.show_nutrition
```

- [ ] **Step 3: Update collect handler**

In the `collect` method's `kitchen` object (around line 69-74), add `show_nutrition`:

```javascript
    event.detail.data = {
      kitchen: {
        site_title: this.siteTitleTarget.value,
        homepage_heading: this.homepageHeadingTarget.value,
        homepage_subtitle: this.homepageSubtitleTarget.value,
        usda_api_key: this.usdaApiKeyTarget.value,
        show_nutrition: this.showNutritionTarget.checked
      }
    }
```

- [ ] **Step 4: Update provideSaveFn handler**

In the `provideSaveFn` method's JSON body (around line 86-93), add `show_nutrition`:

```javascript
      body: JSON.stringify({
        kitchen: {
          site_title: this.siteTitleTarget.value,
          homepage_heading: this.homepageHeadingTarget.value,
          homepage_subtitle: this.homepageSubtitleTarget.value,
          usda_api_key: this.usdaApiKeyTarget.value,
          show_nutrition: this.showNutritionTarget.checked
        }
      })
```

- [ ] **Step 5: Update checkModified handler**

In the `checkModified` method (around line 97-104), add the checkbox check:

```javascript
  checkModified = (event) => {
    event.detail.handled = true
    event.detail.modified =
      this.siteTitleTarget.value !== this.originals.siteTitle ||
      this.homepageHeadingTarget.value !== this.originals.homepageHeading ||
      this.homepageSubtitleTarget.value !== this.originals.homepageSubtitle ||
      this.usdaApiKeyTarget.value !== this.originals.usdaApiKey ||
      this.showNutritionTarget.checked !== this.originals.showNutrition
  }
```

- [ ] **Step 6: Update reset handler**

In the `reset` method (around line 106-112), add:

```javascript
    this.showNutritionTarget.checked = this.originals.showNutrition
```

- [ ] **Step 7: Update storeOriginals**

In `storeOriginals` (around line 114-121), add:

```javascript
      showNutrition: this.showNutritionTarget.checked
```

- [ ] **Step 8: Update disableFields**

In `disableFields` (around line 123-126), add `this.showNutritionTarget` to the array.

- [ ] **Step 9: Build and verify**

Run: `cd /home/claude/familyrecipes && npm run build`
Expected: build succeeds with no errors

- [ ] **Step 10: Commit**

```bash
git add app/javascript/controllers/settings_editor_controller.js
git commit -m "Wire show_nutrition checkbox into settings editor Stimulus controller"
```

## Chunk 3: Documentation + Final Verification

### Task 6: Update documentation

**Files:**
- Modify: `app/models/kitchen.rb:1-9` (header comment)
- Modify: `CLAUDE.md` (Settings paragraph)

- [ ] **Step 1: Update Kitchen model header comment**

In `app/models/kitchen.rb`, update the header comment (lines 1-9) to mention display preferences. Change:

```ruby
# site branding (site_title,
# homepage_heading, homepage_subtitle), and encrypted API keys (usda_api_key).
```

to:

```ruby
# site branding (site_title, homepage_heading, homepage_subtitle), display
# preferences (show_nutrition), and encrypted API keys (usda_api_key).
```

- [ ] **Step 2: Update CLAUDE.md Settings paragraph**

In `CLAUDE.md`, find the Settings paragraph that says:

```
**Settings.** Site branding and API keys live as columns on Kitchen
```

Change to:

```
**Settings.** Site branding, display preferences, and API keys live as columns on Kitchen
```

- [ ] **Step 3: Commit**

```bash
git add app/models/kitchen.rb CLAUDE.md
git commit -m "docs: update Kitchen header comment and CLAUDE.md for show_nutrition

Resolves #241"
```

### Task 7: Full test suite + lint

- [ ] **Step 1: Run full test suite**

Run: `cd /home/claude/familyrecipes && rake test`
Expected: all tests pass, no regressions

- [ ] **Step 2: Run lint**

Run: `cd /home/claude/familyrecipes && rake lint`
Expected: 0 offenses

- [ ] **Step 3: Run html_safe audit**

Run: `cd /home/claude/familyrecipes && rake lint:html_safe`
Expected: passes (no new `.html_safe` or `raw()` calls)

- [ ] **Step 4: Run JS build**

Run: `cd /home/claude/familyrecipes && npm run build`
Expected: builds cleanly

- [ ] **Step 5: Fix any issues**

If lint or tests surfaced problems, fix and commit them.
