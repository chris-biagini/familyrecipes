# Nutrition TUI Polish — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add visual polish (rich text, rounded borders, color scheme), disable mouse events, add basis_grams editing, and fix portions editor keybindings.

**Architecture:** Convert ingredient screen from plain-string rendering to `Text::Line`/`Text::Span` rich text for inline styling. Filter mouse events at the app layer. Extend nutrients editor with a basis_grams field. Fix empty-state keybind hints in portions editor.

**Tech Stack:** Ruby, ratatui_ruby (`Text::Span`, `Text::Line`, `Style::Style`), YAML catalog

**Design doc:** `docs/plans/2026-03-03-nutrition-tui-polish-design.md`

---

### Task 1: Disable mouse reporting

**Files:**
- Modify: `lib/nutrition_tui/app.rb`

**Step 1: Filter mouse events in dispatch**

In `app.rb`, the `dispatch` method receives events from `tui.poll_event`. Add a guard to ignore mouse events:

```ruby
def dispatch(event)
  return if event.nil? || event.respond_to?(:type) && event.type == :mouse

  result = @current_screen.handle_event(event)
  return unless result

  handle_action(result)
end
```

Alternatively, since events use pattern matching, the simplest filter is to check the hash-like event before dispatching. The current screens' `handle_event` methods use `case event in { type: :key, ... }` which already ignores non-key events via `else nil`. However, mouse events may trigger unexpected matches. The safest approach is filtering in `dispatch`.

Actually — looking at the current code, `handle_event` in each screen already only matches `{ type: :key, ... }` patterns and falls through to `else nil` for anything else. Mouse events would be harmless. But the user explicitly wants mouse reporting disabled — the terminal shouldn't even be sending mouse escape sequences. Since ratatui_ruby doesn't expose a disable flag, we need to send the disable escape sequence manually after terminal init.

In `app.rb`'s `run` method, after `RatatuiRuby.run` yields, write the disable-mouse escape sequence to stdout:

```ruby
def run
  RatatuiRuby.run do |tui|
    disable_mouse_reporting
    while @running
      tui.draw { |frame| @current_screen.render(frame) }
      dispatch(tui.poll_event(timeout: 0.05))
    end
  end
end

def disable_mouse_reporting
  $stdout.write("\e[?1000l\e[?1002l\e[?1003l\e[?1006l")
  $stdout.flush
end
```

These escape sequences disable the four mouse tracking modes: X10 (`1000`), button-event (`1002`), any-event (`1003`), and SGR extended (`1006`).

**Step 2: Verify manually**

Run: `bin/nutrition` — mouse clicks and scrolling should produce no events or visual artifacts. The terminal cursor should not change to crosshair on hover.

**Step 3: Commit**

```bash
git add lib/nutrition_tui/app.rb
git commit -m "fix: disable mouse reporting in nutrition TUI"
```

---

### Task 2: Add basis_grams to nutrients editor

**Files:**
- Modify: `lib/nutrition_tui/editors/nutrients_editor.rb`

**Step 1: Add basis_grams as the first editable item**

The nutrients editor currently shows 11 nutrient fields from `Data::NUTRIENTS`. Add `basis_grams` as a special first item. The total selectable items become 12: basis_grams at index 0, then the 11 nutrients at indices 1-11.

Add a constant for the basis_grams field:

```ruby
BASIS_FIELD = { key: 'basis_grams', label: 'Per (grams)', unit: '', indent: 0 }.freeze
```

Update `handle_selecting` to use the combined count:

```ruby
def item_count
  Data::NUTRIENTS.size + 1
end
```

Update navigation clamping from `Data::NUTRIENTS.size - 1` to `item_count - 1`.

Update `open_text_input` to handle index 0 (basis_grams) separately:

```ruby
def open_text_input
  field = selected_field
  current = @entry['nutrients'][field[:key]]
  @text_input = TextInput.new(label: field[:label], default: current || '')
  nil
end

def selected_field
  @selected.zero? ? BASIS_FIELD : Data::NUTRIENTS[@selected - 1]
end
```

Update `apply_edit` similarly — use `selected_field` instead of `Data::NUTRIENTS[@selected]`.

Update `nutrient_display_lines` to prepend the basis_grams line:

```ruby
def nutrient_display_lines
  [format_basis_line] + Data::NUTRIENTS.map { |n| format_nutrient_line(n) }
end

def format_basis_line
  value = @entry['nutrients']['basis_grams'] || 100
  "#{BASIS_FIELD[:label].ljust(20)}#{format_number(value)}g"
end
```

The format for basis_grams: `Per (grams)         100g` — matching the alignment of nutrient lines.

**Step 2: Verify manually**

Run: `bin/nutrition`, open an ingredient, press `n`. The first item should be "Per (grams)" showing the current basis (default 100). Navigate to it, press Enter, change to 30. Esc out. The ingredient screen should now show `[n] Nutrients (per 30g)`.

**Step 3: Commit**

```bash
git add lib/nutrition_tui/editors/nutrients_editor.rb
git commit -m "feat: add basis_grams editing to nutrients editor"
```

---

### Task 3: Fix portions editor keybindings when empty

**Files:**
- Modify: `lib/nutrition_tui/editors/portions_editor.rb`

**Step 1: Show keybind hint when empty**

In `render_list`, change the empty-state title suffix from `''` to `'  a add'`:

```ruby
title_suffix = portion_names.empty? ? '  a add' : '  a add  e edit  d delete'
```

This matches how aliases_editor.rb and sources_editor.rb already handle empty state.

**Step 2: Verify manually**

Run: `bin/nutrition`, open an ingredient with no portions, press `p`. The overlay title should show "Portions  a add". Press `a` to add a portion — verify it works.

**Step 3: Commit**

```bash
git add lib/nutrition_tui/editors/portions_editor.rb
git commit -m "fix: show keybind hints in portions editor when empty"
```

---

### Task 4: Visual polish — ingredient screen rich text

**Files:**
- Modify: `lib/nutrition_tui/screens/ingredient.rb` (substantial — convert all section methods to rich text)

This is the largest task. Every `*_section_lines` method converts from returning `String[]` to `Text::Line[]`. The `Paragraph.new(text:)` calls change from `lines.join("\n")` to passing the line array directly.

**Step 1: Add rich text helpers and constants**

At the top of the class (after the existing constants), add aliases and helper methods:

```ruby
Text = RatatuiRuby::Text

ROUNDED_BORDERS = { border_type: :rounded }.freeze
```

Add private helper methods at the bottom of the class:

```ruby
def span(text, **opts)
  Text::Span.styled(text.to_s, Style::Style.new(**opts))
end

def plain(text)
  Text::Span.raw(text.to_s)
end

def line(*spans)
  Text::Line.new(spans: spans)
end

def blank_line
  Text::Line.from_string('')
end
```

**Step 2: Convert `render_left_column`**

Change from `lines.join("\n")` to passing the array directly:

```ruby
def render_left_column(frame, area)
  paragraph = Widgets::Paragraph.new(
    text: left_column_lines,
    block: Widgets::Block.new(
      title: @name,
      borders: [:all],
      border_type: :rounded,
      title_style: Style::Style.new(modifiers: [:bold])
    )
  )
  frame.render_widget(paragraph, area)
end
```

**Step 3: Convert `render_right_column`**

```ruby
def render_right_column(frame, area)
  paragraph = Widgets::Paragraph.new(
    text: right_column_lines,
    block: Widgets::Block.new(
      title: 'Reference',
      borders: [:all],
      border_type: :rounded,
      title_style: Style::Style.new(fg: :dark_gray, modifiers: [:dim])
    )
  )
  frame.render_widget(paragraph, area)
end
```

**Step 4: Convert `left_column_lines`**

The method now returns `Text::Line[]`. Blank line separators use `blank_line`:

```ruby
def left_column_lines
  group1 = nutrients_section_lines
  group2 = density_section_lines + [blank_line] + portions_section_lines
  group3 = aisle_section_lines + [blank_line] + aliases_section_lines + [blank_line] + sources_section_lines
  [group1, group2, group3].flat_map { |g| g + [blank_line] }
end
```

**Step 5: Convert all section line methods**

Each method returns `Text::Line[]`. Examples:

```ruby
def nutrients_section_lines
  nutrients = @entry['nutrients']
  return [line(span('[n]', fg: :cyan), span(' Nutrients: ', modifiers: [:bold]), span('—', fg: :dark_gray))] unless nutrients.is_a?(Hash)

  header = line(span('[n]', fg: :cyan), span(' Nutrients ', modifiers: [:bold]), span("(per #{basis_grams}g)", fg: :dark_gray))
  [header] + Data::NUTRIENTS.map { |n| format_nutrient_line(nutrients, n) }
end
```

