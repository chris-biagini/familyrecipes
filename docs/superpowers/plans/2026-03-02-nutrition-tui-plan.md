# Nutrition TUI Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the REPL-style `bin/nutrition` with a panel-based TUI using RatatuiRuby, featuring a dashboard overview, ingredient detail screens, and a two-phase USDA import pipeline.

**Architecture:** Standalone TUI module at `lib/nutrition_tui/` loaded only by `bin/nutrition`. Data layer extracted from the current script. RatatuiRuby handles terminal lifecycle, layout, and input. Existing `FamilyRecipes` domain classes and `UsdaClient` are reused unchanged.

**Tech Stack:** RatatuiRuby 1.4.x (panel layouts, widgets, keyboard events), existing TTY::Spinner (USDA API calls), FamilyRecipes domain library.

**Design doc:** `docs/plans/2026-03-02-nutrition-tui-design.md`

---

## Milestone 1: Foundation

### Task 1: Add ratatui_ruby gem and verify installation

**Files:**
- Modify: `Gemfile:21-31`

**Step 1: Add gem to development group**

Add `ratatui_ruby` to the `:development` group in `Gemfile`, alongside the existing TTY gems:

```ruby
group :development do
  gem 'rubocop', require: false
  gem 'rubocop-minitest', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false

  gem 'pastel'
  gem 'ratatui_ruby'
  gem 'tty-prompt'
  gem 'tty-spinner'
  gem 'tty-table'
end
```

**Step 2: Install**

Run: `bundle install`
Expected: Installs precompiled native extension for linux x86_64 (~23MB).

**Step 3: Verify**

Run: `ruby -e "require 'bundler/setup'; require 'ratatui_ruby'; puts RatatuiRuby::VERSION"`
Expected: Prints version number (1.4.x).

**Step 4: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "chore: add ratatui_ruby gem for nutrition TUI"
```

---

### Task 2: Extract data layer from bin/nutrition

Extract all data I/O, lookup, and context-building logic from `bin/nutrition` into `lib/nutrition_tui/data.rb`. This is pure extraction — no behavior changes, just moving functions into a module so the new TUI and the old script can share them.

**Files:**
- Create: `lib/nutrition_tui/data.rb`
- Create: `lib/nutrition_tui.rb` (module root)
- Modify: `bin/nutrition` (replace extracted functions with `require` + module calls)
- Test: `test/nutrition_tui/data_test.rb`

**Step 1: Write tests for the data layer**

Test the key public methods that will be extracted. Use `Minitest::Test` (not `ActiveSupport::TestCase` — this code is Rails-independent). The extracted module should be `NutritionTui::Data`.

Key methods to test:
- `load_nutrition_data` — loads YAML, returns hash
- `save_nutrition_data` — sorts, rounds, writes YAML
- `build_lookup` — builds variant-aware name lookup (case-insensitive, aliases, inflector variants)
- `resolve_to_canonical` — resolves an ingredient name to its canonical form
- `find_needed_units` — given an ingredient name and recipe context, returns list of units used
- `find_missing_ingredients` — returns missing + unresolvable ingredients
- `classify_usda_modifiers` — **new method** that classifies raw USDA modifiers into density candidates, portion candidates, and filtered-out entries

For `classify_usda_modifiers`, test these classifications:

```ruby
def test_classify_simple_volume_as_density_candidate
  modifiers = [{ modifier: 'cup', grams: 160.0, amount: 1.0 }]
  result = NutritionTui::Data.classify_usda_modifiers(modifiers)
  assert_includes result[:density_candidates], { modifier: 'cup', grams: 160.0, amount: 1.0, each: 160.0 }
end

def test_classify_volume_with_prep_as_density_candidate
  modifiers = [{ modifier: 'cup, chopped', grams: 160.0, amount: 1.0 }]
  result = NutritionTui::Data.classify_usda_modifiers(modifiers)
  assert_includes result[:density_candidates], { modifier: 'cup, chopped', grams: 160.0, amount: 1.0, each: 160.0 }
end

def test_classify_count_unit_as_portion_candidate
  modifiers = [{ modifier: 'clove', grams: 3.0, amount: 1.0 }]
  result = NutritionTui::Data.classify_usda_modifiers(modifiers)
  assert_includes result[:portion_candidates], { modifier: 'clove', grams: 3.0, amount: 1.0, each: 3.0 }
end

def test_filter_out_weight_units
  modifiers = [{ modifier: 'oz', grams: 28.35, amount: 1.0 }]
  result = NutritionTui::Data.classify_usda_modifiers(modifiers)
  assert_includes result[:filtered], { modifier: 'oz', grams: 28.35, amount: 1.0, each: 28.35, reason: 'weight unit' }
end

