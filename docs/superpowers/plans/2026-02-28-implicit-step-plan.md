# Implicit Step Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Allow recipes without L2 headers (`##`) to be treated as a single implicit step, rendered without a step title.

**Architecture:** Detect the absence of `:step_header` tokens in `RecipeBuilder#parse_steps` and collect all content into one step with `tldr: nil`. Propagate nil through the domain layer, AR model, and view — each layer simply allows nil where it previously required a title.

**Tech Stack:** Ruby (parser, domain model, AR model), ERB (view partial)

---

### Task 0: RecipeBuilder — parse implicit step

**Files:**
- Modify: `lib/familyrecipes/recipe_builder.rb:77-91` (`parse_steps` method)
- Test: `test/recipe_builder_test.rb`

**Step 1: Write the failing tests**

Add three tests to `test/recipe_builder_test.rb`:

```ruby
def test_builds_implicit_step_when_no_headers
  text = <<~RECIPE
    # Nacho Cheese

    Category: Snacks

    - Cheddar, 225 g
    - Milk, 225 g

    Combine all ingredients.
  RECIPE

  result = build_recipe(text)

  assert_equal 1, result[:steps].size
  assert_nil result[:steps][0][:tldr]
  assert_equal 2, result[:steps][0][:ingredients].size
  assert_includes result[:steps][0][:instructions], 'Combine all ingredients.'
end

def test_implicit_step_with_footer
  text = <<~RECIPE
    # Simple

    Category: Test

    - Salt

    Season.

    ---

    A note.
  RECIPE

  result = build_recipe(text)

  assert_equal 1, result[:steps].size
  assert_nil result[:steps][0][:tldr]
  assert_equal 'A note.', result[:footer]
end

def test_explicit_steps_still_work
  text = <<~RECIPE
    # Recipe

    ## Step one

    Do thing.

    ## Step two

    Do other thing.
  RECIPE

  result = build_recipe(text)

  assert_equal 2, result[:steps].size
  assert_equal 'Step one', result[:steps][0][:tldr]
  assert_equal 'Step two', result[:steps][1][:tldr]
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/recipe_builder_test.rb -n /implicit/`
Expected: FAIL — implicit step tests produce 0 steps (content is skipped)

**Step 3: Implement implicit step detection in `parse_steps`**

Replace the `parse_steps` method in `lib/familyrecipes/recipe_builder.rb`:

```ruby
def parse_steps
  skip_blanks

  return [parse_implicit_step] if !at_end? && peek.type != :step_header && peek.type != :divider

  parse_explicit_steps
end
```

Add two new private methods:

