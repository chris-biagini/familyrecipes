# AI Recipe Import — Design Spec

## Problem

Adding recipes from external sources (websites, cookbooks, handwritten cards)
requires manually reformatting into the app's Markdown syntax. An AI-powered
import would accept pasted text or a photo and produce correctly formatted
recipe Markdown, dramatically reducing friction.

## Overview

A new "Import with AI" flow on the homepage. The user pastes recipe text and/or
uploads an image, the server calls the Anthropic API with a detailed system
prompt, and the generated Markdown lands in the existing recipe editor for
review and editing. A "try again" option lets the user refine the result with
feedback before saving.

## Design Decisions

- **Paste + image input, no URL fetching.** Many sites block automated access.
  Users paste from a print view or photograph a cookbook page.
- **Server-side API call.** API key never leaves the server. Follows the
  existing `UsdaSearchController` pattern.
- **Synchronous request.** No streaming, no background jobs. A 5-15 second
  spinner is acceptable for an import action. Simplest thing that works.
- **Dialog chain handoff.** Import dialog → API call → recipe editor dialog
  pre-filled with result. Recipe doesn't hit the DB until the user saves.
- **Try-again via multi-turn conversation.** Previous result + user feedback
  sent as a follow-up turn. Lightweight refinement without a chat UI.
- **User-configurable model.** Dropdown in Settings alongside the API key.
  Hardcoded list of model IDs (no dynamic API fetching).

## Section 1: Settings

### New Kitchen Columns

| Column | Type | Notes |
|---|---|---|
| `anthropic_api_key` | string (encrypted) | Same pattern as `usda_api_key` |
| `ai_model` | string | Default: `"claude-sonnet-4-6"` |

`Kitchen` gains `encrypts :anthropic_api_key` and an `AI_MODELS` constant
mapping display names to model ID strings. The constant is the single source
of truth for the model dropdown.

### Settings UI

Two new fields in the existing settings form:
- Password-type input for the API key (new Stimulus target:
  `anthropicApiKey`)
- `<select>` dropdown for the model (new Stimulus target: `aiModel`),
  populated from `Kitchen::AI_MODELS`

Changes required in `settings_editor_controller.js`:
- Add `anthropicApiKey` and `aiModel` to `static targets`
- Include both in the `collect` event handler's `kitchen` hash
- Populate both in the `openDialog` content-loaded flow

Changes required in `SettingsController`:
- Add `:anthropic_api_key` and `:ai_model` to `settings_params`
- Include both in the `show` JSON response

No eager validation of the API key — validated when used. Bad key → clear
error at import time.

### Migration

One migration adding both columns to `kitchens`.

## Section 2: Backend

### `AiImportService`

Pure-function service. No database interaction, no side effects.

```ruby
AiImportService.call(
  text:,
  image: nil,          # { data: "base64...", media_type: "image/jpeg" }
  kitchen:,
  previous_result: nil,
  feedback: nil
)
# => Result with .markdown or .error
```

Responsibilities:
- Read API key + model from `kitchen`
- Assemble message array (system prompt + user content blocks + optional
  multi-turn for try-again)
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
specification with examples, rules, and common mistakes.

### `AiImportController`

Thin JSON controller, one action:

```
POST /ai_import   (inside the (/kitchens/:kitchen_slug) scope)
Body: { text: "...", image: "data:image/jpeg;base64,...",
        previous_result: "...", feedback: "..." }
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
  { role: "user", content: [text block, optional image block] }
]
```

**Try-again (with feedback):**
```
system: [system prompt]
messages: [
  { role: "user", content: [text block, optional image block] },
  { role: "assistant", content: [previous markdown result] },
  { role: "user", content: [feedback text] }
]
```

Image is only sent in the first user message. `max_tokens` set to 8192
(complex multi-step recipes with detailed front matter can exceed 4K tokens).

## Section 3: Frontend

### "Import with AI" Button

Always rendered on the homepage next to "New Recipe" (no conditional
visibility — avoids chicken-and-egg discoverability problem). If clicked
without an API key configured, the import dialog opens and shows a
helpful message directing the user to Settings, similar to how USDA search
handles `{ error: "no_api_key" }`.

### Import Dialog

Uses `shared/editor_dialog` layout with custom content:
- `<textarea>` for pasting recipe text (primary input, large)
- File input for image upload (jpeg, png, webp, gif)
- Selected filename displayed as text next to the file input (no image
  preview thumbnail — avoids CSP `img-src` complications with blob/data
  URIs, keeps it simple)
- Feedback text field — hidden initially, shown after first successful import
- Submit button: "Import" initially, "Try again" after first attempt

### `ai_import_controller` (Stimulus)

Manages the import dialog lifecycle:

1. **Submit:** Read textarea + optional file (base64 via FileReader). POST to
   `/ai_import`.
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
  instance variables (pasted text, last result, previous image). This works
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

### Image Upload Size

Client-side check: reject files over 10 MB with a clear message. The
Anthropic API accepts up to 20 MB base64, but 10 MB is generous for a
recipe photo and keeps the POST body reasonable.

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
- Message assembly: text-only, text+image, text+feedback+previous_result
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
- `app/models/kitchen.rb` — `encrypts :anthropic_api_key`, `AI_MODELS` constant
- `app/controllers/settings_controller.rb` — permit new params, include in JSON
- `app/javascript/controllers/settings_editor_controller.js` — new targets + collect/load
- `app/views/homepage/show.html.erb` — import button + dialog partial
- Settings views — API key field + model dropdown
- `app/javascript/application.js` — register `ai_import_controller`
- `config/routes.rb` — `post 'ai_import'` inside kitchen scope
- `CLAUDE.md` — brief entry for AI import pipeline in Architecture section

### Unchanged
- Recipe editor, `RecipeWriteService`, `MarkdownImporter` — AI import
  produces markdown that feeds into the existing new-recipe flow unmodified.
- `html_safe_allowlist.yml` — no `.html_safe` or `raw()` calls needed
  (all DOM construction uses `textContent`/`createElement` per CSP rules).
