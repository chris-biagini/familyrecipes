# Nutrition TUI: Header Cleanup & Schema Validation — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Clean up ingredient editor header display and enforce the same validation constraints in the TUI as in the Rails model via a shared module.

**Architecture:** A new `FamilyRecipes::NutritionConstraints` module in `lib/familyrecipes/` provides validation constants and predicate methods. Both the `IngredientCatalog` Rails model and the `NutritionTui::Editors::*` TUI editors reference this shared module. Display changes in `NutritionTui::Screens::Ingredient` make all section headers pure separators with content on indented lines below.

**Tech Stack:** Ruby, Rails 8 (model validations), Minitest, ratatui_ruby (TUI framework)

**Design doc:** `docs/plans/2026-03-03-nutrition-tui-validation-design.md`

---

### Task 0: Create `FamilyRecipes::NutritionConstraints` with tests

**Files:**
- Create: `lib/familyrecipes/nutrition_constraints.rb`
- Create: `test/nutrition_constraints_test.rb`
- Modify: `lib/familyrecipes.rb` (add require_relative)

**Step 1: Write the test file**

Create `test/nutrition_constraints_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class NutritionConstraintsTest < ActiveSupport::TestCase
  NC = FamilyRecipes::NutritionConstraints

  # --- valid_basis_grams? ---

  test 'valid_basis_grams? accepts positive number' do
    valid, = NC.valid_basis_grams?(30)
    assert valid
  end

  test 'valid_basis_grams? rejects zero' do
    valid, msg = NC.valid_basis_grams?(0)
    assert_not valid
    assert_includes msg, 'greater than 0'
  end

  test 'valid_basis_grams? rejects negative' do
    valid, = NC.valid_basis_grams?(-5)
    assert_not valid
  end

  test 'valid_basis_grams? rejects nil' do
    valid, = NC.valid_basis_grams?(nil)
    assert_not valid
  end

  test 'valid_basis_grams? rejects non-numeric' do
    valid, = NC.valid_basis_grams?('abc')
    assert_not valid
  end

  # --- valid_nutrient? ---

  test 'valid_nutrient? accepts zero' do
    valid, = NC.valid_nutrient?('calories', 0)
    assert valid
  end

  test 'valid_nutrient? accepts value at default cap' do
    valid, = NC.valid_nutrient?('calories', 10_000)
    assert valid
  end

  test 'valid_nutrient? rejects value over default cap' do
    valid, msg = NC.valid_nutrient?('calories', 10_001)
    assert_not valid
    assert_includes msg, '10000'
  end

  test 'valid_nutrient? rejects negative' do
    valid, = NC.valid_nutrient?('fat', -1)
    assert_not valid
  end

  test 'valid_nutrient? allows sodium up to 50000' do
    valid, = NC.valid_nutrient?('sodium', 38_758)
    assert valid
  end

  test 'valid_nutrient? rejects sodium over 50000' do
    valid, msg = NC.valid_nutrient?('sodium', 50_001)
    assert_not valid
    assert_includes msg, '50000'
  end

  test 'valid_nutrient? rejects non-numeric' do
    valid, = NC.valid_nutrient?('calories', 'abc')
    assert_not valid
  end

  # --- density_complete? ---

  test 'density_complete? accepts all three fields' do
    valid, = NC.density_complete?({ 'grams' => 120, 'volume' => 1.0, 'unit' => 'cup' })
    assert valid
  end

  test 'density_complete? accepts empty hash' do
    valid, = NC.density_complete?({})
    assert valid
  end

  test 'density_complete? accepts nil' do
    valid, = NC.density_complete?(nil)
    assert valid
  end

  test 'density_complete? rejects missing unit' do
    valid, msg = NC.density_complete?({ 'grams' => 120, 'volume' => 1.0 })
    assert_not valid
    assert_includes msg, 'unit'
  end

  test 'density_complete? rejects missing grams' do
    valid, msg = NC.density_complete?({ 'volume' => 1.0, 'unit' => 'cup' })
    assert_not valid
    assert_includes msg, 'grams'
  end

  test 'density_complete? rejects missing volume' do
    valid, msg = NC.density_complete?({ 'grams' => 120, 'unit' => 'cup' })
    assert_not valid
    assert_includes msg, 'volume'
  end

  test 'density_complete? rejects non-positive grams' do
    valid, = NC.density_complete?({ 'grams' => 0, 'volume' => 1.0, 'unit' => 'cup' })
    assert_not valid
  end

  test 'density_complete? rejects non-positive volume' do
    valid, = NC.density_complete?({ 'grams' => 120, 'volume' => -1, 'unit' => 'cup' })
    assert_not valid
  end

  test 'density_complete? rejects blank unit' do
    valid, = NC.density_complete?({ 'grams' => 120, 'volume' => 1.0, 'unit' => '' })
    assert_not valid
  end

  # --- valid_portion_value? ---

  test 'valid_portion_value? accepts positive number' do
    valid, = NC.valid_portion_value?(113)
    assert valid
  end

  test 'valid_portion_value? rejects zero' do
    valid, msg = NC.valid_portion_value?(0)
    assert_not valid
    assert_includes msg, 'greater than 0'
  end

  test 'valid_portion_value? rejects negative' do
    valid, = NC.valid_portion_value?(-10)
    assert_not valid
  end

  # --- valid_aisle? ---

  test 'valid_aisle? accepts string within limit' do
    valid, = NC.valid_aisle?('Produce')
    assert valid
  end

  test 'valid_aisle? accepts string at max length' do
    valid, = NC.valid_aisle?('a' * 50)
    assert valid
  end

  test 'valid_aisle? rejects string over max length' do
    valid, msg = NC.valid_aisle?('a' * 51)
    assert_not valid
    assert_includes msg, '50'
  end
end
```

