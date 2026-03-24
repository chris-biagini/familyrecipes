# Standardize Front Matter — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace implicit prose yield lines with explicit `Category:`, `Makes:`, and `Serves:` front matter fields in recipe markdown, with parsing, validation, and HTML presentation.

**Architecture:** Extend `LineClassifier` with a `:front_matter` token type, replace `parse_yield_line` in `RecipeBuilder` with `parse_front_matter`, update `Recipe` to expose structured `makes`/`serves` attrs instead of `yield_line`, and update all consumers (templates, nutrition, tests).

**Tech Stack:** Ruby, ERB templates, Minitest, CSS

---

### Task 1: Add `:front_matter` token to LineClassifier

**Files:**
- Modify: `lib/familyrecipes/line_classifier.rb:13-19`
- Test: `test/line_classifier_test.rb`

**Step 1: Write failing tests**

Add these tests to `test/line_classifier_test.rb`:

```ruby
def test_classifies_category_front_matter
  type, content = LineClassifier.classify_line('Category: Bread')

  assert_equal :front_matter, type
  assert_equal ['Category', 'Bread'], content
end

def test_classifies_makes_front_matter
  type, content = LineClassifier.classify_line('Makes: 12 pancakes')

  assert_equal :front_matter, type
  assert_equal ['Makes', '12 pancakes'], content
end

def test_classifies_serves_front_matter
  type, content = LineClassifier.classify_line('Serves: 4')

  assert_equal :front_matter, type
  assert_equal ['Serves', '4'], content
end

def test_front_matter_requires_colon_space
  type, _content = LineClassifier.classify_line('Makes 30 gougères.')

  assert_equal :prose, type
end
```

**Step 2: Run tests to verify they fail**

Run: `rake test TEST=test/line_classifier_test.rb`
Expected: FAIL — `:front_matter` not recognized, returns `:prose`

**Step 3: Add front_matter pattern to LINE_PATTERNS**

