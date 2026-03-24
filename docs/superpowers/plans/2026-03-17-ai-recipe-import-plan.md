# AI Recipe Import Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an AI-powered recipe import that converts pasted recipe text into the app's Markdown format via the Anthropic API.

**Architecture:** New `AiImportService` calls the Anthropic API server-side with a detailed system prompt. A thin `AiImportController` exposes it as a JSON endpoint. A Stimulus controller manages the import dialog and hands off the result to the existing recipe editor dialog.

**Tech Stack:** Ruby `anthropic` gem (official SDK), Stimulus controller, existing editor dialog infrastructure.

**Spec:** `docs/plans/2026-03-17-ai-recipe-import-design.md`

---

## File Map

### New Files
| File | Responsibility |
|---|---|
| `db/migrate/009_add_anthropic_api_key_to_kitchens.rb` | Add encrypted column |
| `lib/familyrecipes/ai_import_prompt.md` | System prompt for recipe conversion |
| `app/services/ai_import_service.rb` | Anthropic API call orchestration |
| `app/controllers/ai_import_controller.rb` | Thin JSON endpoint |
| `app/javascript/controllers/ai_import_controller.js` | Import dialog + editor handoff |
| `test/services/ai_import_service_test.rb` | Service unit tests |
| `test/controllers/ai_import_controller_test.rb` | Controller integration tests |

### Modified Files
| File | Change |
|---|---|
| `Gemfile:16` | Add `gem 'anthropic'` |
| `app/models/kitchen.rb` | `encrypts :anthropic_api_key`, `AI_MODEL` constant |
| `app/controllers/settings_controller.rb` | Permit + return `anthropic_api_key` |
| `app/javascript/controllers/settings_editor_controller.js` | New `anthropicApiKey` target |
| `app/views/settings/_dialog.html.erb` | Anthropic API key field |
| `app/views/homepage/show.html.erb` | Import button + dialog |
| `app/javascript/application.js` | Register `ai-import` controller |
| `config/routes.rb` | `post 'ai_import'` in kitchen scope |
| `CLAUDE.md` | Brief architecture entry |

---

## Task 1: Migration + Kitchen model

**Files:**
- Create: `db/migrate/009_add_anthropic_api_key_to_kitchens.rb`
- Modify: `app/models/kitchen.rb:25,27-28`
- Test: `test/models/kitchen_test.rb`

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/009_add_anthropic_api_key_to_kitchens.rb
class AddAnthropicApiKeyToKitchens < ActiveRecord::Migration[8.0]
  def change
    add_column :kitchens, :anthropic_api_key, :string
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bundle exec rails db:migrate`
Expected: Schema updated, no errors.

- [ ] **Step 3: Add encryption + constant to Kitchen model**

In `app/models/kitchen.rb`, after `encrypts :usda_api_key` (line 25), add:

```ruby
encrypts :anthropic_api_key
```

After `MAX_AISLES = 50` (line 28), add:

```ruby
AI_MODEL = 'claude-sonnet-4-6'
```

Update the header comment (line 10) to mention `anthropic_api_key` alongside `usda_api_key`.

- [ ] **Step 4: Write encryption test**

In `test/models/kitchen_test.rb`, after the existing `encrypts usda_api_key at rest` test, add:

```ruby
test 'encrypts anthropic_api_key at rest' do
  ActsAsTenant.without_tenant do
    @kitchen.update!(anthropic_api_key: 'sk-ant-test-key-123')
  end

  assert_equal 'sk-ant-test-key-123', @kitchen.anthropic_api_key

  raw = ActiveRecord::Base.connection.select_value(
    "SELECT anthropic_api_key FROM kitchens WHERE id = #{@kitchen.id}"
  )
  assert_not_equal 'sk-ant-test-key-123', raw
end
```

- [ ] **Step 5: Run test**

Run: `ruby -Itest test/models/kitchen_test.rb -n test_encrypts_anthropic_api_key_at_rest`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add db/migrate/009_add_anthropic_api_key_to_kitchens.rb app/models/kitchen.rb test/models/kitchen_test.rb db/schema.rb
git commit -m "Add anthropic_api_key to Kitchen with encryption"
```

---

## Task 2: Settings — backend + UI

**Files:**
- Modify: `app/controllers/settings_controller.rb:12-20,34`
- Modify: `app/javascript/controllers/settings_editor_controller.js:15,52-55,67-77,80-97,100-107,110-116,119-126,129-132`
- Modify: `app/views/settings/_dialog.html.erb:47-61`
- Test: `test/controllers/settings_controller_test.rb`