**Step 2: Write the module**

Create `lib/familyrecipes/nutrition_constraints.rb`:

```ruby
# frozen_string_literal: true

module FamilyRecipes
  # Shared validation constraints for ingredient catalog data. Single source of
  # truth for rules enforced by both the IngredientCatalog Rails model and the
  # bin/nutrition TUI editors. Predicate methods return [valid, error_message]
  # tuples — callers check the first element and use the second for display.
  #
  # Collaborators:
  # - IngredientCatalog (delegates custom validators here)
  # - NutritionTui::Editors::* (calls predicates on close/commit)
  module NutritionConstraints
    NUTRIENT_MAX = Hash.new(10_000).merge('sodium' => 50_000).freeze
    AISLE_MAX_LENGTH = 50

    module_function

    def valid_basis_grams?(value)
      return [false, 'Basis grams must be greater than 0'] unless value.is_a?(Numeric) && value.positive?

      [true, nil]
    end

    def valid_nutrient?(key, value)
      return [false, "#{key} must be a number"] unless value.is_a?(Numeric)

      max = NUTRIENT_MAX[key.to_s]
      return [false, "#{key} must be between 0 and #{max}"] unless value.between?(0, max)

      [true, nil]
    end

    def density_complete?(hash)
      return [true, nil] if hash.nil? || hash.empty?

      missing = %w[grams volume unit].reject { |k| hash[k].present? }
      return [false, "Density requires #{missing.join(', ')}"] if missing.any?

      validate_density_values(hash)
    end

    def valid_portion_value?(value)
      return [false, 'Portion value must be greater than 0'] unless value.is_a?(Numeric) && value.positive?

      [true, nil]
    end

    def valid_aisle?(value)
      return [true, nil] if value.nil?
      return [false, "Aisle name must be #{AISLE_MAX_LENGTH} characters or fewer"] if value.to_s.size > AISLE_MAX_LENGTH

      [true, nil]
    end

    def validate_density_values(hash)
      return [false, 'Density grams must be greater than 0'] unless hash['grams'].is_a?(Numeric) && hash['grams'].positive?
      return [false, 'Density volume must be greater than 0'] unless hash['volume'].is_a?(Numeric) && hash['volume'].positive?
      return [false, 'Density unit must not be blank'] if hash['unit'].to_s.strip.empty?

      [true, nil]
    end

    private_class_method :validate_density_values
  end
end
```

**Step 3: Wire up the require**

In `lib/familyrecipes.rb`, add after line 80 (`require_relative 'familyrecipes/nutrition_calculator'`):

```ruby
require_relative 'familyrecipes/nutrition_constraints'
```

**Step 4: Run the tests**

Run: `ruby -Itest test/nutrition_constraints_test.rb`
Expected: All tests pass.

**Step 5: Commit**

```
feat(nutrition): add shared NutritionConstraints module with tests
```

---

### Task 1: Refactor `IngredientCatalog` to use shared constraints

**Files:**
- Modify: `app/models/ingredient_catalog.rb`
- Modify: `app/models/kitchen.rb`
- Test: `test/models/ingredient_catalog_test.rb` (no changes — proves refactor is correct)

