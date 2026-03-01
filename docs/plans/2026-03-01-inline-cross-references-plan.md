# Inline Cross-Reference Rendering Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace ingredient-style cross-reference links with inline embedded recipe cards using `>>>` block syntax.

**Architecture:** Cross-references become standalone step-level blocks parsed by a new `CrossReferenceParser` module. The view renders resolved references as embedded recipe cards (one level deep) and broken references as warning cards. RecipeBroadcaster cascades page updates to parent recipes when a target recipe changes.

**Tech Stack:** Rails 8, SQLite, Turbo Streams, Stimulus, Minitest

**Design doc:** `docs/plans/2026-03-01-inline-cross-references-design.md`

---

### Task 0: Create CrossReferenceParser module

Extract cross-reference parsing from `IngredientParser` into a focused module.

**Files:**
- Create: `lib/familyrecipes/cross_reference_parser.rb`
- Create: `test/cross_reference_parser_test.rb`
- Modify: `config/initializers/familyrecipes.rb` (add require)

**Step 1: Write the failing tests**

```ruby
# test/cross_reference_parser_test.rb
require 'minitest/autorun'
require_relative '../lib/familyrecipes'

class CrossReferenceParserTest < Minitest::Test
  def test_parses_simple_reference
    result = CrossReferenceParser.parse('@[Pizza Dough]')
    assert_equal 'Pizza Dough', result[:target_title]
    assert_equal 1.0, result[:multiplier]
    assert_nil result[:prep_note]
  end

  def test_parses_integer_multiplier
    result = CrossReferenceParser.parse('@[Pizza Dough], 2')
    assert_equal 2.0, result[:multiplier]
  end

  def test_parses_fraction_multiplier
    result = CrossReferenceParser.parse('@[Pizza Dough], 1/2')
    assert_in_delta 0.5, result[:multiplier]
  end

  def test_parses_decimal_multiplier
    result = CrossReferenceParser.parse('@[Pizza Dough], 0.5')
    assert_in_delta 0.5, result[:multiplier]
  end

  def test_parses_multiplier_and_prep_note
    result = CrossReferenceParser.parse('@[Pizza Dough], 2: Let rest 30 min.')
    assert_equal 2.0, result[:multiplier]
    assert_equal 'Let rest 30 min.', result[:prep_note]
  end

  def test_parses_trailing_period
    result = CrossReferenceParser.parse('@[Pizza Dough].')
    assert_equal 'Pizza Dough', result[:target_title]
  end

  def test_raises_on_missing_reference_syntax
    error = assert_raises(RuntimeError) { CrossReferenceParser.parse('Pizza Dough') }
    assert_match(/Invalid cross-reference/, error.message)
  end

  def test_raises_on_old_quantity_first_syntax
    error = assert_raises(RuntimeError) { CrossReferenceParser.parse('2 @[Pizza Dough]') }
    assert_match(/quantity/, error.message)
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/cross_reference_parser_test.rb`
Expected: FAIL — `CrossReferenceParser` not defined

**Step 3: Implement CrossReferenceParser**

```ruby
# lib/familyrecipes/cross_reference_parser.rb
# frozen_string_literal: true

# Parses the content of a >>> cross-reference block line. Extracts target recipe
# title, optional multiplier, and optional prep note from "@[Title], mult: note"
# syntax. Extracted from IngredientParser as a focused single-purpose module.
module CrossReferenceParser
  PATTERN = %r{\A@\[(.+?)\](?:\.\s*)?(?:,\s*(\d+(?:/\d+)?(?:\.\d+)?))?\s*(?::\s*(.+))?\z}
  OLD_SYNTAX = %r{\A\d+(?:/\d+)?(?:\.\d+)?x?\s*@\[}

  def self.parse(text)
    if text.match?(OLD_SYNTAX)
      raise "Invalid cross-reference syntax: \"#{text}\". " \
            'Use @[Recipe Title], quantity (quantity after reference).'
    end

    match = text.match(PATTERN)
    unless match
      raise "Invalid cross-reference syntax: \"#{text}\". " \
            'Expected >>> @[Recipe Title]'
    end

    title, multiplier_str, prep_note = match.captures
    {
      target_title: title,
      multiplier: parse_multiplier(multiplier_str),
      prep_note: prep_note
    }
  end

  def self.parse_multiplier(str)
    FamilyRecipes::NumericParsing.parse_fraction(str) || 1.0
  end

  private_class_method :parse_multiplier
end
```

Add require to `config/initializers/familyrecipes.rb` alongside the other parser requires.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/cross_reference_parser_test.rb`
Expected: PASS (all 8 tests)

**Step 5: Commit**

```bash
git add lib/familyrecipes/cross_reference_parser.rb test/cross_reference_parser_test.rb config/initializers/familyrecipes.rb
git commit -m "feat: extract CrossReferenceParser module from IngredientParser"
```

---

### Task 1: Add `:cross_reference_block` token to LineClassifier

**Files:**
- Modify: `lib/familyrecipes/line_classifier.rb:11-18`
- Modify: `test/line_classifier_test.rb`

**Step 1: Write the failing tests**

Add to `test/line_classifier_test.rb`:

```ruby
def test_classifies_cross_reference_block
  type, content = LineClassifier.classify_line('>>> @[Pizza Dough]')
  assert_equal :cross_reference_block, type
  assert_equal ['@[Pizza Dough]'], content
end

def test_classifies_cross_reference_block_with_multiplier
  type, content = LineClassifier.classify_line('>>> @[Pizza Dough], 2: Let rest.')
  assert_equal :cross_reference_block, type
  assert_equal ['@[Pizza Dough], 2: Let rest.'], content
end

