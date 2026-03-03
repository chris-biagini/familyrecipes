# Nutrition TUI Redesign

Replaces the current REPL-style `bin/nutrition` with a panel-based TUI built on RatatuiRuby. Improves the USDA import pipeline with two-phase nutrient/portion separation, and fixes data issues with aisle-only entries and bogus portion formats.

## Architecture & Dependencies

**RatatuiRuby** (v1.4.2) as the TUI framework, in the `:development` Gemfile group. Ships precompiled native extensions for Linux x86_64, macOS ARM, and Windows — no Rust toolchain needed at install time. Excluded from production Docker builds.

Existing TTY gems stay for spinner use during USDA API calls (ratatui owns the terminal during the main event loop; spinners run in the search flow).

The current 803-line `bin/nutrition` script splits into a module structure:

```
lib/nutrition_tui/
  app.rb              # event loop, screen management, terminal setup/teardown
  screens/
    dashboard.rb      # overview: coverage stats + scrollable ingredient list
    ingredient.rb     # detail view: nutrients, density, portions, recipe units
    usda_search.rb    # USDA search + nutrient import + portion reference
  widgets/
    nutrients_table.rb
    portions_panel.rb
    coverage_panel.rb
  data.rb             # load/save YAML, context building, lookup resolution
```

Not autoloaded by Rails — `bin/nutrition` requires it directly. `bin/nutrition` itself becomes a thin entry point.

## Dashboard Screen

Launched with `bin/nutrition` (no args). Replaces the old `--missing` mode.

**Top bar:** Coverage summary — total ingredients, count with nutrition, count fully resolvable, count missing.

**Main panel:** Scrollable, filterable ingredient list. Columns:

| Column | Content |
|--------|---------|
| Ingredient Name | Canonical name from catalog |
| Aisle | Grocery aisle assignment |
| Nutrients | Checkmark or dash |
| Density | Checkmark or dash |
| Portions | Count of defined portions |
| Issues | Human-readable: "missing nutrition", "cup unresolvable", etc. |

**Default sort:** Most issues first, then by recipe count (ingredients used in more recipes surface higher). Filterable by: text search, missing nutrition, missing density, has unresolvable units, aisle.

**Keybindings:**

| Key | Action |
|-----|--------|
| Arrow keys | Scroll list |
| Enter | Open ingredient detail |
| `/` | Filter by text |
| `n` | Create new catalog entry |
| `s` | Jump to USDA search |
| `q` | Quit |

**CLI shortcuts preserved:**
- `bin/nutrition "Cream cheese"` — jump directly to ingredient detail screen.
- `bin/nutrition --coverage` — print summary stats to stdout and exit (no TUI, for scripting).
- `bin/nutrition --missing` — removed, replaced by dashboard.

## Ingredient Detail Screen

Three-panel layout showing everything relevant to one ingredient.

**Left panel — Nutrients:**

Standard FDA label format showing all 11 nutrient values and the basis grams. Dash if no nutrition data exists.

**Right panel, top — Density & Portions:**

Density displayed as `Xg per Y unit` (e.g., `160g per 1 cup`). Portions displayed as a name/grams table.

**Right panel, bottom — Recipe Units:**

Replaces "Unit coverage for recipes." Shows each unit used in actual recipes for this ingredient, with resolution status and method:

```
(bare count)  ✓  via ~unitless
g             ✓  weight
cup           ✓  via density
stalk         ✗  no portion
```

This tells you *how* each unit resolves (or *why* it fails), not just OK/MISSING.

**Keybindings:**

| Key | Action |
|-----|--------|
| `e` | Edit sub-menu (nutrients / density / portions) |
| `u` | USDA import |
| `a` | Edit aisle (selector from existing aisle values) |
| `l` | Edit aliases |
| `r` | Edit sources |
| `Ctrl+S` or `w` | Save to YAML |
| `Esc` | Back to dashboard (confirm if unsaved changes) |

## USDA Import Flow

Two-phase: nutrients first (automatic), portions second (manual with reference data).

### Phase 1 — Search & Import Nutrients

1. Search prompt pre-filled with ingredient name, editable, Escape to cancel.
2. Paginated results list with nutrient previews, arrow-key navigation.
3. Enter to select — fetches full detail and immediately imports:
   - All nutrient values (overwriting any existing)
   - Source record (auto-created: type, dataset, FDC ID, description)
4. Left panel updates immediately. No separate review step — edit later if needed.

### Phase 2 — Density & Portions Reference

