# API Keys to Environment Variables — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move USDA and Anthropic API keys from per-kitchen encrypted DB columns to environment variables, removing all per-kitchen key storage and Settings UI.

**Architecture:** Services read `ENV['USDA_API_KEY']` and `ENV['ANTHROPIC_API_KEY']` directly. The encrypted columns, Settings UI fields, the `reveal_controller.js` Stimulus controller, and related CSS are removed entirely. A migration drops both columns from `kitchens`.

**Tech Stack:** Rails 8, SQLite, Stimulus, Minitest

**Spec:** `docs/superpowers/specs/2026-04-12-api-keys-to-env-vars-design.md`

---

## File Map

**Modify:**
- `app/services/ai_import_service.rb` — read key from ENV instead of kitchen
- `app/controllers/usda_search_controller.rb` — read key from ENV instead of kitchen
- `app/controllers/ai_import_controller.rb` — update header comment
- `app/controllers/settings_controller.rb` — remove API key params and flags
- `app/views/settings/_editor_frame.html.erb` — remove API Keys fieldset
- `app/javascript/controllers/settings_editor_controller.js` — remove API key targets
- `app/javascript/application.js` — unregister reveal controller
- `app/models/kitchen.rb` — remove encrypts declarations, update header comment
- `app/assets/stylesheets/editor.css` — remove API key CSS
- `docker-compose.example.yml` — uncomment USDA, add Anthropic
- `.env.example` — add Anthropic key, update encryption comment
- `test/services/ai_import_service_test.rb` — use ENV instead of kitchen column
- `test/controllers/usda_search_controller_test.rb` — use ENV instead of kitchen column
- `test/controllers/settings_controller_test.rb` — remove API key tests

**Create:**
- `db/migrate/005_remove_api_keys_from_kitchens.rb`

**Delete:**
- `app/javascript/controllers/reveal_controller.js`

---

### Task 1: Migration — drop API key columns

**Files:**
- Create: `db/migrate/005_remove_api_keys_from_kitchens.rb`

- [ ] **Step 1: Write the migration**

```ruby
# frozen_string_literal: true

class RemoveApiKeysFromKitchens < ActiveRecord::Migration[8.0]
  def change
    remove_column :kitchens, :usda_api_key, :string
    remove_column :kitchens, :anthropic_api_key, :string
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: schema.rb no longer contains `usda_api_key` or `anthropic_api_key` in the `kitchens` table.

- [ ] **Step 3: Verify schema.rb**

Run: `grep -c 'api_key' db/schema.rb`
Expected: `0`

- [ ] **Step 4: Commit**

```bash
git add db/migrate/005_remove_api_keys_from_kitchens.rb db/schema.rb
git commit -m "Remove usda_api_key and anthropic_api_key columns from kitchens"
```

---

### Task 2: Kitchen model — remove encrypts declarations

**Files:**
- Modify: `app/models/kitchen.rb`

- [ ] **Step 1: Remove the two encrypts lines**

In `app/models/kitchen.rb`, delete these two lines:

```ruby
  encrypts :usda_api_key
  encrypts :anthropic_api_key
```

Leaving only:

```ruby
  encrypts :join_code, deterministic: true
```

- [ ] **Step 2: Update the header comment**

Replace the header comment. The current text references "encrypted API keys (usda_api_key, anthropic_api_key)". Change the relevant sentence from:

```ruby
# display preferences (show_nutrition), encrypted API keys (usda_api_key,
# anthropic_api_key), and an encrypted join_code for membership invitations.
```

to:

```ruby
# display preferences (show_nutrition), and an encrypted join_code for
# membership invitations. Third-party API keys (USDA, Anthropic) are read
# from environment variables, not stored in the database.
```

- [ ] **Step 3: Run tests to check for breakage**

Run: `rake test`
Expected: Failures in tests that still reference `kitchen.usda_api_key` or `kitchen.anthropic_api_key` — those are fixed in later tasks.

- [ ] **Step 4: Commit**

```bash
git add app/models/kitchen.rb
git commit -m "Remove API key encrypts declarations from Kitchen model"
```

---

### Task 3: UsdaSearchController — read from ENV

**Files:**
- Modify: `app/controllers/usda_search_controller.rb`
- Modify: `test/controllers/usda_search_controller_test.rb`

- [ ] **Step 1: Update the controller**

In `app/controllers/usda_search_controller.rb`, replace the `require_api_key` and `usda_client` private methods:

Change `require_api_key` from:

```ruby
  def require_api_key
    return if current_kitchen.usda_api_key.present?

    render json: { error: 'no_api_key' }, status: :unprocessable_content
  end