- [ ] **Step 1: Update SettingsController**

In `app/controllers/settings_controller.rb`:

Add `anthropic_api_key` to the `show` JSON hash (after line 17, the `usda_api_key` line):

```ruby
anthropic_api_key: current_kitchen.anthropic_api_key,
```

Add `:anthropic_api_key` to the params array (line 34):

```ruby
params.expect(kitchen: %i[site_title homepage_heading homepage_subtitle usda_api_key anthropic_api_key show_nutrition])
```

- [ ] **Step 2: Update settings view**

In `app/views/settings/_dialog.html.erb`, after the USDA API key field (after line 60, before `</fieldset>`), add:

```erb
<div class="settings-field" data-controller="reveal">
  <label for="settings-anthropic-api-key">Anthropic API key</label>
  <div class="settings-api-key-row">
    <input type="password" id="settings-anthropic-api-key" class="settings-input"
           autocomplete="off"
           data-settings-editor-target="anthropicApiKey"
           data-reveal-target="input">
    <button type="button" class="btn settings-reveal-btn"
            data-action="reveal#toggle"
            data-reveal-target="button">Show</button>
  </div>
</div>
```

- [ ] **Step 3: Update settings_editor_controller.js**

In `app/javascript/controllers/settings_editor_controller.js`:

Add `"anthropicApiKey"` to `static targets` (line 15):

```javascript
static targets = ["siteTitle", "homepageHeading", "homepageSubtitle", "usdaApiKey", "anthropicApiKey", "showNutrition"]
```

Add to the `openDialog` fetch handler (after line 55):

```javascript
this.anthropicApiKeyTarget.value = data.anthropic_api_key || ""
```

Add to `collect` (after line 74):

```javascript
anthropic_api_key: this.anthropicApiKeyTarget.value,
```

Add to `provideSaveFn` body (after line 93):

```javascript
anthropic_api_key: this.anthropicApiKeyTarget.value,
```

Add to `checkModified` (after line 106):

```javascript
this.anthropicApiKeyTarget.value !== this.originals.anthropicApiKey ||
```

Add to `reset` (after line 115):

```javascript
this.anthropicApiKeyTarget.value = this.originals.anthropicApiKey
```

Add to `storeOriginals` (after line 124):

```javascript
anthropicApiKey: this.anthropicApiKeyTarget.value,
```

Add to `disableFields` array (after line 131, before `this.showNutritionTarget`):

```javascript
this.anthropicApiKeyTarget,
```

- [ ] **Step 4: Write settings tests**

In `test/controllers/settings_controller_test.rb`, add:

```ruby
test 'show includes anthropic_api_key' do
  log_in

  get settings_path(kitchen_slug: kitchen_slug), as: :json

  assert_response :success
  assert response.parsed_body.key?('anthropic_api_key')
end

test 'update persists anthropic_api_key' do
  log_in

  patch settings_path(kitchen_slug: kitchen_slug),
        params: { kitchen: { anthropic_api_key: 'sk-ant-secret' } }, as: :json

  assert_response :success

  @kitchen.reload
  assert_equal 'sk-ant-secret', @kitchen.anthropic_api_key
end
```

- [ ] **Step 5: Run settings tests**

