# Structured Source Metadata for Nutrition Data

**Date:** 2026-02-20
**Status:** Approved

## Problem

The `source` field in `nutrition-data.yaml` is a flat string (`"USDA SR Legacy (FDC 175040)"` or `"King Arthur Flour All-Purpose"`). This makes it hard to machine-parse, hard to distinguish source types, and doesn't capture useful details like the USDA food description or brand vs. product.

## Design

Replace the flat `source: <string>` with a `sources:` array of typed objects.

### Source Types

**`usda`** — USDA FoodData Central entry:

```yaml
sources:
  - type: usda
    dataset: SR Legacy       # FDC dataset name (SR Legacy, Foundation, Survey FNDDS, etc.)
    fdc_id: 168913           # numeric FoodData Central ID
    description: "Wheat flour, white, all-purpose, enriched, unbleached"
    note: "Used for density"  # optional
```

**`label`** — Nutrition facts label from a specific product:

```yaml
sources:
  - type: label
    brand: King Arthur        # optional
    product: All-Purpose Flour # optional
    note: "12oz bag, 2024"    # optional
```

**`other`** — Catch-all for websites, cookbooks, databases, personal measurements:

```yaml
sources:
  - type: other
    name: "NCCDB"             # free-text source name
    detail: "Entry #12345"    # optional
    note: "Cross-referenced"  # optional
```

Every type has an optional `note` field.

### Multi-source example

```yaml
Bouillon:
  nutrients: { ... }
  sources:
    - type: label
      brand: Wegmans
      product: "Broth Concentrate, Chicken-Less Vegetarian"
    - type: usda
      dataset: SR Legacy
      fdc_id: 175040
      description: "Soup, chicken broth, ready-to-serve"
      note: "Cross-referenced for density"
```

## Migration

A one-time script (`bin/migrate-sources`) rewrites the existing YAML:

- **USDA entries** (matching `USDA SR Legacy (FDC \d+)`): Parse out the FDC ID, fetch the USDA description via the FoodData Central API, build a `type: usda` source.
- **Everything else**: Build a `type: label` source with the full string as `product`.
- Replace `source` key with `sources` array.
- Requires `USDA_API_KEY` (from `.env` or environment). API failures warn and omit `description` rather than aborting.

The migration script is one-time and can be deleted after use.

## Changes to `bin/nutrition`

- **USDA mode**: Build `sources` array from the API response already in memory (dataset from `dataType`, FDC ID, description). No extra API call.
- **Manual mode**: Split the current `"Brand/product (optional)"` prompt into separate `"Brand"` and `"Product"` prompts. Build `type: label` source.
- **Edit mode**: Replace the single source-string editor with an edit/add/remove flow for the `sources` array.
- **Display**: Print each source on its own line with a human-readable summary.

## What doesn't change

- `NutritionCalculator` — ignores source today, continues to.
- Templates — no user-facing display now (structured data makes it easy to add later).
- No backwards-compatibility code for the old `source` format.

## CLAUDE.md

Update the nutrition data documentation to show the `sources` schema.
