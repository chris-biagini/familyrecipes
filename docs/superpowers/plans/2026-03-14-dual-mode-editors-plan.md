# Dual-Mode Editors Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add graphical editor mode alongside existing plaintext editors for recipes and Quick Bites, with a mode toggle and canonical markdown serialization.

**Architecture:** Both editors (plaintext and graphical) are peers translating to/from a shared IR (the structured hash that `RecipeBuilder.build` already produces). A Ruby-only serializer (IR → markdown) is the single source of truth for the markdown format. `MarkdownImporter` gains a second entry point accepting the IR directly. Stimulus controllers are split into coordinator + plaintext + graphical per editor.

**Tech Stack:** Rails 8, SQLite, Stimulus, importmap-rails, Minitest

---

## File Map

### New Files (Ruby)

| File | Responsibility |
|------|----------------|
| `lib/familyrecipes/recipe_serializer.rb` | Pure function: IR hash → canonical markdown string |
| `lib/familyrecipes/quick_bites_serializer.rb` | Pure function: Quick Bites IR hash → canonical plaintext string |
| `test/recipe_serializer_test.rb` | Round-trip and edge case tests for recipe serializer |
| `test/quick_bites_serializer_test.rb` | Round-trip tests for Quick Bites serializer |
| `test/services/structured_import_test.rb` | Tests for `MarkdownImporter.import_from_structure` |

### New Files (JavaScript)

| File | Responsibility |
|------|----------------|
| `app/javascript/controllers/recipe_plaintext_controller.js` | Textarea + highlight overlay (extracted from current `recipe_editor_controller`) |
| `app/javascript/controllers/recipe_graphical_controller.js` | Form-based recipe editor (accordion steps, ingredient rows) |
| `app/javascript/controllers/quickbites_plaintext_controller.js` | Textarea + highlight overlay (extracted from current `quickbites_editor_controller`) |
| `app/javascript/controllers/quickbites_graphical_controller.js` | Form-based Quick Bites editor (category/item cards) |

### New Files (Views)

| File | Responsibility |
|------|----------------|
| `app/views/recipes/_graphical_editor.html.erb` | Graphical editor form partial for recipe dialog |
| `app/views/menu/_quickbites_graphical_editor.html.erb` | Graphical editor form partial for Quick Bites dialog |

### Modified Files (Ruby)

| File | Changes |
|------|---------|
| `lib/familyrecipes/recipe_builder.rb` | Extract `category` and `tags` from front matter; add `normalize_tags` |
| `lib/familyrecipes/line_classifier.rb` | Extend front matter regex to recognize `Category` and `Tags` |
| `app/services/markdown_importer.rb` | Add `import_from_structure` class method; extract shared save logic |
| `app/services/recipe_write_service.rb` | Add `create_from_structure` / `update_from_structure` methods |
| `app/services/quick_bites_write_service.rb` | Add `update_from_structure` method |
| `app/services/markdown_validator.rb` | Add `validate_structure` for the structured path |
| `app/controllers/recipes_controller.rb` | Dispatch structured vs markdown params; add `parse`/`serialize` actions |
| `app/controllers/menu_controller.rb` | Add `parse_quick_bites`/`serialize_quick_bites` actions; dispatch structured params |
| `config/routes.rb` | Add parse/serialize routes |
| `lib/familyrecipes.rb` | Require new serializer files |
| `test/recipe_builder_test.rb` | Tests for category/tags front matter parsing |
| `test/services/markdown_importer_test.rb` | Tests for `import_from_structure` |
| `test/services/recipe_write_service_test.rb` | Tests for `create_from_structure`/`update_from_structure` |
| `test/controllers/recipes_controller_test.rb` | Tests for structured create/update, parse/serialize endpoints |
| `test/controllers/menu_controller_test.rb` | Tests for Quick Bites structured update, parse/serialize |

### Modified Files (JavaScript)

| File | Changes |
|------|---------|
| `app/javascript/controllers/recipe_editor_controller.js` | Becomes coordinator: mode toggle, routes lifecycle events to active child |
| `app/javascript/controllers/quickbites_editor_controller.js` | Becomes coordinator: mode toggle, routes lifecycle events to active child |
| `app/javascript/controllers/editor_controller.js` | Minor: support `structure` as alternative body key for graphical saves |

### Modified Files (Views)

| File | Changes |
|------|---------|
| `app/views/recipes/show.html.erb` | Replace split layout with mode-switchable container; remove side panel |
| `app/views/menu/show.html.erb` | Add mode-switchable container for Quick Bites editor |
| `app/views/shared/_editor_dialog.html.erb` | Add mode toggle button to header bar |

---

## Chunk 1: Stage 1 — Front Matter Extension + Serializer

### Task 1: Parse Category and Tags from Front Matter

**Files:**
- Modify: `lib/familyrecipes/line_classifier.rb` (line 21, `LINE_PATTERNS`)
- Modify: `lib/familyrecipes/recipe_builder.rb` (lines 73-84, `parse_front_matter`)
- Test: `test/recipe_builder_test.rb`

- [ ] **Step 1: Write failing tests for category and tags parsing**

Add to `test/recipe_builder_test.rb`. Note: `build_recipe` is a helper that calls `RecipeBuilder.new(LineClassifier.classify(md)).build` — check if one exists in the test file already, create it if not.

```ruby
test 'parses category from front matter' do
  markdown = "# Test\n\nCategory: Basics\n\n## Step\n\n- Flour\n\nMix."
  recipe = build_recipe(markdown)
  assert_equal 'Basics', recipe[:front_matter][:category]
end

test 'parses tags from front matter as array' do
  markdown = "# Test\n\nTags: breakfast, quick\n\n## Step\n\n- Flour\n\nMix."
  recipe = build_recipe(markdown)
  assert_equal %w[breakfast quick], recipe[:front_matter][:tags]
end

test 'normalizes tag whitespace to hyphens' do
  markdown = "# Test\n\nTags: vegan friendly, one pot\n\n## Step\n\n- Flour\n\nMix."
  recipe = build_recipe(markdown)
  assert_equal %w[vegan-friendly one-pot], recipe[:front_matter][:tags]
end

test 'lowercases tags' do
  markdown = "# Test\n\nTags: Breakfast, QUICK\n\n## Step\n\n- Flour\n\nMix."
  recipe = build_recipe(markdown)
  assert_equal %w[breakfast quick], recipe[:front_matter][:tags]
end

test 'omits category and tags when absent' do
  markdown = "# Test\n\nServes: 4\n\n## Step\n\n- Flour\n\nMix."
  recipe = build_recipe(markdown)
  assert_nil recipe[:front_matter][:category]
  assert_nil recipe[:front_matter][:tags]
end
```

Also **update the existing conflicting test** `test_category_line_parsed_as_prose` (around line 210). This test currently asserts `Category: Dessert` is treated as the description. Now that Category is a recognized front matter key, update it:

```ruby
test 'category line parsed as front matter' do
  text = <<~RECIPE
    # Cookies

    Category: Dessert

    ## Mix

    Mix them.
  RECIPE

  result = build_recipe(text)

  assert_equal 'Dessert', result[:front_matter][:category]
  assert_nil result[:description]
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/recipe_builder_test.rb -n '/category|tags/'`
Expected: FAIL — `LineClassifier` doesn't recognize `Category:` or `Tags:` as front matter, so they never reach `parse_front_matter`

- [ ] **Step 3: Extend LineClassifier to recognize Category and Tags**

In `lib/familyrecipes/line_classifier.rb`, line 21, update the front matter regex:

```ruby
# Change:
front_matter: /^(Makes|Serves):\s+(.+)$/,
# To:
front_matter: /^(Makes|Serves|Category|Tags):\s+(.+)$/,
```

- [ ] **Step 4: Add tag normalization in RecipeBuilder**

In `lib/familyrecipes/recipe_builder.rb`, the existing `parse_front_matter` method (lines 73-84) reads `token.content[0]` (key from regex capture group 1) and `token.content[1]` (value from capture group 2), lowercases the key, and stores it. Category and Tags will flow through as `{category: "Basics", tags: "breakfast, quick"}`. Add post-processing for tags:

After the `while` loop in `parse_front_matter`, add:

```ruby
def parse_front_matter
  fields = {}
  skip_blanks

  while !at_end? && peek.type == :front_matter
    token = advance
    key = token.content[0].downcase.to_sym
    fields[key] = token.content[1]
  end

  fields[:tags] = normalize_tags(fields[:tags]) if fields[:tags]
  fields
end
```

Add the `normalize_tags` private method:

```ruby
def normalize_tags(raw)
  raw.split(',').map { |t| t.strip.downcase.gsub(/\s+/, '-') }.reject(&:empty?)
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/recipe_builder_test.rb -n '/category|tags/'`
Expected: PASS

- [ ] **Step 6: Run full test suite to check for regressions**

Run: `rake test`
Expected: All tests pass. The updated `test_category_line_parsed_as_front_matter` test now passes with the new behavior.

- [ ] **Step 7: Commit**

```bash
git add lib/familyrecipes/line_classifier.rb lib/familyrecipes/recipe_builder.rb \
  test/recipe_builder_test.rb
git commit -m "feat: parse category and tags from recipe front matter"
```