def test_does_not_classify_four_arrows_as_cross_reference
  type, _content = LineClassifier.classify_line('>>>> not a cross-ref')
  assert_equal :prose, type
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/line_classifier_test.rb`
Expected: FAIL — `>>>` classified as `:prose`

**Step 3: Add the pattern to LINE_PATTERNS**

In `lib/familyrecipes/line_classifier.rb`, add `cross_reference_block` after `:ingredient`:

```ruby
LINE_PATTERNS = {
  title: /^# (.+)$/,
  step_header: /^## (.+)$/,
  ingredient: /^- (.+)$/,
  cross_reference_block: /^>>>\s+(.+)$/,
  divider: /^---\s*$/,
  front_matter: /^(Category|Makes|Serves):\s+(.+)$/,
  blank: /^\s*$/
}.freeze
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/line_classifier_test.rb`
Expected: PASS (all tests)

**Step 5: Commit**

```bash
git add lib/familyrecipes/line_classifier.rb test/line_classifier_test.rb
git commit -m "feat: add :cross_reference_block token to LineClassifier"
```

---

### Task 2: Remove cross-reference handling from IngredientParser

**Files:**
- Modify: `lib/familyrecipes/ingredient_parser.rb:1-53`
- Modify: `test/ingredient_parser_test.rb`
- Modify: `test/cross_reference_test.rb` (parser-level cross-ref tests move/update)

**Step 1: Update tests — old `@[...]` syntax now raises an error**

In `test/ingredient_parser_test.rb`, remove any tests that expect `IngredientParser.parse` to successfully parse `@[...]` syntax. Add:

```ruby
def test_raises_on_cross_reference_syntax
  error = assert_raises(RuntimeError) { IngredientParser.parse('@[Pizza Dough]') }
  assert_match(/>>> syntax/, error.message)
end
```

In `test/cross_reference_test.rb`, update the parser-level cross-reference parsing tests to use `CrossReferenceParser.parse` instead of `IngredientParser.parse`. The `FamilyRecipes::CrossReference` domain object tests and `FamilyRecipes::Recipe` aggregation tests remain unchanged.

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/ingredient_parser_test.rb`
Expected: FAIL — `IngredientParser` still parses `@[...]` successfully

**Step 3: Remove cross-reference handling from IngredientParser**

In `lib/familyrecipes/ingredient_parser.rb`:
- Remove `CROSS_REF_PATTERN` and `OLD_CROSS_REF_PATTERN`
- Remove the cross-reference branch from `parse`
- Remove `parse_multiplier`
- Add a guard at the top of `parse` that detects `@[` and raises a helpful error:

```ruby
def self.parse(text)
  if text.start_with?('@[')
    raise "Cross-references now use >>> syntax. Write: >>> #{text}"
  end

  parts = text.split(':', 2)
  # ... rest of regular ingredient parsing (unchanged)
end
```

**Step 4: Run all parser tests to verify they pass**

Run: `ruby -Itest test/ingredient_parser_test.rb && ruby -Itest test/cross_reference_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/familyrecipes/ingredient_parser.rb test/ingredient_parser_test.rb test/cross_reference_test.rb
git commit -m "refactor: remove cross-reference handling from IngredientParser"
```

---

### Task 3: Teach RecipeBuilder to handle `>>>` blocks with validation

**Files:**
- Modify: `lib/familyrecipes/recipe_builder.rb:82-131`
- Modify: `test/recipe_builder_test.rb`

**Step 1: Write the failing tests**

Add to `test/recipe_builder_test.rb`:

```ruby
def test_parses_cross_reference_step
  tokens = LineClassifier.classify(<<~MD)
    # Pizza

    Category: Bread

    ## Make dough.
    >>> @[Pizza Dough]

    ## Top.
    - Mozzarella, 8 oz
  MD
  result = RecipeBuilder.new(tokens).build

  assert_equal 2, result[:steps].size

  xref_step = result[:steps][0]
  assert_equal 'Make dough.', xref_step[:tldr]
  assert_equal 'Pizza Dough', xref_step[:cross_reference][:target_title]
  assert_equal 1.0, xref_step[:cross_reference][:multiplier]
  assert_empty xref_step[:ingredients]

  normal_step = result[:steps][1]
  assert_equal 'Top.', normal_step[:tldr]
  assert_nil normal_step[:cross_reference]
  assert_equal 1, normal_step[:ingredients].size
end

def test_parses_cross_reference_with_multiplier_and_prep_note
  tokens = LineClassifier.classify(<<~MD)
    # Pizza

    Category: Bread

    ## Make dough.
    >>> @[Pizza Dough], 2: Let rest 30 min.
  MD
  result = RecipeBuilder.new(tokens).build
  xref = result[:steps][0][:cross_reference]

  assert_equal 2.0, xref[:multiplier]
  assert_equal 'Let rest 30 min.', xref[:prep_note]
end

def test_rejects_cross_reference_in_implicit_step
  tokens = LineClassifier.classify(<<~MD)
    # Pizza

    Category: Bread

    >>> @[Pizza Dough]
  MD

  error = assert_raises(RuntimeError) { RecipeBuilder.new(tokens).build }
  assert_match(/explicit step/, error.message)
end

def test_rejects_cross_reference_mixed_with_ingredients
  tokens = LineClassifier.classify(<<~MD)
    # Pizza

    Category: Bread

    ## Make dough.
    - Flour, 3 cups
    >>> @[Pizza Dough]
  MD

  error = assert_raises(RuntimeError) { RecipeBuilder.new(tokens).build }
  assert_match(/cannot be mixed with ingredients/, error.message)
end

def test_rejects_cross_reference_mixed_with_instructions
  tokens = LineClassifier.classify(<<~MD)
    # Pizza

    Category: Bread

    ## Make dough.
    >>> @[Pizza Dough]

    Mix everything together.
  MD

  error = assert_raises(RuntimeError) { RecipeBuilder.new(tokens).build }
  assert_match(/cannot be mixed with instructions/, error.message)
end

def test_rejects_multiple_cross_references_in_one_step
  tokens = LineClassifier.classify(<<~MD)
    # Pizza

    Category: Bread

    ## Prepare.
    >>> @[Pizza Dough]
    >>> @[Pizza Sauce]
  MD

  error = assert_raises(RuntimeError) { RecipeBuilder.new(tokens).build }
  assert_match(/Only one cross-reference/, error.message)
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/recipe_builder_test.rb`
Expected: FAIL — RecipeBuilder ignores `>>>` tokens

**Step 3: Implement cross-reference block handling in RecipeBuilder**

Modify `collect_step_body` in `lib/familyrecipes/recipe_builder.rb` to handle `:cross_reference_block` tokens:

