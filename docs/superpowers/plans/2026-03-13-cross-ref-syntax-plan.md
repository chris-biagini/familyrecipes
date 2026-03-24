# Cross-Reference Syntax Change + Hyperlinks Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change cross-reference import syntax from `>>>` to `>` and add render-time `@[Title]` hyperlinks in prose/footer.

**Architecture:** Two independent features sharing the `@[Title]` pattern. Part 1 is a mechanical syntax swap across parser + tests. Part 2 adds a render-time helper that linkifies `@[Title]` in HTML output — no DB changes.

**Tech Stack:** Ruby/Rails, Minitest, Stimulus/JS, CSS

**Spec:** `docs/plans/2026-03-13-cross-ref-syntax-design.md`

---

## Chunk 1: Import Syntax Change (`>>>` → `>`)

### Task 1: Update LineClassifier pattern

**Files:**
- Modify: `lib/familyrecipes/line_classifier.rb:14`
- Test: `test/line_classifier_test.rb:127-145`

- [ ] **Step 1: Update the failing test expectations**

In `test/line_classifier_test.rb`, update the three cross-reference tests:

```ruby
def test_classifies_cross_reference_block
  type, content = LineClassifier.classify_line('> @[Pizza Dough]')

  assert_equal :cross_reference_block, type
  assert_equal ['@[Pizza Dough]'], content
end

def test_classifies_cross_reference_block_with_quantity_and_prep
  type, content = LineClassifier.classify_line('> @[Pizza Dough], 2: Let rest.')

  assert_equal :cross_reference_block, type
  assert_equal ['@[Pizza Dough], 2: Let rest.'], content
end

def test_four_angle_brackets_is_not_cross_reference_block
  type, _content = LineClassifier.classify_line('>>>> not a cross-ref')

  assert_equal :prose, type
end
```

Add new tests for no-space variant and plain blockquote rejection:

```ruby
def test_classifies_cross_reference_block_without_space
  type, content = LineClassifier.classify_line('>@[Pizza Dough]')

  assert_equal :cross_reference_block, type
  assert_equal ['@[Pizza Dough]'], content
end

def test_plain_blockquote_is_not_cross_reference
  type, _content = LineClassifier.classify_line('> some quoted text')

  assert_equal :prose, type
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/line_classifier_test.rb -n '/cross_reference|blockquote/'`
Expected: failures — the old `>>>` pattern doesn't match `> @[`.

- [ ] **Step 3: Update the LineClassifier pattern**

In `lib/familyrecipes/line_classifier.rb`, change line 14:

```ruby
cross_reference_block: /^>\s*(@\[.+)$/,
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/line_classifier_test.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/familyrecipes/line_classifier.rb test/line_classifier_test.rb
git commit -m "feat: change cross-reference syntax from >>> to > @["
```

### Task 2: Update error messages in RecipeBuilder and IngredientParser

**Files:**
- Modify: `lib/familyrecipes/recipe_builder.rb:141,152,157`
- Modify: `lib/familyrecipes/ingredient_parser.rb:8`
- Test: `test/ingredient_parser_test.rb:83-87`
- Test: `test/recipe_builder_test.rb` (error message assertions if any)

- [ ] **Step 1: Update RecipeBuilder error messages**

In `lib/familyrecipes/recipe_builder.rb`:

Line 141: change `Cross-reference (>>>)` to `Cross-reference (>)`
Line 152: change `cross-reference (>>>)` to `cross-reference (>)`
Line 157: change `Cross-reference (>>>)` to `Cross-reference (>)`

- [ ] **Step 2: Update IngredientParser error message**

In `lib/familyrecipes/ingredient_parser.rb`, line 8:

```ruby
raise "Cross-references now use > @[...] syntax. Write: > #{text}" if text.start_with?('@[')
```

- [ ] **Step 3: Update IngredientParser test assertion**

In `test/ingredient_parser_test.rb`, line 86:

```ruby
assert_match(/> @\[/, error.message)
```

- [ ] **Step 4: Run relevant tests**

Run: `ruby -Itest test/ingredient_parser_test.rb -n test_raises_on_cross_reference_syntax && ruby -Itest test/recipe_builder_test.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/familyrecipes/recipe_builder.rb lib/familyrecipes/ingredient_parser.rb test/ingredient_parser_test.rb
git commit -m "fix: update cross-reference error messages from >>> to >"
```