```

to:

```ruby
  def require_api_key
    return if ENV['USDA_API_KEY'].present?

    render json: { error: 'no_api_key' }, status: :unprocessable_content
  end
```

Change `usda_client` from:

```ruby
  def usda_client
    Mirepoix::UsdaClient.new(api_key: current_kitchen.usda_api_key)
  end
```

to:

```ruby
  def usda_client
    Mirepoix::UsdaClient.new(api_key: ENV['USDA_API_KEY'])
  end
```

- [ ] **Step 2: Update the header comment**

Replace the header comment. Change:

```ruby
# JSON API for USDA FoodData Central search and detail fetch. Reads the USDA
# API key from the current kitchen's encrypted settings. Search returns
```

to:

```ruby
# JSON API for USDA FoodData Central search and detail fetch. Reads the USDA
# API key from ENV['USDA_API_KEY']. Search returns
```

And in the collaborators list, change:

```ruby
# - Kitchen#usda_api_key (encrypted API key storage)
```

to:

```ruby
# - ENV['USDA_API_KEY'] (operator-provided API key)
```

- [ ] **Step 3: Update the test setup**

In `test/controllers/usda_search_controller_test.rb`, change the `setup` block from:

```ruby
  setup do
    create_kitchen_and_user
    log_in
    @kitchen.update!(usda_api_key: 'test-key-123')
  end
```

to:

```ruby
  setup do
    create_kitchen_and_user
    log_in
    ENV['USDA_API_KEY'] = 'test-key-123'
  end

  teardown do
    ENV.delete('USDA_API_KEY')
  end
```

- [ ] **Step 4: Update the no_api_key tests**

Change the `no_api_key` test (search) from:

```ruby
  test 'search returns no_api_key error when key is blank' do
    @kitchen.update!(usda_api_key: nil)

    get usda_search_path(kitchen_slug: kitchen_slug), params: { q: 'cheese' }, as: :json

    assert_response :unprocessable_entity
    assert_equal 'no_api_key', response.parsed_body['error']
  end
```

to:

```ruby
  test 'search returns no_api_key error when key is blank' do
    ENV.delete('USDA_API_KEY')

    get usda_search_path(kitchen_slug: kitchen_slug), params: { q: 'cheese' }, as: :json

    assert_response :unprocessable_entity
    assert_equal 'no_api_key', response.parsed_body['error']
  end
```

Change the `no_api_key` test (show) from:

```ruby
  test 'show returns no_api_key error when key is blank' do
    @kitchen.update!(usda_api_key: nil)

    get usda_show_path(9003, kitchen_slug: kitchen_slug), as: :json

    assert_response :unprocessable_entity
    assert_equal 'no_api_key', response.parsed_body['error']
  end
```

to:

```ruby
  test 'show returns no_api_key error when key is blank' do
    ENV.delete('USDA_API_KEY')

    get usda_show_path(9003, kitchen_slug: kitchen_slug), as: :json

    assert_response :unprocessable_entity
    assert_equal 'no_api_key', response.parsed_body['error']
  end
```

- [ ] **Step 5: Run the USDA controller tests**

Run: `ruby -Itest test/controllers/usda_search_controller_test.rb`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/usda_search_controller.rb test/controllers/usda_search_controller_test.rb
git commit -m "USDA controller reads API key from ENV instead of kitchen column"
```

---

### Task 4: AiImportService — read from ENV

**Files:**
- Modify: `app/services/ai_import_service.rb`
- Modify: `app/controllers/ai_import_controller.rb`
- Modify: `test/services/ai_import_service_test.rb`

- [ ] **Step 1: Update AiImportService**

In `app/services/ai_import_service.rb`, change the `initialize` method from:

