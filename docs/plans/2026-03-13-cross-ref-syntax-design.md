# Cross-Reference Syntax Change + Hyperlinks

**Date:** 2026-03-13
**Issue:** GH #220

## Summary

Two changes to cross-reference syntax:

1. **Import syntax**: `>>> @[Title]` → `> @[Title]` (or `>@[Title]`). The
   three `>` symbols feel like too much; a single `>` is unambiguous when
   followed by `@[`.
2. **Hyperlinks**: Bare `@[Title]` in prose or footer text renders as a
   clickable link to the referenced recipe. No ingredient import, no
   multiplier, no DB tracking. If the link breaks (target renamed/deleted),
   it breaks — no cascade machinery.

## Part 1: Import Syntax Change

### LineClassifier

Pattern changes from `/^>>>\s+(.+)$/` to `/^>\s*@\[(.+)$/`.

The new pattern requires `@[` after `>` (with optional whitespace), so plain
`>` lines (Markdown blockquotes) are not captured. The captured content starts
at `@[`, which is what `CrossReferenceParser.parse` already expects.

**Note:** The captured group shifts. Currently `token.content[0]` yields the
full text after `>>> ` (e.g., `@[Pizza Dough], 2`). The new pattern should
capture the same content — everything from `@[` onward — so
`CrossReferenceParser` needs no changes.

### CrossReferenceParser

No changes. It already parses `@[Title], multiplier: prep note`. The
`OLD_SYNTAX` rejection pattern also stays — it guards against `2 @[Title]`
which is independent of the `>` prefix.

### RecipeBuilder

Error messages reference `>>>` in three places (lines 141, 152, 157). Update
to `>` for clarity. No logic changes.

### MarkdownImporter

No changes. It receives parsed cross-reference data from RecipeBuilder, not
raw syntax.

### CrossReferenceUpdater

No changes. The `gsub("@[#{old_title}]", "@[#{new_title}]")` pattern doesn't
reference `>>>` — it operates on the `@[Title]` portion, which is unchanged.

### Editor Highlighting (JS)

`recipe_editor_controller.js` line 64: regex changes from `/^>>>\s+.+$/` to
match the new `> @[` / `>@[` pattern.

### Seeds

One seed file uses cross-references: `Pasta with Tomato Sauce.md`. Update to
new syntax. Also add a hyperlink example to a seed recipe to exercise the new
rendering path.

### Backward Compatibility

None. Old `>>>` syntax stops working. Per CLAUDE.md: "not beholden to legacy
code." Users re-save existing recipes and they're fine. The markdown source is
the canonical input; the DB is rebuilt from it.

## Part 2: Inline Hyperlinks

### Concept

`@[Recipe Title]` appearing in prose (step instructions) or footer text
renders as an anchor tag linking to that recipe. It's purely a display concern
— no DB records, no models, no multipliers, no rename cascading.

### Where Allowed

- Step instructions (prose lines) — yes
- Recipe footer — yes
- Ingredient lines — no (structured parsing, would be ambiguous)
- Step headers — no (structural element)
- Title — no

### Rendering

A single helper method `linkify_recipe_references(html)` in `RecipesHelper`:

1. Scans rendered HTML for `@[Title]` patterns (literal text after Redcarpet's
   `escape_html` pass)
2. Slugifies the title via `FamilyRecipes.slugify`
3. Replaces with `<a href="#{recipe_path(slug)}" class="recipe-link">Title</a>`
4. Needs kitchen context for URL generation — available via
   `default_url_options` which auto-injects `kitchen_slug`

Applied in three rendering paths:

- **`render_markdown(text)`** — footer rendering. Redcarpet first, then
  linkify.
- **`scalable_instructions(text)`** — step instruction rendering. Redcarpet +
  scalable number processing, then linkify.
- **`processed_instructions` in views** — pre-rendered HTML stored on Step.
  Pipe through linkifier at render time (small change in `_step.html.erb`
  line 44, and in `MarkdownImporter#process_instructions`).

### Pattern Safety

Redcarpet with `escape_html: true` converts `@[Title]` to literal text in the
HTML output. The `@` and `[` `]` characters have no special meaning in
Redcarpet's Markdown dialect, so they pass through unmodified. The regex
replacement operates on safe, escaped HTML.

The helper must avoid double-linkifying (e.g., if `@[Title]` appears inside
an already-rendered `<a>` tag). Since the only `<a>` tags in rendered recipe
content come from Redcarpet Markdown links (`[text](url)`), and those don't
contain `@[`, this isn't a practical concern. But a negative lookbehind or
check that we're not inside a tag is cheap insurance.

### Editor Highlighting (JS)

Add inline highlighting for `@[Title]` in prose lines. Use a distinct style
from the `hl-cross-ref` class — a subtle underline or different color to
suggest "this is a link, not an import."

### No DB Involvement

- No new models or migrations
- No CrossReference records for hyperlinks
- No rename cascading — if the target recipe is renamed, the `@[Old Title]`
  becomes a dead link (resolves to a 404 slug). Acceptable trade-off for
  simplicity.
- No nutrition, meal plan, or grocery impact

## Files Changed

### Ruby
- `lib/familyrecipes/line_classifier.rb` — pattern change
- `lib/familyrecipes/recipe_builder.rb` — error message text
- `app/helpers/recipes_helper.rb` — new `linkify_recipe_references` helper,
  updated `render_markdown` and `scalable_instructions`
- `app/views/recipes/_step.html.erb` — pipe `processed_instructions` through
  linkifier

### JavaScript
- `app/javascript/controllers/recipe_editor_controller.js` — update cross-ref
  regex, add inline `@[Title]` highlighting

### CSS
- `app/assets/stylesheets/style.css` — add `.recipe-link` style

### Seeds
- `db/seeds/recipes/Basics/Pasta with Tomato Sauce.md` — new syntax
- One seed recipe — add hyperlink example in prose or footer

### Tests
- `test/line_classifier_test.rb` — update cross-ref tests, add `> @[` cases
- `test/cross_reference_parser_test.rb` — no changes expected
- `test/recipe_builder_test.rb` — update any tests using `>>>` syntax
- `test/services/markdown_importer_test.rb` — update cross-ref import tests
- `test/services/cross_reference_updater_test.rb` — update if test fixtures
  use `>>>` in markdown source
- `test/helpers/recipes_helper_test.rb` — new tests for
  `linkify_recipe_references`
- Integration tests for hyperlink rendering in instructions and footer

### Docs
- `CLAUDE.md` — update cross-reference syntax documentation
