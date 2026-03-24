# Nutrition TUI Editor Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the ingredient editor screen with a two-column layout showing the full catalog schema, direct one-key editing, and clear separation of authored data from computed reference.

**Architecture:** The ingredient detail screen (`screens/ingredient.rb`) gets a new two-column layout: left column renders all persisted catalog fields, right column renders computed reference data. The density editor (`editors/density_editor.rb`) changes from a three-step wizard to a form showing all fields at once. The `EditMenu` class is deleted — direct keys replace it.

**Tech Stack:** Ruby, ratatui_ruby (Rust TUI via FFI), YAML catalog

**Design doc:** `docs/plans/2026-03-03-nutrition-tui-editor-design.md`

---

### Task 1: Rewrite DensityEditor as form layout

**Files:**
- Modify: `lib/nutrition_tui/editors/density_editor.rb` (full rewrite)

The current DensityEditor is a state machine: `:menu` → `:entering_grams` → `:entering_volume` → `:entering_unit`. Each step shows a single TextInput. Rewrite to show all three fields simultaneously with a navigable list, matching how NutrientsEditor works.

**Step 1: Rewrite density_editor.rb**

Replace the entire file. The new editor:
- Shows 4 items: Grams, Volume, Unit, Remove density
- Navigates with j/k, Enter to edit selected field (opens inline TextInput at bottom of overlay)
- Esc returns with whatever changes have been made
- No initial menu — opens directly to the field list
- Pre-populates fields from existing density data (or empty for new)
- "Remove density" deletes the density hash from the entry

Model closely on NutrientsEditor (see `editors/nutrients_editor.rb`). Key differences:
- Only 3 data fields + 1 action (vs 11 nutrient fields)
- Fields have different types: Grams and Volume are floats, Unit is a string
- "Remove density" is a selectable action, not a field — highlight it differently or just treat it as a list item
- Field display format: `Grams           30.0` / `Volume          0.25` / `Unit            cup`
- When a field has no value, show `—`

The `FIELDS` constant should be:
```ruby
FIELDS = [
  { key: 'grams', label: 'Grams' },
  { key: 'volume', label: 'Volume' },
  { key: 'unit', label: 'Unit' }
].freeze
```

States: selecting (navigate list, Enter to edit) and editing (TextInput active). The `@selected` index covers fields 0-2 plus index 3 for "Remove density".

On Enter for fields 0-1 (grams, volume): open TextInput, parse as Float on submit, ignore if invalid.
On Enter for field 2 (unit): open TextInput, accept as string, strip whitespace.
On Enter for index 3 (Remove density): delete `@entry['density']` and return done.
On Esc: return `{ done: true, entry: @entry }`.

