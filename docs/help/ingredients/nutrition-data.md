---
layout: page
title: Adding Nutrition Data
section: ingredients
prev: /ingredients/catalog/
next: /import-export/
---

# Adding Nutrition Data

Click any ingredient in the catalog to open the nutrition editor.

## Aisle assignment

At the top of the editor, set the **aisle** for this ingredient. This
determines where it appears on the grocery list. See
[Editing aisles]({{ site.baseurl }}/groceries/aisles/) for how aisles work.

## Nutrients

Fill in the nutrient values per 100 g of the ingredient. The app uses
calories, fat, saturated fat, carbohydrates, sugar, fiber, protein, and sodium.

You don't need to fill in all fields — partial data is used for whatever
nutrients are present.

## Density

If recipes use volume measurements for this ingredient (cups, tbsp, ml),
set a **density** (grams per ml). This lets the app convert volume quantities
to grams for nutrition calculations.

Without a density value, volume-measured quantities can't be calculated.

## Portions

For ingredients measured by count ("2 eggs", "1 avocado"), define a portion:
the weight in grams of one unit. Common portions (small / medium / large)
can be defined separately.

## Unit aliases

If your recipes use shorthand or alternate names for units (e.g., "T" for
tablespoon, "oz" for ounces), add them as aliases so the app recognizes them.

## USDA search

If a [USDA API key]({{ site.baseurl }}/settings/) is configured, an inline
search panel appears in the editor. Search by ingredient name, click a
result to import its nutrient values, density, and portions automatically.

USDA data imports as a starting point — review and adjust values as needed
before saving.

## Saving

Click **Save** to apply changes. Updated nutrition data takes effect on all
recipes that use this ingredient.