```ruby
  def initialize(kitchen:, mode:)
    @api_key = kitchen.anthropic_api_key
    @kitchen = kitchen
    @mode = PROMPTS.key?(mode) ? mode : :faithful
  end
```

to:

```ruby
  def initialize(kitchen:, mode:)
    @api_key = ENV['ANTHROPIC_API_KEY']
    @kitchen = kitchen
    @mode = PROMPTS.key?(mode) ? mode : :faithful
  end
```

- [ ] **Step 2: Update the AuthenticationError message**

In `app/services/ai_import_service.rb`, change line 39:

```ruby
  rescue Anthropic::Errors::AuthenticationError
    Result.new(markdown: nil, error: 'Invalid Anthropic API key. Check your key in Settings.')
  ```

to:

```ruby
  rescue Anthropic::Errors::AuthenticationError
    Result.new(markdown: nil, error: 'Invalid Anthropic API key. Check the ANTHROPIC_API_KEY environment variable.')
```

- [ ] **Step 3: Update the service header comment**

Change:

```ruby
# - Kitchen#anthropic_api_key: encrypted API key for Anthropic
```

to:

```ruby
# - ENV['ANTHROPIC_API_KEY']: operator-provided API key
```

- [ ] **Step 4: Update AiImportController header comment**

In `app/controllers/ai_import_controller.rb`, change:

```ruby
# - Kitchen#anthropic_api_key (key presence check)
```

to:

```ruby
# - ENV['ANTHROPIC_API_KEY'] (key presence check)
```

- [ ] **Step 5: Update the test setup**

In `test/services/ai_import_service_test.rb`, change the `setup` block. Replace:

```ruby
  setup do
    setup_test_kitchen
    @kitchen.update!(anthropic_api_key: 'sk-test-key-123')
    Category.find_or_create_for(@kitchen, 'Baking')
    Category.find_or_create_for(@kitchen, 'Mains')
    Tag.find_or_create_by!(kitchen: @kitchen, name: 'easy')
    Tag.find_or_create_by!(kitchen: @kitchen, name: 'grilled')
  end
```

with:

```ruby
  setup do
    setup_test_kitchen
    ENV['ANTHROPIC_API_KEY'] = 'sk-test-key-123'
    Category.find_or_create_for(@kitchen, 'Baking')
    Category.find_or_create_for(@kitchen, 'Mains')
    Tag.find_or_create_by!(kitchen: @kitchen, name: 'easy')
    Tag.find_or_create_by!(kitchen: @kitchen, name: 'grilled')
  end

  teardown do
    ENV.delete('ANTHROPIC_API_KEY')
  end
```

- [ ] **Step 6: Update the no_api_key test**

Change:

```ruby
  test 'returns error when no API key configured' do
    @kitchen.update!(anthropic_api_key: nil)

    result = AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)

    assert_nil result.markdown
    assert_equal 'no_api_key', result.error
  end
```

to:

```ruby
  test 'returns error when no API key configured' do
    ENV.delete('ANTHROPIC_API_KEY')

    result = AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)

    assert_nil result.markdown
    assert_equal 'no_api_key', result.error
  end
```

- [ ] **Step 7: Update the AuthenticationError test assertion**

Change:

```ruby
  test 'returns error on authentication failure' do
    result = with_anthropic_error(Anthropic::Errors::AuthenticationError) do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_nil result.markdown
    assert_equal 'Invalid Anthropic API key. Check your key in Settings.', result.error
  end
```

to:

```ruby
  test 'returns error on authentication failure' do
    result = with_anthropic_error(Anthropic::Errors::AuthenticationError) do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_nil result.markdown
    assert_equal 'Invalid Anthropic API key. Check the ANTHROPIC_API_KEY environment variable.', result.error
  end
```

- [ ] **Step 8: Run the AI import tests**

Run: `ruby -Itest test/services/ai_import_service_test.rb`
Expected: All tests pass.

- [ ] **Step 9: Commit**

```bash
git add app/services/ai_import_service.rb app/controllers/ai_import_controller.rb test/services/ai_import_service_test.rb
git commit -m "AI import service reads API key from ENV instead of kitchen column"
```

---

### Task 5: Settings UI and controller — remove API key fields

