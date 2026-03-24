# Nutrition TUI Polish — Design

Four changes: disable mouse reporting, add basis_grams editing, fix portions editor keybindings, and visual polish with rich text styling.

## 1. Disable Mouse Reporting

ratatui_ruby enables mouse capture by default with no flag to disable it. Filter mouse events at the application layer — in `app.rb`'s `dispatch` method, ignore any event with `type: :mouse`.

## 2. Nutrients Editor: basis_grams

Add `basis_grams` as the first editable field in the nutrients editor, above the 11 nutrient fields. Label: `Per (grams)`, default 100. Parsed as Float. This lets users change the serving basis (e.g., "per 100g" → "per 30g") directly while editing nutrients.

The `NUTRIENTS` constant in `data.rb` is not modified — `basis_grams` is handled as a special first item in the editor only.

## 3. Portions Editor: Keybindings When Empty

The title currently shows just "Portions" when the list is empty, hiding the `a add` hint. Fix: show `a add` even when empty, matching aliases and sources editors.

## 4. Visual Polish

Convert both columns from plain strings to `Text::Line`/`Text::Span` rich text. Add rounded borders and a consistent color language.

### Borders

- All panels: `:rounded`
- Editor overlays: `:rounded`
- Confirm dialog: `:double`

### Color Scheme

| Element | Style |
|---------|-------|
| Section key hints `[n]` `[d]` etc. | cyan |
| Section labels "Nutrients", "Density" | bold |
| Empty state `—` and placeholders | dim |
| Recipe units `✓` | green |
| Recipe units `✗` | red |
| USDA `★` | yellow |
| `[modified]` indicator | yellow |
| Keybind bar shortcut keys | cyan |
| Keybind bar descriptions | dim gray |
| Ingredient name (block title) | bold |
| "Reference" (block title) | dim (already done) |

### Implementation

The `*_section_lines` methods in `ingredient.rb` switch from returning `String[]` to `Text::Line[]`. Rich text helpers keep the code clean:

```ruby
Text = RatatuiRuby::Text

def span(text, **opts)
  Text::Span.styled(text, Style::Style.new(**opts))
end

def plain(text)
  Text::Span.raw(text)
end

def line(*spans)
  Text::Line.new(spans: spans)
end

def blank_line
  Text::Line.from_string('')
end
```

Section headers become:
```ruby
line(span('[n]', fg: :cyan), span(' Nutrients ', modifiers: [:bold]), span("(per #{basis_grams}g)", fg: :dark_gray))
```

Status indicators become:
```ruby
span('✓', fg: :green)  # resolved
span('✗', fg: :red)    # unresolved
span('★', fg: :yellow)  # auto-selected
```

The `Paragraph.new(text:)` call changes from `lines.join("\n")` to passing the `Text::Line[]` array directly.

### Editors

Editor overlays also get `:rounded` borders. The keybind bar in the ingredient screen gets styled keys (cyan) with dim descriptions.

### Dashboard

Dashboard is out of scope for this change — focus on the ingredient detail screen and editors.