After nutrient import, a USDA Reference panel appears showing the raw portion data:

| # | modifier | grams | amount | each |
|---|----------|-------|--------|------|
| 1 | cup, chopped | 160.0 | 1.0 | 160.0 |
| 2 | medium (2-1/2" dia) | 110.0 | 1.0 | 110.0 |
| ... | | | | |

The "each" column is `grams / amount` — handles cases like ground beef where `oz` has `amount=4, grams=113`.

**Auto-density:** The tool picks the largest volume-based entry as density, updates the density panel, and highlights which USDA row it chose. User can accept, pick a different row, or edit manually.

**Portions stay manual.** The reference panel is read-only. User adds portions via the normal edit flow, using the USDA data as a visual reference.

### USDA Modifier Filtering

The reference panel excludes noise:

| Pattern | Action |
|---------|--------|
| Weight units (`oz`) | Filter out — already handled by weight conversion |
| Regulatory (`NLEA serving`, `serving packet`) | Filter out |
| Variety names (`cherry`, `Italian tomato`) | Filter out |

Everything else is shown. Parenthetical annotations (dimensions, weight equivalents) are stripped for the clean display but the gram weight is preserved.

### Density Candidate Classification

When auto-picking density, the tool considers:

| USDA modifier pattern | Treatment |
|----------------------|-----------|
| Simple volume (`cup`, `tbsp`, `tsp`) | Direct density candidate |
| Volume + prep (`cup, chopped`, `cup grated`) | Density candidate — strip prep qualifier, use gram weight |

Among candidates, pick the one with the largest gram weight (most precise measurement). Display which entry was chosen.

## Navigation & Escape Handling

Universal rule: **Escape always goes back one level, never traps you.**

```
Dashboard
  ├── / filter → Escape clears filter
  ├── Enter → Ingredient Detail
  │     ├── e → Edit sub-menu
  │     │     ├── nutrients → inline editor → Escape back to sub-menu
  │     │     ├── density → inline editor → Escape back to sub-menu
  │     │     └── portions → list editor → Escape back to sub-menu
  │     │     └── Escape back to detail
  │     ├── u → USDA search → results → select → reference panel
  │     │     └── Escape at any point → back to detail
  │     ├── a → aisle selector → Escape back to detail
  │     ├── l → aliases editor → Escape back to detail
  │     ├── r → sources editor → Escape back to detail
  │     └── Escape → back to dashboard
  └── q → quit
```

No free-text prompts that trap. All text input is an inline field that responds to Escape. If you start typing a search and change your mind, Escape cancels it.

Saving is explicit. Edits are held in memory. The detail screen shows a "modified" indicator for unsaved changes. `Ctrl+S` or `w` writes to YAML. Escaping with unsaved changes triggers a yes/no/cancel confirmation.

No batch iteration. The old `--missing` mode force-marched through ingredients in sequence. The dashboard replaces this — pick what to work on, come back when done.

## Data Pipeline Fixes

### NutritionCalculator: silent skip for entries without nutrients

Remove the `warn` call for entries with nil/invalid nutrients. These are valid catalog entries (aisle-only) that don't have nutrition yet. Silently skip them in calculation; surface them as "missing nutrition" in the dashboard.

### Clean up bogus portion formats

Entries like `cup chopped: 128.0` in carrots are portions that would never match a parsed unit. Migrate these to density entries and remove the bogus portion. Apply to any other "volume + prep" entries found in the catalog.

### Aisle editing in the TUI

Aisle is part of the catalog but was never editable in `bin/nutrition`. Add aisle editing via the `a` keybind on the detail screen — present existing aisle values as selectable choices, with an option to type a new one.

### Source auto-tracking

USDA imports auto-record source metadata (type, dataset, FDC ID, description). Manual source entry is available for non-USDA data (product labels, etc.) via the `r` keybind — free-form fields for type, brand/name, and optional note.

## Out of Scope

- **Auto-importing portions from USDA.** Modifier formats are too inconsistent. Manual curation with reference data.
- **Unit conversion during aggregation.** Shopping list concern, not nutrition tool.
- **Web-based nutrition editing.** Terminal tool only. Webapp consumes YAML via `rake catalog:sync`.
- **Rewriting the ingredient parser.** Parser is fine. USDA mess is handled at import time.
- **Batch USDA import.** Data needs human review. Dashboard enables efficient one-at-a-time processing.
- **The `--missing` flag.** Replaced by dashboard.