---

### Task 2: Pass Front Matter Category/Tags Through to RecipeWriteService

**Files:**
- Modify: `app/services/markdown_importer.rb` (lines 78-91, `update_recipe_attributes`)
- Modify: `app/services/recipe_write_service.rb` (lines 31-49, `create`/`update`)
- Test: `test/services/markdown_importer_test.rb`
- Test: `test/services/recipe_write_service_test.rb`

- [ ] **Step 1: Write failing test for front matter category in MarkdownImporter**

Add to `test/services/markdown_importer_test.rb`:

```ruby
test 'uses front matter category when no category argument given' do
  md = "# Front Matter Cat\n\nCategory: Desserts\n\n## Step\n\n- Sugar\n\nMix."
  recipe = MarkdownImporter.import(md, kitchen: @kitchen, category: nil)
  assert_equal 'Desserts', recipe.category.name
end

test 'explicit category argument overrides front matter' do
  md = "# Override Cat\n\nCategory: Desserts\n\n## Step\n\n- Sugar\n\nMix."
  category = @kitchen.categories.create!(name: 'Breads')
  recipe = MarkdownImporter.import(md, kitchen: @kitchen, category: category)
  assert_equal 'Breads', recipe.category.name
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/markdown_importer_test.rb -n '/front matter category/'`
Expected: FAIL — MarkdownImporter doesn't read `parsed[:front_matter][:category]`

- [ ] **Step 3: Implement front matter category fallback in MarkdownImporter**

In `app/services/markdown_importer.rb`, modify `update_recipe_attributes`:

```ruby
def update_recipe_attributes(recipe)
  makes_qty, makes_unit = FamilyRecipes::Recipe.parse_makes(parsed[:front_matter][:makes])
  resolved_category = category || resolve_front_matter_category

  recipe.assign_attributes(
    title: parsed[:title],
    description: parsed[:description],
    category: resolved_category,
    kitchen: kitchen,
    makes_quantity: makes_qty,
    makes_unit_noun: makes_unit,
    serves: parsed[:front_matter][:serves]&.to_i,
    footer: parsed[:footer],
    markdown_source: markdown_source
  )
end

def resolve_front_matter_category
  name = parsed[:front_matter][:category]
  return nil unless name

  kitchen.categories.find_or_create_by!(name: name)
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/markdown_importer_test.rb -n '/front matter category/'`
Expected: PASS

- [ ] **Step 5: Write failing test for front matter tags in RecipeWriteService**

The `RecipeWriteService` already accepts `tags:` param and calls `sync_tags`. We need it to also read tags from front matter when the `tags:` param is nil. To avoid double-parsing, `MarkdownImporter.import` should return the parsed front matter tags so `RecipeWriteService` can read them from the recipe record.

Add to `test/services/recipe_write_service_test.rb`:

```ruby
test 'create uses front matter tags when tags param is nil' do
  md = "# FM Tags\n\nTags: quick, breakfast\n\n## Step\n\n- Eggs\n\nScramble."
  result = RecipeWriteService.create(markdown: md, kitchen: @kitchen)
  assert_equal %w[breakfast quick], result.recipe.tags.pluck(:name).sort
end

test 'explicit tags param overrides front matter tags' do
  md = "# FM Tags Override\n\nTags: breakfast, quick\n\n## Step\n\n- Eggs\n\nScramble."
  result = RecipeWriteService.create(markdown: md, kitchen: @kitchen, tags: %w[dinner])
  assert_equal %w[dinner], result.recipe.tags.pluck(:name)
end
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `ruby -Itest test/services/recipe_write_service_test.rb -n '/front matter tags/'`
Expected: FAIL — front matter tags not read

- [ ] **Step 7: Thread front matter tags through MarkdownImporter**

Rather than re-parsing the markdown, have `MarkdownImporter` store the parsed front matter tags so `RecipeWriteService` can access them. In `app/services/markdown_importer.rb`, expose the parsed tags:

```ruby
attr_reader :front_matter_tags

def parse_markdown
  tokens = LineClassifier.classify(markdown_source)
  parsed = RecipeBuilder.new(tokens).build
  @front_matter_tags = parsed[:front_matter][:tags]
  parsed
end
```

Change `import` from a class method that returns just the recipe to returning the importer instance (so the caller can read `front_matter_tags`). Or simpler: just set `front_matter_tags` on the recipe as a transient attribute. The cleanest approach: have `MarkdownImporter.import` return a result that includes the parsed tags.

Update `MarkdownImporter`:

```ruby
ImportResult = Data.define(:recipe, :front_matter_tags)

def self.import(markdown_source, kitchen:, category:)
  importer = new(markdown_source, kitchen: kitchen, category: category)
  recipe = importer.import
  ImportResult.new(recipe:, front_matter_tags: importer.front_matter_tags)
end
```

Then in `RecipeWriteService`, update `import_and_timestamp` to capture the result:

```ruby
def import_and_timestamp(markdown, category:)
  result = MarkdownImporter.import(markdown, kitchen:, category:)
  result.recipe.update!(edited_at: Time.current)
  @last_front_matter_tags = result.front_matter_tags
  result.recipe
end
```

And update `create`/`update`:

```ruby
def create(markdown:, category_name:, tags: nil)
  category = find_or_create_category(category_name)
  recipe = import_and_timestamp(markdown, category:)
  resolved_tags = tags || @last_front_matter_tags
  sync_tags(recipe, resolved_tags) if resolved_tags
  finalize
  Result.new(recipe:, updated_references: [])
end
```

Same pattern for `update`.

- [ ] **Step 8: Update all callers of `MarkdownImporter.import`**

`MarkdownImporter.import` now returns `ImportResult` instead of a bare `Recipe`. This is a mechanical migration: append `.recipe` to calls that use the return value. Run:

```bash
grep -rn 'MarkdownImporter.import' app/ lib/ db/ test/
```

Callers to update:
- `db/seeds.rb` — wherever the return value is assigned, append `.recipe`
- `test/services/markdown_importer_test.rb` — all `recipe = MarkdownImporter.import(...)` lines become `recipe = MarkdownImporter.import(...).recipe` (many callsites — this is the bulk of the change)
- `test/services/recipe_write_service_test.rb` — any direct `MarkdownImporter.import` calls in setup or helpers
- Any other test files that call `MarkdownImporter.import` directly

Callers that do NOT need changes:
- `app/services/recipe_write_service.rb` — already updated in Step 7
- `app/services/cross_reference_updater.rb` — discards the return value, no change needed
- `db/migrate/003_migrate_cross_reference_syntax.rb` — already run, leave as-is

- [ ] **Step 9: Run tests to verify they pass**

Run: `ruby -Itest test/services/recipe_write_service_test.rb -n '/front matter tags/'`
Expected: PASS

- [ ] **Step 10: Run full test suite**

Run: `rake test`
Expected: All tests pass

- [ ] **Step 11: Commit**

```bash
git add app/services/markdown_importer.rb app/services/recipe_write_service.rb \
  test/services/markdown_importer_test.rb test/services/recipe_write_service_test.rb \
  db/seeds.rb test/
