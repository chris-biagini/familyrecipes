# Ingredient Editor UX Polish

## Overview

Visual refresh of the `bin/nutrition` ingredient detail screen. Six changes, all confined to `NutritionTui::Screens::Ingredient`.

## Changes

### 1. Reference header — white text

Current: `fg: :dark_gray, modifiers: [:dim]`. Change to plain white (no fg override, add bold).

### 2. Section headers with ruled format

Replace `[n] Nutrients: value` with:

```
Nutrients [n] ──────────
  Calories             110
  Total fat            0g
```

Section name (bold), then key hint (cyan), then em-dash fill to the available width. Drop the colon. When a section is empty/missing, the rule still renders with an em-dash value after it:

```
Density [d] ────────── —
```

Multi-line sections (Portions, Aliases, Sources) get the header rule on its own line, detail lines indented below.

Implementation: pass `inner_width` (area width minus border padding) into `left_column_lines`, use it to calculate fill length for each header.

### 3. Deduplicate keybind bar

Section keys (n/d/p/a/l/r) are now discoverable in the section headers. Bottom bar shrinks to one line:

```
 u USDA  w save  Esc back
```

### 4. Dirty indicator in block title

When `@dirty` is true, append ` *` to the ingredient name in the left column block title, styled yellow. Clean state shows just the name.

### 5. Right-align nutrient values

In `format_nutrient_line`, right-align the numeric value + unit within a fixed column so numbers line up visually. Use the inner width to calculate padding.

### 6. Tighter vertical spacing

With ruled section headers providing visual separation, reduce blank lines between groups. One blank line between sections (instead of trailing blanks on every group).
