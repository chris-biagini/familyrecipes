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

The total is then divided by the number of servings (`Serves:` front matter)
to get per-serving values.

## Partial and missing data

If some ingredients don't have catalog entries, the nutrition display shows
what it can and notes which ingredients are missing.

- **Missing**: no catalog entry for this ingredient — nutrition can't be calculated
- **Partial**: the catalog entry exists but is missing some nutrients

A recipe with all ingredients cataloged and complete data shows a full
nutrition label. A recipe with no data shows nothing (even if the setting is on).

## Adding nutrition data

See [Adding nutrition data]({{ site.baseurl }}/ingredients/nutrition-data/)
in the Ingredients section.