def test_filter_out_nlea_serving
  modifiers = [{ modifier: 'NLEA serving', grams: 148.0, amount: 1.0 }]
  result = NutritionTui::Data.classify_usda_modifiers(modifiers)
  assert_includes result[:filtered], { modifier: 'NLEA serving', grams: 148.0, amount: 1.0, each: 148.0, reason: 'regulatory' }
end

def test_amount_normalization
  # Ground beef: oz with amount=4 means 4oz = 113g, so each = 28.25g
  modifiers = [{ modifier: 'oz', grams: 113.0, amount: 4.0 }]
  result = NutritionTui::Data.classify_usda_modifiers(modifiers)
  assert_equal 28.25, result[:filtered].first[:each]
end

def test_strip_parentheticals_for_display
  modifiers = [{ modifier: 'medium (2-1/2" dia)', grams: 110.0, amount: 1.0 }]
  result = NutritionTui::Data.classify_usda_modifiers(modifiers)
  candidate = result[:portion_candidates].first
  assert_equal 'medium', candidate[:display_name]
  assert_equal 'medium (2-1/2" dia)', candidate[:modifier]
end

def test_auto_pick_density
  modifiers = [
    { modifier: 'cup, chopped', grams: 160.0, amount: 1.0 },
    { modifier: 'cup, sliced', grams: 115.0, amount: 1.0 },
    { modifier: 'tbsp chopped', grams: 10.0, amount: 1.0 }
  ]
  result = NutritionTui::Data.classify_usda_modifiers(modifiers)
  best = NutritionTui::Data.pick_best_density(result[:density_candidates])
  assert_equal 160.0, best[:grams]
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/nutrition_tui/data_test.rb`
Expected: NameError — `NutritionTui` not defined.

**Step 3: Create lib/nutrition_tui.rb module root**

```ruby
# frozen_string_literal: true

# Root module for the standalone nutrition TUI. Not loaded by Rails — used only
# by bin/nutrition. Houses the data layer (YAML I/O, lookup resolution, USDA
# modifier classification) and the ratatui-based terminal interface.
module NutritionTui
end

require_relative 'nutrition_tui/data'
```

**Step 4: Create lib/nutrition_tui/data.rb**

Extract from `bin/nutrition` into `NutritionTui::Data`:

Extracted methods (keep same logic):
- `load_nutrition_data`
- `save_nutrition_data(data)`
- `round_entry_values(entry)`, `round_density(density)` (private)
- `build_lookup(nutrition_data)`
- `resolve_to_canonical(name, lookup)`
- `load_context`
- `find_needed_units(name, ctx)`
- `find_missing_ingredients(nutrition_data, ctx)`
- `build_ingredients_to_recipes(ctx)` (private)
- `find_unresolvable_units(nutrition_data, ctx, lookup)` (private)
- `resolve_calc_entry(name, lookup, calculator)` (private)
- `collect_bad_units(amounts, calc_entry, calculator)` (private)
- `count_resolvable(nutrition_data, ctx)`

New methods:
- `classify_usda_modifiers(modifiers)` — classifies USDA portion data
- `pick_best_density(density_candidates)` — picks largest volume-based entry
- `strip_parenthetical(modifier)` — strips `(...)` from modifier strings
- `volume_modifier?(modifier)` — checks if modifier starts with a volume unit
- `weight_modifier?(modifier)` — checks if modifier is oz/lb/etc.
- `regulatory_modifier?(modifier)` — checks for NLEA, serving, packet patterns

The constants `NUTRITION_PATH`, `RECIPES_DIR`, `PROJECT_ROOT`, and `NUTRIENTS` also move here.

Use `module_function` so methods are callable as both `NutritionTui::Data.load_nutrition_data` and included via `include NutritionTui::Data`.

Classification rules for `classify_usda_modifiers`:

```ruby
VOLUME_PREFIXES = /\A(cup|cups|tbsp|tablespoon|tablespoons|tsp|teaspoon|teaspoons|fl oz)\b/i.freeze
WEIGHT_UNITS = /\A(oz|ounce|ounces|lb|pound|pounds|kg|kilogram|kilograms|g|gram|grams)\b/i.freeze
REGULATORY = /\b(NLEA|serving\b|packet\b)/i.freeze