```ruby
def collect_step_body(stop_at: %i[divider])
  ingredients = []
  instruction_lines = []
  cross_reference = nil

  until at_end? || stop_at.include?(peek.type)
    token = advance

    case token.type
    when :cross_reference_block
      validate_cross_reference_placement(token, ingredients, instruction_lines, cross_reference)
      cross_reference = CrossReferenceParser.parse(token.content[0])
    when :ingredient
      raise_mixed_content_error(token, 'ingredients') if cross_reference
      ingredients << IngredientParser.parse(token.content[0])
    when :prose
      raise_mixed_content_error(token, 'instructions') if cross_reference
      instruction_lines << token.content
    end
  end

  { tldr: nil, ingredients: ingredients, instructions: instruction_lines.join("\n\n"),
    cross_reference: cross_reference }
end

def validate_cross_reference_placement(token, ingredients, instruction_lines, existing_xref)
  if existing_xref
    raise "Only one cross-reference (>>>) is allowed per step (line #{token.line_number})"
  end
  if ingredients.any?
    raise "Cross-reference (>>>) at line #{token.line_number} cannot be mixed with ingredients in the same step"
  end
  if instruction_lines.any?
    raise "Cross-reference (>>>) at line #{token.line_number} cannot be mixed with instructions in the same step"
  end
end

def raise_mixed_content_error(token, content_type)
  raise "Cross-reference (>>>) at line #{token.line_number} cannot be mixed with #{content_type} in the same step"
end
```

For implicit steps, add a guard in the implicit step path. When `parse_steps` encounters a `:cross_reference_block` at the top level (before any `##` header):

```ruby
def parse_steps
  skip_blanks

  if !at_end? && peek.type != :step_header && peek.type != :divider
    if peek.type == :cross_reference_block
      raise "Cross-reference (>>>) at line #{peek.line_number} must appear inside " \
            'an explicit step (## Step Name)'
    end
    step = parse_implicit_step
    return step[:ingredients].any? ? [step] : []
  end

  parse_explicit_steps
end
```

Also check inside `parse_implicit_step`/`collect_step_body` when called from the implicit path — if a `>>>` appears mid-body of an implicit step, raise the same error. The cleanest approach: pass a flag to `collect_step_body`:

```ruby
def parse_implicit_step
  collect_step_body(implicit: true)
end

def collect_step_body(stop_at: %i[divider], implicit: false)
  # ... inside the :cross_reference_block case:
  when :cross_reference_block
    if implicit
      raise "Cross-reference (>>>) at line #{token.line_number} must appear inside " \
            'an explicit step (## Step Name)'
    end
    validate_cross_reference_placement(token, ingredients, instruction_lines, cross_reference)
    cross_reference = CrossReferenceParser.parse(token.content[0])
  # ...
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/recipe_builder_test.rb`
Expected: PASS (all tests)

**Step 5: Run full parser test suite**

Run: `ruby -Itest test/line_classifier_test.rb && ruby -Itest test/recipe_builder_test.rb && ruby -Itest test/ingredient_parser_test.rb && ruby -Itest test/cross_reference_test.rb`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/familyrecipes/recipe_builder.rb test/recipe_builder_test.rb
git commit -m "feat: RecipeBuilder handles >>> cross-reference blocks with validation"
```

---

### Task 4: Update MarkdownImporter for new step data shape

**Files:**
- Modify: `app/services/markdown_importer.rb:93-105`
- Modify: `test/services/markdown_importer_test.rb`

**Step 1: Update existing tests and write new ones**

Existing cross-reference tests in `test/services/markdown_importer_test.rb` use `- @[...]` syntax. Update them all to use `>>> @[...]` inside explicit steps. For example, any test fixture like:

```ruby
## Step
- @[Pizza Dough], 1
- Mozzarella, 8 oz
```

Becomes two steps:

```ruby
## Make dough.
>>> @[Pizza Dough]

## Top.
- Mozzarella, 8 oz
```

Add a new test:

```ruby
test 'imports cross-reference step with >>> syntax' do
  recipe = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Test Recipe

    Category: Bread

    ## Make dough.
    >>> @[Pizza Dough]

    ## Top.
    - Mozzarella, 8 oz
  MD

  assert_equal 2, recipe.steps.size

  xref_step = recipe.steps.first
  assert_equal 'Make dough.', xref_step.title
  assert_equal 1, xref_step.cross_references.size
  assert_empty xref_step.ingredients

  xref = xref_step.cross_references.first
  assert_equal 'Pizza Dough', xref.target_title
  assert_equal 'pizza-dough', xref.target_slug
  assert_equal 0, xref.position
end

test 'imports cross-reference with multiplier and prep note via >>> syntax' do
  recipe = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Test Recipe

    Category: Bread

    ## Make dough.
    >>> @[Pizza Dough], 2: Let rest 30 min.
  MD

  xref = recipe.steps.first.cross_references.first
  assert_equal 2.0, xref.multiplier
  assert_equal 'Let rest 30 min.', xref.prep_note
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/markdown_importer_test.rb`
Expected: FAIL — MarkdownImporter doesn't handle new step data shape

**Step 3: Update MarkdownImporter**

In `app/services/markdown_importer.rb`, modify `replace_steps` to branch on step data shape:

```ruby
def replace_steps(recipe)
  recipe.steps.destroy_all

  parsed[:steps].each_with_index do |step_data, index|
    step = recipe.steps.create!(
      title: step_data[:tldr],
      instructions: step_data[:cross_reference] ? nil : step_data[:instructions],
      processed_instructions: step_data[:cross_reference] ? nil : process_instructions(step_data[:instructions]),
      position: index
    )

    if step_data[:cross_reference]
      import_cross_reference(step, step_data[:cross_reference])
    else
      import_step_items(step, step_data[:ingredients])
    end
  end
