# Inline Cross-Reference Rendering

GitHub issue: #68

## Problem

Cross-references (`@[Pizza Dough]`) are currently treated as ingredients inside a
step's ingredient list. The referenced recipe renders as a hyperlink. Reading the
referenced recipe requires navigating away from the current recipe. This is
cumbersome and disconnects the reader from the flow of the parent recipe.

## Solution

Render the referenced recipe's content inline as an embedded card — visually, a
second sheet of paper laid on top of the main recipe card. The embedded card shows
the target recipe's steps (ingredients + instructions) in condensed form, with a
link to navigate to the full recipe.

## Markdown Syntax

### New syntax

Block-level `>>>` directive inside an explicit step:

```markdown
## Make dough.
>>> @[Pizza Dough]

## Make poached garlic.
- Garlic, 30 g
```

With multiplier and prep note:

```markdown
## Make dough.
>>> @[Pizza Dough], 2: Let rest 30 min.
```

### Old syntax removed (clean break)

The `- @[Recipe Title]` ingredient-style syntax is removed entirely. If a user
writes it, the parser raises: `Cross-references now use >>> syntax. Write:
>>> @[Recipe Title]`

### Syntax constraints

A cross-reference step is an explicit step (`##` header) containing exactly one
`>>>` line and nothing else. These constraints are enforced as parser errors:

| Violation | Error message |
|-----------|---------------|
| `>>>` without `##` header | `Cross-reference (>>>) at line N must appear inside an explicit step (## Step Name)` |
| `>>>` mixed with ingredients | `Cross-reference (>>>) at line N cannot be mixed with ingredients in the same step` |
| `>>>` mixed with instructions | `Cross-reference (>>>) at line N cannot be mixed with instructions in the same step` |
| Multiple `>>>` in one step | `Only one cross-reference (>>>) is allowed per step (line N)` |

Implicit steps (ingredients without a `##` header) cannot contain `>>>`. Implicit
steps are for simple single-step recipes and must be self-contained.

### CrossReferenceUpdater behavior

**Rename:** `gsub("@[Old]", "@[New]")` still works — it matches the `@[...]`
portion regardless of whether the line starts with `- ` or `>>> `. No change
needed.

**Delete:** `strip_references` is removed. Recipe deletion nullifies inbound
cross-references (`target_recipe_id` → nil) and re-broadcasts parent recipe pages
to show a broken-reference warning card. The Markdown source is preserved — if a
recipe with the same name is later created, the reference resolves automatically.

## Parser Changes

### LineClassifier

New pattern added to `LINE_PATTERNS`:

```ruby
cross_reference_block: /^>>>\s+(.+)$/
```

Placed after `:ingredient` and before `:divider`. Captures everything after
`>>> ` as content.

### CrossReferenceParser (new module)

Extracted from `IngredientParser`. Parses the content captured by LineClassifier:

- Input: `@[Pizza Dough], 2: Let rest 30 min.`
- Output: `{ target_title: "Pizza Dough", multiplier: 2.0, prep_note: "Let rest 30 min." }`

Takes `CROSS_REF_PATTERN` and `parse_multiplier` from the current
`IngredientParser`.

### IngredientParser

All cross-reference handling removed. If input starts with `@[`, raises a helpful
error pointing to the `>>>` syntax.

### RecipeBuilder

`collect_step_body` handles the new `:cross_reference_block` token:

1. Parse content via `CrossReferenceParser.parse`
2. Store in step data as `cross_reference:` key
3. Stop collecting — any non-blank tokens before the next step header are errors

Step data shapes:

```ruby
# Normal step
{ tldr: "Step title", ingredients: [...], instructions: "..." }

# Cross-reference step
{ tldr: "Step title",
  cross_reference: { target_title: "Pizza Dough", multiplier: 1.0, prep_note: nil },
  ingredients: [],
  instructions: nil }
```

If `:cross_reference_block` appears during implicit step parsing, raise an error.

## Data Model

### No schema changes

The existing `cross_references` table works as-is. The `position` column becomes
always-0 (one cross-reference per step), but removing it isn't worth a migration.

### Step model additions

```ruby
def cross_reference_step?
  cross_references.any?   # no query when eager-loaded
end

def cross_reference_block
  cross_references.first
end
```

### Recipe association change

```ruby
has_many :inbound_cross_references, class_name: 'CrossReference',
                                    foreign_key: :target_recipe_id,
                                    inverse_of: :target_recipe,
                                    dependent: :nullify   # was no dependent
```