def classify_usda_modifiers(modifiers)
  modifiers.each_with_object(density_candidates: [], portion_candidates: [], filtered: []) do |mod, result|
    each_grams = (mod[:grams] / mod[:amount]).round(2)
    base = { modifier: mod[:modifier], grams: mod[:grams], amount: mod[:amount], each: each_grams }

    if weight_modifier?(mod[:modifier])
      result[:filtered] << base.merge(reason: 'weight unit')
    elsif regulatory_modifier?(mod[:modifier])
      result[:filtered] << base.merge(reason: 'regulatory')
    elsif volume_modifier?(mod[:modifier])
      result[:density_candidates] << base
    else
      display = strip_parenthetical(mod[:modifier]).strip
      result[:portion_candidates] << base.merge(display_name: display)
    end
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/nutrition_tui/data_test.rb`
Expected: All green.

**Step 6: Update bin/nutrition to require the new module**

Replace the extracted function definitions in `bin/nutrition` with:

```ruby
require_relative '../lib/nutrition_tui'
include NutritionTui::Data
```

All existing callers still work — same method names, just sourced from the module now. Remove the extracted function bodies from `bin/nutrition`. The display helpers (`display_entry`, `display_nutrients_table`, etc.), USDA flow (`search_and_pick`, `enter_usda`), edit helpers, and main dispatcher stay in `bin/nutrition` for now — they'll be replaced by TUI screens in later tasks.

**Step 7: Run bin/nutrition --coverage to verify nothing broke**

Run: `bin/nutrition --coverage`
Expected: Same output as before the extraction.

**Step 8: Commit**

```bash
git add lib/nutrition_tui.rb lib/nutrition_tui/data.rb test/nutrition_tui/data_test.rb bin/nutrition
git commit -m "refactor: extract nutrition data layer into NutritionTui::Data"
```

---

### Task 3: Create the TUI app skeleton

Build the minimal terminal lifecycle: init ratatui, draw a placeholder screen, handle `q` to quit, clean up on exit. This proves the gem works and establishes the event loop pattern.

**Files:**
- Create: `lib/nutrition_tui/app.rb`

**Step 1: Write the app skeleton**

```ruby
# frozen_string_literal: true

module NutritionTui
  # Main application class. Manages the ratatui terminal lifecycle (init, event
  # loop, cleanup) and delegates to screen objects for rendering and input
  # handling. Screens are swapped by returning navigation commands from their
  # handle_event methods.
  #
  # Collaborators: NutritionTui::Data (data layer), screen classes (rendering),
  # RatatuiRuby (terminal I/O).
  class App
    def initialize
      @running = true
      @screen = :dashboard
      @data = Data.load_nutrition_data
      @ctx = Data.load_context
    end

    def run
      RatatuiRuby.run do
        loop do
          break unless @running

          RatatuiRuby.draw { |frame| render(frame) }
          event = RatatuiRuby.poll_event(timeout: 0.05)
          handle_event(event)
        end
      end
    end

    private

    def render(frame)
      area = frame.area
      widget = Widgets::Paragraph.new(
        text: "Nutrition TUI — press q to quit",
        block: Widgets::Block.new(title: " bin/nutrition ", border_type: :rounded)
      )
      frame.render_widget(widget, area)
    end

    def handle_event(event)
      case event
      in { type: :key, code: 'q' }
        @running = false
      else
        # ignore
      end
    end
  end
end
```

Use `include RatatuiRuby` at the top of the file or reference `RatatuiRuby::Widgets` with an alias:

```ruby
Widgets = RatatuiRuby::Widgets
Layout = RatatuiRuby::Layout
Style = RatatuiRuby::Style
```

**Step 2: Update lib/nutrition_tui.rb to require app.rb**

```ruby
require_relative 'nutrition_tui/data'
require_relative 'nutrition_tui/app'
```

**Step 3: Test manually**

Run: `ruby -e "require_relative 'lib/nutrition_tui'; NutritionTui::App.new.run"`
Expected: See a bordered box with placeholder text. Press `q` to exit cleanly.

**Step 4: Commit**

```bash
git add lib/nutrition_tui/app.rb lib/nutrition_tui.rb
git commit -m "feat: nutrition TUI app skeleton with ratatui lifecycle"
```

---

## Milestone 2: Dashboard Screen

### Task 4: Build the dashboard screen with ingredient list

The main screen showing coverage summary + scrollable ingredient list with keyboard navigation.

**Files:**
- Create: `lib/nutrition_tui/screens/dashboard.rb`
- Modify: `lib/nutrition_tui/app.rb` (delegate to dashboard screen)
- Modify: `lib/nutrition_tui.rb` (require new file)

**Step 1: Write the dashboard screen**

The dashboard screen is a class with `render(frame, area)` and `handle_event(event)` methods. It owns:
- `@ingredients` — sorted list of ingredient entries with computed metadata (has_nutrients?, has_density?, portion_count, issues list)
- `@selected` — currently highlighted row index
- `@filter` — active filter string (nil when not filtering)
- `@filter_input` — whether the filter input is active
- `@scroll_offset` — for viewport management

Data preparation (computed once at init, refreshed after saves):

```ruby
def build_ingredient_list
  lookup = Data.build_lookup(@nutrition_data)
  recipes_map = Data.build_ingredients_to_recipes(@ctx)

  @nutrition_data.map do |name, entry|
    {
      name: name,
      aisle: entry['aisle'] || '',
      has_nutrients: entry['nutrients'].is_a?(Hash),
      has_density: entry['density'].is_a?(Hash),
      portion_count: (entry['portions'] || {}).size,
      issues: compute_issues(name, entry, lookup, recipes_map)
    }
  end.sort_by { |i| [-i[:issues].size, -recipes_map.fetch(i[:name], []).uniq.size, i[:name].downcase] }
