# Dual-Mode Editors: Graphical + Plaintext Recipe and Quick Bites Editing

**Date:** 2026-03-14
**Status:** Draft

## Problem

The app's recipe and Quick Bites editors use a Markdown-based plaintext
format. Power users love it; non-technical users find it intimidating. The
`## ` step header and `- Name, Qty: Prep` ingredient syntax are the biggest
barriers. The goal is to add a graphical editor mode that eliminates the
structural learning curve while keeping the plaintext path fully intact for
power users.

## Core Architecture: Structured IR as the Native Tongue

Both editors (markdown plaintext and graphical form) are peers that translate
to and from a shared **intermediate representation** (IR) — the structured
hash that `RecipeBuilder` already produces today. The write path consumes
this IR, not markdown directly.

```
Markdown text  → Parser pipeline → IR (hash) → MarkdownImporter → DB
Graphical JSON → trivial mapping  → IR (hash) → MarkdownImporter → DB
```

A canonical **serializer** (IR → markdown) lives in Ruby only, used to:
1. Generate `markdown_source` stored on the Recipe record (both paths)
2. Populate the plaintext textarea when toggling graphical → plaintext

The markdown format is defined in exactly one place (the serializer + parser,
both Ruby). No client-side markdown generation.

### Recipe IR Structure

This is a **normalized** version of the hash `RecipeBuilder.build` returns,
extended with `category` and `tags`. Today's `RecipeBuilder` output is close
but not identical — ingredient `quantity` is a raw string that
`MarkdownImporter` splits into qty + unit via
`FamilyRecipes::Ingredient.split_quantity`. Stage 2 formalizes this IR as
the contract between both input paths and `MarkdownImporter`, keeping the
qty/unit split inside the importer where it already lives.

The graphical editor sends JSON matching this shape. The keys map 1:1 to
`RecipeBuilder` output (`:title`, `:description`, `:front_matter`, `:steps`,
`:tldr`, `:ingredients`, `:instructions`, `:cross_reference`, `:footer`).

```ruby
{
  title: "Scrambled Eggs",
  description: "A breakfast staple...",
  front_matter: {
    makes: "12 rolls",
    serves: "4",
    category: "Basics",
    tags: ["breakfast", "quick"]
  },
  steps: [
    {
      tldr: "Prep the eggs.",
      ingredients: [
        { name: "Eggs", quantity: "4", prep_note: "Crack into a bowl." },
        { name: "Salt", quantity: nil, prep_note: nil }
      ],
      instructions: "Whisk eggs with a pinch of salt...",
      cross_reference: nil
    },
    {
      tldr: "Import the dough.",
      ingredients: [],
      instructions: nil,
      cross_reference: {
        target_title: "Pizza Dough",
        multiplier: 0.5,
        prep_note: "Halve the recipe."
      }
    }
  ],
  footer: "Adapted from Julia Child."
}
```

### Quick Bites IR Structure

Anchored to `FamilyRecipes.parse_quick_bites_content`, which returns a
`QuickBitesResult` containing an array of `FamilyRecipes::QuickBite` objects.
The IR normalizes this into a hash for JSON transport:

```ruby
{
  categories: [
    {
      name: "Snacks",
      items: [
        { name: "Apples and Honey", ingredients: ["Apples", "Honey"] },
        { name: "Crackers and Cheese", ingredients: ["Ritz crackers", "Cheddar"] }
      ]
    }
  ]
}
```

Each `QuickBite` has `category`, `title`, and `ingredients` attributes. The
IR groups items by category and preserves ordering. The
`QuickBitesSerializer` inverts this to produce the plaintext format.

## Front Matter Extension

The recipe markdown format gains two new front matter keys:

```markdown
Makes: 12 rolls
Serves: 4
Category: Basics
Tags: breakfast, quick
```

- `LineClassifier` front matter regex extended from `(Makes|Serves)` to
  `(Makes|Serves|Category|Tags)` so these lines tokenize as `:front_matter`.
- `RecipeBuilder` extracts `category` and `tags` (comma-separated, trimmed,
  lowercased) from front matter.
- Tags are normalized: whitespace within a tag becomes hyphens
  (`vegan friendly` → `vegan-friendly`), matching the existing `[a-zA-Z-]`
  validation.
- Canonical serializer emits front matter in fixed order: Makes, Serves,
  Category, Tags. Blank values are omitted.

## Canonical Markdown Serializer

