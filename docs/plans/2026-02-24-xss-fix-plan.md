# XSS Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Close XSS vulnerability #85 by escaping all user-provided HTML in recipe rendering.

**Architecture:** Four targeted fixes — renderer option, preprocessor escaping, two view-level escapes — each verified by tests before and after. No new dependencies.

**Tech Stack:** Redcarpet `escape_html` option, `ERB::Util.html_escape`, Minitest integration tests.

---

### Task 1: Escape HTML in the Redcarpet renderer

**Files:**
- Modify: `lib/familyrecipes/recipe.rb:12-16`
- Test: `test/lib/xss_escape_test.rb` (create)

**Step 1: Write the failing test**

Create `test/lib/xss_escape_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class XssEscapeTest < ActiveSupport::TestCase
  test 'MARKDOWN renderer escapes raw script tags' do
    output = FamilyRecipes::Recipe::MARKDOWN.render('<script>alert("xss")</script>')

    assert_includes output, '&lt;script&gt;'
    assert_not_includes output, '<script>'
  end

  test 'MARKDOWN renderer preserves markdown-generated HTML' do
    output = FamilyRecipes::Recipe::MARKDOWN.render('**bold** and *italic*')

    assert_includes output, '<strong>bold</strong>'
    assert_includes output, '<em>italic</em>'
  end

  test 'MARKDOWN renderer escapes img onerror payload' do
    output = FamilyRecipes::Recipe::MARKDOWN.render('<img src=x onerror=alert(1)>')

    assert_not_includes output, 'onerror'
    assert_includes output, '&lt;img'
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/lib/xss_escape_test.rb`
Expected: FAIL — `<script>` appears unescaped in output.

**Step 3: Write the fix**

In `lib/familyrecipes/recipe.rb`, change line 13 from:

```ruby
Redcarpet::Render::SmartyHTML.new,
```

to:

```ruby
Redcarpet::Render::SmartyHTML.new(escape_html: true),
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/lib/xss_escape_test.rb`
Expected: PASS — all three tests green.

**Step 5: Run full test suite**

Run: `rake test`
Expected: All existing tests pass. The renderer change should not break anything — markdown syntax still produces HTML; only raw HTML tags are escaped.

**Step 6: Commit**

```bash
git add lib/familyrecipes/recipe.rb test/lib/xss_escape_test.rb
git commit -m "fix: escape raw HTML in Redcarpet renderer (#85)"
```

---

### Task 2: Escape user content in ScalableNumberPreprocessor

**Files:**
- Modify: `lib/familyrecipes/scalable_number_preprocessor.rb:49-60, 74-76`
- Test: `test/lib/scalable_number_preprocessor_test.rb` (existing — add tests)

**Step 1: Find and read existing preprocessor tests**

Check if `test/lib/scalable_number_preprocessor_test.rb` exists. If not, create it.

**Step 2: Write failing tests**

Add these tests (to existing file or new file):

```ruby
test 'build_span escapes HTML in original_text' do
  result = ScalableNumberPreprocessor.process_instructions('<b>3</b>*')

  assert_not_includes result, '<b>'
  assert_includes result, '&lt;b&gt;'
end

test 'process_yield_with_unit escapes unit_singular in data attribute' do
  result = ScalableNumberPreprocessor.process_yield_with_unit(
    '12 loaves', '"><script>alert(1)</script>', 'loaves'
  )

  assert_not_includes result, '<script>'
  assert_includes result, '&lt;script&gt;'
end

test 'process_yield_with_unit escapes unit_plural in data attribute' do
  result = ScalableNumberPreprocessor.process_yield_with_unit(
    '12 loaves', 'loaf', '"><script>alert(2)</script>'
  )

  assert_not_includes result, '<script>'
  assert_includes result, '&lt;script&gt;'
end
```

**Step 3: Run tests to verify they fail**

Run: `ruby -Itest test/lib/scalable_number_preprocessor_test.rb`
Expected: FAIL — raw `<script>` tags appear in output.

**Step 4: Write the fix**

In `lib/familyrecipes/scalable_number_preprocessor.rb`:

Change `build_span` (line 74-76) from:

```ruby
def build_span(value, original_text)
  %(<span class="scalable" data-base-value="#{value}" data-original-text="#{original_text}">#{original_text}</span>)
end
```

to:

```ruby
def build_span(value, original_text)
  escaped = ERB::Util.html_escape(original_text)
  %(<span class="scalable" data-base-value="#{value}" data-original-text="#{escaped}">#{escaped}</span>)
end
```

Change `process_yield_with_unit` (lines 49-60) from:

```ruby
def process_yield_with_unit(text, unit_singular, unit_plural)
  match = text.match(YIELD_NUMBER_PATTERN)
  return text unless match

  value = match[1] ? WORD_VALUES[match[1].downcase] : parse_numeral(match[2])
  inner_span = build_span(value, match[1] || match[2])
  rest = text[match.end(0)..]
  "#{text[...match.begin(0)]}" \
    "<span class=\"yield\" data-base-value=\"#{value}\" " \
    "data-unit-singular=\"#{unit_singular}\" data-unit-plural=\"#{unit_plural}\">" \
    "#{inner_span}#{rest}</span>"
end
```

to:

```ruby
def process_yield_with_unit(text, unit_singular, unit_plural)
  match = text.match(YIELD_NUMBER_PATTERN)
  return text unless match

  value = match[1] ? WORD_VALUES[match[1].downcase] : parse_numeral(match[2])
  inner_span = build_span(value, match[1] || match[2])
  rest = ERB::Util.html_escape(text[match.end(0)..])
  escaped_singular = ERB::Util.html_escape(unit_singular)
  escaped_plural = ERB::Util.html_escape(unit_plural)
  "#{ERB::Util.html_escape(text[...match.begin(0)])}" \
    "<span class=\"yield\" data-base-value=\"#{value}\" " \
    "data-unit-singular=\"#{escaped_singular}\" data-unit-plural=\"#{escaped_plural}\">" \
    "#{inner_span}#{rest}</span>"
end
```

**Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/lib/scalable_number_preprocessor_test.rb`
Expected: PASS.

**Step 6: Run full test suite**

Run: `rake test`
Expected: All pass.

**Step 7: Commit**

```bash
git add lib/familyrecipes/scalable_number_preprocessor.rb test/lib/scalable_number_preprocessor_test.rb
git commit -m "fix: escape user content in ScalableNumberPreprocessor (#85)"
```

---

### Task 3: Fix view-level html_safe calls

**Files:**
- Modify: `app/views/recipes/_step.html.erb:19`
- Modify: `app/views/recipes/_nutrition_table.html.erb:16`
- Test: `test/integration/xss_prevention_test.rb` (create)

**Step 1: Write failing integration tests**

Create `test/integration/xss_prevention_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class XssPreventionTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    Category.create!(name: 'Test', slug: 'test', position: 0, kitchen: @kitchen)
  end

  test 'script tag in instructions is escaped' do
    import_recipe(<<~MD)
      # Safe Recipe

      Category: Test

      ## Step one (do it)

      - Flour, 2 cups

      Mix for 3* minutes. <script>alert('xss')</script>
    MD

    get recipe_path('safe-recipe', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_no_match(/<script>alert/, response.body)
    assert_includes response.body, '&lt;script&gt;'
  end

  test 'img onerror in step title is escaped' do
    import_recipe(<<~MD)
      # Safe Recipe

      Category: Test

      ## Mix <img onerror=alert(1)> (do it)

      - Flour, 2 cups

      Mix it.
    MD

    get recipe_path('safe-recipe', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_no_match(/onerror=alert/, response.body)
  end

  test 'script tag in footer is escaped' do
    import_recipe(<<~MD)
      # Safe Recipe

      Category: Test

      ## Mix (do it)

      - Flour, 2 cups

      Mix it.

      ---

      Source: <script>alert('xss')</script>
    MD

    get recipe_path('safe-recipe', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_no_match(/<script>alert/, response.body)
  end

  test 'malicious makes unit is escaped in yield display' do
    import_recipe(<<~MD)
      # Safe Recipe

      Category: Test
      Makes: 12 <b>loaves</b>

      ## Mix (do it)

      - Flour, 2 cups

      Mix it.
    MD

    get recipe_path('safe-recipe', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_no_match(/<b>loaves<\/b>/, response.body)
  end

  private

  def import_recipe(markdown)
    MarkdownImporter.import(markdown, kitchen: @kitchen)
  end
end
```

**Step 2: Run tests to verify current state**

Run: `ruby -Itest test/integration/xss_prevention_test.rb`
Expected: The instructions/footer tests should already PASS (from Task 1 renderer fix). The makes-unit test may still fail if the data flows through `ScalableNumberPreprocessor` and view attributes. This confirms what's left.

**Step 3: Fix _step.html.erb line 19**

Change line 19 from:

```erb
<li<% if item.quantity_value %> data-quantity-value="<%= item.quantity_value %>" data-quantity-unit="<%= item.quantity_unit %>"<%= %( data-quantity-unit-plural="#{FamilyRecipes::Inflector.unit_display(item.quantity_unit, 2)}").html_safe if item.quantity_unit %><% end %>>
```

to:

```erb
<li<% if item.quantity_value %> data-quantity-value="<%= item.quantity_value %>" data-quantity-unit="<%= item.quantity_unit %>"<%= %( data-quantity-unit-plural="#{ERB::Util.html_escape(FamilyRecipes::Inflector.unit_display(item.quantity_unit, 2))}").html_safe if item.quantity_unit %><% end %>>
```

The `.html_safe` is still needed to emit the raw attribute string, but the interpolated value is now escaped.

**Step 4: Fix _nutrition_table.html.erb line 16**

Change line 16 from:

```erb
columns << ["Per Serving<br>(#{formatted_ups} #{ups_unit})".html_safe, nutrition['per_serving'], false]
```

to:

```erb
columns << ["Per Serving<br>(#{ERB::Util.html_escape(formatted_ups)} #{ERB::Util.html_escape(ups_unit)})".html_safe, nutrition['per_serving'], false]
```

The `<br>` remains (intentional HTML), but the user-derived values are escaped before being marked safe.

**Step 5: Run integration tests**

Run: `ruby -Itest test/integration/xss_prevention_test.rb`
Expected: PASS — all tests green.

**Step 6: Run full test suite**

Run: `rake test`
Expected: All pass.

**Step 7: Commit**

```bash
git add app/views/recipes/_step.html.erb app/views/recipes/_nutrition_table.html.erb test/integration/xss_prevention_test.rb
git commit -m "fix: escape user content in view-level html_safe calls (#85)"
```

---

### Task 4: Final verification and close

**Step 1: Run full test suite one final time**

Run: `rake`
Expected: Lint + all tests pass.

**Step 2: Verify no remaining unescaped html_safe on user content**

Grep for `html_safe` across the codebase and confirm every remaining call is either:
- On renderer output (now safe via `escape_html: true`)
- On preprocessor output (now safe via `ERB::Util.html_escape`)
- On hardcoded values (indent integers, nutrient keys)

**Step 3: Commit message to close the issue**

If not already closed by prior commits, ensure the final commit or a squash references `Closes #85`.