end
```

Layout structure:

```ruby
def render(frame, area)
  # Vertical split: 3 rows for summary bar, rest for list, 1 row for keybinds
  chunks = RatatuiRuby::Layout::Layout.split(
    area,
    direction: :vertical,
    constraints: [
      RatatuiRuby::Layout::Constraint.length(3),   # summary bar
      RatatuiRuby::Layout::Constraint.min(5),       # ingredient list
      RatatuiRuby::Layout::Constraint.length(1)     # keybind bar
    ]
  )

  render_summary(frame, chunks[0])
  render_list(frame, chunks[1])
  render_keybinds(frame, chunks[2])
end
```

Summary bar: `Paragraph` widget showing coverage counts.

Ingredient list: `Table` widget with columns: Name, Aisle, Nutrients (checkmark/dash), Density (checkmark/dash), Portions (count), Issues (text). Use `selected_row` for highlighting and arrow key navigation.

Keybind bar: `Paragraph` with dim text: `/ filter  Enter select  n new  s search  q quit`

**Step 2: Event handling**

```ruby
def handle_event(event)
  if @filter_input
    handle_filter_input(event)
  else
    handle_normal_input(event)
  end
end

def handle_normal_input(event)
  case event
  in { type: :key, code: 'Down' } | { type: :key, code: 'j' }
    move_selection(1)
  in { type: :key, code: 'Up' } | { type: :key, code: 'k' }
    move_selection(-1)
  in { type: :key, code: 'Enter' }
    open_selected_ingredient
  in { type: :key, code: '/' }
    start_filter
  in { type: :key, code: 'q' }
    { action: :quit }
  in { type: :key, code: 'n' }
    { action: :new_ingredient }
  in { type: :key, code: 's' }
    { action: :usda_search }
  else
    nil
  end
end

def handle_filter_input(event)
  case event
  in { type: :key, code: 'Escape' }
    clear_filter
  in { type: :key, code: 'Enter' }
    @filter_input = false  # lock in filter, return to normal nav
  in { type: :key, code: 'Backspace' }
    @filter = @filter[0..-2]
    apply_filter
  in { type: :key, code: String => ch } if ch.length == 1
    @filter = (@filter || '') + ch
    apply_filter
  else
    nil
  end
end
```

`handle_event` returns a hash describing navigation intent (e.g., `{ action: :open_ingredient, name: "Onions" }`), which `App` uses to switch screens. Returns `nil` for events that don't trigger navigation.

**Step 3: Wire into App**

Update `App` to instantiate `Screens::Dashboard` and delegate `render`/`handle_event`. The app's main loop dispatches navigation actions:

```ruby
def handle_event(event)
  result = @current_screen.handle_event(event)
  case result
  in { action: :quit }
    @running = false
  in { action: :open_ingredient, name: }
    switch_to_ingredient(name)
  in nil
    # no navigation
  end
end
```

**Step 4: Test manually**

Run: `ruby -e "require_relative 'lib/nutrition_tui'; NutritionTui::App.new.run"`
Expected: See the full ingredient list with summary bar. Arrow keys scroll. `/` opens filter. `q` quits.

**Step 5: Commit**

```bash
git add lib/nutrition_tui/screens/dashboard.rb lib/nutrition_tui/app.rb lib/nutrition_tui.rb
git commit -m "feat: dashboard screen with ingredient list, filtering, and coverage summary"
```

---

## Milestone 3: Ingredient Detail Screen

### Task 5: Build the ingredient detail screen

Three-panel layout: nutrients (left), density+portions (right top), recipe units (right bottom).

**Files:**
- Create: `lib/nutrition_tui/screens/ingredient.rb`
- Modify: `lib/nutrition_tui/app.rb` (screen switching)
- Modify: `lib/nutrition_tui.rb` (require)

**Step 1: Write the ingredient detail screen**

Layout:

```ruby
def render(frame, area)
  # Top-level: vertical split for content area + keybind bar
  main_chunks = Layout::Layout.split(area, direction: :vertical, constraints: [
    Layout::Constraint.min(10),
    Layout::Constraint.length(1)
  ])

  # Content: horizontal split for left (nutrients) and right (density/portions/units)
  content_chunks = Layout::Layout.split(main_chunks[0], direction: :horizontal, constraints: [
    Layout::Constraint.percentage(45),
    Layout::Constraint.percentage(55)
  ])

  render_nutrients_panel(frame, content_chunks[0])

  # Right side: vertical split for density+portions (top) and recipe units (bottom)
  right_chunks = Layout::Layout.split(content_chunks[1], direction: :vertical, constraints: [
    Layout::Constraint.percentage(60),
    Layout::Constraint.percentage(40)
  ])

  render_density_portions_panel(frame, right_chunks[0])
  render_recipe_units_panel(frame, right_chunks[1])
  render_keybinds(frame, main_chunks[1])
