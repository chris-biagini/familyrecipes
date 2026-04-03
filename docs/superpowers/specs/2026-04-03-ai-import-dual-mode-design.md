# AI Import Dual Mode: Faithful + Expert

## Problem

The AI import currently has one mode: pure transcription. Experienced cooks
often find imported recipes verbose — three paragraphs to describe dicing
and sautéing an onion. Users want the option to condense imported recipes
to their essence.

## Goal

Add an "Expert mode" toggle to AI import that condenses recipes for
experienced cooks while preserving all ingredients and quantities. The
existing pure-transcription behavior becomes "Faithful mode" (the default).

## Design Decisions

- **Two separate prompt files** — faithful and expert diverge as they're
  tuned independently. Shared format spec is stable and rarely changes,
  so duplication cost is low.
- **Tags restored in both modes** — Sonnet (unlike Haiku) can be trusted
  with tag selection. Tags are classification metadata, same as categories.
  Both prompts get `{{CATEGORIES}}` and `{{TAGS}}` slots.
- **Expert mode is editorial, not personalized** — it doesn't match the
  user's existing recipe style. It applies a fixed editorial voice:
  terse, article-free, assumes cooking competence.
- **Model stays Sonnet** — expert mode needs editorial judgment that Haiku
  can't reliably provide without hallucination.

## Prompt Architecture

### Faithful Mode (`ai_import_prompt_faithful.md`)

The current production prompt with `{{TAGS}}` restored. Pure transcription:
preserve source wording, strip detritus, format into Markdown syntax.
Already tuned to 95.4 avg on real-world corpus.

### Expert Mode (`ai_import_prompt_expert.md`)

Same format specification (ingredient syntax, step structure, front matter,
fractions, footer). Different job description and instruction handling:

**Job description:**
- Find the recipe, strip detritus (same as faithful)
- Condense instructions for experienced cooks
- Preserve ALL ingredients and quantities exactly (non-negotiable)
- Apply editorial voice to instructions only

**Voice directives (instructions section):**
- Drop articles aggressively: "Add to skillet" not "Add to the skillet"
- Compress verbose instruction sequences to their essence: three paragraphs
  about sautéing an onion becomes "Dice onion. Sauté in oil until softened."
- Assume a competent home cook — omit basics like "wash your hands",
  "gather your ingredients", obvious preheating reminders
- Use imperative mood, short sentences
- Keep temperatures, times, and visual cues — these affect outcomes
- Keep technique tips that aren't obvious (e.g., "don't overwork the dough")
- Use "about" not "approximately"
- Hyphens for ranges: "3-5 minutes"

**Description line:**
- Write a punchy one-liner: "Worth the effort." / "Better than the box."
- Under 10 words, casual tone

**What stays the same as faithful:**
- Ingredient syntax, decomposition rules, name rules, prep notes
- Step structure, splitting guidance
- Front matter (Makes, Serves, Category, Tags)
- Footer conventions (attribution, substitutions, tips)
- ASCII fractions, unit rules, formatting rules
- Anti-hallucination guard (do not invent quantities or ingredients)
- Detritus stripping rules
- OCR recovery hints

**What differs:**
- Instructions: condensed editorial voice vs. source preservation
- Description: punchy one-liner vs. source's description or omit
- Common mistakes: adds voice-level items (articles, "approximately")

### Dynamic Slots

Both prompts contain:
- `{{CATEGORIES}}` — kitchen's category names + Miscellaneous
- `{{TAGS}}` — kitchen's tag names

## Service Changes

### AiImportService

```ruby
PROMPT_FAITHFUL = Rails.root.join('lib/familyrecipes/ai_import_prompt_faithful.md').read.freeze
PROMPT_EXPERT = Rails.root.join('lib/familyrecipes/ai_import_prompt_expert.md').read.freeze

def self.call(text:, kitchen:, mode: :faithful)
  new(kitchen:, mode:).call(text:)
end
```

`build_system_prompt` selects the appropriate template based on `@mode`
and interpolates categories and tags.

### AiImportController

Accept `mode` parameter from request. Map `"expert"` string to `:expert`
symbol, default to `:faithful`.

```ruby
def create
  text = params[:text].to_s.strip
  mode = params[:mode] == 'expert' ? :expert : :faithful
  result = AiImportService.call(text:, kitchen: current_kitchen, mode:)
  # ... existing response handling
end
```

### ai_import_controller.js

Add a checkbox target. Include `mode` in the POST body when checkbox is
checked.

```javascript
// In submit():
const mode = this.expertCheckboxTarget.checked ? 'expert' : 'faithful'
body: JSON.stringify({ text, mode })
```

## UI Changes

A single checkbox added to the AI import dialog, between the textarea
and the footer buttons:

```html
<label class="editor-checkbox">
  <input type="checkbox" data-ai-import-target="expertCheckbox">
  Expert mode — condense for experienced cooks
</label>
```

Styled consistently with existing editor dialog patterns. No tooltip or
help text needed — the label is self-explanatory.

## Testing

### Unit Tests

- `AiImportServiceTest`: test both modes select correct prompt, test
  tag interpolation works for both
- `AiImportControllerTest`: test mode parameter parsing, default to
  faithful

### Ralph Loop

The expert prompt gets its own tuning loop against `corpus_v2`. Scoring
uses the same 3-layer pipeline. An additional fidelity check compares
expert output against faithful output to ensure no ingredients or
quantities are lost — only instructions should change.

## File Changes

| File | Change |
|------|--------|
| `lib/familyrecipes/ai_import_prompt_faithful.md` | Rename from `ai_import_prompt.md`, restore `{{TAGS}}` slot |
| `lib/familyrecipes/ai_import_prompt_expert.md` | New — condensed voice prompt |
| `app/services/ai_import_service.rb` | `mode:` parameter, dual prompt loading |
| `app/controllers/ai_import_controller.rb` | Parse `mode` param |
| `app/javascript/controllers/ai_import_controller.js` | Checkbox target, send mode |
| `app/views/homepage/show.html.erb` | Add checkbox to dialog |
| `test/services/ai_import_service_test.rb` | Tests for both modes |
| `test/controllers/ai_import_controller_test.rb` | Test mode param |
| `test/ai_import/prompt_template.md` | Update for faithful+tags |
| `test/ai_import/prompt_template_expert.md` | New — expert prompt for ralph loop |
| `test/ai_import/runner.rb` | Support `--prompt` flag for expert prompt |