Rendering: use `Widgets::List` for the field list (same as NutrientsEditor). Render TextInput at bottom of overlay area when editing (same pattern as NutrientsEditor's `render_text_input`).

**Step 2: Verify manually**

Run: `bin/nutrition`
- Open any ingredient with density data (e.g., "Flour (all-purpose)")
- Press `d` (once the Ingredient screen keybindings are updated in Task 2; for now, test via `e` → Density)
- Verify all three fields show with current values
- Navigate with j/k, edit each field with Enter
- Verify "Remove density" works
- Verify Esc returns to ingredient screen

**Step 3: Commit**

```bash
git add lib/nutrition_tui/editors/density_editor.rb
git commit -m "refactor: density editor form layout with all fields visible"
```

---

### Task 2: Rewrite Ingredient screen — left column (catalog entry)

**Files:**
- Modify: `lib/nutrition_tui/screens/ingredient.rb` (substantial rewrite of rendering methods)

Replace the three-panel layout (`render_content` → `render_nutrients_panel` + `render_right_panels`) with a two-column layout. This task handles the left column only.

**Step 1: Replace layout structure**

Change `render_content` to split horizontally into two columns (~60% / ~40%):

```ruby
def render_content(frame, area)
  chunks = horizontal_split(area, [Layout::Constraint.percentage(60), Layout::Constraint.percentage(40)])
  render_left_column(frame, chunks[0])
  render_right_column(frame, chunks[1])
end
```

**Step 2: Implement `render_left_column`**

The left column is a single `Widgets::Paragraph` inside a `Widgets::Block` with the ingredient name as the title. The text is built by concatenating all catalog sections with blank-line separators.

The method assembles text lines from these helpers (in order):
1. `nutrients_section_lines` — `[n] Nutrients (per Xg)` header + indented nutrient rows (reuse existing `format_nutrient_line` logic). When no nutrients: `[n] Nutrients: —`
2. blank line
3. `density_section_line` — Single line. When populated: `[d] Density: 30g per 0.25 cup`. When empty: `[d] Density: —`
4. `portions_section_lines` — `[p] Portions` header + indented entries. When empty: `[p] Portions: —`
5. blank line
6. `aisle_section_line` — `[a] Aisle: Baking` or `[a] Aisle: —`
7. `aliases_section_line` — `[l] Aliases: name1, name2` (comma-separated inline) or `[l] Aliases: —`. If 4+ aliases, expand to list format with indented items.
8. `sources_section_lines` — `[r] Sources` header + indented entries (`type – dataset (fdc_id)` and `"description"` on next line). When empty: `[r] Sources: —`

Each helper returns an array of strings. Join them all with `"\n"`.

**Step 3: Remove old panel methods**

Delete: `render_nutrients_panel`, `render_density_portions_panel`, `density_portions_text`, `density_line`, `portion_lines`, `render_right_panels`, `render_right_panels_default`, `render_right_panels_with_usda`.

Keep: `nutrients_text` logic (refactored into `nutrients_section_lines`), `format_nutrient_line`, `basis_grams`, `format_number`, `dim_text`.

**Step 4: Verify manually**

Run: `bin/nutrition`
- Open an ingredient with full data (nutrients, density, portions, aisle, aliases, sources)
- Verify left column shows all sections with `[key]` prefixes
- Open an ingredient with sparse data — verify empty sections show `—`
- Resize terminal — verify layout adapts

**Step 5: Commit**

```bash
git add lib/nutrition_tui/screens/ingredient.rb
git commit -m "feat: two-column layout with full catalog entry in left column"
```

---

### Task 3: Rewrite Ingredient screen — right column (reference) and USDA always-visible

**Files:**
- Modify: `lib/nutrition_tui/screens/ingredient.rb`

**Step 1: Implement `render_right_column`**

The right column contains:
1. Dim "Reference" label at the top-right of the block title
2. Recipe Units section (always shown)
3. USDA Reference section (shown when `@usda_classified` is present, otherwise dim prompt)

The right column is a `Widgets::Paragraph` inside a `Widgets::Block` with title "Reference" and a dim style on the title. Text is built from:
- `recipe_units_section_lines` — "Recipe Units" header + indented unit lines with ✓/✗ status. Reuse existing `format_unit_line` logic. When no recipe usage: dim "No recipe usage found"
- blank line
- `usda_reference_section_lines` — "USDA Reference" header + candidate lines. When no USDA data: dim "No USDA data — press u to search"

**Step 2: Remove USDA toggle state**

Delete `@show_usda_reference` from `initialize`. Remove the conditional in `handle_usda_key` that toggles it — `u` should only trigger USDA import when `@usda_classified` is nil. When USDA data exists, `u` does nothing (it's already visible).

Delete: `render_right_panels_with_usda` (already removed in Task 2). The `render_usda_reference_panel` method gets refactored into `usda_reference_section_lines`.

**Step 3: Verify manually**

Run: `bin/nutrition`
- Open an ingredient with USDA data — verify USDA reference shows in right column permanently
- Open an ingredient without USDA data — verify dim prompt shows
- Verify Recipe Units section displays correctly
- Verify `u` triggers USDA search on ingredients without USDA data
- Verify `u` does nothing on ingredients that already have USDA data

**Step 4: Commit**

```bash
git add lib/nutrition_tui/screens/ingredient.rb
git commit -m "feat: right column with reference data and always-visible USDA"
```

---

### Task 4: Direct edit keybindings — replace EditMenu with one-key shortcuts

**Files:**
- Modify: `lib/nutrition_tui/screens/ingredient.rb`

**Step 1: Replace `dispatch_key`**

Change keybindings from `e` → EditMenu to direct keys:

```ruby
def dispatch_key(event)
  case event
  in { type: :key, code: 'esc' }  then handle_escape
  in { type: :key, code: 'n' }    then open_nutrients_editor
  in { type: :key, code: 'd' }    then open_density_editor
  in { type: :key, code: 'p' }    then open_portions_editor
  in { type: :key, code: 'a' }    then open_aisle_editor
  in { type: :key, code: 'l' }    then open_aliases_editor
  in { type: :key, code: 'r' }    then open_sources_editor
  in { type: :key, code: 'u' }    then handle_usda_key
  in { type: :key, code: 'w' }    then save_entry
  else nil
  end
end
```

**Step 2: Add direct editor openers**

Add `open_nutrients_editor`, `open_density_editor`, `open_portions_editor` methods that directly create the editor instance (no intermediate menu):

```ruby
def open_nutrients_editor
  @active_editor = Editors::NutrientsEditor.new(entry: @entry)
  nil
end

def open_density_editor
  @active_editor = Editors::DensityEditor.new(entry: @entry)
  nil
end

def open_portions_editor
  @active_editor = Editors::PortionsEditor.new(entry: @entry)
  nil
end
```

**Step 3: Remove EditMenu references**

Delete: `open_edit_menu`, `open_sub_editor`. Update `process_editor_result` to remove the `result[:choice]` branch (EditMenu was the only editor that returned `choice:`).

The simplified `process_editor_result`:
```ruby
def process_editor_result(result)
  if result[:entry]
    @entry = result[:entry]
    @dirty = true
    @active_editor = nil
  elsif result[:value]
    apply_value_result(result)
  else
    @active_editor = nil
  end
  nil
end
```

**Step 4: Update keybind bar**

Change `render_keybind_bar` to show the new key layout across two lines:

```ruby
def render_keybind_bar(frame, area)
  suffix = @dirty ? '[modified]' : ''
  line1 = ' n nutrients  d density  p portions  a aisle  l aliases  r sources'
  line2 = " u USDA  w save  Esc back#{suffix.rjust(area.width - 27)}"
  paragraph = Widgets::Paragraph.new(
    text: "#{line1}\n#{line2}",
    style: Style::Style.new(fg: :dark_gray, modifiers: [:dim])
  )
  frame.render_widget(paragraph, area)
end
```

Update the keybind bar area height from 1 to 2 in `render`:
```ruby
main_chunks = vertical_split(frame.area, [Layout::Constraint.min(10), Layout::Constraint.length(2)])
```

**Step 5: Verify manually**

Run: `bin/nutrition`
- Open any ingredient
- Press each key (n, d, p, a, l, r) — verify correct editor opens directly
- Verify `e` does nothing (no longer bound)
- Verify keybind bar shows two lines with all shortcuts
- Verify `[modified]` appears after making any edit
- Test save (w) and back (Esc) with dirty/clean states

**Step 6: Commit**

```bash
git add lib/nutrition_tui/screens/ingredient.rb
git commit -m "feat: direct one-key shortcuts for all editor sections"
```

---

### Task 5: Delete EditMenu and clean up

**Files:**
- Delete: `lib/nutrition_tui/editors/edit_menu.rb`
- Modify: `lib/nutrition_tui.rb` (remove require line)

**Step 1: Delete the file**

```bash
rm lib/nutrition_tui/editors/edit_menu.rb
```

**Step 2: Remove the require**

In `lib/nutrition_tui.rb`, delete the line:
```ruby
require_relative 'nutrition_tui/editors/edit_menu'
```

**Step 3: Verify**

Run: `bin/nutrition` — confirm it boots without errors, open an ingredient, verify all keys work.

**Step 4: Commit**

```bash
git add -u lib/nutrition_tui/editors/edit_menu.rb lib/nutrition_tui.rb
git commit -m "chore: remove EditMenu class replaced by direct keybindings"
```

---

### Task 6: Final manual verification

Run `bin/nutrition` and verify the complete flow:

1. **Full layout:** Open an ingredient with complete data. Verify two-column layout: left shows nutrients, density, portions, aisle, aliases, sources with `[key]` prefixes. Right shows Recipe Units and USDA Reference.
2. **Empty states:** Open an ingredient with minimal data. Verify empty sections show `—` with key hints.
3. **Direct keys:** Press n, d, p, a, l, r — each opens the correct editor. Verify edits apply and `[modified]` shows.
4. **Density form:** Press d — verify all three fields visible. Navigate j/k, edit with Enter, test "Remove density".
5. **USDA always-visible:** Open ingredient with USDA data — reference shows without pressing u. Open ingredient without — shows prompt.
6. **Save/back:** Make edits, press w to save. Make edits, press Esc — verify unsaved-changes dialog.
7. **Resize:** Resize terminal at various points — verify layout adapts.

Run: `bundle exec rubocop lib/nutrition_tui/` to check for lint issues. Fix any offenses.

**Final commit (if lint fixes needed):**
```bash
git add lib/nutrition_tui/
git commit -m "fix: rubocop offenses in nutrition TUI"
```