end
```

Nutrients panel: `Table` widget inside a `Block` with title `" Nutrients (per Xg) "`. Rows from the NUTRIENTS constant, with indentation for sub-items. Use dim style for zero values.

Density + Portions panel: `Block` with title `" Density & Portions "`. Show density as a `Paragraph` line, portions as a small `Table`.

Recipe Units panel: `Block` with title `" Recipe Units "`. For each unit used in recipes, show: unit name, status (checkmark/X), resolution method (`via density`, `via ~unitless`, `weight`, `no portion`). Uses `Data.find_needed_units` and `NutritionCalculator.resolvable?` to compute this — same logic as the current `display_unit_coverage` but with better labels.

**Step 2: Event handling**

```ruby
def handle_event(event)
  case event
  in { type: :key, code: 'Escape' }
    { action: :back }
  in { type: :key, code: 'e' }
    { action: :edit_menu }
  in { type: :key, code: 'u' }
    { action: :usda_import, name: @name }
  in { type: :key, code: 'a' }
    { action: :edit_aisle, name: @name }
  in { type: :key, code: 'l' }
    { action: :edit_aliases, name: @name }
  in { type: :key, code: 'r' }
    { action: :edit_sources, name: @name }
  in { type: :key, code: 'w' } | { type: :key, code: 's', modifiers: ['control'] }
    save_entry
  else
    nil
  end
end
```

Keybind bar: `e edit  u USDA import  a aisle  l aliases  r sources  w save  Esc back`

Show a `[modified]` indicator in the title when `@dirty` is true.

**Step 3: Wire into App**

Add `switch_to_ingredient(name)` and `switch_to_dashboard` methods to `App`. Track the current screen object and delegate render/handle_event.

**Step 4: Test manually**

Navigate to an ingredient with data (e.g., Onions). Verify three panels display correctly. Press Escape to go back. Navigate to an ingredient without data (e.g., Celery). Verify empty state displays cleanly.

**Step 5: Commit**

```bash
git add lib/nutrition_tui/screens/ingredient.rb lib/nutrition_tui/app.rb lib/nutrition_tui.rb
git commit -m "feat: ingredient detail screen with three-panel layout"
```

---

### Task 6: Build inline editors for the detail screen

Edit sub-menu with inline editors for nutrients, density, and portions. Also aisle, aliases, and sources editors.

**Files:**
- Create: `lib/nutrition_tui/editors/edit_menu.rb`
- Create: `lib/nutrition_tui/editors/nutrients_editor.rb`
- Create: `lib/nutrition_tui/editors/density_editor.rb`
- Create: `lib/nutrition_tui/editors/portions_editor.rb`
- Create: `lib/nutrition_tui/editors/aisle_editor.rb`
- Create: `lib/nutrition_tui/editors/aliases_editor.rb`
- Create: `lib/nutrition_tui/editors/sources_editor.rb`
- Create: `lib/nutrition_tui/editors/text_input.rb` (reusable inline text field)
- Modify: `lib/nutrition_tui/screens/ingredient.rb`
- Modify: `lib/nutrition_tui.rb` (require new files)

This is a big task — implement iteratively, one editor at a time. Start with `TextInput` (the reusable component), then `EditMenu`, then each editor.

**Step 1: TextInput widget**

A reusable inline text input that captures keystrokes, shows a cursor, and returns the value on Enter or nil on Escape. This replaces all the `PROMPT.ask()` calls that currently trap users.

```ruby
module NutritionTui
  module Editors
    # Reusable inline text field for the ratatui TUI. Captures keystrokes,
    # renders with a visible cursor, returns the final value on Enter or
    # nil on Escape. Replaces TTY::Prompt.ask() calls that blocked without
    # an exit path.
    class TextInput
      attr_reader :value, :label, :finished, :cancelled

      def initialize(label:, default: '')
        @label = label
        @value = default.to_s
        @cursor = @value.length
        @finished = false
        @cancelled = false
      end

      def handle_event(event)
        case event
        in { type: :key, code: 'Enter' }
          @finished = true
        in { type: :key, code: 'Escape' }
          @cancelled = true
        in { type: :key, code: 'Backspace' }
          delete_char
        in { type: :key, code: 'Left' }
          @cursor = [@cursor - 1, 0].max
        in { type: :key, code: 'Right' }
          @cursor = [@cursor + 1, @value.length].min
        in { type: :key, code: String => ch } if ch.length == 1
          insert_char(ch)
        else
          nil
        end
      end

      def render(frame, area)
        display = "#{@label}: #{@value}"
        # Render as a paragraph with cursor indicator
        frame.render_widget(
          Widgets::Paragraph.new(text: display, style: Style::Style.new(fg: :white)),
          area
        )
      end

      private

      def insert_char(ch)
        @value = @value[0, @cursor] + ch + @value[@cursor..]
        @cursor += 1
      end

      def delete_char
        return if @cursor.zero?
        @value = @value[0, @cursor - 1] + @value[@cursor..]
        @cursor -= 1
      end
    end
  end