end
```

Update `import_cross_reference` to accept the new data shape (hash with `:target_title`, `:multiplier`, `:prep_note` — no `:cross_reference` boolean flag):

```ruby
def import_cross_reference(step, data, position = 0)
  target_slug = FamilyRecipes.slugify(data[:target_title])
  target = kitchen.recipes.find_by(slug: target_slug)

  step.cross_references.create!(
    target_recipe: target,
    target_slug: target_slug,
    target_title: data[:target_title],
    multiplier: data[:multiplier] || 1.0,
    prep_note: data[:prep_note],
    position: position
  )
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/markdown_importer_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/markdown_importer.rb test/services/markdown_importer_test.rb
git commit -m "feat: MarkdownImporter handles >>> cross-reference step data"
```

---

### Task 5: Update domain parser classes for new syntax

The domain `FamilyRecipes::Recipe` class (in `lib/familyrecipes/recipe.rb`) builds `FamilyRecipes::Step` objects, which currently expect cross-references to arrive as part of `ingredient_list_items`. With the new step data shape, cross-reference steps have a `:cross_reference` key instead.

**Files:**
- Modify: `lib/familyrecipes/recipe.rb`
- Modify: `lib/familyrecipes/step.rb`
- Modify: `test/cross_reference_test.rb` (domain-level tests)

**Step 1: Write failing tests**

Update tests in `test/cross_reference_test.rb` that build recipes with cross-references to use the new step data structure. The domain `FamilyRecipes::Step` currently requires either ingredients or instructions — a cross-reference-only step needs to be valid.

```ruby
def test_cross_reference_step_is_valid_with_only_cross_reference
  xref = FamilyRecipes::CrossReference.new(target_title: 'Pizza Dough')
  step = FamilyRecipes::Step.new(
    tldr: 'Make dough.',
    instructions: nil,
    ingredient_list_items: [xref]
  )
  assert_equal [xref], step.cross_references
  assert_empty step.ingredients
end
```

**Step 2: Run tests to verify current behavior**

Run: `ruby -Itest test/cross_reference_test.rb`
Expected: This particular test should PASS already (Step allows items that are only cross-references). Verify, then continue.

**Step 3: Update Recipe's step-building to handle the new data shape**

In `lib/familyrecipes/recipe.rb`, the `build_steps` method (or wherever step data from RecipeBuilder is consumed) needs to handle steps with a `:cross_reference` key. If this recipe domain class is only used in the parser test path (not the import path), the changes may be minimal — confirm by checking how the domain `Recipe` class is constructed and update accordingly.

**Step 4: Run domain tests**

Run: `ruby -Itest test/cross_reference_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/familyrecipes/recipe.rb lib/familyrecipes/step.rb test/cross_reference_test.rb
git commit -m "refactor: domain parser classes handle >>> step data shape"
```

---

### Task 6: Add `cross_reference_step?` and `cross_reference_block` to Step AR model

**Files:**
- Modify: `app/models/step.rb:7-19`
- Modify: `test/models/cross_reference_test.rb`

**Step 1: Write the failing tests**

Add to `test/models/cross_reference_test.rb`:

```ruby
test 'cross_reference_step? returns true when step has a cross-reference' do
  step = @recipe.steps.first
  step.cross_references.create!(
    target_slug: 'pizza-dough', target_title: 'Pizza Dough', position: 0
  )
  assert step.cross_reference_step?
end

test 'cross_reference_step? returns false for normal steps' do
  step = @recipe.steps.first
  refute step.cross_reference_step?
end

test 'cross_reference_block returns the single cross-reference' do
  step = @recipe.steps.first
  xref = step.cross_references.create!(
    target_slug: 'pizza-dough', target_title: 'Pizza Dough', position: 0
  )
  assert_equal xref, step.cross_reference_block
end

test 'cross_reference_block returns nil for normal steps' do
  step = @recipe.steps.first
  assert_nil step.cross_reference_block
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/cross_reference_test.rb`
Expected: FAIL — methods not defined

**Step 3: Add methods to Step model**

In `app/models/step.rb`:

```ruby
def cross_reference_step?
  cross_references.any?
end

def cross_reference_block
  cross_references.first
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/cross_reference_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/step.rb test/models/cross_reference_test.rb
git commit -m "feat: add cross_reference_step? and cross_reference_block to Step"
```

---

### Task 7: Change Recipe `dependent: :destroy` to `dependent: :nullify` on inbound_cross_references

**Files:**
- Modify: `app/models/recipe.rb:15-18`
- Modify: `test/models/cross_reference_test.rb`

**Step 1: Write the failing test**

Add to `test/models/cross_reference_test.rb`:

```ruby
test 'destroying a recipe nullifies inbound cross-references' do
  target = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Target Recipe

    Category: Bread

    ## Mix.
    - Flour, 3 cups
  MD

  parent = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Parent Recipe

    Category: Bread

    ## Use target.
    >>> @[Target Recipe]
  MD

  xref = parent.steps.first.cross_references.first
  assert xref.resolved?

  target.destroy!
  xref.reload

  assert xref.pending?
  assert_nil xref.target_recipe_id
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/cross_reference_test.rb -n test_destroying_a_recipe_nullifies_inbound_cross_references`
Expected: FAIL — `dependent: :destroy` deletes the cross-reference entirely

**Step 3: Change to dependent: :nullify**

In `app/models/recipe.rb`, line 18:

```ruby
# Before:
dependent: :destroy

# After:
dependent: :nullify
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/models/cross_reference_test.rb -n test_destroying_a_recipe_nullifies_inbound_cross_references`
Expected: PASS

**Step 5: Run full model test suite**

Run: `ruby -Itest test/models/cross_reference_test.rb`
Expected: PASS

**Step 6: Commit**

```bash
git add app/models/recipe.rb test/models/cross_reference_test.rb
git commit -m "fix: nullify inbound cross-references on recipe destroy instead of deleting"
```

---

### Task 8: Update CrossReferenceUpdater — remove strip_references, update rename for `>>>` syntax

**Files:**
- Modify: `app/services/cross_reference_updater.rb:1-46`
- Modify: `test/services/cross_reference_updater_test.rb`
- Modify: `app/controllers/recipes_controller.rb:66-82`

**Step 1: Update tests**

In `test/services/cross_reference_updater_test.rb`:
- Update the setup fixture to use `>>>` syntax (the `@pizza` recipe's Markdown)
- Remove `strip_references` tests (3 tests)
- Keep and update `rename_references` tests to verify they work with `>>>` syntax

```ruby
setup do
  # ... @dough stays the same ...

  @pizza = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Margherita Pizza

    Category: Bread

    ## Make dough.
    >>> @[Pizza Dough]

    ## Top.
    - Mozzarella, 8 oz

    Stretch dough and top.
  MD