```ruby
def parse_explicit_steps
  steps = []

  until at_end? || peek.type == :divider
    if peek.type == :step_header
      steps << parse_step
    else
      advance
    end
    skip_blanks
  end

  steps
end

def parse_implicit_step
  ingredients = []
  instruction_lines = []

  until at_end? || peek.type == :divider
    token = advance

    case token.type
    when :ingredient
      ingredients << IngredientParser.parse(token.content[0])
    when :prose
      instruction_lines << token.content
    end
  end

  { tldr: nil, ingredients: ingredients, instructions: instruction_lines.join("\n\n") }
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/recipe_builder_test.rb`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add lib/familyrecipes/recipe_builder.rb test/recipe_builder_test.rb
git commit -m "feat: parse implicit step when recipe has no L2 headers"
```

---

### Task 1: Domain Step — allow nil tldr

**Files:**
- Modify: `lib/familyrecipes/step.rb:8` (remove nil guard on tldr)
- Test: `test/step_test.rb`

**Step 1: Write the failing test**

Add to `test/step_test.rb`:

```ruby
def test_valid_with_nil_tldr
  step = FamilyRecipes::Step.new(
    tldr: nil,
    ingredient_list_items: [FamilyRecipes::Ingredient.new(name: 'Salt')],
    instructions: 'Season.'
  )

  assert_nil step.tldr
  assert_equal 1, step.ingredients.size
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/step_test.rb -n test_valid_with_nil_tldr`
Expected: FAIL — ArgumentError "Step must have a tldr."

**Step 3: Update the guard clause**

In `lib/familyrecipes/step.rb`, change line 8 from:

```ruby
raise ArgumentError, 'Step must have a tldr.' if tldr.nil? || tldr.strip.empty?
```

to:

```ruby
raise ArgumentError, 'Step must have a tldr.' if !tldr.nil? && tldr.strip.empty?
```

This rejects blank strings (a bug) but allows nil (an implicit step).

**Step 4: Update the existing `test_raises_on_nil_tldr` test**

This test now contradicts the new behavior. Remove `test_raises_on_nil_tldr` from `test/step_test.rb` (lines 42-49). The `test_raises_on_blank_tldr` test stays — blank strings are still invalid.

**Step 5: Run all step tests**

Run: `ruby -Itest test/step_test.rb`
Expected: ALL PASS

**Step 6: Commit**

```bash
git add lib/familyrecipes/step.rb test/step_test.rb
git commit -m "feat: allow nil tldr on domain Step for implicit steps"
```

---

### Task 2: Domain Recipe — accept implicit steps

**Files:**
- Test: `test/recipe_test.rb`

No code change needed — `FamilyRecipes::Recipe#parse_recipe` already calls `RecipeBuilder` and
`build_steps`. The validation `raise if @steps.empty?` still fires for truly empty recipes. An
implicit step recipe produces one step, so it passes. We just need a test to prove it.

**Step 1: Write the test**

Add to `test/recipe_test.rb`:

```ruby
def test_parses_implicit_step_recipe
  markdown = <<~MD
    # Nacho Cheese

    Worth the effort.

    Category: Test
    Makes: 1 cup
    Serves: 4

    - Cheddar, 225 g: Cut into small cubes.
    - Milk, 225 g

    Combine all ingredients in saucepan.
  MD

  recipe = make_recipe(markdown)

  assert_equal 'Nacho Cheese', recipe.title
  assert_equal 1, recipe.steps.size
  assert_nil recipe.steps[0].tldr
  assert_equal 2, recipe.steps[0].ingredients.size
  assert_equal 'Cheddar', recipe.steps[0].ingredients[0].name
  assert_includes recipe.steps[0].instructions, 'Combine all ingredients'
end
```

**Step 2: Run test**

Run: `ruby -Itest test/recipe_test.rb -n test_parses_implicit_step_recipe`
Expected: PASS (parser + domain changes from Tasks 0-1 make this work)

**Step 3: Commit**

```bash
git add test/recipe_test.rb
git commit -m "test: domain Recipe accepts implicit step format"
```

---

### Task 3: AR Step model — allow nil title

**Files:**
- Modify: `app/models/step.rb:9` (relax title validation)
- Modify: `test/models/step_test.rb`

**Step 1: Update the test**

In `test/models/step_test.rb`, change the `requires title` test to test that nil is allowed:

Replace the existing test (lines 20-25):

```ruby
test 'requires title' do
  step = Step.new(recipe: @recipe, position: 1)

  assert_not step.valid?
  assert_includes step.errors[:title], "can't be blank"
end
```

with:

```ruby
test 'allows nil title for implicit steps' do
  step = Step.new(recipe: @recipe, title: nil, position: 1)

  assert_predicate step, :valid?
end

test 'rejects blank title' do
  step = Step.new(recipe: @recipe, title: '', position: 1)

  assert_not step.valid?
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/step_test.rb -n test_allows_nil_title_for_implicit_steps`
Expected: FAIL — presence validation rejects nil

**Step 3: Update the validation**

In `app/models/step.rb`, change line 9 from:

```ruby
validates :title, presence: true
```

to:

```ruby
validates :title, length: { minimum: 1 }, allow_nil: true
```

