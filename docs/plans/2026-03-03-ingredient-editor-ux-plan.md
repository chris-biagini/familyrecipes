# Ingredient Editor UX Polish — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Visual refresh of the ingredient detail screen in `bin/nutrition` — ruled section headers, deduplicated keybind bar, right-aligned nutrients, dirty indicator in title.

**Architecture:** All changes in `NutritionTui::Screens::Ingredient`. Add a `section_header` helper that builds ruled lines with the section name, key hint, and fill characters. Pass `inner_width` from the render method down to line-building methods.

**Tech Stack:** ratatui_ruby (Text::Line, Text::Span, Style::Style, Widgets::Block)

---

### Task 1: Add `section_header` helper and pass width through rendering

**Files:**
- Modify: `lib/nutrition_tui/screens/ingredient.rb`

**Step 1: Add `section_header` helper method**

Add after the existing `blank_line` helper (~line 515):

```ruby
def section_header(name, key, width, suffix: nil, suffix_style: nil)
  prefix_len = name.size + key.size + 5
  suffix_len = suffix ? suffix.size + 1 : 0
  fill_len = [width - prefix_len - suffix_len, 4].max
  parts = [
    span(name, modifiers: [:bold]),
    span(" [#{key}]", fg: :cyan),
    span(" #{'─' * fill_len}", fg: :dark_gray)
  ]
  parts << styled_suffix(suffix, suffix_style) if suffix
  styled_line(*parts)
end

def styled_suffix(text, style)
  style ? span(" #{text}", **style) : plain(" #{text}")
end
```

**Step 2: Thread width through `render_left_column` → `left_column_lines`**

In `render_left_column`, compute `inner_width = area.width - 2` (border padding) and pass it to `left_column_lines(inner_width)`. Update `left_column_lines` signature to accept `width`.

**Step 3: Commit**

```bash
git add lib/nutrition_tui/screens/ingredient.rb
git commit -m "feat(nutrition-tui): add section_header helper with ruled lines"
```

---

### Task 2: Convert all section headers to ruled format

**Files:**
- Modify: `lib/nutrition_tui/screens/ingredient.rb`

**Step 1: Update `nutrients_section_lines` and `nutrients_header` / `nutrients_empty_line`**

Replace `nutrients_header` and `nutrients_empty_line` — both become calls to `section_header`:

```ruby
def nutrients_section_lines(width)
  nutrients = @entry['nutrients']
  return [section_header('Nutrients', 'n', width, suffix: '—', suffix_style: { fg: :dark_gray })] unless nutrients.is_a?(Hash)

  [section_header('Nutrients', 'n', width, suffix: "(per #{basis_grams}g)", suffix_style: { fg: :dark_gray })] +
    Data::NUTRIENTS.map { |n| format_nutrient_line(nutrients, n) }
end
```

Delete `nutrients_header` and `nutrients_empty_line`.

**Step 2: Update `density_section_lines` / `density_empty_line`**

```ruby
def density_section_lines(width)
  density = @entry['density']
  return [section_header('Density', 'd', width, suffix: '—', suffix_style: { fg: :dark_gray })] unless density.is_a?(Hash)

  value = "#{format_number(density['grams'])}g per #{format_number(density['volume'])} #{density['unit']}"
  [section_header('Density', 'd', width, suffix: value)]
end
```

Delete `density_empty_line`.

**Step 3: Update `portions_section_lines` / `portions_empty_line`**

```ruby
def portions_section_lines(width)
  portions = @entry['portions']
  return [section_header('Portions', 'p', width, suffix: '—', suffix_style: { fg: :dark_gray })] unless portions.is_a?(Hash) && portions.any?

  [section_header('Portions', 'p', width)] +
    portions.map { |name, grams| Text::Line.from_string("    #{name.ljust(16)}#{format_number(grams)}g") }
end
```

Delete `portions_empty_line`.

**Step 4: Update `aisle_section_lines` / `aisle_empty_line`**

```ruby
def aisle_section_lines(width)
  aisle = @entry['aisle']
  return [section_header('Aisle', 'a', width, suffix: '—', suffix_style: { fg: :dark_gray })] unless aisle

  [section_header('Aisle', 'a', width, suffix: aisle)]
end
```

Delete `aisle_empty_line`.

**Step 5: Update `aliases_section_lines` / `aliases_inline_line` / `aliases_empty_line`**

```ruby
def aliases_section_lines(width)
  aliases = @entry['aliases']
  return [section_header('Aliases', 'l', width, suffix: '—', suffix_style: { fg: :dark_gray })] unless aliases.is_a?(Array) && aliases.any?
  return [section_header('Aliases', 'l', width, suffix: aliases.join(', '))] if aliases.size < 4

  [section_header('Aliases', 'l', width)] + aliases.map { |a| Text::Line.from_string("    #{a}") }
end
```