### Task 3: Update header comments referencing `>>>`

**Files:**
- Modify: `app/services/markdown_importer.rb:10`
- Modify: `lib/familyrecipes/step.rb:34`

- [ ] **Step 1: Update MarkdownImporter comment**

In `app/services/markdown_importer.rb`, line 10, change:
`cross-reference steps (>>> syntax,` to `cross-reference steps (> @[...] syntax,`

- [ ] **Step 2: Update Step comment**

In `lib/familyrecipes/step.rb`, line 34, change:
`cross_reference (from >>>)` to `cross_reference (from > @[...])`

- [ ] **Step 3: Commit**

```bash
git add app/services/markdown_importer.rb lib/familyrecipes/step.rb
git commit -m "docs: update header comments from >>> to > syntax"
```

### Task 4: Update all test fixtures (`>>>` → `>`)

This is a bulk find-and-replace across test files. The pattern is
`>>> @[` → `> @[` in all Markdown fixture strings.

**Files (all in `test/`):**
- `recipe_builder_test.rb`
- `build_validator_test.rb`
- `cross_reference_test.rb`
- `recipe_test.rb`
- `services/markdown_importer_test.rb`
- `services/cross_reference_updater_test.rb`
- `services/recipe_write_service_test.rb`
- `services/recipe_availability_calculator_test.rb`
- `services/shopping_list_builder_test.rb`
- `jobs/recipe_nutrition_job_test.rb`
- `nutrition_calculator_test.rb`
- `integration/end_to_end_test.rb`
- `controllers/recipes_controller_test.rb`

- [ ] **Step 1: Bulk replace `>>>` in test files**

Search for `>>> @[` and replace with `> @[` in all test files. Also search for
`>>>` in error message assertions and update them (e.g., `assert_match(/>>>/`
becomes `assert_match(/> @/`).

Be careful: some tests assert error messages containing `>>>` — update those
to match the new error text from Task 2.

- [ ] **Step 2: Run the full test suite**

