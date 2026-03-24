# bin/nutrition Overhaul — Design

## Motivation

The `bin/nutrition` CLI tool curates the ingredient catalog via the USDA
FoodData Central API. Four batches of trial runs (commits `5d630ba`–`6c672fc`)
and a recipe validation study (`docs/plans/2026-03-02-ingredient-catalog-recipe-validation.md`)
exposed real friction points: search results capped at 10 with no pagination,
no way to edit density/portions without hand-editing YAML, automatic density
picks that sometimes choose the wrong unit, no error handling on API calls, and
Ruby style violations throughout. GH #140 catalogues all eight issues.

This overhaul addresses the friction, extracts a reusable USDA client for
future web integration, and adds TUI creature comforts via the TTY gem suite.

## Scope

**In scope:**

1. Extract `FamilyRecipes::UsdaClient` — reusable for future web integration
2. Full TTY suite for TUI comfort (tty-prompt, tty-table, tty-spinner, tty-box, pastel)
3. Search pagination (page forward/back through USDA results)
4. Interactive density/portion/nutrient editing in the review loop
5. Smarter default search query (keep all keywords, not just pre-parenthetical)
6. Alias UI improvements (multi-select with tty-prompt)
7. API error handling (custom exceptions, colored messages)
8. Dead code removal and Ruby style cleanup

**Out of scope:**

- `--list`, delete entry, rename/move entry CLI capabilities
- Handoff polish (better `--help`, discoverability)
- Aisle-driven or name-parsing alias auto-suggestions
- Writing to the database (stays YAML-only; `rake catalog:sync` pushes to DB)

## 1. USDA Client Extraction

**File:** `lib/familyrecipes/usda_client.rb`
**Module:** `FamilyRecipes::UsdaClient`

This class owns all USDA FoodData Central API interaction: search, fetch,
nutrient extraction, portion classification, and error handling. No TUI
concerns — pure data in, data out. Both `bin/nutrition` and a future web
USDA integration consume this class.

### Interface

```ruby
client = FamilyRecipes::UsdaClient.new(api_key:)

# Search with pagination
results = client.search("flour", page: 0, page_size: 10)
# → { foods: [...], total_hits: 342, total_pages: 35, current_page: 0 }

# Fetch full detail
detail = client.fetch(fdc_id: 168913)
# → { fdc_id:, description:, data_type:, nutrients: {}, portions: { volume: [], non_volume: [] } }
```

### What moves out of bin/nutrition

- `search_usda`, `fetch_usda_detail` (API calls)
- `extract_nutrients` (USDA response → our nutrient hash)
- `classify_portions`, `volume_unit?`, `normalize_volume_unit` (portion processing)
- `NUTRIENT_MAP`, `VOLUME_UNITS` (constants)
- `load_api_key` (API key resolution from env/`.env`)

### What stays in bin/nutrition

- All interactive code (menus, prompts, display)
- `pick_density`, `build_non_volume_portions` (depend on TUI for overrides)
- Data I/O (`load_nutrition_data`, `save_nutrition_data`)
- Coverage/missing analysis

### Error handling

Custom exception hierarchy in `UsdaClient`:

```
UsdaClient::Error
  ├── NetworkError     (timeouts, DNS, connection refused)
  ├── RateLimitError   (429 — includes retry_after when provided)
  ├── AuthError        (401/403 — bad API key)
  ├── ServerError      (5xx)
  └── ParseError       (malformed JSON)
```

The TUI layer rescues these and displays colored messages:

- **NetworkError** → red "Connection failed — check your internet"
- **RateLimitError** → yellow "Rate limited — wait N seconds and try again"
- **AuthError** → red "Invalid API key — check USDA_API_KEY in .env"
- **ServerError** → yellow "USDA servers returned an error — try again later"
- **ParseError** → red "Unexpected response from USDA"

All non-fatal in the interactive loop — the user stays in the prompt and can
retry or search again.

### Data model alignment

The YAML file and the database share the same data model. The YAML ↔ AR
attribute bridge (currently `catalog_attrs` in `catalog_sync.rake`) should be
extracted so both the rake task and `bin/nutrition` can call it. If the model
schema evolves, there's one place to update.

`UsdaClient` returns data shaped to our canonical model (nutrients hash with
`basis_grams`, classified portions, source metadata with USDA provenance).
Both the CLI (writing YAML) and the future web tool (calling
`IngredientCatalog.assign_from_params`) consume the same shape.

`build_lookup` in `bin/nutrition` remains a YAML-based mirror of
`IngredientCatalog.lookup_for` — making `bin/nutrition` query the DB just for
lookups would add a Rails boot dependency for marginal benefit. Aliases flow
through both paths identically.

## 2. TUI Gems

All gems in the `:development` Gemfile group — `bin/nutrition` is a dev tool,
not production code. The `UsdaClient` has no TUI dependency, so web
integration requires no extra gems.

| Gem | Replaces | Purpose |
|-----|----------|---------|
| `tty-prompt` | All `print`/`$stdin.gets` loops, manual menu numbering | Arrow-key menus, multi-select, confirm dialogs, text input with defaults |
| `tty-table` | Printf-style nutrient display, search result alignment | Formatted tables for nutrients, search results, coverage reports |
| `tty-spinner` | Nothing (new) | Loading indicator during USDA API calls |
| `tty-box` | Nothing (new) | Framed panels for entry display |
| `pastel` | Nothing (comes with tty-prompt) | Color coding: green=OK, red=MISSING, yellow=incomplete |

