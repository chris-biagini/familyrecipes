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

Pattern changes from `/^>>>\s+(.+)$/` to `/^>\s*(@\[.+)$/`.

The capture group includes `@[` so that `token.content[0]` yields
`@[Pizza Dough], 2` — exactly what `CrossReferenceParser.parse` expects
(its pattern starts with `\A@\[`). The `>` prefix and optional whitespace
are consumed but not captured, matching the old behavior where `>>>` was
consumed and only the `@[...]` portion was passed through.

### CrossReferenceParser

No changes. It already parses `@[Title], multiplier: prep note`. The
`OLD_SYNTAX` rejection pattern also stays — it guards against `2 @[Title]`
which is independent of the `>` prefix.

### RecipeBuilder

Error messages reference `>>>` in three places (lines 141, 152, 157). Update
to `>` for clarity. No logic changes.

### IngredientParser

Error message at line 8 references `>>>` syntax — update to `>`. Test at
`test/ingredient_parser_test.rb:86` asserts `>>> syntax` in the error — update.

### MarkdownImporter

Header comment references `>>>` syntax — update. No logic changes; it receives
parsed cross-reference data from RecipeBuilder, not raw syntax.

### CrossReferenceUpdater

No changes. The `gsub("@[#{old_title}]", "@[#{new_title}]")` operates on the
`@[Title]` portion, which is unchanged. **Side effect:** this gsub also
catches `@[Title]` hyperlinks in prose/footer, giving hyperlinks free rename
cascading as a bonus — desirable behavior.

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

Applied at render time only — never baked into stored HTML:

- **`render_markdown(text)`** — footer rendering (used in both
  `_recipe_content.html.erb` and `_embedded_recipe.html.erb`). Redcarpet
  first, then linkify.
- **`scalable_instructions(text)`** — step instruction rendering. Redcarpet +
  scalable number processing, then linkify.
- **`processed_instructions` in views** — pre-rendered HTML stored on Step.
  Pipe through linkifier at render time in `_step.html.erb` (line 44). Do
  NOT bake links into `MarkdownImporter#process_instructions` — that would
  create stale URLs on rename.

**Not applied to:** recipe descriptions (rendered as plain text, not
Markdown — `@[Title]` would display literally).

### Pattern Safety

Redcarpet with `escape_html: true` converts `@[Title]` to literal text in the
HTML output. The `@` and `[` `]` characters have no special meaning in
Redcarpet's Markdown dialect, so they pass through unmodified. The regex
replacement operates on safe, escaped HTML.

The helper must avoid replacing `@[Title]` inside HTML tags (`<a>`, `<code>`).
Use a non-greedy match `@\[(.+?)\]` (matching `CrossReferenceParser`'s
approach) and skip matches inside `<code>` spans or existing links. A simple
check that the match is not preceded by `>` (closing of an HTML tag) or inside
a `<code>` block is cheap insurance.

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
- `lib/familyrecipes/recipe_builder.rb` — error message text (`>>>` → `>`)
- `lib/familyrecipes/ingredient_parser.rb` — error message text (`>>>` → `>`)
- `lib/familyrecipes/step.rb` — header comment references `>>>`
- `app/services/markdown_importer.rb` — header comment references `>>>`
- `app/helpers/recipes_helper.rb` — new `linkify_recipe_references` helper,
  updated `render_markdown` and `scalable_instructions`
- `app/views/recipes/_step.html.erb` — pipe `processed_instructions` through
  linkifier
- `config/html_safe_allowlist.yml` — update line numbers if shifted

### JavaScript
- `app/javascript/controllers/recipe_editor_controller.js` — update cross-ref
  regex, add inline `@[Title]` highlighting

### CSS
- `app/assets/stylesheets/style.css` — add `.recipe-link` style

### Seeds
- `db/seeds/recipes/Basics/Pasta with Tomato Sauce.md` — new syntax
- One seed recipe — add hyperlink example in prose or footer

### Tests (all `>>>` → `>` in markdown fixtures)
- `test/line_classifier_test.rb` — update cross-ref tests, add `> @[` cases
- `test/cross_reference_parser_test.rb` — no changes expected
- `test/ingredient_parser_test.rb` — error message assertion
- `test/recipe_builder_test.rb`
- `test/build_validator_test.rb` (12 occurrences)
- `test/cross_reference_test.rb` (5 occurrences)
- `test/recipe_test.rb`
- `test/services/markdown_importer_test.rb`
- `test/services/cross_reference_updater_test.rb`
- `test/services/recipe_write_service_test.rb`
- `test/services/recipe_availability_calculator_test.rb`
- `test/services/shopping_list_builder_test.rb`
- `test/jobs/recipe_nutrition_job_test.rb`
- `test/nutrition_calculator_test.rb`
- `test/integration/end_to_end_test.rb`
- `test/helpers/recipes_helper_test.rb` — new tests for
  `linkify_recipe_references`

### Docs
- `CLAUDE.md` — update cross-reference syntax documentation