end

test 'rename_references updates @[Old] to @[New] in referencing recipes with >>> syntax' do
  CrossReferenceUpdater.rename_references(old_title: 'Pizza Dough', new_title: 'Neapolitan Dough',
                                          kitchen: @kitchen)
  @pizza.reload

  assert_includes @pizza.markdown_source, '>>> @[Neapolitan Dough]'
  assert_not_includes @pizza.markdown_source, '@[Pizza Dough]'
end

# Keep the "returns titles" test with same assertion
```

**Step 2: Remove strip_references from the service**

In `app/services/cross_reference_updater.rb`:
- Remove `self.strip_references` class method
- Remove `strip_references` instance method
- Keep `rename_references` and `update_referencing_recipes` unchanged

**Step 3: Remove strip_references call from RecipesController#destroy**

In `app/controllers/recipes_controller.rb`, the destroy action currently calls `CrossReferenceUpdater.strip_references(@recipe)`. Remove this call. The `dependent: :nullify` on the model handles the cross-reference cleanup now.

```ruby
def destroy
  @recipe = current_kitchen.recipes.find_by!(slug: params[:slug])

  RecipeBroadcaster.notify_recipe_deleted(@recipe, recipe_title: @recipe.title)
  @recipe.destroy!
  Category.cleanup_orphans(current_kitchen)
  plan = MealPlan.for_kitchen(current_kitchen)
  plan.with_optimistic_retry { plan.prune_checked_off }

  RecipeBroadcaster.broadcast(kitchen: current_kitchen, action: :deleted,
                              recipe_title: @recipe.title)

  render json: { redirect_url: home_path }
end
```

Note: The `updated_references` response field is removed from destroy. It was only used for `strip_references`.

**Step 4: Run tests**

Run: `ruby -Itest test/services/cross_reference_updater_test.rb && ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: Some controller tests may fail (e.g., `test_destroy_strips_cross-references_from_referencing_recipes`). Update those tests to assert nullification instead of stripping.

**Step 5: Update controller tests**

Replace `test_destroy_strips_cross-references_from_referencing_recipes` with:

```ruby
test 'destroy nullifies inbound cross-references' do
  # Setup: create target and parent recipe with >>> reference
  # Destroy target
  # Assert: parent's cross-reference still exists but target_recipe_id is nil
end
```

**Step 6: Run full test suite**

Run: `rake test`
Expected: PASS

**Step 7: Commit**

```bash
git add app/services/cross_reference_updater.rb test/services/cross_reference_updater_test.rb app/controllers/recipes_controller.rb test/controllers/recipes_controller_test.rb
git commit -m "refactor: remove strip_references, rely on dependent: :nullify for recipe deletion"
```

---

### Task 9: Update seed files to `>>>` syntax

**Files:**
- Modify: `db/seeds/recipes/Pizza/White Pizza.md:6-8`

**Step 1: Update the Markdown**

Change:

```markdown
## Make dough.

- @[Pizza Dough]
```

To:

```markdown
## Make dough.

>>> @[Pizza Dough]
```

**Step 2: Verify seeds work**

Run: `rails db:seed`
Expected: No errors, Pizza Dough reference resolves

**Step 3: Commit**

```bash
git add db/seeds/recipes/Pizza/White\ Pizza.md
git commit -m "chore: migrate seed cross-references to >>> syntax"
```

---

### Task 10: Create embedded recipe view partials

**Files:**
- Create: `app/views/recipes/_embedded_recipe.html.erb`
- Create: `app/views/recipes/_broken_reference.html.erb`
- Modify: `app/views/recipes/_step.html.erb`
- Modify: `app/views/recipes/_recipe_content.html.erb:18-20`
- Modify: `app/helpers/recipes_helper.rb`

**Step 1: Write controller test for embedded rendering**

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'show renders resolved cross-reference as embedded recipe card' do
  dough = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Pizza Dough

    Category: Bread

    ## Mix.
    - Flour, 500 g
    - Water, 300 ml

    Combine ingredients.
  MD

  pizza = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # White Pizza

    Category: Bread

    ## Make dough.
    >>> @[Pizza Dough]

    ## Top.
    - Mozzarella, 200 g
  MD

  get recipe_path('white-pizza')
  assert_response :success

  assert_select 'article.embedded-recipe' do
    assert_select 'a[href=?]', recipe_path('pizza-dough'), text: 'Pizza Dough'
    assert_select '.ingredients li', text: /Flour/
    assert_select '.ingredients li', text: /Water/
  end
end

test 'show renders pending cross-reference as broken reference card' do
  pizza = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # White Pizza

    Category: Bread

    ## Make dough.
    >>> @[Nonexistent Recipe]
  MD

  get recipe_path('white-pizza')
  assert_response :success

  assert_select '.broken-reference', text: /Nonexistent Recipe/
  assert_select '.broken-reference', text: /does not exist/
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n test_show_renders_resolved_cross_reference_as_embedded_recipe_card`
Expected: FAIL — no `article.embedded-recipe` in response

**Step 3: Create the embedded recipe partial**

```erb
<%# app/views/recipes/_embedded_recipe.html.erb %>
<%# locals: (cross_reference:) %>
<article class="embedded-recipe">
  <header>
    <h3>
      <%= link_to cross_reference.target_title, recipe_path(cross_reference.target_slug) %>
    </h3>
    <%- if cross_reference.multiplier != 1.0 -%>
    <span class="embedded-multiplier">&times; <%= cross_reference.multiplier == cross_reference.multiplier.to_i ? cross_reference.multiplier.to_i : cross_reference.multiplier %></span>
    <%- end -%>
    <%- if cross_reference.prep_note -%>
    <p class="embedded-prep-note"><%= cross_reference.prep_note %></p>
    <%- end -%>
  </header>

  <%- cross_reference.target_recipe.steps.each do |step| -%>
    <%= render 'recipes/step', step: step, embedded: true, heading_level: 3 %>
  <%- end -%>
