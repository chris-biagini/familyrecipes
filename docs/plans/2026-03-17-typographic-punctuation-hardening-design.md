# Typographic Punctuation Hardening

## Problem

The app's "store ASCII, display typographic" pattern works well for vulgar
fractions and en-dashes in quantity ranges, but has two gaps:

1. **Em-dashes in quantities** — `normalize_quantity` handles en-dash (U+2013)
   but not em-dash (U+2014). A user pasting "1—2 cups" from a recipe blog gets
   a silently unparsed quantity.

2. **Smart apostrophes/quotes in string comparisons** — Three lookup paths use
   exact string matching or `.downcase` comparison without normalizing
   typographic apostrophes (U+2018/U+2019) and quotes (U+201C/U+201D) to their
   ASCII equivalents. When a user's phone autocorrects a straight apostrophe to
   a curled one, lookups silently fail.

## Non-goals

- **ASCII-ifying all prose on import.** Titles, descriptions, instructions, and
  ingredient names are stored as-authored. SmartyHTML already handles display
  for instructions/descriptions. Normalizing all text is more work than the
  failure modes justify.
- **Normalizing dashes in prose.** Em-dashes in instructions are legitimate
  grammatical punctuation. Only quantity ranges need dash normalization.
- **Normalizing exotic Unicode** (ellipsis, non-breaking spaces, etc.). The
  practical failure surface is apostrophes and quotes from phone autocorrect.

## Design

### 1. Em-dash fix in quantity normalization

**File:** `lib/familyrecipes/ingredient.rb`

Change line 25 from:

```ruby
result.tr("\u2013", '-')
```

to:

```ruby
result.tr("\u2013\u2014", '--')
```

This converts both en-dashes and em-dashes to ASCII hyphens in quantity
strings, so "1—2 cups" parses the same as "1-2 cups" and "1–2 cups".

**Test:** Add a case in `test/ingredient_test.rb` for em-dash normalization.

### 2. En-dash display for ranges (no work needed)

En-dash display is already implemented in all three range display paths:

- `Ingredient#formatted_quantity` — `app/models/ingredient.rb:47`
- `RecipesHelper#scaled_quantity_str` — `app/helpers/recipes_helper.rb:174`
- `recipe_state_controller.js` — line 178

The only hyphen-in-ranges path is `RecipeSerializer#format_numeric_quantity`,
which correctly uses ASCII for storage/export. No changes needed.

### 3. Harden string comparisons against smart punctuation

#### Shared normalization

A small `normalize_for_comparison` helper (Ruby) and `normalizeForSearch` (JS)
that converts smart apostrophes and quotes to their ASCII equivalents:

- `'` `'` (U+2018, U+2019) → `'` (U+0027)
- `"` `"` (U+201C, U+201D) → `"` (U+0022)

Applied to both sides of every comparison — the indexed/stored value and the
query value.

#### 3a. IngredientResolver

**File:** `app/services/ingredient_resolver.rb`

Normalize ingredient names when building the lookup hash (both the
case-sensitive and case-insensitive indexes) and when querying via `find_entry`.
This ensures "baker's chocolate" (curled) matches "baker's chocolate" (straight)
in the catalog.

**Test:** Lookup succeeds with curled apostrophe when catalog has straight, and
vice versa.

#### 3b. CrossReferenceUpdater

**File:** `app/services/cross_reference_updater.rb`

When searching for `@[Old Title]` in markdown source, normalize both the
pattern and the source text for matching purposes. The replacement inserts the
new title as-given (no normalization on the output side).

**Test:** Rename succeeds when stored markdown has curled apostrophe but the
old title has straight, and vice versa.

#### 3c. Search overlay

**File:** `app/javascript/controllers/search_overlay_controller.js`

Add a `normalizeForSearch` function. Apply it to both the pre-indexed recipe
data (titles, descriptions, ingredient names) and the user's search query
before substring matching.

**Test:** Search for "grandma's" (straight) finds "Grandma's Cookies"
(curled), and vice versa.