**Step 1: Update `IngredientCatalog`**

In `app/models/ingredient_catalog.rb`:

Replace the `NUTRIENT_MAX` constant (line 35):

```ruby
# old
NUTRIENT_MAX = Hash.new(10_000).merge(sodium: 50_000).freeze
# new
NUTRIENT_MAX = FamilyRecipes::NutritionConstraints::NUTRIENT_MAX
```

Note: The shared module uses string keys (`'sodium'`); the model currently uses symbol keys (`:sodium`). The model's `nutrient_values_in_range` passes `col` (a symbol) to `NUTRIENT_MAX[col]`. Since the shared `NUTRIENT_MAX` has a default of 10,000 via `Hash.new(10_000)`, symbol lookups that miss the `'sodium'` string key will still get 10,000 — which is correct for all non-sodium nutrients. But for sodium, the symbol `:sodium` won't match `'sodium'`. Fix: use `NUTRIENT_MAX[col.to_s]` in `nutrient_values_in_range`, or change the shared constant to accept both. Simplest: update `nutrient_values_in_range` to use `.to_s`.

Replace `nutrient_values_in_range` (lines 155-163):

```ruby
def nutrient_values_in_range
  NUTRIENT_COLUMNS.each do |col|
    value = public_send(col)
    next unless value

    valid, msg = FamilyRecipes::NutritionConstraints.valid_nutrient?(col, value)
    errors.add(col, msg) unless valid
  end
end
```

Replace `density_completeness` (lines 165-171):

```ruby
def density_completeness
  present = DENSITY_FIELDS.select { |f| public_send(f).present? }
  return if present.empty? || present.size == DENSITY_FIELDS.size

  missing = DENSITY_FIELDS - present
  missing.each { |f| errors.add(f, 'is required when other density fields are set') }
end
```

Note: `density_completeness` operates on separate columns (`density_grams`, `density_volume`, `density_unit`) whereas `NutritionConstraints.density_complete?` works on a hash. The Rails model should keep its column-based check because the data shape differs. The **constants** are shared; the model's per-column validation stays as-is. Only `nutrient_values_in_range` and `portion_values_positive` should delegate.

Replace `portion_values_positive` (lines 173-179):

```ruby
def portion_values_positive
  return if portions.blank?

  portions.each do |name, value|
    valid, = FamilyRecipes::NutritionConstraints.valid_portion_value?(value.to_f)
    errors.add(:portions, "value for '#{name}' must be greater than 0") unless valid
  end
end
```

Replace the aisle validation on line 39:

```ruby
# old
validates :aisle, length: { maximum: Kitchen::MAX_AISLE_NAME_LENGTH }, allow_nil: true
# new
validates :aisle, length: { maximum: FamilyRecipes::NutritionConstraints::AISLE_MAX_LENGTH }, allow_nil: true
```

Remove `NUTRIENT_MAX` constant line entirely (the model now references the shared one only in `nutrient_values_in_range`).

**Step 2: Update `Kitchen`**

In `app/models/kitchen.rb`, change line 18:

```ruby
# old
MAX_AISLE_NAME_LENGTH = 50
# new
MAX_AISLE_NAME_LENGTH = FamilyRecipes::NutritionConstraints::AISLE_MAX_LENGTH
```

This keeps existing references (`Kitchen::MAX_AISLE_NAME_LENGTH` in `GroceriesController`) working without modification.

**Step 3: Run the full test suite**

Run: `rake test`
Expected: All existing tests pass with zero changes to test files.

**Step 4: Commit**

```
refactor(catalog): delegate validation to shared NutritionConstraints
```

---

### Task 2: Display changes — clean up section headers

**Files:**
- Modify: `lib/nutrition_tui/screens/ingredient.rb`

**Step 1: Remove suffix support from `section_header`**

Replace the `section_header` method (lines 475-486) with:

```ruby
def section_header(name, key, width)
  prefix_len = name.size + key.size + 5
  fill_len = [width - prefix_len, 4].max
  styled_line(
    span(name, modifiers: [:bold]),
    span(" [#{key}]", fg: :cyan),
    span(" #{'─' * fill_len}", fg: :dark_gray)
  )
end
```

Remove `styled_suffix` method (lines 488-490) — no longer needed.

**Step 2: Update `empty_section_header` to put em dash on indented line**

Replace `empty_section_header` (lines 492-494) with:

```ruby
def empty_section_header(name, key, width)
  [section_header(name, key, width),
   Text::Line.from_string("    \u2014")]
end
```