`FamilyRecipes::RecipeSerializer` — a pure-function Ruby module in
`lib/familyrecipes/`. Takes the IR hash (or a `FamilyRecipes::Recipe` parse
artifact) and emits canonical markdown.

Rules:
- `# Title` on line 1
- Blank line, then description paragraphs (if present)
- Blank line, then front matter lines in order: Makes, Serves, Category, Tags
- Blank line, then steps
- Each step: `## Name`, blank line, ingredient bullets (`- Name, Qty: Prep`),
  blank line, instruction paragraphs
- Cross-reference steps: `## Name`, blank line, `> @[Title], multiplier: prep`
- Footer: `---`, blank line, footer text (if present)
- One blank line between sections, no trailing whitespace

A `FamilyRecipes::QuickBitesSerializer` follows the same pattern for Quick
Bites content.

Testable via round-trip: parse markdown → serialize → parse again → assert
structural equality.

## MarkdownImporter Refactor

`MarkdownImporter` gains a second entry point:

- `import(markdown_string, kitchen:, category:)` — existing path, parses then
  imports
- `import_from_structure(ir_hash, kitchen:, category:)` — new path, skips
  parsing, uses the serializer to generate `markdown_source` for storage,
  then imports

Both paths converge on the same internal `save_recipe` / `replace_steps`
logic.

`RecipeWriteService` gains parallel methods:

- `create(markdown:, kitchen:, ...)` / `update(slug:, markdown:, ...)` —
  existing, call `MarkdownImporter.import`
- `create_from_structure(structure:, kitchen:, ...)` /
  `update_from_structure(slug:, structure:, ...)` — new, extract `category`
  and `tags` from `structure[:front_matter]`, call
  `MarkdownImporter.import_from_structure`

`RecipesController` dispatches based on the presence of a `structure` param
key (JSON from graphical editor) vs `markdown_source` (string from plaintext
editor). Same endpoint, same response format.

Same pattern for Quick Bites: `QuickBitesWriteService` gains
`update_from_structure(structure:, kitchen:)` alongside the existing
`update(content:, kitchen:)`.

## Editor Controller Architecture

### Current structure:
- `editor_controller` — generic dialog lifecycle
- `recipe_editor_controller` — plaintext textarea + highlight overlay +
  category/tag side panel

### New structure:
- `editor_controller` — unchanged, still owns dialog lifecycle
- `recipe_editor_controller` — **coordinator**. Owns mode toggle and routes
  `editor:collect` / `editor:content-loaded` / `editor:modified` to the
  active child
- `recipe_plaintext_controller` — textarea + highlight overlay, extracted from
  current `recipe_editor_controller`. No side panel — category and tags are
  front matter lines
- `recipe_graphical_controller` — form-based editor (see UI section below)

Same pattern for Quick Bites:
- `quickbites_editor_controller` — coordinator with mode toggle
- `quickbites_plaintext_controller` — textarea + highlight overlay
- `quickbites_graphical_controller` — category/item form

### Mode toggle

A small `</>` icon button in the editor dialog's header bar. Toggling:

1. Active mode serializes its state (plaintext → markdown string, graphical →
   JSON structure)
2. Coordinator stores that state
3. For graphical → plaintext: coordinator POSTs the JSON structure to
   `POST /recipes/serialize` (or `POST /menu/serialize_quick_bites`), which
   returns `{ markdown: "..." }`. Populates the textarea.
4. For plaintext → graphical: coordinator POSTs the markdown string to
   `POST /recipes/parse` (or `POST /menu/parse_quick_bites`), which returns
   the IR as JSON. Populates the form.
5. New mode becomes visible, old mode hides

These are stateless utility endpoints on the existing controllers — no
authentication or tenant scoping needed beyond what the controllers already
enforce. They do not write to the database.

### Mode preference

Stored in `localStorage`. Initial default is graphical mode. The preference
persists per-browser — same person may prefer different modes on phone vs
desktop.

## Graphical Recipe Editor UI

Form-based editor inside the existing editor dialog:

**Top section:**
- Title — text input
- Description — textarea (optional)
- Front matter row: Serves (input), Makes (input), Category (dropdown with
  inline "New category..." creation)
- Tags — pill input with autocomplete (reuses existing `tag_input_controller`)

**Steps section:**
- Collapsible accordion cards, one per step
- Collapsed: step name + ingredient count summary
- Expanded: step name input, ingredient rows, instructions textarea
- Ingredient rows: three fields per row — Name, Qty, Prep note. ↑↓ buttons
  for reordering. Add/remove buttons.
- Step reordering via ↑↓ buttons on the card header
- Add Step button at the bottom

