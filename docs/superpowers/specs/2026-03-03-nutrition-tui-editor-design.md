# Nutrition TUI Editor Redesign

## Problem

The ingredient editor screen hides aisle, aliases, and sources behind editor-only views — you can't see their current values without opening an editor. Editing nutrients/density/portions requires pressing `e` to open an intermediate menu before reaching the actual editor. There's no visual distinction between data you're authoring and computed reference information.

## Design

### Two-Column Layout

Left column (~60%) shows the full catalog entry. Right column (~40%) shows computed reference data with a dim "Reference" label. The ingredient name is the outer block title.

```
┌─ Flour (all-purpose) ──────────────────────────────────────────────────────┐
│                                                        Reference           │
│  [n] Nutrients (per 30g)                                                   │
│  Calories          110                  Recipe Units                       │
│  Total fat         0.0g                   cup          ✓ via density       │
│    Saturated fat   0.0g                   (bare count) ✓ via ~unitless     │
│    Trans fat       0.0g                   tbsp         ✗ no density        │
│  Cholesterol       0mg                                                     │
│  Sodium            0mg                  USDA Reference                     │
│  Total carbs       28g                    ★ cup                    120g    │
│    Fiber           0g                       tablespoon             8g      │
│    Total sugars    0g                                                      │
│      Added sugars  0g                                                      │
│  Protein           3g                                                      │
│                                                                            │
│  [d] Density: 30g per 0.25 cup                                             │
│  [p] Portions                                                              │
│    stick            113.0g                                                 │
│    ~unitless        50g                                                    │
│                                                                            │
│  [a] Aisle: Baking                                                         │
│  [l] Aliases: all-purpose flour, wheat flour, AP flour                     │
│  [r] Sources                                                               │
│    usda – SR Legacy (168913)                                               │
│    "Wheat flour, white, all-purpose, enriched, unbleached"                 │
│                                                                            │
├────────────────────────────────────────────────────────────────────────────┤
│ n nutrients  d density  p portions  a aisle  l aliases  r sources          │
│ u USDA  w save  Esc back                                      [modified]  │
└────────────────────────────────────────────────────────────────────────────┘
```

### Direct Edit Keys

Each section gets a one-key shortcut. The `e` key and `EditMenu` class are removed.

| Key | Action |
|-----|--------|
| `n` | Open nutrients editor |
| `d` | Open density editor |
| `p` | Open portions editor |
| `a` | Open aisle editor |
| `l` | Open aliases editor |
| `r` | Open sources editor |
| `u` | USDA search/import (when no USDA data) |
| `w` | Save |
| `Esc` | Back (unsaved-changes confirm if dirty) |

### Section Display Rules

**Nutrients:** Same hierarchical indentation as today. Header shows basis grams: `[n] Nutrients (per 30g)`.

**Density:** Inline when populated: `[d] Density: 30g per 0.25 cup`. Dash when empty: `[d] Density: —`.

**Portions:** Header line `[p] Portions` with indented entries below. When empty: `[p] Portions: —`.

**Aisle:** Always inline: `[a] Aisle: Baking` or `[a] Aisle: —`.

**Aliases:** Inline comma-separated: `[l] Aliases: all-purpose flour, wheat flour`. When empty: `[l] Aliases: —`. Expands to indented list only if 4+ aliases.

**Sources:** Header line `[r] Sources` with indented entries. Each source shows type, dataset, FDC ID, and description compactly. When empty: `[r] Sources: —`.

### USDA Reference Always Visible

Once USDA data has been imported, the reference panel shows permanently in the right column below Recipe Units. No toggle. The `@show_usda_reference` state variable is removed. When no USDA data exists, show dim "No USDA data — press u to search".

### Density Editor: Form Layout

The density editor currently uses a three-step wizard (grams → volume → unit, one TextInput at a time). Redesign to show all three fields simultaneously, matching the nutrients editor pattern:

```
┌─ Density ────────────────────────┐
│                                  │
│ > Grams           30.0           │
│   Volume          0.25           │
│   Unit            cup            │
│                                  │
│   Remove density                 │
│                                  │
│ j/k navigate  Enter edit  Esc done│
└──────────────────────────────────┘
```

Navigate with j/k, Enter to edit selected field (opens inline TextInput), "Remove density" as a selectable action. Esc returns with changes. The initial "Enter custom / Remove / Cancel" menu is eliminated.

### Keybind Bar

Two-line bar at the bottom. First line lists edit keys grouped by function. Second line lists utility keys. `[modified]` indicator right-aligned.

### What Gets Removed

- `EditMenu` class (`editors/edit_menu.rb`) — replaced by direct keys
- The `e` keybinding
- `@show_usda_reference` state variable and toggle behavior
- DensityEditor's `:menu` state and `MENU_OPTIONS` — replaced by form layout
- DensityEditor's sequential `advance_state` wizard flow

### What Stays the Same

- Nutrients, portions, aisle, aliases, and sources editors work as today
- Overlay positioning and styling
- Unsaved-changes confirmation dialog
- Save behavior
- TextInput widget (reused within the new density form)