Delete `aliases_inline_line` and `aliases_empty_line`.

**Step 6: Update `sources_section_lines` / `sources_empty_line`**

```ruby
def sources_section_lines(width)
  sources = @entry['sources']
  return [section_header('Sources', 'r', width, suffix: '—', suffix_style: { fg: :dark_gray })] unless sources.is_a?(Array) && sources.any?

  [section_header('Sources', 'r', width)] + sources.flat_map { |s| format_source_lines(s) }
end
```

Delete `sources_empty_line`.

**Step 7: Update `left_column_lines` to flatten sections with single blank-line spacing**

```ruby
def left_column_lines(width)
  [
    nutrients_section_lines(width),
    density_section_lines(width),
    portions_section_lines(width),
    aisle_section_lines(width),
    aliases_section_lines(width),
    sources_section_lines(width)
  ].flat_map { |s| s + [blank_line] }
end
```

**Step 8: Commit**

```bash
git add lib/nutrition_tui/screens/ingredient.rb
git commit -m "feat(nutrition-tui): ruled section headers with key hints"
```

---

### Task 3: Reference header white, dirty indicator in title, keybind bar simplification

**Files:**
- Modify: `lib/nutrition_tui/screens/ingredient.rb`

**Step 1: Change Reference header to white bold**

In `render_right_column`, change:
```ruby
title_style: Style::Style.new(fg: :dark_gray, modifiers: [:dim])
```
to:
```ruby
title_style: Style::Style.new(modifiers: [:bold])
```

**Step 2: Add dirty indicator to left column title**

In `render_left_column`, change the block to use dynamic title and style:

```ruby
block: Widgets::Block.new(
  title: @dirty ? "#{@name} *" : @name,
  borders: [:all],
  border_type: :rounded,
  title_style: @dirty ? Style::Style.new(fg: :yellow, modifiers: [:bold]) : Style::Style.new(modifiers: [:bold])
)
```

**Step 3: Simplify keybind bar to one line**

Change the main layout constraint from `length(2)` to `length(1)`.

Replace `keybind_bar_lines`, `keybind_top_line`, `keybind_bottom_line` with:

```ruby
def keybind_bar_lines
  parts = [
    plain(' '), span('u', fg: :cyan), span(' USDA  ', fg: :dark_gray),
    span('w', fg: :cyan), span(' save  ', fg: :dark_gray),
    span('Esc', fg: :cyan), span(' back', fg: :dark_gray)
  ]
  parts << span('  [unsaved]', fg: :yellow, modifiers: [:bold]) if @dirty
  [Text::Line.new(spans: parts)]
end
```

Delete `keybind_top_line` and `keybind_bottom_line`.

**Step 4: Commit**

```bash
git add lib/nutrition_tui/screens/ingredient.rb
git commit -m "feat(nutrition-tui): white reference header, dirty title indicator, slim keybind bar"
```

---

### Task 4: Right-align nutrient values

**Files:**
- Modify: `lib/nutrition_tui/screens/ingredient.rb`

**Step 1: Update `format_nutrient_line` to accept width and right-align**

```ruby
def format_nutrient_line(nutrients, nutrient, width)
  indent = '  ' * nutrient[:indent]
  label = "#{indent}#{nutrient[:label]}"
  value = nutrients[nutrient[:key]]
  formatted = value ? format_number(value) : "\u2014"
  suffix = nutrient[:unit].empty? ? '' : " #{nutrient[:unit]}"
  value_str = "#{formatted}#{suffix}"
  padding = [width - label.size - value_str.size, 1].max
  Text::Line.from_string("#{label}#{' ' * padding}#{value_str}")
end
```

**Step 2: Update the call site in `nutrients_section_lines` to pass width**

```ruby
Data::NUTRIENTS.map { |n| format_nutrient_line(nutrients, n, width) }
```

**Step 3: Commit**

```bash
git add lib/nutrition_tui/screens/ingredient.rb
git commit -m "feat(nutrition-tui): right-align nutrient values"
```

---

### Task 5: Run RuboCop and verify manually

**Step 1: Run linter**

```bash
bundle exec rubocop lib/nutrition_tui/screens/ingredient.rb
```

Fix any offenses.

**Step 2: Manual verification**

```bash
bin/nutrition
```

Navigate to an ingredient with full data (nutrients, density, portions, aliases, sources) and verify:
- Ruled section headers with key hints
- Right-aligned nutrient values
- White bold "Reference" header
- Dirty indicator appears in title after editing
- Keybind bar is one line with only u/w/Esc
- Blank line spacing is clean

**Step 3: Final commit if any fixes needed**

```bash
git add lib/nutrition_tui/screens/ingredient.rb
git commit -m "fix: resolve rubocop offenses in ingredient editor polish"
```