This allows nil (implicit step) but rejects empty strings.

**Step 4: Run all step model tests**

Run: `ruby -Itest test/models/step_test.rb`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add app/models/step.rb test/models/step_test.rb
git commit -m "feat: AR Step allows nil title for implicit steps"
```

---

### Task 4: View — suppress h2 for implicit steps

**Files:**
- Modify: `app/views/recipes/_step.html.erb:2`

**Step 1: Update the partial**

In `app/views/recipes/_step.html.erb`, change line 2 from:

```erb
  <h2><%= step.title %></h2>
```

to:

```erb
  <%- if step.title -%>
  <h2><%= step.title %></h2>
  <%- end -%>
```

**Step 2: Verify manually (or via integration test in Task 5)**

This is a view-only change — the integration test in Task 5 will confirm correct rendering.

**Step 3: Commit**

```bash
git add app/views/recipes/_step.html.erb
git commit -m "feat: suppress h2 when step has no title"
```

---

### Task 5: Integration — import and render implicit step recipe

**Files:**
- Test: `test/services/markdown_importer_test.rb`

**Step 1: Write the integration test**

Add to `test/services/markdown_importer_test.rb`:

```ruby
test 'imports implicit step recipe without L2 headers' do
  markdown = <<~MARKDOWN
    # Nacho Cheese

    Worth the effort.

    Category: Snacks
    Makes: 1 cup
    Serves: 4

    - Cheddar, 225 g: Cut into small cubes.
    - Milk, 225 g
    - Sodium citrate, 8 g
    - Salt, 2 g
    - Pickled jalapeños, 40 g

    Combine all ingredients in saucepan.

    Warm over low heat, stirring occasionally, until cheese is mostly melted. Puree with immersion blender.

    ---

    Based on a recipe from ChefSteps.
  MARKDOWN

  recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)

  assert_equal 'Nacho Cheese', recipe.title
  assert_equal 1, recipe.steps.size

  step = recipe.steps.first

  assert_nil step.title
  assert_equal 0, step.position
  assert_equal 5, step.ingredients.count
  assert_equal 'Cheddar', step.ingredients.first.name
  assert_includes step.instructions, 'Combine all ingredients'
  assert_includes step.processed_instructions, 'Combine all ingredients'
  assert_includes recipe.footer, 'ChefSteps'
end
```

**Step 2: Run the test**

Run: `ruby -Itest test/services/markdown_importer_test.rb -n /implicit/`
Expected: PASS

**Step 3: Commit**

```bash
git add test/services/markdown_importer_test.rb
git commit -m "test: integration test for implicit step import"
```

---

### Task 6: Seed data — convert Nacho Cheese

**Files:**
- Modify: `db/seeds/recipes/Snacks/Nacho Cheese.md`

**Step 1: Update the seed file**

Replace the contents of `db/seeds/recipes/Snacks/Nacho Cheese.md` with:

```markdown
# Nacho Cheese

Worth the effort.

Category: Snacks
Makes: 1 cup
Serves: 4

- Cheddar, 225 g: Cut into small cubes.
- Milk, 225 g
- Sodium citrate, 8 g
- Salt, 2 g
- Pickled jalapeños, 40 g

Combine all ingredients in saucepan.

Warm over low heat, stirring occasionally, until cheese is mostly melted. Puree with immersion blender.

---

Based on a recipe from [ChefSteps](https://www.chefsteps.com/activities/nacho-cheese).
```

**Step 2: Verify seed imports cleanly**

Run: `rails db:seed`
Expected: No errors; Nacho Cheese recipe now has 1 step with nil title.

**Step 3: Run full test suite**

Run: `rake`
Expected: ALL PASS, 0 RuboCop offenses

**Step 4: Commit**

```bash
git add "db/seeds/recipes/Snacks/Nacho Cheese.md"
git commit -m "feat: convert Nacho Cheese to implicit step format, closes #58"
```