Run: `rake test`
Expected: all tests pass. Any remaining `>>>` in Markdown fixtures will cause
parse failures (LineClassifier now treats `>>>` as prose, so RecipeBuilder
won't find the cross-reference).

- [ ] **Step 3: Commit**

```bash
git add test/
git commit -m "test: update all cross-reference fixtures from >>> to > syntax"
```

### Task 5: Update seed data and editor highlighting

**Files:**
- Modify: `db/seeds/recipes/Basics/Pasta with Tomato Sauce.md:9`
- Modify: `app/javascript/controllers/recipe_editor_controller.js:64`

- [ ] **Step 1: Update seed file**

In `db/seeds/recipes/Basics/Pasta with Tomato Sauce.md`, line 9, change
`>>> @[Simple Tomato Sauce]` to `> @[Simple Tomato Sauce]`.

Also add a footer with a hyperlink example:

```markdown
---

This pairs well with @[Simple Salad].
```

- [ ] **Step 2: Update editor cross-ref regex**

In `app/javascript/controllers/recipe_editor_controller.js`, line 64:

```javascript
} else if (/^>\s*@\[.+$/.test(line)) {
```

- [ ] **Step 3: Run tests and verify**

Run: `rake test`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add "db/seeds/recipes/Basics/Pasta with Tomato Sauce.md" app/javascript/controllers/recipe_editor_controller.js
git commit -m "feat: update seeds and editor highlighting for > syntax"
```

---

## Chunk 2: Inline Hyperlinks (`@[Title]`)

### Task 6: Add `linkify_recipe_references` helper with tests

**Files:**
- Modify: `app/helpers/recipes_helper.rb`
- Test: `test/helpers/recipes_helper_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/helpers/recipes_helper_test.rb`:

```ruby
test 'linkify_recipe_references converts @[Title] to link' do
  html = '<p>Try the @[Simple Tomato Sauce] next.</p>'
  result = linkify_recipe_references(html)

  assert_includes result, '<a href='
  assert_includes result, 'simple-tomato-sauce'
  assert_includes result, '>Simple Tomato Sauce</a>'
end

test 'linkify_recipe_references handles multiple references' do
  html = '<p>See @[Pizza Dough] and @[Tomato Sauce].</p>'
  result = linkify_recipe_references(html)

  assert_includes result, 'pizza-dough'
  assert_includes result, 'tomato-sauce'
end

test 'linkify_recipe_references ignores @[Title] inside code tags' do
  html = '<p>Use <code>@[Recipe Title]</code> syntax.</p>'
  result = linkify_recipe_references(html)

  refute_includes result, '<a href='
end

test 'linkify_recipe_references with no references returns unchanged html' do
  html = '<p>Just regular text.</p>'

  assert_equal html, linkify_recipe_references(html)
end

test 'linkify_recipe_references uses non-greedy match for brackets' do
  html = '<p>@[First] and @[Second]</p>'
  result = linkify_recipe_references(html)

  assert_includes result, '>First</a>'
  assert_includes result, '>Second</a>'
end

test 'render_markdown linkifies recipe references in footer text' do
  text = 'See also @[Pizza Dough].'
  result = render_markdown(text)

  assert_includes result, 'pizza-dough'
  assert_includes result, '>Pizza Dough</a>'
end

test 'scalable_instructions linkifies recipe references in prose' do
  text = 'Use the @[Simple Tomato Sauce] from yesterday.'
  result = scalable_instructions(text)

  assert_includes result, 'simple-tomato-sauce'
  assert_includes result, '>Simple Tomato Sauce</a>'
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/helpers/recipes_helper_test.rb -n '/linkify|linkifies/'`
Expected: failures — method doesn't exist yet.

- [ ] **Step 3: Implement `linkify_recipe_references`**

In `app/helpers/recipes_helper.rb`, add the constant and method before
the `private` keyword (before line 96):

```ruby
RECIPE_REF_PATTERN = /@\[(.+?)\]/

def linkify_recipe_references(html)
  return html unless html.include?('@[')

  html.gsub(RECIPE_REF_PATTERN) do |match|
    title = Regexp.last_match(1)
    next match if inside_html_tag?(Regexp.last_match.pre_match)

    slug = FamilyRecipes.slugify(title)
    %(<a href="#{recipe_path(slug)}" class="recipe-link">#{ERB::Util.html_escape(title)}</a>)
  end
end
```

Add the private helper below the `private` keyword:

```ruby
def inside_html_tag?(preceding)
  open = preceding.rindex('<')
  return false unless open

  close = preceding.rindex('>', open)
  close.nil? || close < open
end
```

- [ ] **Step 4: Wire into `render_markdown` and `scalable_instructions`**

Update `render_markdown` (line 18-22):

```ruby
def render_markdown(text)
  return '' if text.blank?

  html = FamilyRecipes::Recipe::MARKDOWN.render(text)
  linkify_recipe_references(html).html_safe # rubocop:disable Rails/OutputSafety
end
```

Update `scalable_instructions` (line 24-29):

```ruby
def scalable_instructions(text)
  return '' if text.blank?

  html = FamilyRecipes::Recipe::MARKDOWN.render(text)
  html = ScalableNumberPreprocessor.process_instructions(html)
  linkify_recipe_references(html).html_safe # rubocop:disable Rails/OutputSafety
end
```

- [ ] **Step 5: Update `html_safe_allowlist.yml` line numbers**

Adding the `linkify_recipe_references` call grows `render_markdown` and
`scalable_instructions` by one line each. This shifts four allowlist entries
in `recipes_helper.rb`. Run `rake lint:html_safe` and update the line numbers
for all `recipes_helper.rb` entries in `config/html_safe_allowlist.yml`.

- [ ] **Step 6: Run tests and lint**

Run: `rake`
Expected: all pass, 0 RuboCop offenses, html_safe audit clean.

- [ ] **Step 7: Commit**

```bash
git add app/helpers/recipes_helper.rb test/helpers/recipes_helper_test.rb config/html_safe_allowlist.yml
git commit -m "feat: add linkify_recipe_references helper for @[Title] hyperlinks"
```

### Task 7: Wire linkifier into `processed_instructions` view path

**Files:**
- Modify: `app/views/recipes/_step.html.erb:44`

- [ ] **Step 1: Update the view**

In `app/views/recipes/_step.html.erb`, line 42-45, change:

```erb
<%- if step.processed_instructions.present? -%>
<div class="instructions">
  <%= linkify_recipe_references(step.processed_instructions).html_safe %>
</div>
```

The `processed_instructions` is already pre-rendered safe HTML. We pipe it
through the linkifier (which only adds safe `<a>` tags with escaped titles)
before marking as `html_safe`.

- [ ] **Step 2: Run full test suite and lint**

Run: `rake`
Expected: all pass, 0 RuboCop offenses, html_safe audit clean. The
`_step.html.erb:44` allowlist entry should still be correct (same line
number). If not, update `config/html_safe_allowlist.yml`.

- [ ] **Step 3: Commit**

```bash
git add app/views/recipes/_step.html.erb
git commit -m "feat: linkify @[Title] in processed_instructions view path"
```

### Task 8: Add editor highlighting for inline `@[Title]`

**Files:**
- Modify: `app/javascript/controllers/recipe_editor_controller.js:57-75`
- Modify: `app/assets/stylesheets/style.css`

- [ ] **Step 1: Add inline `@[Title]` highlighting to the editor**

In `recipe_editor_controller.js`, update the `classifyLine` method. The last
`else` branch (line 73-74) currently does
`fragment.appendChild(document.createTextNode(line))`. Replace it with:

```javascript
} else {
  this.highlightProseLinks(line, fragment)
}
```

Add the new method after `highlightIngredient`:

```javascript
highlightProseLinks(line, fragment) {
  const pattern = /@\[(.+?)\]/g
  let lastIndex = 0
  let match

  while ((match = pattern.exec(line)) !== null) {
    if (match.index > lastIndex) {
      fragment.appendChild(document.createTextNode(line.slice(lastIndex, match.index)))
    }
    this.appendSpan(fragment, match[0], "hl-recipe-link")
    lastIndex = pattern.lastIndex
  }

  if (lastIndex < line.length) {
    fragment.appendChild(document.createTextNode(line.slice(lastIndex)))
  } else if (lastIndex === 0) {
    fragment.appendChild(document.createTextNode(line))
  }
}
```

- [ ] **Step 2: Add CSS for `.hl-recipe-link` (editor overlay)**

In `app/assets/stylesheets/style.css`, near the existing `.hl-cross-ref`
rule (around line 1736):

```css
.hl-recipe-link {
  color: var(--link-color);
  text-decoration: underline;
  text-decoration-style: dotted;
}
```

Use whatever `--link-color` variable exists, or fall back to the same color
used for regular links in the app. The dotted underline distinguishes it from
the cross-ref import style (bold red italic).

- [ ] **Step 3: Add CSS for `.recipe-link` (rendered output)**

Also in `style.css`, add a style for the rendered recipe links:

```css
a.recipe-link {
  text-decoration-style: dotted;
}
```

Keep it minimal — it inherits the standard link color. The dotted underline
signals "internal recipe link" vs regular Markdown links.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/recipe_editor_controller.js app/assets/stylesheets/style.css
git commit -m "feat: add editor highlighting and CSS for @[Title] recipe links"
```

### Task 9: Update CLAUDE.md and final verification

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

In the "Recipe & Data Formats" section, update the cross-reference syntax
reference. Change any mention of `>>>` to describe the new `> @[Title]`
syntax. Add a note about the `@[Title]` hyperlink syntax in prose/footer.

Also update `CrossReferenceParser` in the reference to mention `> @[Title]`
syntax instead of `>>> @[Title]`.

- [ ] **Step 2: Run full test suite and lint**

Run: `rake`
Expected: 0 RuboCop offenses, all tests pass, html_safe audit clean.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for new cross-reference and hyperlink syntax"
```

- [ ] **Step 4: Verify in browser (manual)**

Start the dev server (`bin/dev`) and:
1. Check that "Pasta with Tomato Sauce" renders its cross-reference correctly
2. Check that the footer hyperlink `@[Simple Salad]` renders as a clickable
   link
3. Open the recipe editor and verify syntax highlighting works for both
   `> @[Title]` (cross-ref style) and `@[Title]` in prose (link style)