**Step 3: Update `nutrients_section_lines` to move basis to indented line**

Replace `nutrients_section_lines` (lines 167-173) with:

```ruby
def nutrients_section_lines(width)
  nutrients = @entry['nutrients']
  return empty_section_header('Nutrients', 'n', width) unless nutrients.is_a?(Hash)

  [section_header('Nutrients', 'n', width),
   Text::Line.from_string("    Per #{basis_grams}g")] +
    Data::NUTRIENTS.map { |n| format_nutrient_line(nutrients, n) }
end
```

**Step 4: Update `density_section_lines` — remove suffix call**

This section already puts content on indented lines, but verify `section_header` call doesn't pass extra args. Current line 181: `section_header('Density', 'd', width)` — already correct, no suffix. No change needed.

Verify same for `portions_section_lines`, `aisle_section_lines`, `aliases_section_lines`, `sources_section_lines` — all call `section_header(name, key, width)` without suffix. No changes needed.

**Step 5: Visually test**

Run: `bin/nutrition`
Navigate to an ingredient with nutrients and one without. Verify:
- Nutrients header shows `Nutrients [n] ────────`, with `Per 30g` on the next line
- Empty sections show `SectionName [key] ────────` with `—` on the next line
- No trailing dashes or em dashes on header lines

**Step 6: Commit**

```
fix(nutrition-tui): clean up section headers — content below, not inline
```

---

### Task 3: Density editor validation

**Files:**
- Modify: `lib/nutrition_tui/editors/density_editor.rb`

**Step 1: Add validation on close**

Replace `handle_selecting` (lines 52-67) to validate on Esc:

```ruby
def handle_selecting(event)
  case event
  in { type: :key, code: 'esc' }
    validate_and_close
  in { type: :key, code: 'up' | 'k' }
    @selected = (@selected - 1).clamp(0, ITEM_COUNT - 1)
    nil
  in { type: :key, code: 'down' | 'j' }
    @selected = (@selected + 1).clamp(0, ITEM_COUNT - 1)
    nil
  in { type: :key, code: 'enter' }
    activate_selected
  else
    nil
  end
end
```

Add the validation method and error state:

In `initialize` (line 29-33), add `@error = nil`:

```ruby
def initialize(entry:)
  @entry = entry
  @selected = 0
  @text_input = nil
  @error = nil
end
```

Add validation method after `remove_density`:

```ruby
def validate_and_close
  valid, msg = FamilyRecipes::NutritionConstraints.density_complete?(@entry['density'])
  if valid
    @error = nil
    { done: true, entry: @entry }
  else
    @error = msg
    nil
  end
end
```

**Step 2: Add error display to render**

Replace `render` (lines 39-48):

```ruby
def render(frame, area)
  list = Widgets::List.new(
    items: display_lines,
    selected_index: @text_input ? nil : @selected,
    highlight_style: Style::Style.new(fg: :cyan, modifiers: [:bold]),
    block: Widgets::Block.new(title: 'Edit Density', borders: [:all], border_type: :rounded)
  )
  frame.render_widget(list, area)
  render_text_input(frame, area) if @text_input
  render_error(frame, area) if @error
end
```

Add error rendering helper and dismiss logic:

```ruby
def render_error(frame, area)
  error_area = Layout::Rect.new(
    x: area.x + 1,
    y: area.bottom - 2,
    width: area.width - 2,
    height: 1
  )
  text = RatatuiRuby::Text::Line.new(
    spans: [RatatuiRuby::Text::Span.styled(@error, Style::Style.new(fg: :red))]
  )
  frame.render_widget(Widgets::Paragraph.new(text: text), error_area)
end
```

In `handle_selecting`, dismiss error on any non-Esc keypress by adding at the top of the method:

```ruby
def handle_selecting(event)
  if @error
    @error = nil
    return nil
  end
  # ... rest of case statement
end
```

**Step 3: Visually test**

Run: `bin/nutrition "Almonds"`
Press `d` to open density editor. Set grams to 120, leave volume and unit empty. Press Esc.
Expected: Error message appears in red. Press any key to dismiss. Fill in all fields. Press Esc.
Expected: Editor closes.

**Step 4: Commit**

```
feat(nutrition-tui): validate density completeness on editor close
```

---

### Task 4: Nutrients editor validation

**Files:**
- Modify: `lib/nutrition_tui/editors/nutrients_editor.rb`

**Step 1: Add validation on close**

In `initialize`, add `@error = nil`:

```ruby
def initialize(entry:)
  @entry = entry
  @entry['nutrients'] ||= {}
  @selected = 0
  @text_input = nil
  @error = nil
end
```

Replace the Esc handler in `handle_selecting` (lines 55-69):

```ruby
def handle_selecting(event)
  if @error
    @error = nil
    return nil
  end

  case event
  in { type: :key, code: 'esc' }
    validate_and_close
  in { type: :key, code: 'up' | 'k' }
    @selected = (@selected - 1).clamp(0, item_count - 1)
    nil
  in { type: :key, code: 'down' | 'j' }
    @selected = (@selected + 1).clamp(0, item_count - 1)
    nil
  in { type: :key, code: 'enter' }
    open_text_input
  else
    nil
  end
end
```

Add validation method:

```ruby
def validate_and_close
  error = find_validation_error
  if error
    @error = error
    nil
  else
    { done: true, entry: @entry }
  end
end

def find_validation_error
  nutrients = @entry['nutrients']
  has_values = Data::NUTRIENTS.any? { |n| nutrients[n[:key]] }

  if has_values && nutrients['basis_grams']
    valid, msg = FamilyRecipes::NutritionConstraints.valid_basis_grams?(nutrients['basis_grams'])
    return msg unless valid
  elsif has_values
    return 'Basis grams is required when nutrients are present'
  end

  find_nutrient_range_error(nutrients)
end

def find_nutrient_range_error(nutrients)
  Data::NUTRIENTS.each do |n|
    value = nutrients[n[:key]]
    next unless value

    valid, msg = FamilyRecipes::NutritionConstraints.valid_nutrient?(n[:key], value)
    return msg unless valid
  end
  nil
end
```

**Step 2: Add error rendering to `render`**

Replace `render` (lines 34-43):

```ruby
def render(frame, area)
  list = Widgets::List.new(
    items: display_lines,
    selected_index: @text_input ? nil : @selected,
    highlight_style: Style::Style.new(fg: :cyan, modifiers: [:bold]),
    block: Widgets::Block.new(title: 'Edit Nutrients', borders: [:all], border_type: :rounded)
  )
  frame.render_widget(list, area)
  render_text_input(frame, area) if @text_input
  render_error(frame, area) if @error
end

def render_error(frame, area)
  error_area = Layout::Rect.new(
    x: area.x + 1,
    y: area.bottom - 2,
    width: area.width - 2,
    height: 1
  )
  text = RatatuiRuby::Text::Line.new(
    spans: [RatatuiRuby::Text::Span.styled(@error, Style::Style.new(fg: :red))]
  )
  frame.render_widget(Widgets::Paragraph.new(text: text), error_area)
end
```

**Step 3: Visually test**

Run: `bin/nutrition "Almonds"`
Press `n`. Delete basis_grams (select, clear, enter). Press Esc.
Expected: Error about basis_grams required. Dismiss, set basis_grams to 30. Set calories to -5. Press Esc.
Expected: Error about calories range. Fix, press Esc. Editor closes.

**Step 4: Commit**

```
feat(nutrition-tui): validate nutrients on editor close
```

---

### Task 5: Portions editor validation

**Files:**
- Modify: `lib/nutrition_tui/editors/portions_editor.rb`

**Step 1: Add validation to `apply_grams`**

Replace `apply_grams` (lines 123-127):

```ruby
def apply_grams(value)
  parsed = Float(value, exception: false)
  return reset_to_list unless parsed

  valid, msg = FamilyRecipes::NutritionConstraints.valid_portion_value?(parsed)
  unless valid
    @text_input = TextInput.new(label: "#{@pending_name} (grams)")
    @error = msg
    return nil
  end

  @entry['portions'][@pending_name] = parsed
  reset_to_list
end
```

In `initialize`, add `@error = nil`. In `reset_to_list`, add `@error = nil`.

**Step 2: Add error rendering**

Update `render_text_input` (lines 157-159) to show error:

```ruby
def render_text_input(frame, area)
  frame.render_widget(Widgets::Clear.new, area)
  @text_input.render(frame, area)
  render_error(frame, area) if @error
end

def render_error(frame, area)
  error_area = Layout::Rect.new(
    x: area.x + 1,
    y: area.bottom - 2,
    width: area.width - 2,
    height: 1
  )
  text = RatatuiRuby::Text::Line.new(
    spans: [RatatuiRuby::Text::Span.styled(@error, Style::Style.new(fg: :red))]
  )
  frame.render_widget(Widgets::Paragraph.new(text: text), error_area)
end
```