end
```

**Step 2: Edit menu**

When `e` is pressed on the detail screen, show a `List` widget overlay with options: Nutrients, Density, Portions, Done. Arrow keys + Enter to select, Escape to dismiss.

**Step 3: Nutrients editor**

Shows the nutrients `Table` with the selected row editable. Arrow keys to navigate rows, Enter to edit a value (opens `TextInput` for that field), Escape to go back. Edits update `@entry` in memory (not saved to YAML until explicit save).

**Step 4: Density editor**

Three options via `List`: Enter custom (opens three `TextInput` fields in sequence: grams, volume, unit), Remove density, Cancel. If entering custom, Escape at any field cancels the whole density edit.

**Step 5: Portions editor**

Shows the portions `Table` with Add/Edit/Remove/Done options at bottom. Add opens two `TextInput` fields (name, grams). Edit selects a row then opens `TextInput` for the gram value. Remove selects a row and deletes it.

**Step 6: Aisle editor**

Collect unique aisle values from the catalog. Show as a `List` with an "Other..." option that opens `TextInput`. Escape cancels.

**Step 7: Aliases editor**

Show current aliases as a `List` with Add/Remove/Done options. Add opens `TextInput`. Remove selects and deletes. Suggest aliases based on parenthetical pattern (same logic as current `suggest_aliases`).

**Step 8: Sources editor**

Show current sources as a `List`. Options: Add manual source (opens `TextInput` fields for type, name/brand, note), Remove, Done. USDA sources are auto-added during import — this is for non-USDA provenance only.

**Step 9: Test manually**

Navigate to Onions. Press `e`, select Nutrients, edit a value, Escape back. Press `e`, select Density, enter custom values, Escape. Press `a`, change aisle, verify it shows in detail. Press `w` to save, verify YAML updated. Press Escape back to dashboard, verify changes persisted.

**Step 10: Commit**

```bash
git add lib/nutrition_tui/editors/ lib/nutrition_tui/screens/ingredient.rb lib/nutrition_tui.rb
git commit -m "feat: inline editors for nutrients, density, portions, aisle, aliases, sources"
```

---

## Milestone 4: USDA Import Flow

### Task 7: Build the USDA search screen

Search USDA, display paginated results, select a food item.

**Files:**
- Create: `lib/nutrition_tui/screens/usda_search.rb`
- Modify: `lib/nutrition_tui/app.rb` (screen switching)
- Modify: `lib/nutrition_tui.rb` (require)

**Step 1: Write the USDA search screen**

This screen has two states: searching (text input active) and browsing results (list navigation).

Layout:
```
┌ USDA Search ─────────────────────────────────┐
│ Search: [onion raw          ]                │
│                                               │
│ Page 1 of 5 (47 results)                      │
│                                               │
│ > Onions, raw                                 │
│     40 cal | 0g fat | 9g carbs | 1g protein   │
│   Onions, spring or scallions                 │
│     32 cal | 0g fat | 7g carbs | 2g protein   │
│   Onions, sweet, raw                          │
│     32 cal | 0g fat | 8g carbs | 1g protein   │
│   ...                                         │
│                                               │
│ ← prev  → next  Enter select  Esc cancel      │
└───────────────────────────────────────────────┘
```

Use `TextInput` for the search field. On Enter, call `UsdaClient#search` (wrap in a brief screen update showing "Searching..." — since ratatui owns the terminal, we can't use TTY::Spinner, so just render a "Searching..." text and do the HTTP call synchronously). Display results as a `List` with two-line items (description + nutrient summary).

Page navigation: `Left`/`Right` arrows or `[`/`]` for prev/next page. `Enter` on a result fetches the full detail and returns it to the caller.

**Step 2: Event handling**

Returns `{ action: :import, detail: usda_detail }` when a food is selected, or `{ action: :cancel }` on Escape.

**Step 3: Wire into App**

USDA search can be triggered from:
- Dashboard `s` key → search, then create new ingredient with results
- Ingredient detail `u` key → search, then import into current ingredient