In `lib/familyrecipes/line_classifier.rb`, add the `front_matter` pattern before the `blank` line (so it's checked before the `:prose` fallback but after structural tokens):

```ruby
LINE_PATTERNS = {
  title: /^# (.+)$/,
  step_header: /^## (.+)$/,
  ingredient: /^- (.+)$/,
  divider: /^---\s*$/,
  front_matter: /^(Category|Makes|Serves):\s+(.+)$/,
  blank: /^\s*$/
}.freeze
```

**Step 4: Run tests to verify they pass**

Run: `rake test TEST=test/line_classifier_test.rb`
Expected: ALL PASS

**Step 5: Commit**

```
feat: add :front_matter token type to LineClassifier (#57)
```

---

### Task 2: Replace `parse_yield_line` with `parse_front_matter` in RecipeBuilder

**Files:**
- Modify: `lib/familyrecipes/recipe_builder.rb:18-84`
- Test: `test/recipe_builder_test.rb`

**Step 1: Update existing yield_line tests and add new front matter tests**

Replace the yield_line tests (lines 208-294) in `test/recipe_builder_test.rb` with:

```ruby
# --- Front matter parsing ---

def test_parses_category
  text = <<~RECIPE
    # Cookies

    Delicious cookies.

    Category: Dessert

    ## Mix

    Mix them.
  RECIPE

  result = build_recipe(text)

  assert_equal 'Dessert', result[:front_matter][:category]
end

def test_parses_makes_with_unit_noun
  text = <<~RECIPE
    # Cookies

    Delicious cookies.

    Category: Dessert
    Makes: 32 cookies

    ## Mix

    Mix them.
  RECIPE

  result = build_recipe(text)

  assert_equal '32 cookies', result[:front_matter][:makes]
end

def test_parses_serves
  text = <<~RECIPE
    # Beans

    A hearty dish.

    Category: Mains
    Serves: 4

    ## Cook

    Cook them.
  RECIPE

  result = build_recipe(text)

  assert_equal '4', result[:front_matter][:serves]
end

def test_parses_all_front_matter_fields
  text = <<~RECIPE
    # Pizza Dough

    Basic dough.

    Category: Pizza
    Makes: 6 dough balls
    Serves: 4

    ## Mix

    Mix.
  RECIPE

  result = build_recipe(text)

  assert_equal 'Pizza', result[:front_matter][:category]
  assert_equal '6 dough balls', result[:front_matter][:makes]
  assert_equal '4', result[:front_matter][:serves]
end

def test_front_matter_without_description
  text = <<~RECIPE
    # Pizza

    Category: Pizza

    ## Make dough

    Do it.
  RECIPE

  result = build_recipe(text)

  assert_nil result[:description]
  assert_equal 'Pizza', result[:front_matter][:category]
end

def test_no_front_matter_returns_empty_hash
  text = <<~RECIPE
    # Simple Recipe

    ## Step one

    Do the thing.
  RECIPE

  result = build_recipe(text)

  assert_equal({}, result[:front_matter])
end

def test_description_not_consumed_as_front_matter
  text = <<~RECIPE
    # Cookies

    Delicious chocolate chip cookies.

    Category: Dessert

    ## Mix

    Mix them.
  RECIPE

  result = build_recipe(text)

  assert_equal 'Delicious chocolate chip cookies.', result[:description]
  assert_equal 'Dessert', result[:front_matter][:category]
end

def test_unknown_front_matter_key_raises_error
  text = <<~RECIPE
    # Cookies

    Categroy: Dessert

    ## Mix

    Mix them.
  RECIPE

  # "Categroy" doesn't match the front_matter regex, so it's parsed as description (prose).
  # This is fine — the Category-missing validation happens in Recipe, not RecipeBuilder.
  result = build_recipe(text)

  assert_equal 'Categroy: Dessert', result[:description]
end
```

**Step 2: Run tests to verify they fail**

Run: `rake test TEST=test/recipe_builder_test.rb`
Expected: FAIL — `result[:front_matter]` doesn't exist yet

**Step 3: Replace `parse_yield_line` with `parse_front_matter` in RecipeBuilder**

In `lib/familyrecipes/recipe_builder.rb`:

1. Update the `build` method to return `front_matter:` instead of `yield_line:`:

```ruby
def build
  {
    title: parse_title,
    description: parse_description,
    front_matter: parse_front_matter,
    steps: parse_steps,
    footer: parse_footer
  }
end
```

2. Replace `parse_yield_line` (lines 77-84) with:

```ruby
# Parse optional front matter fields (Category, Makes, Serves)
def parse_front_matter
  fields = {}
  skip_blanks

  while !at_end? && peek.type == :front_matter
    token = advance
    key = token.content[0].downcase.to_sym
    fields[key] = token.content[1]
  end

  fields
end
```

3. Also update `parse_description` to stop treating `Makes`/`Serves` prose lines specially — now they'll be `:front_matter` tokens, not `:prose`. Remove the `match?` guard:

```ruby
def parse_description
  skip_blanks

  return nil if at_end?
  return nil if peek.type == :step_header
  return nil if peek.type == :front_matter

  advance.content if peek.type == :prose
end
```

**Step 4: Run tests to verify they pass**

Run: `rake test TEST=test/recipe_builder_test.rb`
Expected: ALL PASS

**Step 5: Commit**

```
feat: replace parse_yield_line with parse_front_matter in RecipeBuilder (#57)
```

---

### Task 3: Update Recipe class to use structured front matter

**Files:**
- Modify: `lib/familyrecipes/recipe.rb`
- Test: `test/recipe_test.rb`

**Step 1: Write failing tests**

Add to `test/recipe_test.rb`:

```ruby
def test_parses_category_from_front_matter
  markdown = <<~MD
    # Hard-Boiled Eggs

    Protein!

    Category: Test

    ## Cook eggs.

    - Eggs

    Cook them.
  MD

  recipe = make_recipe(markdown)

  assert_equal 'Test', recipe.category
end

def test_parses_makes
  markdown = <<~MD
    # Cookies

    Category: Test
    Makes: 32 cookies

    ## Mix

    - Flour, 250 g

    Mix.
  MD

  recipe = make_recipe(markdown)

  assert_equal '32 cookies', recipe.makes
  assert_equal '32', recipe.makes_quantity
  assert_equal 'cookies', recipe.makes_unit_noun
end

def test_parses_serves
  markdown = <<~MD
    # Beans

    Category: Test
    Serves: 4

    ## Cook

    - Beans

    Cook.
  MD

  recipe = make_recipe(markdown)

  assert_equal '4', recipe.serves
end

def test_category_mismatch_raises_error
  markdown = <<~MD
    # Cookies

    Category: Dessert

    ## Mix

    - Flour

    Mix.
  MD

  error = assert_raises(StandardError) do
    make_recipe(markdown)
  end

  assert_includes error.message, 'Category'
end

def test_missing_category_raises_error
  markdown = <<~MD
    # Cookies

    ## Mix

    - Flour

    Mix.
  MD

  error = assert_raises(StandardError) do
    make_recipe(markdown)
  end

  assert_includes error.message, 'Category'
end

def test_makes_without_unit_noun_raises_error
  markdown = <<~MD
    # Cookies

    Category: Test
    Makes: 4

    ## Mix

    - Flour

    Mix.
  MD

  error = assert_raises(StandardError) do
    make_recipe(markdown)
  end

  assert_includes error.message, 'Makes'
end
```

**Step 2: Run tests to verify they fail**

Run: `rake test TEST=test/recipe_test.rb`
Expected: FAIL — `recipe.makes` not defined, no validation yet

**Step 3: Update Recipe class**

In `lib/familyrecipes/recipe.rb`:

1. Replace `yield_line` with new attrs (line 8):

```ruby
attr_reader :title, :description, :makes, :serves, :steps, :footer, :source, :id, :version_hash, :category
```

2. Add derived accessors after `relative_url`:

```ruby
def makes_quantity
  @makes&.match(/\A(\S+)/)&.captures&.first
end

def makes_unit_noun
  @makes&.match(/\A\S+\s+(.+)/)&.captures&.first
end
```

3. Update `parse_recipe` (lines 105-118) to use front matter:

```ruby
def parse_recipe
  tokens = LineClassifier.classify(@source)
  builder = RecipeBuilder.new(tokens)
  doc = builder.build

  @title = doc[:title]
  @description = doc[:description]
  @steps = build_steps(doc[:steps])
  @footer = doc[:footer]

  apply_front_matter(doc[:front_matter])
  validate_front_matter

  raise StandardError, 'Invalid recipe format: Must have at least one step.' if @steps.empty?
end
```

4. Add private methods:

```ruby
def apply_front_matter(fields)
  @makes = fields[:makes]
  @serves = fields[:serves]
  @front_matter_category = fields[:category]
end

def validate_front_matter
  raise "Missing 'Category:' in front matter for '#{@title}'." unless @front_matter_category
  return if @front_matter_category == @category

  raise "Category mismatch for '#{@title}': front matter says '#{@front_matter_category}' but file is in '#{@category}/' directory."
end
```

Note: `Makes:` without unit noun validation is not needed at the RecipeBuilder/Recipe level — the `:front_matter` regex requires at least one character after the colon, and the `makes_unit_noun` method will just return `nil` for bare numbers. We validate this where it matters: in the nutrition display. Actually, per the design, let's add validation:

```ruby
def validate_front_matter
  raise "Missing 'Category:' in front matter for '#{@title}'." unless @front_matter_category
  if @front_matter_category != @category
    raise "Category mismatch for '#{@title}': front matter says '#{@front_matter_category}' but file is in '#{@category}/' directory."
  end
  return unless @makes && !makes_unit_noun

  raise "Makes field for '#{@title}' requires a unit noun (e.g., 'Makes: 12 pancakes', not 'Makes: 12')."
end
```

5. Remove `@yield_line = nil` from initialize (line 26) and `@yield_line = doc[:yield_line]` from parse_recipe.

6. Update `to_html` (lines 37-52) to pass new vars instead of `yield_line:`:

```ruby
def to_html(erb_template_path:, nutrition: nil)
  template = File.read(erb_template_path)
  ERB.new(template, trim_mode: '-').result_with_hash(
    markdown: MARKDOWN,
    render: ->(name, locals = {}) { FamilyRecipes.render_partial(name, locals) },
    inflector: FamilyRecipes::Inflector,
    title: @title,
    description: @description,
    category: @category,
    makes: @makes,
    serves: @serves,
    steps: @steps,
    footer: @footer,
    id: @id,
    version_hash: @version_hash,
    nutrition: nutrition
  )
end
```

**Step 4: Update existing tests that reference yield_line**

The `full_recipe_markdown` helper in `test/recipe_test.rb` needs a `Category:` line. Update `full_recipe_markdown` (line 165):

```ruby
def full_recipe_markdown
  <<~MD
    # Hard-Boiled Eggs

    Protein!

    Category: Test

    ## Make ice bath.

    - Water
    - Ice

    Make ice bath in large bowl.

    ## Cook eggs.

    - Eggs

    Fill steamer pot with water and bring to a boil.

    ---

    Based on a recipe from Serious Eats.
  MD
end
```

Also update **all other test helpers** in `recipe_test.rb` that call `make_recipe` — every test recipe now needs a `Category: Test` line. Add it after the title or description, before the first `## Step`.

**Step 5: Run tests to verify they pass**

Run: `rake test TEST=test/recipe_test.rb`
Expected: ALL PASS

**Step 6: Commit**

```
feat: update Recipe to use structured front matter with validation (#57)
```

---

### Task 4: Update NutritionCalculator to use `makes`/`serves`

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb:82-83,152-155`
- Test: `test/nutrition_calculator_test.rb`

**Step 1: Update nutrition tests**

In `test/nutrition_calculator_test.rb`, replace the yield-line tests (lines 238-320) with:

```ruby
# --- Serving count from front matter ---

def test_serves_field
  recipe = make_recipe(<<~MD)
    # Test

    Category: Test
    Serves: 4

    ## Mix (combine)

    - Flour (all-purpose), 400 g

    Mix.
  MD

  result = @calculator.calculate(recipe, @alias_map, @recipe_map)

  assert_equal 4, result.serving_count
  assert_in_delta 364, result.per_serving[:calories], 1
end

def test_makes_field
  recipe = make_recipe(<<~MD)
    # Test

    Category: Test
    Makes: 30 gougeres

    ## Mix (combine)

    - Eggs, 3

    Mix.
  MD

  result = @calculator.calculate(recipe, @alias_map, @recipe_map)

  assert_equal 30, result.serving_count
  refute_nil result.per_serving
end

def test_serves_preferred_over_makes_for_serving_count
  recipe = make_recipe(<<~MD)
    # Test

    Category: Test
    Makes: 12 cookies
    Serves: 6

    ## Mix (combine)

    - Eggs, 2

    Mix.
  MD

  result = @calculator.calculate(recipe, @alias_map, @recipe_map)

  assert_equal 6, result.serving_count
end

def test_no_serves_or_makes_returns_nil_serving_count
  recipe = make_recipe(<<~MD)
    # Test

    Category: Test

    ## Mix (combine)

    - Flour (all-purpose), 500 g

    Mix.
  MD

  result = @calculator.calculate(recipe, @alias_map, @recipe_map)

  assert_nil result.serving_count
  assert_nil result.per_serving
end
```

Also check: does `make_recipe` in the nutrition test file use the same helper? Check the test_helper or the top of the nutrition test file for the helper method — it likely constructs Recipe objects that now need `Category: Test`.

**Step 2: Run tests to verify they fail**

Run: `rake test TEST=test/nutrition_calculator_test.rb`
Expected: FAIL — still calling `recipe.yield_line`

**Step 3: Update NutritionCalculator**

In `lib/familyrecipes/nutrition_calculator.rb`:

1. Replace line 82:
```ruby
# Old:
serving_count = parse_serving_count(recipe.yield_line)
# New:
serving_count = parse_serving_count(recipe)
```

2. Replace `parse_serving_count` method (lines 152-155):
```ruby
def parse_serving_count(recipe)
  if recipe.serves
    recipe.serves.to_i
  elsif recipe.makes
    recipe.makes_quantity&.to_i
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `rake test TEST=test/nutrition_calculator_test.rb`
Expected: ALL PASS

**Step 5: Commit**

```
feat: update NutritionCalculator to use structured makes/serves (#57)
```

---

### Task 5: Update recipe HTML template and CSS

**Files:**
- Modify: `templates/web/recipe-template.html.erb:20-22`
- Modify: `resources/web/style.css:288-302`
- Modify: `templates/pdf/cookbook.typ.erb:82-85`

**Step 1: Update recipe-template.html.erb**

Replace the yield-line block (lines 20-22) with:

```erb
        <p class="recipe-meta">
          <a href="index.html#<%= id.match(/[^-]+/)[0] rescue category.downcase %>"><%= category %></a><%- if makes -%>
          · Makes <%= ScalableNumberPreprocessor.process_yield_line(makes) %><%- end -%><%- if serves -%>
          · Serves <%= ScalableNumberPreprocessor.process_yield_line(serves) %><%- end -%>
        </p>
```

Wait — the category link href should go to the homepage section anchor. The homepage slugifies category names. We should use the same slugify function. The template has access to `id` but not `slugify`. Let's pass it through, or use a simpler approach: just lowercase the category.

Actually, looking at the homepage template, it uses `slugify.call(category)` to make the anchor ID. The `FamilyRecipes.slugify` method converts to lowercase and replaces spaces with hyphens. For single-word categories like "Bread", "Pizza" etc., `category.downcase` works. But for safety, let's just use `category.downcase.gsub(/\s+/, '-')` inline, or better: pass the slugify function to the recipe template too.

Simpler: add `slugify` to the `to_html` call in `recipe.rb`. But actually, the simplest correct approach: the recipe template already has access to `id`, and we can add `slugify` to the template vars. Let's just do that.

In `recipe.rb` `to_html`, add `slugify: FamilyRecipes.method(:slugify)` to the hash. Then in the template:

```erb
        <p class="recipe-meta">
          <a href="index.html#<%= slugify.call(category) %>"><%= category %></a><%- if makes -%>
          · Makes <%= ScalableNumberPreprocessor.process_yield_line(makes) %><%- end -%><%- if serves -%>
          · Serves <%= ScalableNumberPreprocessor.process_yield_line(serves) %><%- end -%>
        </p>
```

**Step 2: Update CSS**

In `resources/web/style.css`, replace `.yield-line` rules (lines 288-302) with:

```css
header .recipe-meta {
  font-style: normal;
  font-size: 1.1rem;
  margin-top: -0.5rem;
  color: #666;
}

header .recipe-meta a {
  color: inherit;
  text-decoration: none;
}

header .recipe-meta a:hover {
  text-decoration: underline;
}

.recipe-meta .scalable.scaled {
  background-color: transparent;
}
```

**Step 3: Update PDF template**

In `templates/pdf/cookbook.typ.erb`, replace yield_line block (lines 82-85) with:

```erb
<%- meta_parts = [recipe.category] -%>
<%- meta_parts << "Makes #{recipe.makes}" if recipe.makes -%>
<%- meta_parts << "Serves #{recipe.serves}" if recipe.serves -%>

#text(size: 10pt, fill: muted)[<%= typst_escape.call(meta_parts.join(' · ')) %>]
```

**Step 4: Run full test suite**

Run: `rake test`
Expected: ALL PASS (the site_generator_test will fail until recipes are migrated — that's Task 7)

**Step 5: Commit**

```
feat: update recipe template and CSS for front matter display (#57)
```

---

### Task 6: Update ScalableNumberPreprocessor tests

**Files:**
- Modify: `test/scalable_number_preprocessor_test.rb`

The `process_yield_line` method is still used (now called on `makes`/`serves` values instead of full prose yield lines). The existing tests are still valid since they test the method itself, not how it's called. However, rename the test methods to reflect the new usage and add a test for the `Serves: 4` case:

**Step 1: Rename tests**

Rename test methods from `test_yield_line_*` to `test_process_yield_line_*` — actually, the method name `process_yield_line` is a bit of a misnomer now. It's really "wrap the first number in a string." But renaming the method is a separate concern. Leave the tests as-is for now; they still test the right behavior.

No code changes needed in this task. Skip it.

---

### Task 7: Migrate all recipe files to include front matter

**Files:**
- Modify: All `.md` files under `recipes/` (except `Quick Bites.md`)

This is the bulk migration. A subagent should handle this.

**Rules for each recipe:**
1. Determine category from the directory name (e.g., `recipes/Bread/Bagels.md` → `Category: Bread`)
2. If an existing yield line exists (like `Makes 30 gougères.`), convert it:
   - `Makes about 32 cookies.` → `Makes: 32 cookies` (drop "about", drop period)
   - `Makes 30 gougères.` → `Makes: 30 gougères` (drop period)
   - `Makes enough for 2 pizzas.` → `Makes: 2 pizzas` (drop "enough for", drop period)
   - `Makes 12 pancakes.` → `Makes: 12 pancakes` (drop period)
   - `Serves 4.` → `Serves: 4` (drop period)
3. Remove the old yield line from its current position
4. Insert the front matter block after the description (or after title if no description), before the first `## Step`
5. Blank line before and after the front matter block

**Existing yield lines (5 recipes):**
- `recipes/Mains/Red Beans and Rice.md` — `Serves 4.` → `Serves: 4`
- `recipes/Pizza/White Pizza.md` — `Makes enough for 2 pizzas.` → `Makes: 2 pizzas`
- `recipes/Dessert/Pizzelle.md` — `Makes about 32 cookies.` → `Makes: 32 cookies`
- `recipes/Snacks/Gougères.md` — `Makes 30 gougères.` → `Makes: 30 gougères`
- `recipes/Breakfast/Pancakes.md` — `Makes 12 pancakes.` → `Makes: 12 pancakes`

**All other recipes (41 files):** Add only `Category: <dirname>` with no Makes/Serves.

**Step 1: Run subagent to migrate all files**

The subagent reads each recipe, applies the conversion rules, and writes back.

**Step 2: Run `bin/generate` to validate**

Run: `bin/generate`
Expected: Clean build, no errors. All recipes should parse correctly with the new front matter.

**Step 3: Spot-check a few recipes**

Read 3-4 migrated files to verify the format looks correct.

**Step 4: Commit**

```
feat: add front matter to all recipe files (#57)
```

---

### Task 8: Run full test suite and fix any remaining issues

**Step 1: Run lint**

Run: `rake lint`
Expected: PASS

**Step 2: Run full test suite**

Run: `rake test`
Expected: ALL PASS

**Step 3: Run generate**

Run: `bin/generate`
Expected: Clean build

**Step 4: Visual spot-check**

Start dev server and visually verify a recipe page shows the metadata line correctly:

Run: `bin/serve`
Check: `http://rika:8888/gougeres` — should show "Snacks · Makes 30 gougères"
Check: `http://rika:8888/red-beans-and-rice` — should show "Mains · Serves 4"
Check: `http://rika:8888/hard-boiled-eggs` — should show just "Snacks" (no makes/serves)

**Step 5: Final commit if any fixes were needed**

---

### Task 9: Close the issue

**Step 1: Verify all changes are committed**

Run: `git status`

**Step 2: Note for user**

The commit closing #57 should reference `Closes #57` in the message (or the final merge/PR can reference it).