git commit -m "feat: pass front matter category and tags through write path"
```

---

### Task 3: Update Highlight Overlay for New Front Matter Lines

**Files:**
- Modify: `app/javascript/controllers/recipe_editor_controller.js` (lines 61-80, `classifyLine`)

- [ ] **Step 1: Update `classifyLine` to highlight Category and Tags lines**

In `app/javascript/controllers/recipe_editor_controller.js`, the `classifyLine` method already handles `Makes:` and `Serves:` via the pattern `/^(Makes|Serves): .+$/`. Extend this to include `Category` and `Tags`:

```javascript
// Change this line:
} else if (/^(Makes|Serves): .+$/.test(line)) {
// To:
} else if (/^(Makes|Serves|Category|Tags): .+$/.test(line)) {
```

Both lines get the `hl-front-matter` class, which is the same styling as Makes/Serves. No new CSS needed.

- [ ] **Step 2: Verify manually in dev**

Run: `bin/dev`
Open a recipe editor, type `Category: Basics` and `Tags: breakfast, quick` in the textarea. Verify they get the front-matter highlight color (same as Makes/Serves lines).

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/recipe_editor_controller.js
git commit -m "feat: highlight Category and Tags front matter in plaintext editor"
```

---

### Task 4: Build Canonical Recipe Serializer

**Files:**
- Create: `lib/familyrecipes/recipe_serializer.rb`
- Create: `test/recipe_serializer_test.rb`
- Modify: `lib/familyrecipes.rb` (add require)

- [ ] **Step 1: Write round-trip test**

Create `test/recipe_serializer_test.rb`:

```ruby
require 'test_helper'

class RecipeSerializerTest < Minitest::Test
  def test_round_trip_simple_recipe
    markdown = <<~MD.strip
      # Scrambled Eggs

      A breakfast staple.

      Serves: 2
      Category: Basics
      Tags: breakfast, quick

      ## Prep the eggs.

      - Eggs, 4: Crack into a bowl.
      - Salt
      - Black pepper

      Whisk eggs with a pinch of salt and pepper until uniform.

      ## Cook.

      - Butter, 1 tbsp

      Melt butter in a non-stick pan over low heat.
    MD

    ir = parse(markdown)
    serialized = FamilyRecipes::RecipeSerializer.serialize(ir)
    re_parsed = parse(serialized)

    assert_equal ir[:title], re_parsed[:title]
    assert_equal ir[:description], re_parsed[:description]
    assert_equal ir[:front_matter][:serves], re_parsed[:front_matter][:serves]
    assert_equal ir[:front_matter][:category], re_parsed[:front_matter][:category]
    assert_equal ir[:front_matter][:tags], re_parsed[:front_matter][:tags]
    assert_equal ir[:steps].size, re_parsed[:steps].size

    ir[:steps].each_with_index do |step, i|
      assert_equal step[:tldr], re_parsed[:steps][i][:tldr]
      assert_equal step[:ingredients], re_parsed[:steps][i][:ingredients]
      assert_equal step[:instructions], re_parsed[:steps][i][:instructions]
    end
  end

  def test_round_trip_with_cross_reference
    markdown = <<~MD.strip
      # Pasta Night

      ## Make the sauce.

      - Tomatoes, 2: Diced.

      Simmer for 20 minutes.

      ## Make the dough.

      > @[Pizza Dough], 0.5: Halve the recipe.
    MD

    ir = parse(markdown)
    serialized = FamilyRecipes::RecipeSerializer.serialize(ir)
    re_parsed = parse(serialized)

    assert_equal 'Pizza Dough', re_parsed[:steps][1][:cross_reference][:target_title]
    assert_in_delta 0.5, re_parsed[:steps][1][:cross_reference][:multiplier]
    assert_equal 'Halve the recipe.', re_parsed[:steps][1][:cross_reference][:prep_note]
  end

  def test_round_trip_with_footer
    markdown = <<~MD.strip
      # With Footer

      ## Step one.

      - Flour

      Mix.

      ---

      Adapted from Julia Child.
    MD

    ir = parse(markdown)
    serialized = FamilyRecipes::RecipeSerializer.serialize(ir)
    re_parsed = parse(serialized)

    assert_equal 'Adapted from Julia Child.', re_parsed[:footer]
  end

  def test_round_trip_with_makes
    markdown = <<~MD.strip
      # Dinner Rolls

      Makes: 12 rolls

      ## Mix.

      - Flour, 3 cups

      Combine.
    MD

    ir = parse(markdown)
    serialized = FamilyRecipes::RecipeSerializer.serialize(ir)
    re_parsed = parse(serialized)

    assert_equal '12 rolls', re_parsed[:front_matter][:makes]
  end

  def test_omits_blank_front_matter
    markdown = <<~MD.strip
      # Minimal

      ## Step.

      - Flour

      Mix.
    MD

    ir = parse(markdown)
    serialized = FamilyRecipes::RecipeSerializer.serialize(ir)

    refute_match(/Makes:/, serialized)
    refute_match(/Serves:/, serialized)
    refute_match(/Category:/, serialized)
    refute_match(/Tags:/, serialized)
  end

  def test_ingredient_with_only_name
    markdown = <<~MD.strip
      # Simple

      ## Step.

      - Salt

      Add salt.
    MD

    ir = parse(markdown)
    serialized = FamilyRecipes::RecipeSerializer.serialize(ir)

    assert_includes serialized, '- Salt'
    refute_includes serialized, '- Salt,'
  end

  def test_ingredient_with_quantity_no_prep
    markdown = <<~MD.strip
      # Qty Only

      ## Step.

      - Flour, 2 cups

      Mix.
    MD

    ir = parse(markdown)
    serialized = FamilyRecipes::RecipeSerializer.serialize(ir)

    assert_includes serialized, '- Flour, 2 cups'
    refute_includes serialized, '- Flour, 2 cups:'
  end

  def test_cross_reference_without_prep_note
    markdown = <<~MD.strip
      # No Prep

      ## Import.

      > @[Base Recipe]
    MD

    ir = parse(markdown)
    serialized = FamilyRecipes::RecipeSerializer.serialize(ir)

    assert_includes serialized, '> @[Base Recipe]'
    refute_includes serialized, '> @[Base Recipe],'
  end

  def test_cross_reference_multiplier_1_omitted
    markdown = <<~MD.strip
      # Default Mult

      ## Import.

      > @[Base Recipe]
    MD

    ir = parse(markdown)
    serialized = FamilyRecipes::RecipeSerializer.serialize(ir)

    refute_match(/> @\[Base Recipe\], 1/, serialized)
  end

  private

  def parse(markdown)
    tokens = LineClassifier.classify(markdown)
    RecipeBuilder.new(tokens).build
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/recipe_serializer_test.rb`
Expected: FAIL — `FamilyRecipes::RecipeSerializer` doesn't exist

- [ ] **Step 3: Implement RecipeSerializer**

Create `lib/familyrecipes/recipe_serializer.rb`:

```ruby
# frozen_string_literal: true

module FamilyRecipes
  # Pure-function serializer: takes an IR hash (as produced by RecipeBuilder#build)
  # and emits canonical Markdown. This is the single source of truth for the
  # recipe Markdown format — the inverse of the parser pipeline.
  #
  # Collaborators:
  #   - RecipeBuilder (produces the IR this consumes)
  #   - MarkdownImporter (calls this to generate markdown_source for structured imports)
  #   - RecipesController (calls this for the serialize endpoint)
  module RecipeSerializer
    module_function

    def serialize(ir)
      lines = []
      lines << "# #{ir[:title]}"
      append_description(lines, ir[:description])
      append_front_matter(lines, ir[:front_matter])
      ir[:steps].each { |step| append_step(lines, step) }
      append_footer(lines, ir[:footer])
      "#{lines.join("\n").strip}\n"
    end

    def append_description(lines, description)
      return if description.nil? || description.strip.empty?

      lines << ''
      lines << description
    end

    def append_front_matter(lines, fm)
      entries = []
      entries << "Makes: #{fm[:makes]}" if fm[:makes] && !fm[:makes].strip.empty?
      entries << "Serves: #{fm[:serves]}" if fm[:serves] && !fm[:serves].to_s.strip.empty?
      entries << "Category: #{fm[:category]}" if fm[:category] && !fm[:category].strip.empty?
      entries << "Tags: #{fm[:tags].join(', ')}" if fm[:tags]&.any?
      return if entries.empty?

      lines << ''
      lines.concat(entries)
    end

    def append_step(lines, step)
      lines << ''
      lines << "## #{step[:tldr]}"

      if step[:cross_reference]
        lines << ''
        lines << serialize_cross_reference(step[:cross_reference])
      else
        append_ingredients(lines, step[:ingredients])
        append_instructions(lines, step[:instructions])
      end
    end

    def append_ingredients(lines, ingredients)
      return if ingredients.empty?

      lines << ''
      ingredients.each { |ing| lines << serialize_ingredient(ing) }
    end

    def serialize_ingredient(ing)
      parts = ["- #{ing[:name]}"]
      parts << ", #{ing[:quantity]}" if ing[:quantity] && !ing[:quantity].strip.empty?
      parts << ": #{ing[:prep_note]}" if ing[:prep_note] && !ing[:prep_note].strip.empty?
      parts.join
    end

    def serialize_cross_reference(xref)
      parts = ["> @[#{xref[:target_title]}]"]
      parts << ", #{xref[:multiplier]}" if xref[:multiplier] && xref[:multiplier] != 1.0
      parts << ": #{xref[:prep_note]}" if xref[:prep_note] && !xref[:prep_note].strip.empty?
      parts.join
    end

    def append_instructions(lines, instructions)
      return if instructions.nil? || instructions.strip.empty?

      lines << ''
      lines << instructions
    end

    def append_footer(lines, footer)
      return if footer.nil? || footer.strip.empty?

      lines << ''
      lines << '---'
      lines << ''
      lines << footer
    end
  end
end
```

- [ ] **Step 4: Register the serializer in the loader**

In `lib/familyrecipes.rb`, add the require alongside the other parser files:

```ruby
require_relative 'familyrecipes/recipe_serializer'
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/recipe_serializer_test.rb`
Expected: All PASS

- [ ] **Step 6: Run full test suite**

Run: `rake test`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add lib/familyrecipes/recipe_serializer.rb lib/familyrecipes.rb \
  test/recipe_serializer_test.rb
git commit -m "feat: add canonical recipe serializer (IR → markdown)"
```

---

### Task 5: Build Quick Bites Serializer

**Files:**
- Create: `lib/familyrecipes/quick_bites_serializer.rb`
- Create: `test/quick_bites_serializer_test.rb`
- Modify: `lib/familyrecipes.rb` (add require)

- [ ] **Step 1: Write round-trip test**

Create `test/quick_bites_serializer_test.rb`:

```ruby
require 'test_helper'

class QuickBitesSerializerTest < Minitest::Test
  def test_round_trip
    content = <<~TXT.strip
      Snacks:
      - Apples and Honey: Apples, Honey
      - Crackers and Cheese: Ritz crackers, Cheddar

      Breakfast:
      - Cereal: Rolled oats, Milk
    TXT

    ir = parse_to_ir(content)
    serialized = FamilyRecipes::QuickBitesSerializer.serialize(ir)
    re_parsed_ir = parse_to_ir(serialized)

    assert_equal ir[:categories].size, re_parsed_ir[:categories].size
    ir[:categories].each_with_index do |cat, i|
      assert_equal cat[:name], re_parsed_ir[:categories][i][:name]
      assert_equal cat[:items].size, re_parsed_ir[:categories][i][:items].size
      cat[:items].each_with_index do |item, j|
        assert_equal item[:name], re_parsed_ir[:categories][i][:items][j][:name]
        assert_equal item[:ingredients], re_parsed_ir[:categories][i][:items][j][:ingredients]
      end
    end
  end

  def test_item_without_ingredients
    content = <<~TXT.strip
      Snacks:
      - Banana
    TXT

    ir = parse_to_ir(content)
    serialized = FamilyRecipes::QuickBitesSerializer.serialize(ir)

    assert_includes serialized, '- Banana'
    refute_includes serialized, '- Banana:'
  end

  def test_empty_categories_omitted
    ir = { categories: [] }
    serialized = FamilyRecipes::QuickBitesSerializer.serialize(ir)

    assert_equal '', serialized.strip
  end

  def test_items_without_subcategory_header
    content = "- Banana\n- Apple"

    ir = parse_to_ir(content)
    serialized = FamilyRecipes::QuickBitesSerializer.serialize(ir)
    re_parsed_ir = parse_to_ir(serialized)

    assert_equal 1, ir[:categories].size
    assert_equal 'Quick Bites', ir[:categories][0][:name]
    assert_equal 2, re_parsed_ir[:categories][0][:items].size
  end

  private

  def parse_to_ir(content)
    result = FamilyRecipes.parse_quick_bites_content(content)
    FamilyRecipes::QuickBitesSerializer.to_ir(result.quick_bites)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/quick_bites_serializer_test.rb`
Expected: FAIL — `FamilyRecipes::QuickBitesSerializer` doesn't exist

- [ ] **Step 3: Implement QuickBitesSerializer**

Create `lib/familyrecipes/quick_bites_serializer.rb`:

```ruby
# frozen_string_literal: true

module FamilyRecipes
  # Pure-function serializer: takes a Quick Bites IR hash and emits canonical
  # plaintext. Inverse of parse_quick_bites_content. Also provides to_ir to
  # convert parsed QuickBite arrays into the IR hash format.
  #
  # Collaborators:
  #   - FamilyRecipes.parse_quick_bites_content (produces QuickBite arrays)
  #   - QuickBitesWriteService (calls this for structured imports)
  #   - MenuController (calls this for the serialize endpoint)
  module QuickBitesSerializer
    module_function

    def serialize(ir)
      lines = []
      ir[:categories].each_with_index do |cat, i|
        lines << '' if i > 0
        lines << "#{cat[:name]}:"
        cat[:items].each { |item| lines << serialize_item(item) }
      end
      "#{lines.join("\n")}\n"
    end

    def to_ir(quick_bites)
      grouped = quick_bites.group_by(&:category)
      categories = grouped.map do |full_category, items|
        subcategory = full_category.split(': ', 2).last
        {
          name: subcategory,
          items: items.map { |qb| { name: qb.title, ingredients: qb.ingredients } }
        }
      end
      { categories: categories }
    end

    def serialize_item(item)
      if item[:ingredients]&.any? && item[:ingredients] != [item[:name]]
        "- #{item[:name]}: #{item[:ingredients].join(', ')}"
      else
        "- #{item[:name]}"
      end
    end
  end
end
```

Note: `to_ir` converts the flat `QuickBite` array (with `category` strings like `"Quick Bites: Snacks"`) into the grouped IR hash. The category prefix (`"Quick Bites: "`) comes from `CONFIG[:quick_bites_category]` — `to_ir` strips it by splitting on `": "`.

- [ ] **Step 4: Register in loader**

In `lib/familyrecipes.rb`, add:

```ruby
require_relative 'familyrecipes/quick_bites_serializer'
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/quick_bites_serializer_test.rb`
Expected: All PASS

- [ ] **Step 6: Run full test suite**

Run: `rake test`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add lib/familyrecipes/quick_bites_serializer.rb lib/familyrecipes.rb \
  test/quick_bites_serializer_test.rb
git commit -m "feat: add canonical Quick Bites serializer (IR → plaintext)"
```

---

### Task 6: Lint and Full Verification

- [ ] **Step 1: Run RuboCop**

Run: `bundle exec rubocop lib/familyrecipes/recipe_serializer.rb lib/familyrecipes/quick_bites_serializer.rb`
Expected: 0 offenses. Fix any issues.

- [ ] **Step 2: Run full test suite + lint**

Run: `rake`
Expected: All tests pass, 0 RuboCop offenses

- [ ] **Step 3: Commit any lint fixes**

Only if Step 1 required changes.

---

## Chunk 2: Stage 2 — Structured Import Path + Stage 3 — Plaintext Simplification

### Task 7: Add `import_from_structure` to MarkdownImporter

**Files:**
- Modify: `app/services/markdown_importer.rb`
- Create: `test/services/structured_import_test.rb`

- [ ] **Step 1: Write failing test for structured import**

Create `test/services/structured_import_test.rb`:

```ruby
require 'test_helper'

class StructuredImportTest < ActiveSupport::TestCase
  setup do
    @kitchen, @user = create_kitchen_and_user
  end

  test 'import_from_structure creates recipe from IR hash' do
    ir = {
      title: 'Structured Recipe',
      description: 'Created from JSON.',
      front_matter: { serves: '4', category: 'Basics', tags: %w[test] },
      steps: [
        {
          tldr: 'Mix.',
          ingredients: [
            { name: 'Flour', quantity: '2 cups', prep_note: nil },
            { name: 'Salt', quantity: nil, prep_note: nil }
          ],
          instructions: 'Combine dry ingredients.',
          cross_reference: nil
        }
      ],
      footer: nil
    }

    result = MarkdownImporter.import_from_structure(ir, kitchen: @kitchen, category: nil)
    recipe = result.recipe

    assert_equal 'Structured Recipe', recipe.title
    assert_equal 'Created from JSON.', recipe.description
    assert_equal 4, recipe.serves
    assert_equal 1, recipe.steps.size
    assert_equal 2, recipe.steps.first.ingredients.size
    assert_equal 'Flour', recipe.steps.first.ingredients.first.name
    assert_equal '2', recipe.steps.first.ingredients.first.quantity
    assert_equal 'cups', recipe.steps.first.ingredients.first.unit
    assert recipe.markdown_source.include?('# Structured Recipe')
    assert recipe.markdown_source.include?('- Flour, 2 cups')
  end

  test 'import_from_structure resolves category from front matter' do
    ir = {
      title: 'Categorized',
      description: nil,
      front_matter: { category: 'Desserts' },
      steps: [{ tldr: 'Bake.', ingredients: [{ name: 'Sugar', quantity: nil, prep_note: nil }],
                 instructions: 'Bake.', cross_reference: nil }],
      footer: nil
    }

    result = MarkdownImporter.import_from_structure(ir, kitchen: @kitchen, category: nil)
    assert_equal 'Desserts', result.recipe.category.name
  end

  test 'import_from_structure handles cross-reference steps' do
    ir = {
      title: 'With Xref',
      description: nil,
      front_matter: {},
      steps: [
        {
          tldr: 'Import dough.',
          ingredients: [],
          instructions: nil,
          cross_reference: { target_title: 'Pizza Dough', multiplier: 0.5, prep_note: 'Halve.' }
        }
      ],
      footer: nil
    }

    result = MarkdownImporter.import_from_structure(ir, kitchen: @kitchen, category: nil)
    xref = result.recipe.steps.first.cross_references.first

    assert_equal 'Pizza Dough', xref.target_title
    assert_in_delta 0.5, xref.multiplier
    assert_equal 'Halve.', xref.prep_note
  end

  test 'import_from_structure generates valid markdown_source' do
    ir = {
      title: 'Round Trip',
      description: 'Test round-trip.',
      front_matter: { makes: '12 rolls', serves: '4' },
      steps: [{ tldr: 'Mix.', ingredients: [{ name: 'Flour', quantity: '3 cups', prep_note: nil }],
                 instructions: 'Mix well.', cross_reference: nil }],
      footer: 'Notes here.'
    }

    result = MarkdownImporter.import_from_structure(ir, kitchen: @kitchen, category: nil)
    source = result.recipe.markdown_source

    assert source.start_with?('# Round Trip')
    assert_includes source, 'Makes: 12 rolls'
    assert_includes source, 'Serves: 4'
    assert_includes source, '## Mix.'
    assert_includes source, '- Flour, 3 cups'
    assert_includes source, '---'
    assert_includes source, 'Notes here.'
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/structured_import_test.rb`
Expected: FAIL — `import_from_structure` method doesn't exist

- [ ] **Step 3: Implement `import_from_structure`**

Refactor `MarkdownImporter` so the constructor accepts an optional pre-parsed hash. Both entry points converge on a shared `run` method:

```ruby
class MarkdownImporter
  ImportResult = Data.define(:recipe, :front_matter_tags)

  def self.import(markdown_source, kitchen:, category:)
    new(markdown_source, kitchen:, category:).run
  end

  def self.import_from_structure(ir_hash, kitchen:, category:)
    markdown_source = FamilyRecipes::RecipeSerializer.serialize(ir_hash)
    new(markdown_source, kitchen:, category:, parsed: ir_hash).run
  end

  def initialize(markdown_source, kitchen:, category:, parsed: nil)
    @markdown_source = markdown_source
    @kitchen = kitchen
    @category = category
    @parsed = parsed || parse_markdown
  end

  def run
    recipe = save_recipe
    CrossReference.resolve_pending(kitchen:)
    compute_nutrition(recipe)
    ImportResult.new(recipe:, front_matter_tags: parsed.dig(:front_matter, :tags))
  end

  # ... rest of private methods unchanged (save_recipe, replace_steps, etc.)
end
```

Key points:
- `self.import` unchanged in behavior — still parses markdown via constructor
- `self.import_from_structure` generates markdown via serializer, passes pre-parsed IR via `parsed:` kwarg
- Both return `ImportResult` (established in Chunk 1)
- The `parsed:` kwarg means the structured path skips the redundant re-parse of serializer output

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/structured_import_test.rb`
Expected: All PASS

- [ ] **Step 5: Run full test suite**

Run: `rake test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add app/services/markdown_importer.rb test/services/structured_import_test.rb
git commit -m "feat: add import_from_structure to MarkdownImporter"
```

---

### Task 8: Add Structured Write Methods to RecipeWriteService

**Files:**
- Modify: `app/services/recipe_write_service.rb`
- Test: `test/services/recipe_write_service_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/services/recipe_write_service_test.rb`:

```ruby
test 'create_from_structure creates recipe from IR' do
  ir = {
    title: 'Structured Create',
    description: nil,
    front_matter: { category: 'Basics', tags: %w[test] },
    steps: [{ tldr: 'Mix.', ingredients: [{ name: 'Flour', quantity: nil, prep_note: nil }],
               instructions: 'Mix.', cross_reference: nil }],
    footer: nil
  }

  result = RecipeWriteService.create_from_structure(
    structure: ir, kitchen: @kitchen
  )

  assert_equal 'Structured Create', result.recipe.title
  assert_equal 'Basics', result.recipe.category.name
  assert_equal %w[test], result.recipe.tags.pluck(:name)
end

test 'update_from_structure updates existing recipe' do
  md = "# Original\n\n## Step\n\n- Flour\n\nMix."
  original = RecipeWriteService.create(markdown: md, kitchen: @kitchen)

  ir = {
    title: 'Updated Title',
    description: nil,
    front_matter: { category: 'Desserts' },
    steps: [{ tldr: 'Bake.', ingredients: [{ name: 'Sugar', quantity: nil, prep_note: nil }],
               instructions: 'Bake.', cross_reference: nil }],
    footer: nil
  }

  result = RecipeWriteService.update_from_structure(
    slug: original.recipe.slug, structure: ir, kitchen: @kitchen
  )

  assert_equal 'Updated Title', result.recipe.title
  assert_equal 'Desserts', result.recipe.category.name
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/recipe_write_service_test.rb -n '/from_structure/'`
Expected: FAIL — methods don't exist

- [ ] **Step 3: Implement `create_from_structure` and `update_from_structure`**

In `app/services/recipe_write_service.rb`:

```ruby
def self.create_from_structure(structure:, kitchen:)
  new(kitchen:).create_from_structure(structure:)
end

def self.update_from_structure(slug:, structure:, kitchen:)
  new(kitchen:).update_from_structure(slug:, structure:)
end

def create_from_structure(structure:)
  category_name = structure.dig(:front_matter, :category) || 'Miscellaneous'
  tags = structure.dig(:front_matter, :tags)
  category = find_or_create_category(category_name)
  result = MarkdownImporter.import_from_structure(structure, kitchen:, category:)
  result.recipe.update!(edited_at: Time.current)
  sync_tags(result.recipe, tags) if tags
  finalize
  Result.new(recipe: result.recipe, updated_references: [])
end

def update_from_structure(slug:, structure:)
  old_recipe = kitchen.recipes.find_by!(slug:)
  category_name = structure.dig(:front_matter, :category) || 'Miscellaneous'
  tags = structure.dig(:front_matter, :tags)
  category = find_or_create_category(category_name)
  result = MarkdownImporter.import_from_structure(structure, kitchen:, category:)
  result.recipe.update!(edited_at: Time.current)
  sync_tags(result.recipe, tags) if tags
  updated_references = rename_cross_references(old_recipe, result.recipe)
  handle_slug_change(old_recipe, result.recipe)
  finalize
  Result.new(recipe: result.recipe, updated_references:)
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/recipe_write_service_test.rb -n '/from_structure/'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/recipe_write_service.rb test/services/recipe_write_service_test.rb
git commit -m "feat: add structured write methods to RecipeWriteService"
```

---

### Task 9: Add Parse and Serialize Endpoints to RecipesController

**Files:**
- Modify: `app/controllers/recipes_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/recipes_controller_test.rb`

- [ ] **Step 1: Add routes**

In `config/routes.rb`, within the kitchen scope, add:

```ruby
post 'recipes/parse', to: 'recipes#parse', as: :recipe_parse
post 'recipes/serialize', to: 'recipes#serialize', as: :recipe_serialize
```

Place these BEFORE `resources :recipes` to avoid the route matching `:slug` for "parse"/"serialize".

- [ ] **Step 2: Write failing tests**

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'parse returns IR from markdown' do
  log_in
  post recipe_parse_path, params: { markdown_source: "# Test\n\nServes: 2\n\n## Mix.\n\n- Flour\n\nMix." },
       as: :json

  assert_response :ok
  body = response.parsed_body
  assert_equal 'Test', body['title']
  assert_equal 'Mix.', body['steps'][0]['tldr']
  assert_equal 'Flour', body['steps'][0]['ingredients'][0]['name']
end

test 'parse returns errors for invalid markdown' do
  log_in
  post recipe_parse_path, params: { markdown_source: '' }, as: :json

  assert_response :unprocessable_content
  assert response.parsed_body['errors'].any?
end

test 'serialize returns markdown from IR' do
  log_in
  ir = {
    title: 'Test',
    description: nil,
    front_matter: { serves: '2' },
    steps: [{ tldr: 'Mix.', ingredients: [{ name: 'Flour', quantity: nil, prep_note: nil }],
               instructions: 'Mix.', cross_reference: nil }],
    footer: nil
  }

  post recipe_serialize_path, params: { structure: ir }, as: :json

  assert_response :ok
  body = response.parsed_body
  assert_includes body['markdown'], '# Test'
  assert_includes body['markdown'], '## Mix.'
  assert_includes body['markdown'], '- Flour'
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n '/parse|serialize/'`
Expected: FAIL — actions don't exist

- [ ] **Step 4: Implement parse and serialize actions**

In `app/controllers/recipes_controller.rb`:

```ruby
def parse
  errors = MarkdownValidator.validate(params[:markdown_source])
  return render json: { errors: }, status: :unprocessable_content if errors.any?

  tokens = LineClassifier.classify(params[:markdown_source])
  ir = RecipeBuilder.new(tokens).build
  render json: ir
end

def serialize
  markdown = FamilyRecipes::RecipeSerializer.serialize(structure_params)
  render json: { markdown: }
end

private

def structure_params
  params[:structure].to_unsafe_h.deep_symbolize_keys
end
```

Add `require_membership` for both actions (they're write-adjacent utility endpoints). The `structure_params` helper will also be used by `create` and `update` in Task 10.

- [ ] **Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n '/parse|serialize/'`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/controllers/recipes_controller.rb config/routes.rb \
  test/controllers/recipes_controller_test.rb
git commit -m "feat: add parse and serialize endpoints for recipe editor mode switching"
```

---

### Task 10: Add Structured Dispatch to Recipe Create/Update

**Files:**
- Modify: `app/controllers/recipes_controller.rb`
- Test: `test/controllers/recipes_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'create with structure param uses structured path' do
  log_in
  ir = {
    title: 'GUI Recipe',
    description: nil,
    front_matter: { category: 'Basics', tags: %w[test] },
    steps: [{ tldr: 'Mix.', ingredients: [{ name: 'Flour', quantity: nil, prep_note: nil }],
               instructions: 'Mix.', cross_reference: nil }],
    footer: nil
  }

  assert_difference 'Recipe.count', 1 do
    post recipes_path, params: { structure: ir }, as: :json
  end

  assert_response :ok
  recipe = Recipe.last
  assert_equal 'GUI Recipe', recipe.title
  assert_equal 'Basics', recipe.category.name
end

test 'update with structure param uses structured path' do
  log_in
  recipe = create_recipe("# Existing\n\n## Step\n\n- Flour\n\nMix.")

  ir = {
    title: 'Existing',
    description: 'Now with a description.',
    front_matter: {},
    steps: [{ tldr: 'Step.', ingredients: [{ name: 'Flour', quantity: nil, prep_note: nil }],
               instructions: 'Mix.', cross_reference: nil }],
    footer: nil
  }

  patch recipe_path(recipe.slug), params: { structure: ir }, as: :json

  assert_response :ok
  recipe.reload
  assert_equal 'Now with a description.', recipe.description
end
```

If a `create_recipe` helper doesn't already exist in the test suite, add it to `test/test_helper.rb`:

```ruby
def create_recipe(markdown, category_name: 'Miscellaneous', kitchen: @kitchen)
  RecipeWriteService.create(markdown:, kitchen:, category_name:).recipe
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n '/structure param/'`
Expected: FAIL — controller doesn't check for `structure` param

- [ ] **Step 3: Implement structured dispatch in create/update**

In `app/controllers/recipes_controller.rb`, modify `create` and `update`:

```ruby
def create
  if params[:structure]
    result = RecipeWriteService.create_from_structure(
      structure: structure_params, kitchen: current_kitchen
    )
    render json: { redirect_url: recipe_path(result.recipe.slug) }
  else
    return render_validation_errors if validation_errors.any?
    result = RecipeWriteService.create(
      markdown: params[:markdown_source], kitchen: current_kitchen,
      category_name: params[:category], tags: params[:tags]
    )
    render json: { redirect_url: recipe_path(result.recipe.slug) }
  end
rescue ActiveRecord::RecordInvalid, RuntimeError => error
  render json: { errors: [error.message] }, status: :unprocessable_content
end

def update
  current_kitchen.recipes.find_by!(slug: params[:slug])

  if params[:structure]
    result = RecipeWriteService.update_from_structure(
      slug: params[:slug], structure: structure_params, kitchen: current_kitchen
    )
    render json: update_response(result)
  else
    return render_validation_errors if validation_errors.any?
    result = RecipeWriteService.update(
      slug: params[:slug], markdown: params[:markdown_source],
      kitchen: current_kitchen, category_name: params[:category],
      tags: params[:tags]
    )
    render json: update_response(result)
  end
rescue ActiveRecord::RecordInvalid, RuntimeError => error
  render json: { errors: [error.message] }, status: :unprocessable_content
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n '/structure param/'`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `rake test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add app/controllers/recipes_controller.rb test/controllers/recipes_controller_test.rb
git commit -m "feat: dispatch structured create/update in RecipesController"
```

---

### Task 11: Add Quick Bites Parse/Serialize and Structured Update

**Files:**
- Modify: `app/controllers/menu_controller.rb`
- Modify: `app/services/quick_bites_write_service.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/menu_controller_test.rb`

- [ ] **Step 1: Add routes**

In `config/routes.rb`, within the kitchen scope:

```ruby
post 'menu/parse_quick_bites', to: 'menu#parse_quick_bites', as: :menu_parse_quick_bites
post 'menu/serialize_quick_bites', to: 'menu#serialize_quick_bites', as: :menu_serialize_quick_bites
```

- [ ] **Step 2: Write failing tests**

Add to `test/controllers/menu_controller_test.rb`:

```ruby
test 'parse_quick_bites returns IR from content' do
  log_in
  content = "Snacks:\n- Apples and Honey: Apples, Honey"

  post menu_parse_quick_bites_path, params: { content: }, as: :json

  assert_response :ok
  body = response.parsed_body
  assert_equal 1, body['categories'].size
  assert_equal 'Snacks', body['categories'][0]['name']
  assert_equal 'Apples and Honey', body['categories'][0]['items'][0]['name']
end

test 'serialize_quick_bites returns content from IR' do
  log_in
  ir = {
    categories: [
      { name: 'Snacks', items: [{ name: 'Apples', ingredients: %w[Apples] }] }
    ]
  }

  post menu_serialize_quick_bites_path, params: { structure: ir }, as: :json

  assert_response :ok
  assert_includes response.parsed_body['content'], 'Snacks:'
  assert_includes response.parsed_body['content'], '- Apples'
end

test 'update_quick_bites with structure param uses structured path' do
  log_in
  ir = {
    categories: [
      { name: 'Snacks', items: [{ name: 'Crackers', ingredients: %w[Ritz] }] }
    ]
  }

  patch menu_quick_bites_path, params: { structure: ir }, as: :json

  assert_response :ok
  assert_includes @kitchen.reload.quick_bites_content, 'Snacks:'
  assert_includes @kitchen.quick_bites_content, '- Crackers: Ritz'
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n '/parse_quick_bites|serialize_quick_bites|structure param/'`
Expected: FAIL

- [ ] **Step 4: Implement Quick Bites structured path**

In `app/services/quick_bites_write_service.rb`, add:

```ruby
def self.update_from_structure(kitchen:, structure:)
  content = FamilyRecipes::QuickBitesSerializer.serialize(structure)
  new(kitchen:).update(content:)
end
```

In `app/controllers/menu_controller.rb`, add:

```ruby
def parse_quick_bites
  result = FamilyRecipes.parse_quick_bites_content(params[:content])
  ir = FamilyRecipes::QuickBitesSerializer.to_ir(result.quick_bites)
  render json: ir
end

def serialize_quick_bites
  structure = params[:structure].to_unsafe_h.deep_symbolize_keys
  content = FamilyRecipes::QuickBitesSerializer.serialize(structure)
  render json: { content: }
end
```

Also modify `update_quick_bites` to dispatch on `structure` param:

```ruby
def update_quick_bites
  if params[:structure]
    structure = params[:structure].to_unsafe_h.deep_symbolize_keys
    result = QuickBitesWriteService.update_from_structure(
      kitchen: current_kitchen, structure:
    )
  else
    result = QuickBitesWriteService.update(
      kitchen: current_kitchen, content: params[:content]
    )
  end

  body = { status: 'ok' }
  body[:warnings] = result.warnings if result.warnings.any?
  render json: body
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n '/parse_quick_bites|serialize_quick_bites|structure param/'`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/controllers/menu_controller.rb app/services/quick_bites_write_service.rb \
  config/routes.rb test/controllers/menu_controller_test.rb
git commit -m "feat: add Quick Bites structured import and parse/serialize endpoints"
```

---

### Task 12: Expand Content Endpoint to Return Structure

**Files:**
- Modify: `app/controllers/recipes_controller.rb` (`content` action)
- Test: `test/controllers/recipes_controller_test.rb`

The `content` endpoint currently returns `{ markdown_source, category, tags }`. Expand it to also return the parsed IR structure (for graphical mode) and regenerated markdown (for recipes without front matter category/tags).

- [ ] **Step 1: Write failing test**

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'content returns structure alongside markdown' do
  log_in
  recipe = create_recipe("# Eggs\n\nServes: 2\n\n## Scramble.\n\n- Eggs, 4\n\nScramble.")

  get recipe_content_path(recipe.slug)

  assert_response :ok
  body = response.parsed_body
  assert body['markdown_source'].include?('# Eggs')
  assert_equal 'Eggs', body['structure']['title']
  assert_equal 1, body['structure']['steps'].size
  assert_equal 'Scramble.', body['structure']['steps'][0]['tldr']
end

test 'content regenerates markdown_source with front matter' do
  log_in
  category = @kitchen.categories.create!(name: 'Breakfast')
  recipe = create_recipe("# Plain\n\n## Step.\n\n- Eggs\n\nCook.", category_name: 'Breakfast')
  recipe.tags.create!(name: 'morning', kitchen: @kitchen)

  get recipe_content_path(recipe.slug)

  body = response.parsed_body
  assert_includes body['markdown_source'], 'Category: Breakfast'
  assert_includes body['markdown_source'], 'Tags: morning'
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n '/content returns structure|content regenerates/'`
Expected: FAIL

- [ ] **Step 3: Implement expanded content endpoint**

First, add a `from_record` class method to `FamilyRecipes::RecipeSerializer` in `lib/familyrecipes/recipe_serializer.rb`. This keeps the controller thin (CLAUDE.md: "controllers are thin adapters"):

```ruby
def from_record(recipe)
  {
    title: recipe.title,
    description: recipe.description,
    front_matter: build_front_matter(recipe),
    steps: recipe.steps.map { |step| build_step_ir(step) },
    footer: recipe.footer
  }
end

def build_front_matter(recipe)
  fm = {}
  makes = [recipe.makes_quantity, recipe.makes_unit_noun].compact.join(' ')
  fm[:makes] = makes unless makes.empty?
  fm[:serves] = recipe.serves.to_s if recipe.serves
  fm[:category] = recipe.category.name if recipe.category
  tags = recipe.tags.pluck(:name)
  fm[:tags] = tags if tags.any?
  fm
end

def build_step_ir(step)
  if step.cross_references.any?
    xref = step.cross_references.first
    { tldr: step.title, ingredients: [], instructions: nil,
      cross_reference: { target_title: xref.target_title,
                         multiplier: xref.multiplier, prep_note: xref.prep_note } }
  else
    { tldr: step.title,
      ingredients: step.ingredients.map { |ing| build_ingredient_ir(ing) },
      instructions: step.instructions, cross_reference: nil }
  end
end

def build_ingredient_ir(ing)
  quantity = [ing.quantity, ing.unit].compact.join(' ')
  { name: ing.name, quantity: quantity.empty? ? nil : quantity, prep_note: ing.prep_note }
end
```

Note: `from_record` uses ActiveRecord methods (`pluck`, associations) — this is acceptable since `RecipeSerializer` is already loaded in a Rails context. The `serialize` method remains pure-Ruby (takes a hash), but `from_record` is the Rails-aware bridge.

Then in `app/controllers/recipes_controller.rb`, modify `content`:

```ruby
def content
  recipe = current_kitchen.recipes.with_full_tree.find_by!(slug: params[:slug])
  ir = FamilyRecipes::RecipeSerializer.from_record(recipe)
  markdown = FamilyRecipes::RecipeSerializer.serialize(ir)

  render json: {
    markdown_source: markdown,
    category: recipe.category&.name,
    tags: recipe.tags.pluck(:name),
    structure: ir
  }
end
```

Note: The `content` endpoint now always returns serializer-generated markdown. This means existing recipes without `Category:` and `Tags:` in their `markdown_source` will get those front matter lines added when loaded into the editor. The stored `markdown_source` on the DB record is NOT modified — it's only the editor-loaded content that gets the enriched version.

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n '/content returns structure|content regenerates/'`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `rake test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add app/controllers/recipes_controller.rb test/controllers/recipes_controller_test.rb
git commit -m "feat: expand content endpoint with IR structure and enriched markdown"
```

---

### Task 13: Remove Recipe Editor Side Panel (Stage 3)

**Files:**
- Modify: `app/views/recipes/show.html.erb` (editor dialog section)
- Modify: `app/javascript/controllers/recipe_editor_controller.js`

- [ ] **Step 1: Remove side panel HTML from recipe editors**

Two views have the side panel:

**`app/views/recipes/show.html.erb`** (edit-existing-recipe dialog) — the editor dialog currently has a `div.editor-body-split` layout with the textarea and a `div.editor-side-panel` containing the category dropdown and tag pills. Remove:

1. The `div.editor-body-split` wrapper — replace with just the textarea
2. The entire `div.editor-side-panel` (category select, tag input controller)
3. The `div.editor-mobile-meta` mobile preview panel

**`app/views/homepage/show.html.erb`** (new-recipe dialog, around lines 133-169) — has an identical side panel. Apply the same removal.

In both views, the textarea becomes the sole child of the dialog's yield block. Keep the `data-editor-target="textarea"` and `data-recipe-editor-target="textarea"` attributes.

- [ ] **Step 2: Remove category/tag handling from recipe_editor_controller**

In `app/javascript/controllers/recipe_editor_controller.js`:

1. Remove targets: `categorySelect`, `categoryInput`, `mobilePillPreview`
2. Remove `handleCollect` logic that reads category and tags — the `editor:collect` event now just passes through the textarea value (or the coordinator will handle this in Stage 4)
3. Remove `handleModified` logic for category/tag changes
4. Remove `handleContentLoaded` logic for populating category/tags
5. Remove `selectedCategory()` method
6. Remove `get tagController()` getter
7. Keep: `buildFragment`, `classifyLine`, `highlightIngredient`, `highlightProseLinks` — all the syntax highlighting logic stays

The controller becomes focused solely on syntax highlighting, which is exactly what `recipe_plaintext_controller` will be in Stage 4. This is effectively the pre-extraction refactor.

- [ ] **Step 3: Update `handleCollect` to pass through textarea only**

```javascript
handleCollect (event) {
  event.detail.handled = true
  event.detail.data = { markdown_source: this.textareaTarget.value }
}
```

Category and tags are now in the front matter — the server-side parser extracts them.

- [ ] **Step 4: Update `handleContentLoaded` to just populate textarea**

Since the `content` endpoint now returns enriched markdown (with Category/Tags front matter), the `handleContentLoaded` event handler only needs to handle the textarea population, which the parent `editor_controller` already does via `editor_load_key_value: 'markdown_source'`. The recipe editor controller's `handleContentLoaded` can be removed entirely — the base behavior is sufficient.

- [ ] **Step 5: Verify in dev**

Run: `bin/dev`
- Open a recipe with an existing category and tags
- Click Edit — the editor should show just the textarea
- The textarea should contain `Category:` and `Tags:` front matter lines
- Save without changes — the recipe should retain its category and tags
- Change the category in front matter, save — the category should update

- [ ] **Step 6: Run full test suite**

Run: `rake test`
Expected: All tests pass. Controller tests for recipe create/update via the plaintext path should still work because the markdown now carries category and tags in front matter.

- [ ] **Step 7: Commit**

```bash
git add app/views/recipes/show.html.erb \
  app/javascript/controllers/recipe_editor_controller.js
git commit -m "refactor: remove recipe editor side panel, category and tags now in front matter"
```

---

### Task 14: Lint and Full Verification for Stage 2+3

- [ ] **Step 1: Run RuboCop**

Run: `bundle exec rubocop`
Expected: 0 offenses. Fix any issues.

- [ ] **Step 2: Run full test suite + lint**

Run: `rake`
Expected: All tests pass, 0 RuboCop offenses

- [ ] **Step 3: Commit any lint fixes**

Only if Step 1 required changes.

---

## Chunk 3: Stage 4 — Recipe Graphical Editor + Stage 5 — Quick Bites Graphical Editor

This is the UI-heavy chunk. The server-side work is done in Chunks 1-2; this chunk is entirely Stimulus controllers and views.

### Task 15: Extract Recipe Plaintext Controller

**Files:**
- Create: `app/javascript/controllers/recipe_plaintext_controller.js`

- [ ] **Step 1: Create recipe_plaintext_controller.js**

Extract the syntax highlighting logic from `recipe_editor_controller.js` into a new standalone controller. This controller is responsible for the textarea + highlight overlay in plaintext mode.

Copy `buildFragment`, `classifyLine`, `highlightIngredient`, and `highlightProseLinks` verbatim from the current `recipe_editor_controller.js`. Add a public API for the coordinator:

- `static targets = ['textarea']`
- `textareaTargetConnected`: creates and attaches `HighlightOverlay`
- `textareaTargetDisconnected`: detaches overlay
- `get content()`: returns `this.textareaTarget.value`
- `set content(markdown)`: sets textarea value and re-highlights
- `isModified(originalContent)`: returns boolean

Header comment: plaintext recipe editor, collaborators: recipe_editor_controller (coordinator), HighlightOverlay (utility), editor_controller (dialog lifecycle).

- [ ] **Step 2: Verify plaintext controller works in isolation**

Temporarily wire up the plaintext controller to the recipe editor dialog (swap the controller name in the view). Verify syntax highlighting still works. Then revert.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/recipe_plaintext_controller.js
git commit -m "feat: extract recipe plaintext controller with highlight overlay"
```

---

### Task 16: Build Recipe Graphical Controller

**Files:**
- Create: `app/javascript/controllers/recipe_graphical_controller.js`

This is the largest single file in the plan. It manages the form-based editor: title, description, front matter, step accordion cards with ingredient rows. All DOM construction uses `createElement`/`textContent` — no `innerHTML` (strict CSP compliance).

- [ ] **Step 1: Create the controller with public API**

Targets: `title`, `description`, `serves`, `makes`, `categorySelect`, `categoryInput`, `stepsContainer`, `footer`. Values: `categories` (Array), `allTags` (Array).

Public methods for the coordinator:
- `loadStructure(ir)`: populates all form fields from IR hash
- `toStructure()`: serializes all form fields to IR hash
- `isModified(originalStructure)`: JSON comparison
- `addStep(data)`: creates a new step card (called by Add Step button and for empty-form initialization)

- [ ] **Step 2: Implement step management (add/remove/reorder/collapse)**

Methods: `loadSteps`, `addStep`, `removeStep` (guard: can't remove last step), `moveStep(index, direction)`, `rebuildSteps` (clears container, rebuilds from `this.steps` array), `toggleStep`, `expandStep`, `findExpandedIndex`.

The `this.steps` array holds the current step data. Each mutation to the array is followed by `rebuildSteps()` which re-renders all cards. This is simpler than targeted DOM updates and fast enough for typical recipe step counts (< 20).

- [ ] **Step 3: Implement step card DOM builder**

`buildStepCard(index, stepData)`: dispatches to either `buildCrossRefCard` (read-only, shows target title + multiplier + "edit in </> mode" hint) or `buildStepHeader` + `buildStepBody` (editable).

Step header: toggle icon (▶/▼), step title text, ingredient count summary, ↑/↓/× buttons.
Cross-ref card: link icon, "Imports from [Title] ×multiplier", hint text.

- [ ] **Step 4: Implement step body with ingredient rows**

`buildStepBody(index, stepData)`: step name input, ingredients section, instructions textarea. All collapsed by default (`body.hidden = true`).

`buildIngredientsSection(stepIndex, ingredients)`: header with label + Add button, rows container.

`buildIngredientRow(stepIndex, ingIndex, ing)`: three fields (Name flex:2, Qty flex:1, Prep note flex:2) + ↑/↓ reorder buttons + × remove button. Each input has an `input` event listener that updates `this.steps[stepIndex].ingredients[ingIndex]` directly.

- [ ] **Step 5: Implement helper methods**

DOM builders: `buildButton(text, onClick, style)`, `buildInput(placeholder, value, onChange)`, `buildFieldGroup(label, type, value, onChange)`, `buildTextareaGroup(label, value, onChange)`.

Category handling: `selectedCategory()` (reads select or new-category input), `setCategoryFromIR(category)` (sets select value or shows new-category input).

Tag handling: `get tagController()` (finds nested tag-input controller), `loadTagsFromIR(tags)`.

Front matter: `buildFrontMatter()` (assembles front matter hash from form fields).

Serialization: `serializeSteps()` (maps steps, filters empty ingredient names, passes through cross-ref steps unchanged).

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/recipe_graphical_controller.js
git commit -m "feat: add recipe graphical editor controller"
```

---

### Task 17: Refactor recipe_editor_controller as Coordinator

**Files:**
- Modify: `app/javascript/controllers/recipe_editor_controller.js`

- [ ] **Step 1: Rewrite as coordinator**

The controller manages mode toggle and routes editor lifecycle events. Key pieces:

Targets: `plaintextContainer`, `graphicalContainer`, `modeToggle`.
Values: `parseUrl` (String), `serializeUrl` (String).

On connect: read mode from `localStorage` (default `'graphical'`), store `originalContent` and `originalStructure` as null, register listeners for `editor:collect`, `editor:modified`, `editor:content-loaded`.

`toggleMode()`: calls `switchTo()` with the opposite mode.

`async switchTo(newMode)`:
- Graphical → Plaintext: `POST serializeUrlValue` with `{ structure }`, get `{ markdown }`, set `plaintextController.content`
- Plaintext → Graphical: `POST parseUrlValue` with `{ markdown_source }`, get IR, call `graphicalController.loadStructure(ir)`
- Update `localStorage`, call `showActiveMode()`

`showActiveMode()`: toggle `hidden` on both containers, update toggle button icon/title.

`handleCollect(event)`: set `event.detail.data` to either `{ markdown_source }` or `{ structure }` based on active mode.

`handleModified(event)`: delegate to active controller's `isModified`.

`handleContentLoaded(event)`: store `originalContent` and `originalStructure` from loaded data, populate both child controllers, call `showActiveMode()`.

Child access: `get plaintextController()` and `get graphicalController()` — find nested controllers via `this.application.getControllerForElementAndIdentifier`.

Header comment: coordinator for dual-mode recipe editing, collaborators: editor_controller, recipe_plaintext_controller, recipe_graphical_controller.

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/recipe_editor_controller.js
git commit -m "refactor: recipe_editor_controller becomes dual-mode coordinator"
```

---

### Task 18: Update Recipe Editor View for Dual Mode

**Files:**
- Modify: `app/views/recipes/show.html.erb`
- Create: `app/views/recipes/_graphical_editor.html.erb`
- Modify: `app/views/shared/_editor_dialog.html.erb`
- Modify: `app/views/homepage/show.html.erb` (new recipe dialog)

- [ ] **Step 1: Add mode toggle button to editor dialog partial**

In `app/views/shared/_editor_dialog.html.erb`, add a toggle button in the header bar before the close button. Use an optional `mode_toggle` local — only recipe and Quick Bites editors pass `mode_toggle: true`.

- [ ] **Step 2: Create graphical editor partial**

Create `app/views/recipes/_graphical_editor.html.erb` with the form structure matching the wireframe: title input, description textarea, front matter row (serves, makes, category dropdown with inline new-category option), tag input (reuses `tag_input_controller`), steps container with Add Step button, footer textarea. All elements use `data-recipe-graphical-target` attributes.

- [ ] **Step 3: Update recipe show view for dual mode**

Replace the current single-textarea yield block with a switchable container: `plaintextContainer` (textarea + recipe-plaintext controller) and `graphicalContainer` (graphical editor partial, hidden by default). Pass `recipe_editor_parse_url_value` and `recipe_editor_serialize_url_value` via `extra_data`.

- [ ] **Step 4: Update homepage new-recipe dialog similarly**

Apply the same dual-mode pattern to the new-recipe editor dialog in `app/views/homepage/show.html.erb`. The graphical controller starts with one empty step pre-created.

- [ ] **Step 5: Verify in dev**

Run: `bin/dev`
- Open a recipe, click Edit — should open in graphical mode (localStorage default)
- Toggle to plaintext — should show textarea with markdown
- Toggle back to graphical — form fields should be populated
- Save from graphical mode — recipe should update
- Save from plaintext mode — recipe should update
- New Recipe — should open in graphical mode with empty fields and one blank step

- [ ] **Step 6: Commit**

```bash
git add app/views/recipes/show.html.erb app/views/recipes/_graphical_editor.html.erb \
  app/views/shared/_editor_dialog.html.erb app/views/homepage/show.html.erb
git commit -m "feat: dual-mode recipe editor with mode toggle"
```

---

### Task 19: Add CSS for Graphical Editor

**Files:**
- Modify: `app/assets/stylesheets/style.css` (or appropriate stylesheet)

- [ ] **Step 1: Add graphical editor styles**

Key classes: `.graphical-form`, `.graphical-field-group`, `.graphical-label`, `.graphical-optional`, `.graphical-input`, `.graphical-textarea`, `.graphical-input-title`, `.graphical-front-matter-row`, `.graphical-step-card`, `.graphical-step-header`, `.graphical-step-header-left`, `.graphical-step-body`, `.graphical-step-readonly`, `.graphical-step-hint`, `.graphical-step-toggle`, `.graphical-step-summary`, `.graphical-step-controls`, `.graphical-ingredients-section`, `.graphical-ingredient-row`, `.graphical-ingredient-reorder`, `.graphical-section-header`, `.graphical-btn`, `.graphical-btn-danger`, `.editor-mode-toggle`, `.editor-header-actions`.

Responsive: `.graphical-front-matter-row` wraps on mobile, ingredient rows stack vertically. Match existing editor dialog aesthetics.

- [ ] **Step 2: Verify visual appearance matches wireframe**

Run `bin/dev` and compare against the wireframe mockup from brainstorming.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "feat: add CSS for graphical recipe editor"
```

---

### Task 20: Quick Bites Dual-Mode Editor

**Files:**
- Create: `app/javascript/controllers/quickbites_plaintext_controller.js`
- Create: `app/javascript/controllers/quickbites_graphical_controller.js`
- Modify: `app/javascript/controllers/quickbites_editor_controller.js`
- Create: `app/views/menu/_quickbites_graphical_editor.html.erb`
- Modify: `app/views/menu/show.html.erb`

Same pattern as recipe editor, but simpler — two levels (categories with items).

- [ ] **Step 1: Create quickbites_plaintext_controller**

Extract `buildFragment` from `quickbites_editor_controller.js`. Same structure as Task 15.

- [ ] **Step 2: Create quickbites_graphical_controller**

Accordion card pattern with: category header (editable name input + ↑↓ + ×), item rows (Name + Ingredients comma-separated text + ↑↓ + ×), Add Category and Add Item buttons. Public API: `loadStructure(ir)`, `toStructure()`, `isModified(original)`. All DOM via `createElement`/`textContent`.

- [ ] **Step 3: Refactor quickbites_editor_controller as coordinator**

Same pattern as Task 17: mode toggle, event routing, fetch to `menu_parse_quick_bites_path` / `menu_serialize_quick_bites_path`.

- [ ] **Step 4: Create graphical editor partial and update view**

Create `app/views/menu/_quickbites_graphical_editor.html.erb` and update `app/views/menu/show.html.erb` with dual-mode container pattern.

- [ ] **Step 5: Add Quick Bites graphical CSS**

Reuses most `.graphical-*` classes. Add Quick Bites-specific classes if needed.

- [ ] **Step 6: Verify in dev**

Run `bin/dev`, test: graphical mode, toggle, save from both modes, round-trip.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/quickbites_plaintext_controller.js \
  app/javascript/controllers/quickbites_graphical_controller.js \
  app/javascript/controllers/quickbites_editor_controller.js \
  app/views/menu/_quickbites_graphical_editor.html.erb \
  app/views/menu/show.html.erb
git commit -m "feat: add Quick Bites dual-mode editor"
```

---

### Task 21: Final Lint and Full Verification

- [ ] **Step 1: Run RuboCop**

Run: `bundle exec rubocop`
Expected: 0 offenses

- [ ] **Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass

- [ ] **Step 3: Update html_safe_allowlist if needed**

If any new `.html_safe` calls were added (unlikely — all DOM construction uses `createElement`/`textContent`), update `config/html_safe_allowlist.yml`.

- [ ] **Step 4: Verify both editors end-to-end**

Run `bin/dev` and test:
1. Recipe: create new (graphical), edit existing (graphical), toggle to plaintext, save from both modes
2. Quick Bites: edit (graphical), toggle, save from both modes
3. Cross-reference recipe: verify read-only card in graphical mode
4. Mode preference persists across page reloads (localStorage)

- [ ] **Step 5: Commit any remaining fixes**
