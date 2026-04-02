---
layout: page
title: Ingredient Catalog
section: ingredients
prev: /ingredients/
next: /ingredients/nutrition-data/
---

# Ingredient Catalog

The Ingredients page lists every ingredient referenced across your recipes
and QuickBites. Entries are created automatically when you save a recipe —
you don't add ingredients here manually.

## Search

Use the search bar at the top to filter by name. Partial matches work.

## Filter pills

The pills below the search bar let you filter the list and see counts at a
glance:

| Pill | Shows |
|------|-------|
| **All** | Every ingredient |
| **Complete** | Ingredients with full nutrition data and all conversions in place |
| **Custom** | Ingredients where you've added or edited catalog data |
| **No Aisle** | Ingredients without a grocery aisle assigned |
| **No Nutrition** | Ingredients missing nutrient values |
| **No Density** | Ingredients missing a volume-to-weight conversion |
| **Not Resolvable** | Ingredients that can't be used for nutrition calculations (see below) |

Click a pill to filter the table. Click it again to go back to All.

## What "resolvable" means

An ingredient is resolvable if the app can calculate its nutrition contribution
to a recipe. That requires:

1. A catalog entry with at least some nutrient data
2. A way to convert the recipe's unit to grams (either the unit is weight-based,
   or a density value is set)

Ingredients with only count-based quantities (e.g., "2 eggs") are resolvable
if the catalog entry has a per-item portion defined.