When import completes, `App` calls into the ingredient screen to apply the nutrient data and trigger Phase 2 (portion reference).

**Step 4: Test manually**

From dashboard, press `s`, search for "butter". Verify paginated results appear. Select an entry. Verify it creates a new ingredient with nutrients populated.

From ingredient detail for Celery, press `u`, search for "celery raw". Select. Verify nutrients populate in the left panel.

**Step 5: Commit**

```bash
git add lib/nutrition_tui/screens/usda_search.rb lib/nutrition_tui/app.rb lib/nutrition_tui.rb
git commit -m "feat: USDA search screen with paginated results"
```

---

### Task 8: Nutrient import and USDA reference panel

After selecting a USDA food item, auto-import nutrients + source, auto-pick density, and show the USDA portion reference panel.

**Files:**
- Modify: `lib/nutrition_tui/screens/ingredient.rb` (add USDA reference panel)
- Modify: `lib/nutrition_tui/data.rb` (if needed for classification)

**Step 1: Implement nutrient import**

When `App` receives `{ action: :import, detail: usda_detail }` from the search screen, it calls a method on the ingredient screen:

```ruby
def apply_usda_import(detail)
  # Phase 1: nutrients + source
  @entry['nutrients'] = detail[:nutrients]
  @entry['sources'] ||= []
  @entry['sources'] << {
    'type' => 'usda',
    'dataset' => detail[:data_type],
    'fdc_id' => detail[:fdc_id],
    'description' => detail[:description]
  }

  # Phase 2: classify portions and auto-pick density
  all_modifiers = detail[:portions][:volume] + detail[:portions][:non_volume]
  @usda_classified = Data.classify_usda_modifiers(all_modifiers)
  best_density = Data.pick_best_density(@usda_classified[:density_candidates])

  if best_density
    unit = Data.normalize_volume_unit(best_density[:modifier])
    @entry['density'] = {
      'grams' => best_density[:each].round(2),
      'volume' => 1.0,
      'unit' => unit
    }
    @auto_density_source = best_density[:modifier]
  end

  @dirty = true
  @show_usda_reference = true
end
```

**Step 2: USDA reference panel**

When `@show_usda_reference` is true, the right side of the detail screen adds a fourth panel below recipe units: the USDA Reference panel.

```
┌ USDA Reference ─────────────────────────────────┐
│ ★ cup, chopped       160.0g  (density source)    │
│   cup, sliced        115.0g                      │
│   medium             110.0g                      │
│   large              150.0g                      │
│   small               70.0g                      │
│   slice, medium       14.0g                      │
│   tbsp chopped        10.0g                      │
│   rings (×10)          6.0g each                  │
└──────────────────────────────────────────────────┘
```

Shows all density candidates and portion candidates (filtered entries are excluded). The auto-picked density row gets a `★` marker. Entries where `amount > 1` show the per-unit ("each") value with a multiplier note.

This panel is scrollable if there are many entries. It's read-only — a reference to consult while manually adding portions via `e` → Portions.

The panel can be dismissed with `Escape` or toggled with `u` (when not in search mode).

**Step 3: Test manually**

Navigate to Celery, press `u`, search and select "Celery, raw". Verify:
- Nutrients panel populates
- Density auto-picks from largest volume entry
- USDA Reference panel shows remaining portion data
- `[modified]` indicator appears
- Press `w` to save, verify YAML

**Step 4: Commit**

```bash
git add lib/nutrition_tui/screens/ingredient.rb lib/nutrition_tui/data.rb
git commit -m "feat: USDA nutrient import with auto-density and reference panel"
```

---

## Milestone 5: Data Fixes & Polish

### Task 9: Fix NutritionCalculator warning for aisle-only entries

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb:38-49`
- Modify: `test/familyrecipes/nutrition_calculator_test.rb`

**Step 1: Write a test for silent skip**

```ruby
def test_silently_skips_entries_without_nutrients
  data = { 'Celery' => { 'aisle' => 'Produce' } }
  # Should not emit any warnings
  assert_silent do
    FamilyRecipes::NutritionCalculator.new(data)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/familyrecipes/nutrition_calculator_test.rb -n test_silently_skips_entries_without_nutrients`
Expected: FAIL — the current code calls `warn`.

**Step 3: Fix the constructor**

Change the `warn` calls to silent filtering. Replace lines 38-49 of `nutrition_calculator.rb`:

```ruby
@nutrition_data = nutrition_data.select do |_name, entry|
  next false unless entry['nutrients'].is_a?(Hash)

  basis_grams = entry.dig('nutrients', 'basis_grams')
  next false unless basis_grams.is_a?(Numeric) && basis_grams.positive?

  true