When a recipe is destroyed, inbound cross-references get `target_recipe_id` set
to nil. The cross-references remain in their parent recipes. The view renders a
broken-reference warning card.

### MarkdownImporter

`replace_steps` branches on step data shape:

```ruby
if step_data[:cross_reference]
  import_cross_reference(step, step_data[:cross_reference])
else
  import_step_items(step, step_data[:ingredients])
end
```

`import_cross_reference` creates a CrossReference with `position: 0`.

## View Rendering

### Partial flow

```
recipe_content.html.erb
  steps.each → step.html.erb (embedded: false, heading_level: 2)
    ├─ Normal step → ingredients + instructions (unchanged)
    ├─ Cross-ref step, resolved →
    │    embedded_recipe.html.erb (cross_reference:)
    │      target_recipe.steps.each → step.html.erb (embedded: true, heading_level: 3)
    │        ├─ Normal step → ingredients + instructions
    │        └─ Cross-ref step → link (no recursion)
    └─ Cross-ref step, pending → broken_reference.html.erb
```

### Step partial locals

```erb
<%# locals: (step:, embedded: false, heading_level: 2) %>
```

- `embedded:` — when true, cross-reference steps render as links instead of
  embedded cards. Prevents recursive embedding.
- `heading_level:` — 2 for top-level steps, 3 for steps inside an embedded
  recipe. Maintains correct heading hierarchy.

### One-level embedding rule

When rendering an embedded recipe's steps, any cross-reference steps within it
render as links (the current behavior). This prevents infinite nesting and
circular references without any special detection logic:

- White Pizza embeds Pizza Dough → embedded card with full content
- Pizza Dough references Some Starter → renders as a link inside the card
- Circular (A embeds B, B embeds A) → A shows B as a card, B's reference back
  to A renders as a link. No loop.

### Heading levels

- `<h2>` — parent step header ("Make dough.")
- Embedded card title — styled link, not a heading element (navigational, not
  structural)
- `<h3>` — embedded recipe's step headers ("Mix dry ingredients.", "Knead.")

### Eager loading

Controller show action:

```ruby
.includes(steps: [
  :ingredients,
  { cross_references: {
    target_recipe: { steps: [:ingredients, :cross_references] }
  } }
])
```

Loads the target recipe's steps and ingredients (for rendering) plus their
cross-references (for detection — render as links). Does not load the second
level's target recipes.

### Multiplier scaling

When a cross-reference has `multiplier: 2`, the embedded recipe's ingredient
quantities display doubled. Apply the multiplier to `data-base-quantity`
attributes at render time so the JavaScript scaling system works on top of the
already-multiplied base.

## Visual Design

### Embedded recipe card

```
┌──────────────────────────────────────────┐
│              White Pizza                 │
│          Pizza · Makes 2 pizzas          │
│                                          │
│  Make dough.                             │
│  ┌──────────────────────────────────┐    │
│  │  Pizza Dough                   → │    │
│  │                                  │    │
│  │  Mix dry ingredients.            │    │
│  │  Flour       500 g              │    │
│  │  Salt        10 g               │    │
│  │                                  │    │
│  │  Knead.                          │    │
│  │  Water       300 ml             │    │
│  │  Knead 10 minutes...            │    │
│  └──────────────────────────────────┘    │
│                                          │
│  Make poached garlic.                    │
│  Garlic                    30 g          │
│  ...                                     │
└──────────────────────────────────────────┘
```

- Same `border`, `border-radius`, `box-shadow` as the main `<main>` card — two
  sheets of the same paper
- Full content-area width (no horizontal inset)
- Card header: recipe title as a link, multiplier indicator if != 1.0, prep note
  if present
- Steps inside the card use tighter spacing than the main recipe
- `<h3>` headers styled smaller/lighter than the main recipe's `<h2>` headers

### Broken reference card

```
│  Make dough.                             │
│  ┌──────────────────────────────────┐    │
│  │  This step references            │    │
│  │  "Pizza Dough", but no recipe    │    │
│  │  with that name exists.          │    │
│  └──────────────────────────────────┘    │
```

Same card shape so layout doesn't shift if the reference is later resolved. Muted
text, faint warm background tint to signal "something's off" without being
alarming.

### Mobile

The main card drops border/shadow on small screens. The embedded card keeps its
border and shadow — that's the only visual distinction from surrounding content.

### Print

