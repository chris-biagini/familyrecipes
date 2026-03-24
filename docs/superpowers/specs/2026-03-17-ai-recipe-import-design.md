# AI Recipe Import — Design Spec

## Problem

Adding recipes from external sources (websites, cookbooks, handwritten cards)
requires manually reformatting into the app's Markdown syntax. An AI-powered
import would accept pasted text and produce correctly formatted recipe
Markdown, dramatically reducing friction.

## Overview

A new "Import with AI" flow on the homepage. The user pastes recipe text,
the server calls the Anthropic API with a detailed system prompt, and the
generated Markdown lands in the existing recipe editor for review and
editing. A "try again" option lets the user refine the result with feedback
before saving.

## Design Decisions

- **Text-only input, no URL fetching.** Many sites block automated access.
  Users paste from a print view. Image support deferred to v2.
- **Server-side API call.** API key never leaves the server. Follows the
  existing `UsdaSearchController` pattern.
- **Synchronous request.** No streaming, no background jobs. A 5-15 second
  spinner is acceptable for an import action. Simplest thing that works.
- **Dialog chain handoff.** Import dialog → API call → recipe editor dialog
  pre-filled with result. Recipe doesn't hit the DB until the user saves.
- **Try-again via multi-turn conversation.** Previous result + user feedback
  sent as a follow-up turn. Lightweight refinement without a chat UI.
- **Hardcoded model.** Always uses `claude-sonnet-4-6`. No model picker —
  keeps Settings simple. Upgrade the constant when better models ship.

## Section 1: Settings

### New Kitchen Column

| Column | Type | Notes |
|---|---|---|
| `anthropic_api_key` | string (encrypted) | Same pattern as `usda_api_key` |

`Kitchen` gains `encrypts :anthropic_api_key`. Model is hardcoded as a
constant (`AI_MODEL = 'claude-sonnet-4-6'`) — no database column needed.

### Settings UI

One new field in the existing settings form:
- Password-type input for the API key (new Stimulus target:
  `anthropicApiKey`)

Changes required in `settings_editor_controller.js`:
- Add `anthropicApiKey` to `static targets`
- Include in the `collect` event handler's `kitchen` hash
- Populate in the `openDialog` content-loaded flow

Changes required in `SettingsController`:
- Add `:anthropic_api_key` to `settings_params`
- Include in the `show` JSON response

No eager validation of the API key — validated when used. Bad key → clear
error at import time.

### Migration

One migration adding the column to `kitchens`.

## Section 2: Backend

### `AiImportService`

Pure-function service. No database interaction, no side effects.

```ruby
AiImportService.call(
  text:,
  kitchen:,
  previous_result: nil,
  feedback: nil
)
# => Result with .markdown or .error
```

Responsibilities:
- Read API key from `kitchen`, use hardcoded model constant
- Assemble message array (system prompt + user text + optional multi-turn
  for try-again)
- Call Anthropic API via the `anthropic` Ruby gem (official SDK,
  `github.com/anthropics/anthropic-sdk-ruby`, v1.24+)
- Light output cleanup (strip code fences if present)
- Return markdown string or structured error

### Gem

The official Anthropic Ruby SDK: `gem 'anthropic'` (currently v1.24.0).
Exception classes used by the service:

| Exception | HTTP | Meaning |
|---|---|---|
| `Anthropic::Errors::AuthenticationError` | 401 | Invalid API key |
| `Anthropic::Errors::RateLimitError` | 429 | Too many requests |
| `Anthropic::Errors::APIConnectionError` | — | Network failure |
| `Anthropic::Errors::APITimeoutError` | — | Request timeout |
| `Anthropic::Errors::APIStatusError` | any | Base for HTTP errors |
| `Anthropic::Errors::APIError` | — | Base for all errors |

### System Prompt

Stored in `lib/familyrecipes/ai_import_prompt.md` as a standalone file. Read
once at boot (consistent with other `lib/familyrecipes/` files — server
restart required for prompt changes). Contains the full recipe format
specification with examples, rules, and common mistakes. The prompt
references for image and URL input should be removed for v1 (text-only).

### `AiImportController`

Thin JSON controller, one action:

```
POST /ai_import   (inside the (/kitchens/:kitchen_slug) scope)
Body: { text: "...", previous_result: "...", feedback: "..." }
Response: { markdown: "# Recipe Title\n..." }
Error: { error: "message" }
```

- Lives inside the optional kitchen scope (needs `current_kitchen` for
  API key access, consistent with all tenant-scoped routes)
- Guarded by `require_membership`
- 422 for missing API key or empty input
- 503 for upstream API failures

### API Call Structure

**First attempt:**
```
system: [system prompt]
messages: [
  { role: "user", content: "pasted recipe text" }
]
```

**Try-again (with feedback):**
```
system: [system prompt]
messages: [
  { role: "user", content: "pasted recipe text" },
  { role: "assistant", content: "previous markdown result" },
  { role: "user", content: "user feedback" }
]
```

Model: `claude-sonnet-4-6` (hardcoded constant). `max_tokens` set to 8192
(complex multi-step recipes with detailed front matter can exceed 4K tokens).

## Section 3: Frontend

### "Import with AI" Button