**Cross-reference steps:**
- Rendered as read-only cards showing the target recipe name, multiplier, and
  prep note
- "Edit in </> mode" hint text
- Not editable in graphical mode (deferred to a future stage)
- Pass through unchanged during serialization

**Footer section:**
- Textarea (optional), labeled "Notes, history, credits"

## Graphical Quick Bites Editor UI

Simpler two-level form:

**Categories** as collapsible accordion cards:
- Category name is an editable inline input in the card header
- Reorder categories via ↑↓ buttons
- Add/remove categories

**Items** within each category:
- Two fields per row: Name (text input) and Ingredients (comma-separated text
  input)
- ↑↓ buttons for reordering within a category
- Add/remove items

## Validation in Graphical Mode

The graphical editor's structured form prevents most syntax errors by
construction (no way to forget `## ` or `- `). Remaining validation:

- **Title required** — client-side: disable Save when title is blank.
  Server-side: `RecipeWriteService` already validates title presence.
- **At least one step required** — client-side: prevent removing the last
  step. Server-side: `MarkdownImporter` raises if steps are empty.
- **Step name required** — client-side: highlight blank step names on save
  attempt. Server-side: the parser requires step headers.
- **Whitespace-only fields** — client-side: trim on collect. Server-side:
  the parser and importer already handle blank strings.
- **Tag format** — the existing `tag_input_controller` enforces `[a-zA-Z-]`
  with hyphen normalization; reused in graphical mode.

Server-side validation is unchanged — both paths produce the same IR, which
goes through the same validation in `MarkdownImporter` and
`RecipeWriteService`. The graphical path returns 422 with `{ errors: [...] }`
just like the plaintext path, and the coordinator displays errors the same
way.

## Loading Existing Recipes in Graphical Mode

When the editor opens in graphical mode for an existing recipe, the
`content` endpoint (`GET /recipes/:slug/content`) returns the IR structure
alongside the markdown source. This avoids a second round-trip to parse:

```json
{
  "markdown_source": "# Scrambled Eggs\n...",
  "category": "Basics",
  "tags": ["breakfast", "quick"],
  "structure": { "title": "...", "steps": [...], ... }
}
```

The coordinator routes `markdown_source` to the plaintext controller and
`structure` to the graphical controller. Only the active mode consumes its
data; the other is available if the user toggles.

For existing recipes whose `markdown_source` lacks `Category:` and `Tags:`
front matter, the `content` endpoint uses the serializer to regenerate
`markdown_source` from the DB record, which will include the front matter
lines. This ensures plaintext mode always shows complete front matter.

## Staging

Five stages, each independently shippable:

### Stage 1: Front matter extension
- Parser accepts `Category:` and `Tags:` in front matter
- `MarkdownImporter` passes them through to `RecipeWriteService`
- Highlight overlay colors the new front matter lines
- Canonical serializer (`FamilyRecipes::RecipeSerializer`)
- Tag hyphen normalization
- Round-trip tests: parse → serialize → parse → assert equality

### Stage 2: MarkdownImporter accepts structured input
- Extract `import_from_structure(ir_hash, ...)` entry point
- Structured path uses serializer to generate `markdown_source`
- Controller gains second param format (JSON structure)

### Stage 3: Plaintext editor simplification
- Remove category dropdown and tag pills side panel
- Plaintext editor = textarea + highlight overlay only
- Category and tags come from front matter exclusively
- On load, pre-populate front matter lines from DB values for existing recipes
  that lack them

### Stage 4: Recipe graphical editor
- New `recipe_graphical_controller` with form layout
- `recipe_editor_controller` becomes coordinator with mode toggle
- `recipe_plaintext_controller` extracted from existing code
- Mode preference in localStorage
- Cross-reference steps as read-only cards
- "New Recipe" in graphical mode: empty form with one blank step pre-created

### Stage 5: Quick Bites graphical editor
- Coordinator + plaintext + graphical controllers
- `FamilyRecipes::QuickBitesSerializer`
- Structured import path for Quick Bites

## Non-Goals

- Rich text editing for prose sections (future upgrade path exists — replace
  instruction textareas with a rich-text editor)
- Cross-reference editing in graphical mode (read-only cards for now)
- CodeMirror or other advanced plaintext editing (future possibility)
- Drag-and-drop reordering (↑↓ buttons throughout; drag-and-drop is a future
  polish item)
- Mobile-specific layout changes (the form layout is responsive by default;
  the accordion pattern works on small screens)