Clear error when text input starts (in `handle_text_input`, when a new event comes in):

```ruby
def handle_text_input(event)
  @error = nil
  result = @text_input.handle_event(event)
  return nil unless result&.dig(:done)

  if result[:cancelled]
    reset_to_list
  else
    advance_input(result[:value])
  end
end
```

**Step 3: Visually test**

Run: `bin/nutrition "American cheese"`
Press `p`. Press `a` to add. Name: `test`. Grams: `-5`. Enter.
Expected: Error "Portion value must be greater than 0". Type `28`. Enter.
Expected: Portion added, back to list.

**Step 4: Commit**

```
feat(nutrition-tui): validate portion values are positive
```

---

### Task 6: Aisle editor validation

**Files:**
- Modify: `lib/nutrition_tui/editors/aisle_editor.rb`

**Step 1: Add validation to the "Other..." text input path**

Replace `handle_text_input` (lines 72-82):

```ruby
def handle_text_input(event)
  result = @text_input.handle_event(event)
  return nil unless result&.dig(:done)

  if result[:cancelled]
    @text_input = nil
    @error = nil
    nil
  else
    validate_and_return(result[:value].strip)
  end
end

def validate_and_return(value)
  valid, msg = FamilyRecipes::NutritionConstraints.valid_aisle?(value)
  if valid
    { done: true, value: value }
  else
    @error = msg
    nil
  end
end
```

In `initialize`, add `@error = nil`.

**Step 2: Add error rendering**

Update `render` to show error when in text input mode:

```ruby
def render(frame, area)
  if @text_input
    frame.render_widget(Widgets::Clear.new, area)
    @text_input.render(frame, area)
    render_error(frame, area) if @error
  else
    render_list(frame, area)
  end
end

def render_error(frame, area)
  error_area = Layout::Rect.new(
    x: area.x + 1,
    y: area.bottom - 2,
    width: area.width - 2,
    height: 1
  )
  text = RatatuiRuby::Text::Line.new(
    spans: [RatatuiRuby::Text::Span.styled(@error, Style::Style.new(fg: :red))]
  )
  frame.render_widget(Widgets::Paragraph.new(text: text), error_area)
end
```

**Step 3: Visually test**

Run: `bin/nutrition "Almonds"`
Press `a`. Select "Other...". Type a 51-character string. Enter.
Expected: Error about max length. Shorten it. Enter. Editor closes.

**Step 4: Commit**

```
feat(nutrition-tui): validate aisle name length
```

---

### Task 7: Update architectural comments and CLAUDE.md

**Files:**
- Modify: `lib/familyrecipes/nutrition_constraints.rb` (header comment already written in Task 0)
- Modify: `lib/nutrition_tui/editors/density_editor.rb` (update header comment)
- Modify: `lib/nutrition_tui/editors/nutrients_editor.rb` (update header comment)
- Modify: `lib/nutrition_tui/editors/portions_editor.rb` (update header comment)
- Modify: `lib/nutrition_tui/editors/aisle_editor.rb` (update header comment)
- Modify: `app/models/ingredient_catalog.rb` (update header comment)
- Modify: `CLAUDE.md` (mention NutritionConstraints)

**Step 1: Update editor header comments**

Each editor that now validates should mention `NutritionConstraints` in its collaborators list. For example, `DensityEditor`:

```ruby
# Collaborators:
# - NutritionTui::Editors::TextInput (inline value editing)
# - NutritionTui::Screens::Ingredient (creates and processes results)
# - FamilyRecipes::NutritionConstraints (density completeness validation)
```

Similarly for `NutrientsEditor` (basis_grams + nutrient range), `PortionsEditor` (positive values), `AisleEditor` (length limit).

**Step 2: Update `IngredientCatalog` header comment**

Add `FamilyRecipes::NutritionConstraints` to the collaborators list in the header comment.

**Step 3: Update CLAUDE.md**

In the **Nutrition pipeline** section, add a sentence about `NutritionConstraints`:

> `FamilyRecipes::NutritionConstraints` is the single source of truth for validation rules (nutrient ranges, density completeness, portion positivity, aisle length) — used by both `IngredientCatalog` and the TUI editors.

**Step 4: Run lint**

Run: `bundle exec rubocop`
Expected: No new offenses.

**Step 5: Run full test suite**

Run: `rake test`
Expected: All tests pass.

**Step 6: Commit**

```
docs: update architectural comments and CLAUDE.md for NutritionConstraints
```