Run: `ruby -Itest test/controllers/settings_controller_test.rb`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/settings_controller.rb app/views/settings/_dialog.html.erb app/javascript/controllers/settings_editor_controller.js test/controllers/settings_controller_test.rb
git commit -m "Add Anthropic API key to Settings"
```

---

## Task 3: Gemfile + system prompt

**Files:**
- Modify: `Gemfile:14`
- Create: `lib/familyrecipes/ai_import_prompt.md`

- [ ] **Step 1: Add anthropic gem to Gemfile**

In `Gemfile`, after `gem 'solid_cable'` (line 16), add:

```ruby
gem 'anthropic'
```

- [ ] **Step 2: Install the gem**

Run: `bundle install`
Expected: `anthropic` gem installed, `Gemfile.lock` updated.

- [ ] **Step 3: Create system prompt file**

Create `lib/familyrecipes/ai_import_prompt.md` with the user's system prompt (provided during brainstorming). Remove the opening line about images and URLs — change the first paragraph to:

```
You convert recipes into a specific Markdown format for a family recipe
collection. The user will give you recipe content — text pasted from a website,
a typed-out recipe, or any other text source — and you produce a single Markdown
document in the format described below. Output ONLY the Markdown recipe. No
commentary, no explanation, no code fences.
```

The rest of the prompt remains as-is from the user's original.

- [ ] **Step 4: Commit**

```bash
git add Gemfile Gemfile.lock lib/familyrecipes/ai_import_prompt.md
git commit -m "Add anthropic gem and AI import system prompt"
```

---

## Task 4: AiImportService

**Files:**
- Create: `app/services/ai_import_service.rb`
- Create: `test/services/ai_import_service_test.rb`

- [ ] **Step 1: Write failing tests for the service**

Create `test/services/ai_import_service_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class AiImportServiceTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    @kitchen.update!(anthropic_api_key: 'sk-ant-test-key')
  end

  test 'returns markdown on successful API call' do
    stub_anthropic_response('# Pancakes') do
      result = AiImportService.call(text: 'pancake recipe here', kitchen: @kitchen)

      assert result.markdown
      assert_equal '# Pancakes', result.markdown
      assert_nil result.error
    end
  end

  test 'returns error when no API key configured' do
    @kitchen.update!(anthropic_api_key: nil)

    result = AiImportService.call(text: 'some recipe', kitchen: @kitchen)

    assert_nil result.markdown
    assert_equal 'no_api_key', result.error
  end

  test 'builds multi-turn messages for try-again' do
    captured_messages = nil

    mock_client = build_mock_client('# Revised') do |messages|
      captured_messages = messages
    end

    Anthropic::Client.stub :new, mock_client do
      AiImportService.call(
        text: 'original recipe',
        kitchen: @kitchen,
        previous_result: '# First Attempt',
        feedback: 'Make steps shorter'
      )
    end

    assert_equal 3, captured_messages.size
    assert_equal 'user', captured_messages[0][:role]
    assert_equal 'assistant', captured_messages[1][:role]
    assert_equal '# First Attempt', captured_messages[1][:content]
    assert_equal 'user', captured_messages[2][:role]
    assert_equal 'Make steps shorter', captured_messages[2][:content]
  end

  test 'strips code fences from response' do
    response_text = "```markdown\n# Pancakes\n\nDelicious.\n```"

    stub_anthropic_response(response_text) do
      result = AiImportService.call(text: 'pancake recipe', kitchen: @kitchen)

      assert_equal "# Pancakes\n\nDelicious.", result.markdown
    end
  end

  test 'strips leading text before first heading' do
    response_text = "Here is the recipe:\n\n# Pancakes\n\nDelicious."

    stub_anthropic_response(response_text) do
      result = AiImportService.call(text: 'pancake recipe', kitchen: @kitchen)

      assert_equal "# Pancakes\n\nDelicious.", result.markdown
    end
  end

  test 'returns error on authentication failure' do
    stub_anthropic_error(Anthropic::Errors::AuthenticationError.new(message: 'invalid key', response: {}, body: nil)) do
      result = AiImportService.call(text: 'recipe', kitchen: @kitchen)

      assert_nil result.markdown
      assert_includes result.error, 'API key'
    end
  end

  test 'returns error on rate limit' do
    stub_anthropic_error(Anthropic::Errors::RateLimitError.new(message: 'rate limited', response: {}, body: nil)) do
      result = AiImportService.call(text: 'recipe', kitchen: @kitchen)

      assert_nil result.markdown
      assert_includes result.error, 'Rate limited'
    end
  end

  test 'returns error on connection failure' do
    stub_anthropic_error(Anthropic::Errors::APIConnectionError.new(message: 'connection refused')) do
      result = AiImportService.call(text: 'recipe', kitchen: @kitchen)

      assert_nil result.markdown
      assert_includes result.error, 'reach'
    end
  end

  test 'returns error on timeout' do
    stub_anthropic_error(Anthropic::Errors::APITimeoutError.new(message: 'timed out')) do
      result = AiImportService.call(text: 'recipe', kitchen: @kitchen)

      assert_nil result.markdown
      assert_includes result.error, 'timed out'
    end
  end

  private

  def stub_anthropic_response(text, &block)
    mock_client = build_mock_client(text)
    Anthropic::Client.stub(:new, mock_client, &block)
  end

  def stub_anthropic_error(error, &block)
    mock_client = Object.new
    mock_messages = Object.new
    mock_messages.define_singleton_method(:create) { |**_| raise error }
    mock_client.define_singleton_method(:messages) { mock_messages }
    Anthropic::Client.stub(:new, mock_client, &block)
  end

  def build_mock_client(response_text, &on_create)
    mock_client = Object.new
    mock_messages = Object.new
    mock_messages.define_singleton_method(:create) do |**kwargs|
      on_create&.call(kwargs[:messages])
      OpenStruct.new(content: [OpenStruct.new(type: 'text', text: response_text)])
    end
    mock_client.define_singleton_method(:messages) { mock_messages }
    mock_client
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/ai_import_service_test.rb`
Expected: FAIL — `AiImportService` not defined.

- [ ] **Step 3: Implement AiImportService**

Create `app/services/ai_import_service.rb`:

```ruby
# frozen_string_literal: true