**Files:**
- Modify: `app/controllers/settings_controller.rb`
- Modify: `app/views/settings/_editor_frame.html.erb`
- Modify: `app/javascript/controllers/settings_editor_controller.js`
- Modify: `app/javascript/application.js`
- Delete: `app/javascript/controllers/reveal_controller.js`
- Modify: `app/assets/stylesheets/editor.css`
- Modify: `test/controllers/settings_controller_test.rb`

- [ ] **Step 1: Update SettingsController#show — remove key-set flags**

In `app/controllers/settings_controller.rb`, change the `show` method. Remove the two `_set` lines from the JSON response:

```ruby
      usda_api_key_set: current_kitchen.usda_api_key.present?,
      anthropic_api_key_set: current_kitchen.anthropic_api_key.present?,
```

The resulting `show` method:

```ruby
  def show
    render json: {
      site_title: current_kitchen.site_title,
      homepage_heading: current_kitchen.homepage_heading,
      homepage_subtitle: current_kitchen.homepage_subtitle,
      show_nutrition: current_kitchen.show_nutrition,
      decorate_tags: current_kitchen.decorate_tags,
      join_code: current_kitchen.join_code,
      members: member_list,
      current_user_name: current_user.name,
      current_user_email: current_user.email
    }
  end
```

- [ ] **Step 2: Update filtered_settings_params and settings_params**

Replace `filtered_settings_params` from:

```ruby
  def filtered_settings_params
    permitted = settings_params
    permitted.delete(:usda_api_key) if permitted[:usda_api_key].blank?
    permitted.delete(:anthropic_api_key) if permitted[:anthropic_api_key].blank?
    permitted
  end

  def settings_params
    params.expect(kitchen: %i[site_title homepage_heading homepage_subtitle usda_api_key anthropic_api_key
                              show_nutrition decorate_tags])
  end
```

with:

```ruby
  def settings_params
    params.expect(kitchen: %i[site_title homepage_heading homepage_subtitle
                              show_nutrition decorate_tags])
  end
```

And update the `update` method to call `settings_params` directly instead of `filtered_settings_params`:

```ruby
  def update
    if current_kitchen.update(settings_params)
      current_kitchen.broadcast_update
      render json: { status: 'ok' }
    else
      render json: { errors: current_kitchen.errors.full_messages }, status: :unprocessable_content
    end
  end
```

- [ ] **Step 3: Update SettingsController header comment**

Change:

```ruby
# Manages kitchen-scoped settings: site branding (title, heading, subtitle),
# API keys (USDA, Anthropic), join code management, member listing, and user
```

to:

```ruby
# Manages kitchen-scoped settings: site branding (title, heading, subtitle),
# display preferences, join code management, member listing, and user
```

- [ ] **Step 4: Remove the API Keys fieldset from the view**

In `app/views/settings/_editor_frame.html.erb`, delete the entire API Keys fieldset (lines 48-76):

```erb
      <fieldset class="editor-section">
        <legend class="editor-section-title">API Keys</legend>
        <div class="settings-field" data-controller="reveal">
          <label for="settings-usda-api-key">USDA API key</label>
          <div class="settings-api-key-row">
            <input type="password" id="settings-usda-api-key" class="input-base input-lg"
                   autocomplete="off"
                   data-settings-editor-target="usdaApiKey"
                   data-reveal-target="input"
                   placeholder="<%= kitchen.usda_api_key.present? ? 'Key set — enter new key to change' : '' %>">
            <button type="button" class="btn settings-reveal-btn"
                    data-action="reveal#toggle"
                    data-reveal-target="button">Show</button>
          </div>
        </div>
        <div class="settings-field" data-controller="reveal">
          <label for="settings-anthropic-api-key">Anthropic API key</label>
          <div class="settings-api-key-row">
            <input type="password" id="settings-anthropic-api-key" class="input-base input-lg"
                   autocomplete="off"
                   data-settings-editor-target="anthropicApiKey"
                   data-reveal-target="input"
                   placeholder="<%= kitchen.anthropic_api_key.present? ? 'Key set — enter new key to change' : '' %>">
            <button type="button" class="btn settings-reveal-btn"
                    data-action="reveal#toggle"
                    data-reveal-target="button">Show</button>
          </div>
        </div>
      </fieldset>
```