### Interaction model change

**Before (manual I/O):**
```
Results:
  1. [168913] Wheat flour, white, all-purpose, enriched, unbleached
         110 cal | 0g fat | 23g carbs | 4g protein
  s. Search again
  q. Quit

Pick (1-10): _
```

**After (tty-prompt):**
```
┌ USDA Search: "flour" ─── Page 1 of 12 (116 results) ┐
│                                                        │
│  ‣ Wheat flour, white, all-purpose, enriched           │
│    110 cal · 0g fat · 23g carbs · 4g protein           │
│    Wheat flour, white, bread, enriched                  │
│    120 cal · 1g fat · 22g carbs · 4g protein           │
│    ...                                                  │
│    Next page →                                          │
│    Search again                                         │
│    Quit                                                 │
└────────────────────────────────────────────────────────┘
```

Arrow keys to navigate, Enter to select. No typing numbers. Pagination items
appear inline in the menu.

## 3. Search Pagination

The FDC API natively supports `pageNumber` (0-indexed), `pageSize` (max 200),
and returns `totalHits`, `totalPages`, `currentPage`.

**In `UsdaClient`:** The `search` method accepts `page:` and `page_size:`
keyword arguments and returns pagination metadata alongside results.

**In the TUI layer:** `search_and_pick` holds pagination state in a loop.
The tty-prompt `select` menu includes all food results plus:

- `"Next page →"` (when not on last page)
- `"← Previous page"` (when not on first page)
- `"Search again"`
- `"Quit"`

The header shows page position and total results via a tty-box panel. The
tty-spinner runs during each API call. Page size stays at 10.

### Smarter default search query

The current `name.sub(/\s*\(.*\)/, '').strip` drops the parenthetical, so
`Flour (whole wheat)` searches for just `Flour`. Instead, strip punctuation
and keep all keywords:

```ruby
# Before: "Flour (whole wheat)" → "Flour"
# After:  "Flour (whole wheat)" → "Flour whole wheat"
name.gsub(/[(),]/, ' ').squeeze(' ').strip
```

The user can still type a custom query at the search prompt.

## 4. Density Picker

**No change to auto-select logic.** `pick_density` continues to choose the
volume portion with the highest gram weight (cup when available). The
`NutritionCalculator` derives smaller units (tsp, tbsp) from the stored
density via a grams-per-mL ratio (`derive_density` in
`lib/familyrecipes/nutrition_calculator.rb`), so storing the cup value gives
the best precision — less rounding error at larger quantities.

The edit menu's density submenu lets the user override if the auto-pick is
wrong (e.g., USDA only provides a tsp portion), but no interactive chooser
during initial import.

## 5. Portion & Nutrient Editing

The edit menu currently has 2 options (re-import from USDA, sources). Expand:

```
Edit Cinnamon:
  ‣ Density         (1 cup = 125.0g)
    Portions        (2 defined)
    Nutrients       (per 100g basis)
    Re-import from USDA
    Sources         (1 source)
    Done editing
```

### Density submenu

- Re-pick from USDA portions (auto-selects highest-gram as usual)
- Enter custom values (grams / volume / unit)
- Remove density

### Portions submenu

```
Portions for Cinnamon:
  stick = 113.0g
  ~unitless = 5.0g

  ‣ Add portion
    Edit portion
    Remove portion
    Done
```

- Add: prompt for name + gram weight. Offer `~unitless` as a shortcut for
  bare-count ingredients.
- Edit: select existing → edit gram weight
- Remove: select existing → confirm

### Nutrients submenu

- Display as a tty-table
- Select a nutrient to edit → enter new value
- Useful for small corrections without a full re-import

All submenus return to the edit menu, preserving the review loop.

## 6. Alias UI

**No auto-pattern generation.** No aisle-driven suggestions, no name-parsing
heuristics. These don't generalize as the catalog expands.

**Keep existing suggestion logic:**

- Parenthetical decomposition: `Flour (all-purpose)` → `Flour`, `All-purpose flour`
- Qualifier flip: `Sugar (brown)` → `Brown sugar`

**TUI upgrade:** Replace comma-separated text input with a tty-prompt
**multi-select**. Existing aliases pre-checked, suggestions shown unchecked,
plus "Add custom..." for freeform entry.

```
Select aliases for Flour (all-purpose):
  ◉ AP flour         (existing)
  ◉ Plain flour      (existing)
  ○ Flour            (suggested)
  ○ All-purpose flour (suggested)
  Add custom...
```

Check/uncheck with space, Enter to confirm.

## 7. Dead Code & Ruby Style Cleanup

### Remove

- `resolve_name` — no-op stub that returns its argument unchanged. Remove the
  method and its call site in the main dispatcher.

### Clean up

- `edit_sources` — already USDA-only in practice. Rename the generic
  "Add source" label to "Add USDA source" for clarity.
- `format_source` label/other branches — keep for display of legacy data.

### Ruby style (per CLAUDE.md)

- `build_lookup` — `each` + hash mutation → `each_with_object`
- `find_needed_units` — 3-level nested `each` → `flat_map` + `filter_map`
- `save_nutrition_data` — `each_value` with mutation → cleaner transforms
- Other `each` + accumulator patterns fixed during the rewrite

These get fixed as part of the rewrite, not a separate pass.