</article>
```

**Step 4: Create the broken reference partial**

```erb
<%# app/views/recipes/_broken_reference.html.erb %>
<%# locals: (cross_reference:) %>
<div class="embedded-recipe broken-reference">
  <p>This step references "<%= cross_reference.target_title %>", but no recipe with that name exists.</p>
</div>
```

**Step 5: Rewrite the step partial**

Replace `app/views/recipes/_step.html.erb` to handle the three cases: normal step, cross-reference step (resolved/pending), and embedded cross-reference step (link fallback).

```erb
<%# locals: (step:, embedded: false, heading_level: 2) %>
<section>
  <%- if step.cross_reference_step? -%>

    <%- xref = step.cross_reference_block -%>
    <%- if step.title -%>
    <%= content_tag("h#{heading_level}", step.title) %>
    <%- end -%>

    <%- if xref.resolved? -%>
      <%- if embedded -%>
        <p><%= link_to xref.target_title, recipe_path(xref.target_slug) %></p>
      <%- else -%>
        <%= render 'recipes/embedded_recipe', cross_reference: xref %>
      <%- end -%>
    <%- else -%>
      <%= render 'recipes/broken_reference', cross_reference: xref %>
    <%- end -%>

  <%- else -%>

    <%- if step.title -%>
    <%= content_tag("h#{heading_level}", step.title) %>
    <%- end -%>
    <div>
      <%- unless step.ingredient_list_items.empty? -%>
      <div class="ingredients">
        <ul>
          <%- step.ingredient_list_items.each do |item| -%>
          <li <%= ingredient_data_attrs(item) %>>
            <b class="ingredient-name"><%= item.name %></b><% if item.quantity_display %>, <span class="quantity"><%= item.quantity_display %></span><% end %>
          <%- if item.prep_note -%>
            <small><%= item.prep_note %></small>
          <%- end -%>
          </li>
          <%- end -%>
        </ul>
      </div>
      <%- end -%>

      <%- if step.processed_instructions.present? -%>
      <div class="instructions">
        <%= step.processed_instructions.html_safe %>
      </div>
      <%- elsif step.instructions.present? -%>
      <div class="instructions">
        <%= scalable_instructions(step.instructions) %>
      </div>
      <%- end -%>
    </div>

  <%- end -%>
</section>
```

Note: The old cross-reference rendering inside the ingredient list (`item.respond_to?(:target_slug)` branch) is removed entirely. Cross-references are no longer ingredients.

**Step 6: Update `_recipe_content.html.erb` to pass locals**

```erb
<% recipe.steps.each do |step| %>
  <%= render 'recipes/step', step: step, embedded: false, heading_level: 2 %>
<% end %>
```

**Step 7: Update eager loading in RecipesController#show**

In `app/controllers/recipes_controller.rb:12-15`:

```ruby
def show
  @recipe = current_kitchen.recipes
    .includes(steps: [
      :ingredients,
      { cross_references: { target_recipe: { steps: [:ingredients, :cross_references] } } }
    ])
    .find_by!(slug: params[:slug])
  @nutrition = @recipe.nutrition_data
end
```

**Step 8: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: PASS

**Step 9: Update `html_safe_allowlist.yml`**

The step partial's `.html_safe` call may have shifted line numbers. Run `rake lint:html_safe` and update the allowlist if needed.

**Step 10: Commit**

```bash
git add app/views/recipes/_step.html.erb app/views/recipes/_embedded_recipe.html.erb app/views/recipes/_broken_reference.html.erb app/views/recipes/_recipe_content.html.erb app/controllers/recipes_controller.rb
git commit -m "feat: render cross-references as embedded recipe cards"
```

---

### Task 11: Add CSS for embedded recipe cards

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Start dev server and verify visually**

Run: `bin/dev`
Navigate to White Pizza recipe page. The embedded card should appear but without distinct styling yet.

**Step 2: Add embedded recipe CSS**

Add to `app/assets/stylesheets/style.css`:

```css
/* Embedded recipe card — "paper on paper" effect */
.embedded-recipe {
  border: 1px solid var(--border-color);
  border-radius: 0.25rem;
  background-color: var(--content-background-color);
  box-shadow:
    0 1px 3px rgba(0, 0, 0, 0.08),
    0 4px 12px rgba(0, 0, 0, 0.06);
  padding: 1.5rem;
  margin-top: 0.5rem;
}

.embedded-recipe header {
  text-align: left;
  margin-bottom: 1rem;
}

.embedded-recipe header h3 {
  font-size: 1.15rem;
  margin: 0;
}

.embedded-recipe header h3 a {
  color: inherit;
  text-decoration: none;
}

.embedded-recipe header h3 a:hover {
  text-decoration: underline;
}

.embedded-multiplier {
  font-size: 0.9rem;
  color: #666;
  margin-left: 0.5rem;
}

.embedded-prep-note {
  font-size: 0.9rem;
  color: #666;
  margin: 0.25rem 0 0;
}

/* Tighter spacing for embedded steps */
.embedded-recipe section {
  margin-top: 1.5rem;
}

.embedded-recipe section:first-of-type {
  margin-top: 0;
}

.embedded-recipe section h3 {
  font-size: 1rem;
  font-weight: 600;
}

/* Broken reference warning card */
.broken-reference {
  background-color: #fdf6f0;
  color: #666;
}

.broken-reference p {
  margin: 0;
  font-style: italic;
}

/* Mobile: keep embedded card border/shadow even when main drops it */
@media (max-width: 640px) {
  .embedded-recipe {
    padding: 1rem;
  }
}

/* Print: flatten shadow, keep border */
@media print {
  .embedded-recipe {
    box-shadow: none;
  }
}
```

**Step 3: Visually verify in browser**

Check desktop and mobile views. Verify:
- Card-on-card appearance
- Heading hierarchy
- Broken reference styling (create a test recipe with an unresolved reference)
- Cross-off interaction works inside embedded card

**Step 4: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "style: embedded recipe card and broken reference styling"
```

---

### Task 12: Add broadcaster cascade for referencing recipes