- [ ] **Step 5: Update settings_editor_controller.js — remove API key targets**

In `app/javascript/controllers/settings_editor_controller.js`:

Remove `"usdaApiKey", "anthropicApiKey"` from the `static targets` array:

```javascript
  static targets = [
    "siteTitle", "homepageHeading", "homepageSubtitle",
    "showNutrition", "decorateTags",
    "joinCode", "regenerateButton",
    "profileName", "profileEmail"
  ]
```

Remove the two API key lines from `checkModified`:

```javascript
      this.usdaApiKeyTarget.value.length > 0 ||
      this.anthropicApiKeyTarget.value.length > 0 ||
```

Remove the two API key lines from `reset`:

```javascript
    this.usdaApiKeyTarget.value = ""
    this.anthropicApiKeyTarget.value = ""
```

Remove the two API key lines from `#buildPayload`:

```javascript
      usda_api_key: this.usdaApiKeyTarget.value,
      anthropic_api_key: this.anthropicApiKeyTarget.value,
```

The resulting `checkModified`:

```javascript
  checkModified = (event) => {
    event.detail.handled = true
    event.detail.modified =
      this.siteTitleTarget.value !== this.originals.siteTitle ||
      this.homepageHeadingTarget.value !== this.originals.homepageHeading ||
      this.homepageSubtitleTarget.value !== this.originals.homepageSubtitle ||
      this.showNutritionTarget.checked !== this.originals.showNutrition ||
      this.decorateTagsTarget.checked !== this.originals.decorateTags ||
      this.#profileChanged()
  }
```

The resulting `reset`:

```javascript
  reset = (event) => {
    event.detail.handled = true
    this.siteTitleTarget.value = this.originals.siteTitle
    this.homepageHeadingTarget.value = this.originals.homepageHeading
    this.homepageSubtitleTarget.value = this.originals.homepageSubtitle
    this.showNutritionTarget.checked = this.originals.showNutrition
    this.decorateTagsTarget.checked = this.originals.decorateTags
    if (this.hasProfileNameTarget) this.profileNameTarget.value = this.originals.profileName
    if (this.hasProfileEmailTarget) this.profileEmailTarget.value = this.originals.profileEmail
  }
```

The resulting `#buildPayload`:

```javascript
  #buildPayload() {
    const kitchen = {
      site_title: this.siteTitleTarget.value,
      homepage_heading: this.homepageHeadingTarget.value,
      homepage_subtitle: this.homepageSubtitleTarget.value,
      show_nutrition: this.showNutritionTarget.checked,
      decorate_tags: this.decorateTagsTarget.checked
    }
    return { kitchen }
  }
```

- [ ] **Step 6: Delete reveal_controller.js and unregister it**

Delete `app/javascript/controllers/reveal_controller.js`.

In `app/javascript/application.js`, remove the import and registration lines:

```javascript
import RevealController from "./controllers/reveal_controller"
```

```javascript
application.register("reveal", RevealController)
```

- [ ] **Step 7: Remove API key CSS from editor.css**

In `app/assets/stylesheets/editor.css`, remove the three API-key-only rules (lines 42-56):

```css
.settings-api-key-row {
  display: flex;
  gap: 0.5rem;
  align-items: stretch;
}

.settings-api-key-row .input-base {
  flex: 1;
  font-family: var(--font-mono);
}

.settings-reveal-btn {
  white-space: nowrap;
  min-width: 3.5rem;
}
```

- [ ] **Step 8: Update settings controller tests**

In `test/controllers/settings_controller_test.rb`, delete these tests entirely:

1. `'updates usda api key via JSON'` (lines 52-61)
2. `'show returns key-set flags instead of raw keys'` (lines 96-105)
3. `'update persists anthropic_api_key'` (lines 107-118)
4. `'blank API key on update preserves existing key'` (lines 120-132)
5. `'editor_frame does not render raw API keys'` (lines 134-142)

Update the `'returns settings as JSON for logged-in member'` test — remove the API key assertions:

```ruby
    assert_not data.key?('usda_api_key'), 'raw API key must not appear in JSON'
    assert data.key?('usda_api_key_set')
```

The resulting test:

```ruby
  test 'returns settings as JSON for logged-in member' do
    log_in
    get settings_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    data = response.parsed_body

    assert_equal @kitchen.site_title, data['site_title']
    assert_equal @kitchen.homepage_heading, data['homepage_heading']
    assert_equal @kitchen.homepage_subtitle, data['homepage_subtitle']
  end
```

- [ ] **Step 9: Run settings controller tests**

Run: `ruby -Itest test/controllers/settings_controller_test.rb`
Expected: All tests pass.

- [ ] **Step 10: Rebuild JS bundle**

Run: `npm run build`
Expected: Build succeeds with no errors about missing `reveal_controller`.

- [ ] **Step 11: Commit**

```bash
git add app/controllers/settings_controller.rb \
        app/views/settings/_editor_frame.html.erb \
        app/javascript/controllers/settings_editor_controller.js \
        app/javascript/application.js \
        app/assets/stylesheets/editor.css \
        test/controllers/settings_controller_test.rb
git rm app/javascript/controllers/reveal_controller.js
git commit -m "Remove API key fields from Settings UI, controller, and tests"
```

---

### Task 6: Config files — update docker-compose and .env.example

**Files:**
- Modify: `docker-compose.example.yml`
- Modify: `.env.example`

- [ ] **Step 1: Update docker-compose.example.yml**

Uncomment the `USDA_API_KEY` line and add `ANTHROPIC_API_KEY`. Change the environment section from:

```yaml
    environment:
      SECRET_KEY_BASE: ${SECRET_KEY_BASE:-}
      ALLOWED_HOSTS: ${ALLOWED_HOSTS:-}
      # RAILS_LOG_LEVEL: ${RAILS_LOG_LEVEL:-info}
      # USDA_API_KEY: ${USDA_API_KEY:-}
```

to:

```yaml
    environment:
      SECRET_KEY_BASE: ${SECRET_KEY_BASE:-}
      ALLOWED_HOSTS: ${ALLOWED_HOSTS:-}
      # RAILS_LOG_LEVEL: ${RAILS_LOG_LEVEL:-info}
      # USDA_API_KEY: ${USDA_API_KEY:-}        # enables USDA nutrition lookups
      # ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}  # enables AI recipe import
```

Both remain commented — they're optional for homelab users.

- [ ] **Step 2: Update .env.example**

Change the encryption comment on line 14 from:

```
# Active Record Encryption (protects encrypted columns like usda_api_key)
```

to:

```
# Active Record Encryption (protects encrypted columns like join_code)
```

Add the Anthropic key after the USDA key section. Change:

```
# Nutrition data (optional — for USDA API lookups)
# USDA_API_KEY=
```

to:

```
# Nutrition data (optional — enables USDA nutrition lookups in ingredient editor)
# USDA_API_KEY=

# AI recipe import (optional — enables AI-powered recipe import)
# ANTHROPIC_API_KEY=
```

- [ ] **Step 3: Commit**

```bash
git add docker-compose.example.yml .env.example
git commit -m "Add ANTHROPIC_API_KEY to config examples, update encryption comment"
```

---

### Task 7: Full test suite + lint

- [ ] **Step 1: Run the full test suite**

Run: `rake test`
Expected: All tests pass. Zero failures, zero errors.

- [ ] **Step 2: Run RuboCop**

Run: `bundle exec rubocop`
Expected: No offenses.

- [ ] **Step 3: Run JS build**

Run: `npm run build`
Expected: Build succeeds.

- [ ] **Step 4: Run Brakeman**

Run: `bundle exec brakeman -q --no-pager`
Expected: No warnings.

- [ ] **Step 5: Fix any failures, commit if needed**

If any of the above fail, fix the issue and commit the fix.

---

### Task 8: File a rate-limiting issue

This task is non-code. The design spec explicitly deferred rate limiting for AI imports.

- [ ] **Step 1: Create the GitHub issue**

```bash
gh issue create \
  --title "Rate-limit AI imports for hosted mode" \
  --body "Deferred from #367. Design questions: per-kitchen or per-user? Monthly reset? What UX at the limit? The orientation doc suggested ~10 free AI imports/month for hosted — needs its own spec."
```

- [ ] **Step 2: Note the issue number for the PR description**