end.to_h
```

Remove both `warn` calls. Entries without nutrients are simply excluded from calculation — they're surfaced as "missing nutrition" in the TUI dashboard, not logged to stderr.

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/familyrecipes/nutrition_calculator_test.rb -n test_silently_skips_entries_without_nutrients`
Expected: PASS.

**Step 5: Run full test suite**

Run: `rake test`
Expected: All green.

**Step 6: Commit**

```bash
git add lib/familyrecipes/nutrition_calculator.rb test/familyrecipes/nutrition_calculator_test.rb
git commit -m "fix: silently skip aisle-only entries in NutritionCalculator"
```

---

### Task 10: Clean up bogus "cup chopped" portions in catalog

Migrate `cup chopped: 128.0` in Carrots (and any similar entries) from portions to density.

**Files:**
- Modify: `db/seeds/resources/ingredient-catalog.yaml`

**Step 1: Audit for volume+prep portions**

Search the catalog for any portion key that starts with a volume unit followed by a prep word:

Run: `grep -E '^\s+(cup |tbsp |tsp )\w' db/seeds/resources/ingredient-catalog.yaml`

Fix each one: if the ingredient already has a density entry, just remove the bogus portion. If it doesn't, convert the portion to a density entry.

For Carrots specifically:
- Remove `cup chopped: 128.0` from portions
- Add density: `grams: 128.0, volume: 1.0, unit: cup`

**Step 2: Verify**

Run: `bin/nutrition --coverage`
Expected: Coverage report unchanged or improved (Carrots should now resolve `cup` via density instead of failing).

**Step 3: Commit**

```bash
git add db/seeds/resources/ingredient-catalog.yaml
git commit -m "fix: migrate volume+prep portions to density entries in catalog"
```

---

### Task 11: Navigation polish and CLI entry points

Wire up unsaved-changes confirmation, `bin/nutrition` CLI shortcuts, and final integration testing.

**Files:**
- Modify: `lib/nutrition_tui/app.rb`
- Modify: `lib/nutrition_tui/screens/ingredient.rb`
- Modify: `bin/nutrition`

**Step 1: Unsaved changes confirmation**

When pressing Escape on the ingredient detail screen with `@dirty == true`, show a confirmation dialog instead of navigating back immediately. Use a `List` widget with three options: Save and go back, Discard and go back, Cancel. Escape on the confirmation cancels it (stays on detail screen).

**Step 2: CLI entry points**

Update `bin/nutrition` to dispatch to the new TUI:

```ruby
if ARGV.include?('--coverage')
  # Keep as non-TUI text output
  run_coverage_mode
  exit 0
end

if ARGV.include?('--help') || ARGV.include?('-h')
  # Keep help text, update to reflect new modes
  puts 'Usage:'
  puts '  bin/nutrition                        Dashboard TUI'
  puts '  bin/nutrition "Cream cheese"         Jump to ingredient detail'
  puts '  bin/nutrition --coverage             Coverage report (no TUI)'
  exit 0
end

require_relative '../lib/nutrition_tui'

ingredient_name = ARGV.reject { |a| a.start_with?('-') }.first
NutritionTui::App.new(jump_to: ingredient_name).run
```

Update `App#initialize` to accept `jump_to:` keyword — if provided, start on the ingredient detail screen for that name instead of the dashboard.

Remove `--missing` from help text and argument handling.

**Step 3: Test CLI shortcuts**

- `bin/nutrition` → dashboard
- `bin/nutrition "Onions"` → ingredient detail for Onions
- `bin/nutrition --coverage` → text report, no TUI
- `bin/nutrition --help` → help text

**Step 4: Final integration test**

Walk through the full workflow:
1. Launch dashboard, verify ingredient list and coverage summary
2. Filter by "on", verify Onions appears
3. Navigate to Onions, verify three panels
4. Press `e`, edit a nutrient value, press Escape
5. Verify `[modified]` indicator
6. Press `w` to save
7. Press Escape to dashboard
8. Navigate to Celery, press `u`, search USDA, import
9. Verify nutrients + density + reference panel
10. Add a portion manually
11. Save, go back to dashboard
12. Verify Celery now shows nutrients checkmark

**Step 5: Commit**

```bash
git add bin/nutrition lib/nutrition_tui/
git commit -m "feat: complete nutrition TUI with CLI entry points and unsaved-changes handling"
```

---

## Summary

| Milestone | Tasks | Description |
|-----------|-------|-------------|
| 1. Foundation | 1-3 | Add gem, extract data layer, create app skeleton |
| 2. Dashboard | 4 | Scrollable ingredient list with filtering and coverage |
| 3. Detail | 5-6 | Three-panel detail view with inline editors |
| 4. USDA Import | 7-8 | Search, nutrient import, auto-density, reference panel |
| 5. Fixes & Polish | 9-11 | NutritionCalculator fix, catalog cleanup, CLI wiring |