**Files:**
- Modify: `app/services/recipe_broadcaster.rb:104-123`
- Modify: `test/services/recipe_broadcaster_test.rb`

**Step 1: Write the failing test**

Add to `test/services/recipe_broadcaster_test.rb`:

```ruby
test 'broadcast_recipe_updated also broadcasts to referencing recipe pages' do
  dough = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Pizza Dough

    Category: Bread

    ## Mix.
    - Flour, 3 cups
  MD

  pizza = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # White Pizza

    Category: Bread

    ## Make dough.
    >>> @[Pizza Dough]
  MD

  streams = []
  Turbo::StreamsChannel.stub :broadcast_replace_to, ->(*args, **kwargs) { streams << args[0] } do
    RecipeBroadcaster.broadcast(kitchen: @kitchen, action: :updated, recipe_title: 'Pizza Dough', recipe: dough)
  end

  # Should broadcast to both the recipe's own stream and the parent's stream
  assert streams.any? { |s| s.is_a?(Recipe) && s.slug == 'pizza-dough' },
         'Expected broadcast to pizza-dough recipe stream'
  assert streams.any? { |s| s.is_a?(Recipe) && s.slug == 'white-pizza' },
         'Expected broadcast to white-pizza recipe stream (referencing recipe)'
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb`
Expected: FAIL — no broadcast to white-pizza stream

**Step 3: Add cascade to RecipeBroadcaster**

In `app/services/recipe_broadcaster.rb`, after `broadcast_recipe_updated`:

```ruby
SHOW_INCLUDES = {
  steps: [:ingredients, { cross_references: { target_recipe: { steps: [:ingredients, :cross_references] } } }]
}.freeze

def broadcast_recipe_updated(recipe)
  fresh = kitchen.recipes.includes(SHOW_INCLUDES).find_by(slug: recipe.slug)
  return unless fresh

  replace_recipe_content(fresh)
  broadcast_referencing_recipes(fresh)
end

def broadcast_referencing_recipes(recipe)
  recipe.referencing_recipes.includes(SHOW_INCLUDES).find_each do |parent|
    replace_recipe_content(parent)
  end
end

def replace_recipe_content(recipe)
  Turbo::StreamsChannel.broadcast_replace_to(
    recipe, 'content',
    target: 'recipe-content',
    partial: 'recipes/recipe_content',
    locals: { recipe: recipe, nutrition: recipe.nutrition_data }
  )
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/recipe_broadcaster.rb test/services/recipe_broadcaster_test.rb
git commit -m "feat: RecipeBroadcaster cascades page updates to referencing recipes"
```

---

### Task 13: Update RecipesController#destroy to re-broadcast parent pages

**Files:**
- Modify: `app/controllers/recipes_controller.rb:66-82`
- Modify: `test/controllers/recipes_controller_test.rb`

**Step 1: Write the failing test**

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'destroy broadcasts to referencing recipe pages' do
  dough = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Pizza Dough

    Category: Bread

    ## Mix.
    - Flour, 3 cups
  MD

  pizza = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # White Pizza

    Category: Bread

    ## Make dough.
    >>> @[Pizza Dough]
  MD

  streams = []
  Turbo::StreamsChannel.stub :broadcast_replace_to, ->(*args, **kwargs) { streams << [args, kwargs] } do
    log_in
    delete recipe_path('pizza-dough')
  end

  # Should include a broadcast to the parent recipe's stream
  parent_broadcasts = streams.select { |args, _| args[0].is_a?(Recipe) && args[0].slug == 'white-pizza' }
  assert parent_broadcasts.any?, 'Expected broadcast to referencing recipe page'
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n test_destroy_broadcasts_to_referencing_recipe_pages`
Expected: FAIL

**Step 3: Update the destroy action**

In `app/controllers/recipes_controller.rb`:

```ruby
def destroy
  @recipe = current_kitchen.recipes.find_by!(slug: params[:slug])
  parent_ids = @recipe.referencing_recipes.pluck(:id)

  RecipeBroadcaster.notify_recipe_deleted(@recipe, recipe_title: @recipe.title)
  @recipe.destroy!
  Category.cleanup_orphans(current_kitchen)
  plan = MealPlan.for_kitchen(current_kitchen)
  plan.with_optimistic_retry { plan.prune_checked_off }

  RecipeBroadcaster.broadcast(kitchen: current_kitchen, action: :deleted,
                              recipe_title: @recipe.title)

  broadcast_to_referencing_recipes(parent_ids) if parent_ids.any?

  render json: { redirect_url: home_path }
end

private

def broadcast_to_referencing_recipes(parent_ids)
  includes = RecipeBroadcaster::SHOW_INCLUDES
  current_kitchen.recipes.where(id: parent_ids).includes(includes).find_each do |parent|
    Turbo::StreamsChannel.broadcast_replace_to(
      parent, 'content',
      target: 'recipe-content',
      partial: 'recipes/recipe_content',
      locals: { recipe: parent, nutrition: parent.nutrition_data }
    )
  end
end
```

**Step 4: Run tests**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/controllers/recipes_controller.rb test/controllers/recipes_controller_test.rb
git commit -m "feat: destroy action re-broadcasts to referencing recipe pages"
```

---

### Task 14: Handle multiplier scaling in embedded recipe view

When a cross-reference has a multiplier (e.g., `>>> @[Pizza Dough], 2`), the embedded recipe's ingredient quantities should display multiplied. The scaling JavaScript reads `data-quantity-value` attributes.

**Files:**
- Modify: `app/views/recipes/_embedded_recipe.html.erb`
- Modify: `app/views/recipes/_step.html.erb`
- Modify: `app/helpers/recipes_helper.rb`
- Modify: `test/controllers/recipes_controller_test.rb`

**Step 1: Write the failing test**

```ruby
test 'embedded recipe with multiplier shows scaled quantities' do
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Pizza Dough

    Category: Bread

    ## Mix.
    - Flour, 500 g
  MD

  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Double Pizza

    Category: Bread

    ## Make dough.
    >>> @[Pizza Dough], 2
  MD

  get recipe_path('double-pizza')
  assert_response :success

  assert_select 'article.embedded-recipe' do
    assert_select '.quantity', text: /1000/
  end
end
```