For `density_section_lines`:
```ruby
def density_section_lines
  density = @entry['density']
  return [line(span('[d]', fg: :cyan), span(' Density: ', modifiers: [:bold]), span('—', fg: :dark_gray))] unless density.is_a?(Hash)

  value = "#{format_number(density['grams'])}g per #{format_number(density['volume'])} #{density['unit']}"
  [line(span('[d]', fg: :cyan), span(' Density: ', modifiers: [:bold]), plain(value))]
end
```

Apply the same pattern to `portions_section_lines`, `aisle_section_lines`, `aliases_section_lines`, `sources_section_lines`. The key pattern is:
- `span('[x]', fg: :cyan)` for the key hint
- `span(' Label: ', modifiers: [:bold])` or `span(' Label ', modifiers: [:bold])` for the section name
- `span('—', fg: :dark_gray)` for empty state
- `plain(value)` for data values

`format_nutrient_line` should return a `Text::Line` instead of a String:
```ruby
def format_nutrient_line(nutrients, nutrient)
  indent = '  ' * nutrient[:indent]
  value = nutrients[nutrient[:key]]
  formatted = value ? format_number(value) : "\u2014"
  suffix = nutrient[:unit].empty? ? '' : " #{nutrient[:unit]}"
  Text::Line.from_string("#{indent}#{nutrient[:label].ljust(20 - (nutrient[:indent] * 2))}#{formatted}#{suffix}")
end
```

**Step 6: Convert `right_column_lines`**

```ruby
def right_column_lines
  recipe_units_section_lines + [blank_line] + usda_reference_section_lines
end
```

Convert `recipe_units_section_lines` — the key change is coloring `✓` green and `✗` red:
```ruby
def recipe_units_section_lines
  return [line(span('No recipe usage found', fg: :dark_gray))] if @needed_units.empty?

  calculator, calc_entry = build_calculator
  [line(span('Recipe Units', modifiers: [:bold]))] +
    @needed_units.map { |unit| format_unit_line(unit, calculator, calc_entry) }
end
```

`format_unit_line` returns a `Text::Line` with colored status:
```ruby
def format_unit_line(unit, calculator, calc_entry)
  display = unit.nil? ? '(bare count)' : unit
  resolved = calc_entry && calculator.resolvable?(1, unit, calc_entry)
  status_span = resolved ? span(' ✓ ', fg: :green) : span(' ✗ ', fg: :red)
  method = resolution_method(unit, resolved)
  line(plain("  #{display.to_s.ljust(16)}"), status_span, span(method, fg: :dark_gray))
end
```

Convert `usda_reference_section_lines` — color `★` yellow:
```ruby
def usda_reference_section_lines
  return [line(span("No USDA data \u2014 press u to search", fg: :dark_gray))] unless @usda_classified

  [line(span('USDA Reference', modifiers: [:bold]))] + usda_candidate_lines
end
```

`format_usda_candidate` returns a `Text::Line` with yellow star:
```ruby
def format_usda_candidate(candidate)
  star = candidate[:modifier] == @auto_density_source ? span("\u2605 ", fg: :yellow) : plain('  ')
  label = usda_candidate_label(candidate)
  grams = usda_candidate_grams(candidate)
  line(star, plain(label.ljust(25)), plain(grams))
end
```

**Step 7: Style the keybind bar**

Convert `keybind_bar_text` to return `Text::Line[]`:

```ruby
def render_keybind_bar(frame, area)
  paragraph = Widgets::Paragraph.new(text: keybind_bar_lines(area.width))
  frame.render_widget(paragraph, area)
end

def keybind_bar_lines(width)
  [keybind_line_1, keybind_line_2(width)]
end

def keybind_line_1
  line(
    plain(' '), span('n', fg: :cyan), span(' nutrients  ', fg: :dark_gray),
    span('d', fg: :cyan), span(' density  ', fg: :dark_gray),
    span('p', fg: :cyan), span(' portions  ', fg: :dark_gray),
    span('a', fg: :cyan), span(' aisle  ', fg: :dark_gray),
    span('l', fg: :cyan), span(' aliases  ', fg: :dark_gray),
    span('r', fg: :cyan), span(' sources', fg: :dark_gray)
  )
end

def keybind_line_2(width)
  parts = [
    plain(' '), span('u', fg: :cyan), span(' USDA  ', fg: :dark_gray),
    span('w', fg: :cyan), span(' save  ', fg: :dark_gray),
    span('Esc', fg: :cyan), span(' back', fg: :dark_gray)
  ]
  parts << span('  [modified]', fg: :yellow) if @dirty
  Text::Line.new(spans: parts)
end
```