Only rendered when `current_kitchen.anthropic_api_key.present?` — same
pattern as `has_usda_key` in the ingredients controller. When no key is
configured, the button simply doesn't appear. Users discover the feature
by adding their API key in Settings.

The button uses a sparkle icon (SVG) to signal AI functionality, placed
next to the existing "New Recipe" button.

### Import Dialog

Uses `shared/editor_dialog` layout with custom content:
- `<textarea>` for pasting recipe text (primary input, large)
- Feedback text field — hidden initially, shown after first successful import
- Submit button: "Import" initially, "Try again" after first attempt

### `ai_import_controller` (Stimulus)

Manages the import dialog lifecycle:

1. **Submit:** Read textarea value. POST to `/ai_import`.
2. **Loading state:** Disable inputs, show "Importing..." spinner.
3. **Success:** Close import dialog, programmatically open recipe editor
   dialog, set textarea content to returned markdown. Reveal feedback field
   and change button to "Try again."
4. **Error:** Show error message inline in the dialog.
5. **Try again:** Send original text + previous result + feedback to endpoint.
   On success, update the recipe editor content.

### Handoff to Recipe Editor

The `editor:opened` event does not bubble (`bubbles: false`, dispatched on
the dialog element). The import controller cannot listen for it from a
different dialog. Instead, the handoff uses direct DOM access:

1. Import controller calls `showModal()` on the recipe editor `<dialog>`
2. After a microtask delay (to let Stimulus connect), sets the plaintext
   editor's `.content` directly via its Stimulus controller reference
3. Falls back to setting the `<textarea>` value if the controller isn't
   ready yet

This avoids needing cross-dialog event wiring or changes to the editor
controller's event dispatching.

### Try-Again Flow

- After success, the import dialog retains its state in Stimulus controller
  instance variables (pasted text, last result). This works
  because `<dialog>` elements remain in the DOM when closed — the Stimulus
  controller stays connected and state survives.
- **Turbo morph protection:** The existing `turbo:before-morph-element`
  handler protects open dialogs. The import dialog may be closed when a
  morph runs, which could reset state. This is acceptable — the user
  would simply re-paste and re-import. No special protection needed.
- User closes recipe editor without saving → can re-open import dialog
- Feedback field accepts free-text refinement instructions
- Service builds multi-turn conversation from original input + previous result
  + feedback

## Section 4: Error Handling

| Error | Source | Response |
|---|---|---|
| No API key configured | Service | 422 `{ error: "no_api_key" }` |
| Invalid API key | `Anthropic::Errors::AuthenticationError` | 422, clear message pointing to Settings |
| Rate limited | `Anthropic::Errors::RateLimitError` | 503, "Wait a moment and try again" |
| Network/timeout | `Anthropic::Errors::APIConnectionError` | 503, "Could not reach Anthropic API" |
| Timeout | `Anthropic::Errors::APITimeoutError` | 503, "Request timed out" |
| Other API error | `Anthropic::Errors::APIError` | 503, "AI import failed: {message}" |

**Output cleanup:** Strip leading/trailing code fences if present. Strip text
before first `# `. No deep validation — user reviews in editor.

**Request timeout:** 90 seconds server-side on the HTTP call to Anthropic.
No client-side timeout — spinner until server responds.

## Section 5: Testing

### `AiImportService` Unit Tests
- Mock Anthropic client
- Message assembly: text-only, text+feedback+previous_result
- Each error case (auth, rate limit, network, unexpected)
- Code fence stripping and output cleanup

### `AiImportController` Integration Tests
- Mock `AiImportService.call` at service boundary
- Happy path: JSON with markdown
- Missing API key: 422
- Upstream failure: 503
- `require_membership` guard

### System Test (Playwright)
- Smoke test: open dialog, paste text, submit, verify editor opens with content
- Mock API at controller level

No automated tests for prompt quality — validated by hand.

## Section 6: File Inventory

### New Files
- `app/services/ai_import_service.rb`
- `app/controllers/ai_import_controller.rb`
- `app/javascript/controllers/ai_import_controller.js`
- `lib/familyrecipes/ai_import_prompt.md`
- `test/services/ai_import_service_test.rb`
- `test/controllers/ai_import_controller_test.rb`
- `db/migrate/0XX_add_ai_settings_to_kitchen.rb`

### Modified Files
- `Gemfile` — add `anthropic` gem
- `app/models/kitchen.rb` — `encrypts :anthropic_api_key`, `AI_MODEL` constant
- `app/controllers/settings_controller.rb` — permit new param, include in JSON
- `app/javascript/controllers/settings_editor_controller.js` — new target + collect/load
- `app/views/homepage/show.html.erb` — import button (with sparkle icon) + dialog
- Settings views — API key field
- `app/javascript/application.js` — register `ai_import_controller`
- `config/routes.rb` — `post 'ai_import'` inside kitchen scope
- `CLAUDE.md` — brief entry for AI import pipeline in Architecture section

### Unchanged
- Recipe editor, `RecipeWriteService`, `MarkdownImporter` — AI import
  produces markdown that feeds into the existing new-recipe flow unmodified.
- `html_safe_allowlist.yml` — no `.html_safe` or `raw()` calls needed
  (all DOM construction uses `textContent`/`createElement` per CSP rules).