# Converts pasted recipe text into the app's Markdown format by calling the
# Anthropic API with a detailed system prompt. Pure function: no database writes,
# no side effects. Supports multi-turn refinement via previous_result + feedback.
#
# Collaborators:
# - Kitchen#anthropic_api_key (encrypted API key)
# - Kitchen::AI_MODEL (hardcoded model constant)
# - lib/familyrecipes/ai_import_prompt.md (system prompt, loaded at boot)
class AiImportService
  Result = Data.define(:markdown, :error)

  SYSTEM_PROMPT = Rails.root.join('lib/familyrecipes/ai_import_prompt.md').read.freeze
  MAX_TOKENS = 8192

  def self.call(text:, kitchen:, previous_result: nil, feedback: nil)
    new(kitchen:).call(text:, previous_result:, feedback:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def call(text:, previous_result: nil, feedback: nil)
    return Result.new(markdown: nil, error: 'no_api_key') unless @kitchen.anthropic_api_key.present?

    markdown = fetch_completion(build_messages(text, previous_result, feedback))
    Result.new(markdown: clean_output(markdown), error: nil)
  rescue Anthropic::Errors::AuthenticationError
    Result.new(markdown: nil, error: 'Invalid Anthropic API key. Check your key in Settings.')
  rescue Anthropic::Errors::RateLimitError
    Result.new(markdown: nil, error: 'Rate limited by Anthropic. Wait a moment and try again.')
  rescue Anthropic::Errors::APITimeoutError
    Result.new(markdown: nil, error: 'Request timed out. Try again.')
  rescue Anthropic::Errors::APIConnectionError
    Result.new(markdown: nil, error: 'Could not reach the Anthropic API. Check your connection.')
  rescue Anthropic::Errors::APIError => e
    Result.new(markdown: nil, error: "AI import failed: #{e.message}")
  end

  private

  def fetch_completion(messages)
    response = client.messages.create(
      model: Kitchen::AI_MODEL,
      max_tokens: MAX_TOKENS,
      system: SYSTEM_PROMPT,
      messages:
    )
    response.content.find { |block| block.type == 'text' }&.text || ''
  end

  def build_messages(text, previous_result, feedback)
    messages = [{ role: 'user', content: text }]
    return messages unless previous_result && feedback

    messages << { role: 'assistant', content: previous_result }
    messages << { role: 'user', content: feedback }
    messages
  end

  def clean_output(text)
    text = text.strip
    text = text.sub(/\A```\w*\n/, '').sub(/\n```\z/, '') if text.start_with?('```')
    text = text.sub(/\A.*?(?=^# )/m, '') if text.match?(/^# /m) && !text.start_with?('# ')
    text.strip
  end

  def client
    Anthropic::Client.new(api_key: @kitchen.anthropic_api_key, timeout: 90)
  end
end
```

- [ ] **Step 4: Run tests**

Run: `ruby -Itest test/services/ai_import_service_test.rb`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/ai_import_service.rb test/services/ai_import_service_test.rb
git commit -m "Add AiImportService with Anthropic API integration"
```

---

## Task 5: AiImportController

**Files:**
- Create: `app/controllers/ai_import_controller.rb`
- Modify: `config/routes.rb:50`
- Create: `test/controllers/ai_import_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Create `test/controllers/ai_import_controller_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class AiImportControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    log_in
    @kitchen.update!(anthropic_api_key: 'sk-ant-test-key')
  end

  test 'create returns markdown on success' do
    mock_result = AiImportService::Result.new(markdown: '# Pancakes', error: nil)

    AiImportService.stub :call, mock_result do
      post ai_import_path(kitchen_slug: kitchen_slug),
           params: { text: 'pancake recipe' }, as: :json
    end

    assert_response :success
    assert_equal '# Pancakes', response.parsed_body['markdown']
  end

  test 'create passes through try-again params' do
    captured_args = nil
    mock_call = ->(**kwargs) {
      captured_args = kwargs
      AiImportService::Result.new(markdown: '# Revised', error: nil)
    }

    AiImportService.stub :call, mock_call do
      post ai_import_path(kitchen_slug: kitchen_slug),
           params: { text: 'recipe', previous_result: '# First', feedback: 'shorter steps' },
           as: :json
    end

    assert_response :success
    assert_equal 'recipe', captured_args[:text]
    assert_equal '# First', captured_args[:previous_result]
    assert_equal 'shorter steps', captured_args[:feedback]
  end

  test 'create returns 422 when no API key' do
    mock_result = AiImportService::Result.new(markdown: nil, error: 'no_api_key')

    AiImportService.stub :call, mock_result do
      post ai_import_path(kitchen_slug: kitchen_slug),
           params: { text: 'recipe' }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal 'no_api_key', response.parsed_body['error']
  end

  test 'create returns 422 on invalid API key' do
    mock_result = AiImportService::Result.new(markdown: nil, error: 'Invalid Anthropic API key. Check your key in Settings.')

    AiImportService.stub :call, mock_result do
      post ai_import_path(kitchen_slug: kitchen_slug),
           params: { text: 'recipe' }, as: :json
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body['error'], 'API key'
  end

  test 'create returns 422 when text is blank' do
    post ai_import_path(kitchen_slug: kitchen_slug),
         params: { text: '' }, as: :json

    assert_response :unprocessable_entity
    assert_equal 'Text is required', response.parsed_body['error']
  end

  test 'create returns 503 on API failure' do
    mock_result = AiImportService::Result.new(markdown: nil, error: 'Could not reach the Anthropic API.')

    AiImportService.stub :call, mock_result do
      post ai_import_path(kitchen_slug: kitchen_slug),
           params: { text: 'recipe' }, as: :json
    end

    assert_response :service_unavailable
    assert_includes response.parsed_body['error'], 'Anthropic'
  end

  test 'create requires membership' do
    delete logout_path

    post ai_import_path(kitchen_slug: kitchen_slug),
         params: { text: 'recipe' }, as: :json

    assert_response :forbidden
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/ai_import_controller_test.rb`
Expected: FAIL — route not found / controller not defined.

- [ ] **Step 3: Add route**

In `config/routes.rb`, inside the kitchen scope, after the settings routes (after `patch 'settings', to: 'settings#update'`), add:

```ruby
post 'ai_import', to: 'ai_import#create', as: :ai_import
```

- [ ] **Step 4: Implement controller**

Create `app/controllers/ai_import_controller.rb`:

```ruby
# frozen_string_literal: true

# Thin JSON adapter for AI-powered recipe import. Accepts pasted recipe text,
# delegates to AiImportService for Anthropic API call, returns generated Markdown.
# Supports try-again via previous_result + feedback params. The no_api_key error
# returns 422; upstream API failures return 503; all other errors return the
# service's error message.
#
# Collaborators:
# - AiImportService (API call orchestration)
# - Kitchen#anthropic_api_key (key presence check)
class AiImportController < ApplicationController
  before_action :require_membership

  def create
    text = params[:text].to_s.strip
    return render json: { error: 'Text is required' }, status: :unprocessable_entity if text.blank?

    result = AiImportService.call(
      text:,
      kitchen: current_kitchen,
      previous_result: params[:previous_result],
      feedback: params[:feedback]
    )

    if result.markdown
      render json: { markdown: result.markdown }
    elsif result.error == 'no_api_key' || result.error&.include?('API key')
      render json: { error: result.error }, status: :unprocessable_entity
    else
      render json: { error: result.error }, status: :service_unavailable
    end
  end
end
```

- [ ] **Step 5: Run tests**

Run: `ruby -Itest test/controllers/ai_import_controller_test.rb`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/ai_import_controller.rb config/routes.rb test/controllers/ai_import_controller_test.rb
git commit -m "Add AiImportController with JSON endpoint"
```

---

## Task 6: Frontend — Stimulus controller + dialog + button

**Files:**
- Create: `app/javascript/controllers/ai_import_controller.js`
- Modify: `app/javascript/application.js:13-14,35-36`
- Modify: `app/views/homepage/show.html.erb:28-31,123-171`

- [ ] **Step 1: Create the Stimulus controller**

Create `app/javascript/controllers/ai_import_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"
import { getCsrfToken, showErrors } from "../utilities/editor_utils"

/**
 * Manages the AI recipe import dialog. Posts pasted recipe text to the
 * server-side Anthropic endpoint, then hands off the generated Markdown to
 * the recipe editor dialog. Supports a try-again flow with user feedback.
 *
 * Collaborators:
 * - editor_controller (recipe editor dialog lifecycle)
 * - plaintext_editor_controller (sets editor content via .content setter)
 * - editor_utils (CSRF tokens, error display)
 */
export default class extends Controller {
  static targets = ["textarea", "feedback", "feedbackField", "errors", "submitButton"]
  static values = { url: String, editorDialogId: String }

  connect() {
    this.previousResult = null
    this.boundOpenClick = (e) => {
      if (e.target.closest('#ai-import-button')) this.open()
    }
    document.addEventListener('click', this.boundOpenClick)
  }

  disconnect() {
    document.removeEventListener('click', this.boundOpenClick)
  }

  open() {
    this.element.showModal()
    this.textareaTarget.focus()
  }

  close() {
    this.element.close()
  }

  async submit(event) {
    event.preventDefault()
    const text = this.textareaTarget.value.trim()
    if (!text) return

    this.setLoading(true)
    this.clearErrors()

    const body = { text }
    if (this.previousResult && this.hasFeedbackTarget && this.feedbackTarget.value.trim()) {
      body.previous_result = this.previousResult
      body.feedback = this.feedbackTarget.value.trim()
    }

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCsrfToken()
        },
        body: JSON.stringify(body)
      })
      const data = await response.json()

      if (!response.ok) {
        this.showError(data.error || "Import failed")
        return
      }

      this.previousResult = data.markdown
      this.showFeedbackField()
      this.element.close()
      this.openRecipeEditor(data.markdown)
    } catch {
      this.showError("Network error. Check your connection.")
    } finally {
      this.setLoading(false)
    }
  }

  openRecipeEditor(markdown) {
    const editorDialog = document.getElementById(this.editorDialogIdValue)
    if (!editorDialog) return

    editorDialog.showModal()

    requestAnimationFrame(() => {
      const plaintextEl = editorDialog.querySelector('[data-controller~="plaintext-editor"]')
      if (plaintextEl) {
        const ctrl = this.application.getControllerForElementAndIdentifier(plaintextEl, "plaintext-editor")
        if (ctrl) {
          ctrl.content = markdown
          return
        }
      }
      const textarea = editorDialog.querySelector('textarea')
      if (textarea) textarea.value = markdown
    })
  }

  showFeedbackField() {
    if (this.hasFeedbackFieldTarget) {
      this.feedbackFieldTarget.hidden = false
    }
    this.submitButtonTarget.textContent = "Try Again"
  }

  setLoading(loading) {
    this.submitButtonTarget.disabled = loading
    this.submitButtonTarget.textContent = loading
      ? "Importing\u2026"
      : (this.previousResult ? "Try Again" : "Import")
    this.textareaTarget.disabled = loading
    if (this.hasFeedbackTarget) this.feedbackTarget.disabled = loading
  }

  showError(message) {
    if (this.hasErrorsTarget) {
      showErrors(this.errorsTarget, [message])
    }
  }

  clearErrors() {
    if (this.hasErrorsTarget) {
      this.errorsTarget.hidden = true
      this.errorsTarget.textContent = ""
    }
  }
}
```

- [ ] **Step 2: Register in application.js**

In `app/javascript/application.js`:

Add import after line 12 (after the existing imports, alphabetically before `DualModeEditorController`):

```javascript
import AiImportController from "./controllers/ai_import_controller"
```

Add registration after line 34 (before `application.register("dual-mode-editor", ...)`):

```javascript
application.register("ai-import", AiImportController)
```

- [ ] **Step 3: Add import button to homepage**

In `app/views/homepage/show.html.erb`, after the "Add Recipe" button (after line 31, before `</div>`):

```erb
<% if current_kitchen.anthropic_api_key.present? %>
  <span class="recipe-actions-dot">&middot;</span>
  <button type="button" id="ai-import-button" class="edit-toggle">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3l1.5 4.5L18 9l-4.5 1.5L12 15l-1.5-4.5L6 9l4.5-1.5z"/><path d="M19 13l.75 2.25L22 16l-2.25.75L19 19l-.75-2.25L16 16l2.25-.75z"/></svg>
    AI Import
  </button>
<% end %>
```

- [ ] **Step 4: Add import dialog to homepage**

In `app/views/homepage/show.html.erb`, after the recipe editor dialog closing `<% end %>` (after line 171), add:

```erb
<% if current_kitchen.anthropic_api_key.present? %>
<dialog id="ai-import-editor" class="editor-dialog"
        data-controller="ai-import"
        data-ai-import-url-value="<%= ai_import_path %>"
        data-ai-import-editor-dialog-id-value="recipe-editor">
  <div class="editor-header">
    <h2>Import with AI</h2>
    <button type="button" class="btn editor-close" data-action="click->ai-import#close" aria-label="Close">&times;</button>
  </div>
  <div class="editor-errors" data-ai-import-target="errors" hidden></div>
  <div class="editor-body">
    <textarea class="editor-textarea"
              data-ai-import-target="textarea"
              placeholder="Paste a recipe from any source&#x2026;"
              rows="16"></textarea>
    <div class="settings-field" data-ai-import-target="feedbackField" hidden>
      <label for="ai-import-feedback">Feedback for refinement</label>
      <input type="text" id="ai-import-feedback" class="settings-input"
             data-ai-import-target="feedback"
             placeholder="e.g., Make the steps more detailed">
    </div>
  </div>
  <div class="editor-footer">
    <button type="button" class="btn editor-cancel" data-action="click->ai-import#close">Cancel</button>
    <button type="button" class="btn btn-primary editor-save"
            data-ai-import-target="submitButton"
            data-action="click->ai-import#submit">Import</button>
  </div>
</dialog>
<% end %>
```

- [ ] **Step 5: Build JS bundle**

Run: `npm run build`
Expected: Build succeeds with no errors.

- [ ] **Step 6: Run full test suite to check for regressions**

Run: `bundle exec rake test`
Expected: All pass.

- [ ] **Step 7: Run lint**

Run: `bundle exec rubocop`
Expected: No new offenses.

- [ ] **Step 8: Commit**

```bash
git add app/javascript/controllers/ai_import_controller.js app/javascript/application.js app/views/homepage/show.html.erb
git commit -m "Add AI import button, dialog, and Stimulus controller"
```

---

## Task 7: CLAUDE.md update

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add AI import entry to Architecture section**

In `CLAUDE.md`, in the Architecture section (after the "Write path" subsection), add a brief entry:

```
**AI import.** `AiImportService` calls the Anthropic API (`anthropic` gem)
with a system prompt (`lib/familyrecipes/ai_import_prompt.md`) to convert
pasted recipe text into the app's Markdown format. `AiImportController` is a
thin JSON adapter (`POST /ai_import`). The Stimulus `ai_import_controller`
manages the import dialog and hands off generated Markdown to the recipe
editor. API key stored encrypted on Kitchen (`anthropic_api_key`); model
hardcoded as `Kitchen::AI_MODEL`. Button hidden when no key configured.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document AI import pipeline in CLAUDE.md"
```

---

## Task 8: Manual smoke test

This task is manual — verify the full flow works end-to-end.

- [ ] **Step 1: Restart the server** (required — new gem + lib/ files)

```bash
pkill -f puma; rm -f tmp/pids/server.pid
bin/dev &
```

- [ ] **Step 2: Configure an API key**

Open Settings, enter a valid Anthropic API key, save.

- [ ] **Step 3: Verify the import button appears**

Reload the homepage. The "AI Import" button with sparkle icon should appear next to "Add Recipe".

- [ ] **Step 4: Test the import flow**

1. Click "AI Import"
2. Paste a recipe from any source
3. Click "Import" — spinner should show for 5-15 seconds
4. Recipe editor should open pre-filled with formatted Markdown
5. Review, edit if needed, save — recipe should appear on the homepage

- [ ] **Step 5: Test the try-again flow**

1. Click "AI Import" again (button should still be there)
2. Previous text should still be in the textarea
3. Feedback field should be visible
4. Type feedback like "Make the steps shorter"
5. Click "Try Again" — revised Markdown should appear in the editor

- [ ] **Step 6: Test error cases**

1. Remove the API key from Settings, reload — button should disappear
2. Set an invalid key, try importing — should see auth error message