**Step 8: Verify manually**

Run: `bin/nutrition`
- Open an ingredient with full data — verify colored section headers, green/red status, yellow star
- Verify rounded borders on both columns
- Verify keybind bar has cyan key letters
- Verify `[modified]` shows in yellow after making an edit
- Open an ingredient with sparse data — verify dim empty states
- Test all editor overlays still work correctly

**Step 9: Commit**

```bash
git add lib/nutrition_tui/screens/ingredient.rb
git commit -m "feat: rich text styling with colored sections and rounded borders"
```

---

### Task 5: Visual polish — editor overlays

**Files:**
- Modify: `lib/nutrition_tui/editors/nutrients_editor.rb`
- Modify: `lib/nutrition_tui/editors/density_editor.rb`
- Modify: `lib/nutrition_tui/editors/portions_editor.rb`
- Modify: `lib/nutrition_tui/editors/aisle_editor.rb`
- Modify: `lib/nutrition_tui/editors/aliases_editor.rb`
- Modify: `lib/nutrition_tui/editors/sources_editor.rb`
- Modify: `lib/nutrition_tui/screens/ingredient.rb` (confirm dialog border)

**Step 1: Add rounded borders to all editor overlays**

In each editor's `render` method, change `Widgets::Block.new(title: ..., borders: [:all])` to include `border_type: :rounded`.

For `nutrients_editor.rb`:
```ruby
block: Widgets::Block.new(title: 'Edit Nutrients', borders: [:all], border_type: :rounded)
```

For `density_editor.rb`:
```ruby
block: Widgets::Block.new(title: 'Edit Density', borders: [:all], border_type: :rounded)
```

For `portions_editor.rb`:
```ruby
block: Widgets::Block.new(title: "Portions#{title_suffix}", borders: [:all], border_type: :rounded)
```

For `aisle_editor.rb`:
```ruby
block: Widgets::Block.new(title: 'Aisle', borders: [:all], border_type: :rounded)
```

For `aliases_editor.rb`:
```ruby
block: Widgets::Block.new(title: "Aliases#{title_suffix}", borders: [:all], border_type: :rounded)
```

For `sources_editor.rb`:
```ruby
block: Widgets::Block.new(title: "Sources#{title_suffix}", borders: [:all], border_type: :rounded)
```

**Step 2: Double border for confirm dialog**

In `ingredient.rb`, change `confirm_list_widget`:
```ruby
block: Widgets::Block.new(title: 'Unsaved changes', borders: [:all], border_type: :double)
```

**Step 3: Rounded border for text input**

In `text_input.rb`:
```ruby
block: Widgets::Block.new(borders: [:all], border_type: :rounded)
```

**Step 4: Verify manually**

Run: `bin/nutrition`, open an ingredient, press each editor key (n, d, p, a, l, r). Verify all overlays have rounded borders. Make an edit, press Esc — verify confirm dialog has double border.

**Step 5: Commit**

```bash
git add lib/nutrition_tui/editors/ lib/nutrition_tui/screens/ingredient.rb
git commit -m "feat: rounded borders on editor overlays, double border on confirm dialog"
```

---

### Task 6: Final verification and lint

Run `bundle exec rubocop lib/nutrition_tui/` and fix any offenses.

Run `bin/nutrition` and verify the complete flow:
1. Mouse clicks and scroll produce no effect
2. Nutrients editor shows basis_grams as first field, editable
3. Portions editor shows `a add` hint when empty
4. Rich text renders correctly — colored key hints, green/red status, yellow stars
5. Rounded borders on all panels and overlays
6. Double border on unsaved-changes confirm dialog
7. Keybind bar has cyan keys with dim descriptions
8. `[modified]` shows in yellow

**Commit if lint fixes needed:**
```bash
git add lib/nutrition_tui/
git commit -m "fix: rubocop offenses in nutrition TUI"
```