**Step 2: Implement multiplier pass-through**

Pass the multiplier from the embedded recipe partial down to the step partial, which passes it to `ingredient_data_attrs`. The helper multiplies the base quantity value:

Add a `scale_factor:` local to the step partial. In `_embedded_recipe.html.erb`:

```erb
<% cross_reference.target_recipe.steps.each do |step| %>
  <%= render 'recipes/step', step: step, embedded: true, heading_level: 3,
             scale_factor: cross_reference.multiplier %>
<% end %>
```

In `_step.html.erb`, pass `scale_factor` through to ingredient rendering. Add a helper method:

```ruby
def ingredient_data_attrs(item, scale_factor: 1.0)
  attrs = {}
  return tag.attributes(attrs) unless item.quantity_value

  scaled_value = item.quantity_value * scale_factor
  attrs[:'data-quantity-value'] = scaled_value
  # ... rest unchanged
end
```

And update the ingredient display to show the scaled quantity.

**Step 3: Run tests**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: PASS

**Step 4: Commit**

```bash
git add app/views/recipes/_embedded_recipe.html.erb app/views/recipes/_step.html.erb app/helpers/recipes_helper.rb test/controllers/recipes_controller_test.rb
git commit -m "feat: multiplier scaling for embedded recipe ingredient quantities"
```

---

### Task 15: Namespace crossed-off state for embedded recipe steps

The `recipe-state` Stimulus controller keys crossed-off state by numeric index in the `.ingredients li, .instructions p` node list. Embedded recipe content adds nodes to this list, which would collide with the parent recipe's state indices.

**Files:**
- Modify: `app/javascript/controllers/recipe_state_controller.js`
- Verify manually in browser

**Step 1: Investigate current keying**

Read `recipe_state_controller.js` — the `crossableItemNodes` getter queries `.ingredients li, .instructions p`. When an embedded recipe is inside the DOM, these selectors pick up embedded content too.

**Step 2: Scope the selector**

The simplest fix: exclude embedded recipe content from the parent's crossable items by using `:scope > section` or adding a `:not(.embedded-recipe *)` qualifier. Alternatively, mark the embedded recipe's `<article>` with its own `data-controller="recipe-state"` so it manages its own state independently.

Recommended approach: add `data-controller="recipe-state"` to the `<article class="embedded-recipe">` element, with a `data-recipe-id` based on the cross-reference's target slug. Each recipe-state controller instance will scope its queries to its own element and key state by its own recipe ID.

Update `_embedded_recipe.html.erb`:

```erb
<article class="embedded-recipe"
         data-controller="recipe-state"
         data-recipe-state-recipe-id-value="<%= cross_reference.target_slug %>">
```

Update `recipe_state_controller.js` to scope `crossableItemNodes` query to `this.element` (which it likely already does if using Stimulus targets or `this.element.querySelectorAll`).

**Step 3: Verify manually**

- Open a recipe with an embedded recipe
- Cross off items in the parent recipe
- Cross off items in the embedded recipe
- Refresh — verify both states are preserved independently
- Verify no index collisions

**Step 4: Commit**

```bash
git add app/javascript/controllers/recipe_state_controller.js app/views/recipes/_embedded_recipe.html.erb
git commit -m "fix: namespace crossed-off state for embedded recipe steps"
```

---

### Task 16: Update `html_safe_allowlist.yml` and run full lint

**Files:**
- Modify: `config/html_safe_allowlist.yml`

**Step 1: Run lint**

Run: `rake lint`
Expected: May fail on shifted line numbers in the allowlist

**Step 2: Run html_safe audit**

Run: `rake lint:html_safe`
Fix any line number shifts in the allowlist.

**Step 3: Run full test suite**

Run: `rake test`
Expected: PASS — all tests green

**Step 4: Commit**

```bash
git add config/html_safe_allowlist.yml
git commit -m "chore: update html_safe allowlist for shifted line numbers"
```

---

### Task 17: Add architectural header comments to new files

Every new file needs a header comment per the project convention.

**Files:**
- Verify: `lib/familyrecipes/cross_reference_parser.rb` (added in Task 0)
- Verify: `app/views/recipes/_embedded_recipe.html.erb` (added in Task 10)
- Verify: `app/views/recipes/_broken_reference.html.erb` (added in Task 10)
- Modify: any files whose header comments are now stale

**Step 1: Audit and update headers**

Check that:
- `CrossReferenceParser` has a header explaining its role
- `CrossReferenceUpdater` header no longer mentions `strip_references`
- `MarkdownImporter` header mentions `>>>` syntax
- `_step.html.erb` — ERB comment explaining the three rendering branches
- `_embedded_recipe.html.erb` — ERB comment explaining the partial
- `_broken_reference.html.erb` — ERB comment explaining the partial

**Step 2: Commit**

```bash
git add -u
git commit -m "docs: update architectural header comments for inline cross-references"
```

---

### Task 18: Final verification — end-to-end manual testing

**Step 1: Reset and reseed**

Run: `rails db:reset`
Expected: Seeds complete without errors, all cross-references resolve

**Step 2: Start dev server**

Run: `bin/dev`

**Step 3: Manual test checklist**

- [ ] View White Pizza — Pizza Dough renders as embedded card
- [ ] View Pizza Dough standalone — renders normally
- [ ] Edit Pizza Dough — White Pizza's page updates via Turbo Stream
- [ ] Create a new recipe with `>>> @[Nonexistent]` — broken reference card appears
- [ ] Create the referenced recipe — broken reference becomes embedded card
- [ ] Delete Pizza Dough — White Pizza shows broken reference card
- [ ] Rename Pizza Dough — White Pizza's Markdown source updates automatically
- [ ] Cross off items in embedded recipe — state persists independently
- [ ] Scale recipe — embedded recipe quantities scale correctly
- [ ] Mobile view — embedded card retains border/shadow
- [ ] Old `- @[...]` syntax in editor — helpful error message

**Step 4: Run full test suite one final time**

Run: `rake`
Expected: PASS — lint clean, all tests green

**Step 5: Commit any fixes**

If any issues found during manual testing, fix and commit.