Embedded card flattens for print — retains a thin border for grouping, drops
shadow.

### Crossed-off interaction

The existing click-to-cross-off feature (recipe-state Stimulus controller) should
work inside embedded recipes — same markup structure. Crossed-off state keys need
namespacing (e.g., prefixed with cross-reference ID) so embedded step state
doesn't collide with parent recipe state.

## Live Updates / Broadcaster

### Cascade rule

When a recipe is updated, RecipeBroadcaster re-renders its own show page AND the
show pages of every recipe that embeds it. The parent page re-render is a
terminal operation — it does not trigger further cascade.

This mirrors the one-level embedding rule in the view: the broadcaster goes
exactly as deep as the view renders.

### Scenario: target recipe updated

1. Pizza Dough saved → `RecipeBroadcaster.broadcast(recipe: pizza_dough)`
2. `broadcast_recipe_updated` re-renders Pizza Dough's page
3. Queries `pizza_dough.referencing_recipes` → finds White Pizza
4. `broadcast_referencing_recipe_page(white_pizza)` — Turbo Stream replace of
   `#recipe-content` only. No toast, no listings, no further cascade.

### Scenario: target recipe deleted

1. Capture `parent_ids = @recipe.referencing_recipes.pluck(:id)` before destroy
2. `@recipe.destroy!` — `dependent: :nullify` sets `target_recipe_id = nil`
3. Existing cleanup (categories, meal plan, main broadcast)
4. Re-query parents with fresh eager loading (picks up nullified state)
5. `broadcast_referencing_recipe_page` for each — view renders broken-reference
   card

### Scenario: target recipe created (resolves pending references)

1. `MarkdownImporter.import` saves Pizza Dough
2. `CrossReference.resolve_pending` links pending references
3. `broadcast_recipe_updated(pizza_dough)` queries `referencing_recipes` — finds
   White Pizza (now linked by resolve_pending)
4. Re-renders White Pizza's page — embedded card appears where broken-reference
   card was

### Scenario: target recipe renamed

Handled by existing `CrossReferenceUpdater.rename_references`:

1. Rewrites `@[Old]` → `@[New]` in referencing recipes' Markdown
2. Re-imports each via `MarkdownImporter.import`
3. Each re-import triggers its own broadcast cycle

No new cascade logic needed.

### Edge cases

**Version hash:** Parent recipe's `markdown_source` doesn't change when a
target recipe is updated — only the rendered view changes. The version hash
stays the same, which is correct.

**Nobody viewing the parent:** Turbo Stream broadcast is a no-op. Next page
load renders fresh data.

**`broadcast_referencing_recipe_page` is terminal:** It does a Turbo Stream
replace only. No broadcaster cycle, no action callbacks, no further
`referencing_recipes` queries.

## Testing Strategy

### Parser tests (Minitest::Test)

**LineClassifier:** new `:cross_reference_block` token type; edge cases (no
content, extra `>`).

**CrossReferenceParser:** title, multiplier (integer, fraction, decimal), prep
note, trailing period, missing `@[...]`, old quantity-first syntax.

**IngredientParser:** regular ingredients unchanged; `@[...]` input raises
error pointing to `>>>` syntax.

**RecipeBuilder constraints:** all five validation errors from the constraints
table. Valid cross-reference steps produce correct data shape. Normal steps
before/after cross-reference steps parse correctly.

### Model tests (ActiveSupport::TestCase)

**Step:** `cross_reference_step?` true/false, `cross_reference_block`
present/nil.

**Recipe:** destroying nullifies inbound cross-references (not destroys);
`referencing_recipes` query.

### Service tests

**MarkdownImporter:** `>>>` syntax creates Step with one CrossReference and no
Ingredients; cross-reference resolution with new syntax; round-trip
import/modify/re-import.

**CrossReferenceUpdater:** `rename_references` with `>>>` syntax;
`strip_references` removed.

**RecipeBroadcaster:** update cascades to referencing recipes; create resolves
and cascades; `broadcast_referencing_recipe_page` does not cascade further.

### Controller tests

**show:** resolved cross-reference → 200 with embedded content; pending →
200 with warning.

**create:** `>>>` syntax accepted; old `- @[...]` syntax → 422.

**update:** target recipe update triggers parent re-broadcast; rename cascades.

**destroy:** inbound references nullified; parent pages re-broadcast.

### Seed validation

`rake db:seed` passes after Markdown migration. All cross-references resolve.
