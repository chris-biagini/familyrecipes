---
layout: page
title: Nutrition
section: recipes
prev: /recipes/tags-and-categories/
next: /menu/
---

# Nutrition

familyrecipes can display per-serving nutrition facts under each recipe,
calculated from the ingredient quantities and your nutrition catalog data.

## Enabling nutrition display

In [Settings]({{ site.baseurl }}/settings/), turn on **Display nutrition
information under recipes**. Nutrition will appear under any recipe that has
complete enough data to calculate it.

## How it's calculated

Each ingredient in the recipe is looked up in the [ingredient catalog]({{ site.baseurl }}/ingredients/catalog/).
If the catalog has nutrition data for that ingredient, the amounts are scaled
to the recipe's quantity and summed across all ingredients.

The total is divided by the number of servings to get per-serving values. If
the recipe has a `Serves:` line, that's used. Otherwise, the number from
`Makes:` is used (so "Makes: 12 pancakes" would divide by 12).

## Partial and missing data

If some ingredients can't be fully calculated, the nutrition label shows what
it can and notes which ingredients are affected.

- **Missing**: no catalog entry for this ingredient — nutrition can't be calculated for it
- **Partial**: the catalog entry exists, but the recipe's unit can't be converted to grams (e.g., "1 bunch" without a defined weight for that unit)
- **Skipped**: the ingredient has no quantity (e.g., just "Salt" with no amount) — it's left out of the calculation entirely

A recipe with all ingredients cataloged and fully convertible shows a complete
nutrition label. A recipe with no usable data shows nothing (even if the
setting is on).

## Adding nutrition data

See [Adding nutrition data]({{ site.baseurl }}/ingredients/nutrition-data/)
in the Ingredients section.
