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

## Volume conversions

If recipes measure this ingredient by volume (cups, tbsp, ml), set a
conversion: how much does one unit of volume weigh? For example,
"1 cup = 120 g". This lets the app convert volume quantities to grams
for nutrition calculations.

Without a volume conversion, volume-measured quantities can't be calculated.

## Unit weights

For ingredients measured by count ("2 eggs", "1 avocado"), set a unit
weight: how many grams does one unit weigh? Click **+ Add unit weight**
to define named units (e.g., "large", "stick").

## Unit aliases

If your recipes use shorthand or alternate names for units (e.g., "T" for
tablespoon, "oz" for ounces), add them as aliases so the app recognizes them.

## USDA search

If a [USDA API key]({{ site.baseurl }}/settings/) is configured, an inline
search panel appears in the editor. Search by ingredient name, click a
result to import its nutrient values, volume conversions, and unit weights automatically.

USDA data imports as a starting point — review and adjust values as needed
before saving.

## Saving

Click **Save** to apply changes. Updated nutrition data takes effect on all
recipes that use this ingredient.
