# Recipe Editor Enhancement — Design

## Goal

Add syntax highlighting, auto-continuation, and placeholder text to the recipe markdown editor. Same overlay technique as the QuickBites editor, with token styles that mirror the QuickBites vocabulary and extend it for recipe-specific syntax.

## What changes

### 1. Syntax-highlighted overlay

Same transparent-textarea-over-pre approach as QuickBites. The JS controller splits each line by regex (mirroring `LineClassifier` patterns) and wraps segments in styled spans.

**Token styles:**

| Token | Example | Weight | Color | Style | QB parallel |
|---|---|---|---|---|---|
| Title | `# Pizza Margherita` | 700 | accent | underline | = category header |
| Step header | `## Make dough.` | 700 | text-color | underline | — |
| Ingredient name | `- Mozzarella` | 600 | text-color | — | = item name |
| Ingredient qty | `, 8 oz` | 400 | text-color | — | — |
| Ingredient prep | `: shredded` | 400 | muted-text | italic | = QB ingredients |
| Cross-reference | `>>> @[Pizza Dough]` | 600 | accent | italic | — |
| Front matter | `Category: Pizza` | 400 | muted-text | — | — |
| Divider | `---` | 400 | muted-text | — | — |
| Prose | step instructions | 400 | text-color | — | — |

**Ingredient line splitting** mirrors `IngredientParser`: split on first `:` for prep note, then first `,` on the left side for quantity. The `- ` dash prefix is part of the name span.

### 2. Auto-continuation on Enter

- On a `- ` ingredient line: insert `\n- ` (same as QuickBites auto-dash)
- On an empty `- ` line: remove the dash, leave blank line
- No auto-continuation for step headers or prose (too varied)

### 3. Placeholder example

Show format example when the textarea is empty:

```
# Recipe Title

Category: Dinner
Serves: 4

## First step.

- Ingredient one, 1 cup: diced
- Ingredient two

Instructions for this step.

## Second step.

- More ingredients

More instructions.
```

## What doesn't change

- Save/load flow (generic editor controller)
- Parse warnings after save
- No live error indicators
- No auto-completion for cross-reference titles

## Implementation approach

A new Stimulus controller (`recipe-editor`) that attaches alongside the existing `editor` controller, identical pattern to `quickbites-editor`. It:

- Creates the `<pre>` overlay behind the textarea on connect
- Syncs overlay content on every `input` event via `highlight()`
- Handles `keydown` for Enter (auto-dash on ingredient lines)
- Sets the placeholder attribute on the textarea

### CSS classes

Reuse the existing overlay infrastructure (`.qb-highlight-wrap`, `.qb-highlight-overlay`, `.qb-highlight-input`) since the positioning/transparency behavior is identical. Rename the shared classes to a generic prefix (`hl-`) so both editors use the same base. Add recipe-specific token classes:

- `.hl-title` — bold 700, accent, underline (same rules as `.qb-hl-category`)
- `.hl-step-header` — bold 700, text-color, underline
- `.hl-ingredient-name` — semi-bold 600, text-color (same rules as `.qb-hl-item`)
- `.hl-ingredient-qty` — regular 400, text-color
- `.hl-ingredient-prep` — regular 400, muted-text, italic (same rules as `.qb-hl-ingredients`)
- `.hl-cross-ref` — semi-bold 600, accent, italic
- `.hl-front-matter` — regular 400, muted-text
- `.hl-divider` — regular 400, muted-text

QuickBites classes (`.qb-hl-category`, `.qb-hl-item`, `.qb-hl-ingredients`) become aliases or are migrated to the shared `hl-` prefix.

### Line classification regex (JS)

Mirrors `LineClassifier::LINE_PATTERNS` order:

```javascript
const TITLE       = /^# (.+)$/
const STEP_HEADER = /^## (.+)$/
const INGREDIENT  = /^- (.+)$/
const CROSS_REF   = /^>>>\s+(.+)$/
const DIVIDER     = /^---\s*$/
const FRONT_MATTER = /^(Category|Makes|Serves):\s+(.+)$/
const BLANK       = /^\s*$/
```

Ingredient lines get a second pass to split name/quantity/prep note.

### File changes

- `app/javascript/controllers/recipe_editor_controller.js` — new Stimulus controller
- `app/assets/stylesheets/style.css` — shared overlay base + recipe highlight classes
- `app/views/recipes/show.html.erb` — add `data-controller="recipe-editor"` and target
- `app/views/homepage/show.html.erb` — same for the new-recipe editor
- `app/javascript/controllers/quickbites_editor_controller.js` — migrate to shared `hl-` overlay classes
- `app/views/menu/show.html.erb` — update class references if wrapper classes change
