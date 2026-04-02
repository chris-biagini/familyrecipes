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

Fill in the nutrient values for a given weight of the ingredient (the
default is 100 g, but you can change it). The app tracks calories, fat,
saturated fat, carbohydrates, sugar, fiber, protein, and sodium.

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

## Ingredient aliases

If the same ingredient goes by different names in your recipes (e.g.,
"cilantro" and "coriander," or "scallions" and "green onions"), add the
alternate names as aliases. The app will treat them as the same ingredient
for grocery and nutrition purposes.

## USDA search

If a [USDA API key]({{ site.baseurl }}/settings/) is configured, an inline
search panel appears in the editor. Search by ingredient name, click a
result to import its nutrient values, volume conversions, and unit weights automatically.

USDA data imports as a starting point — review and adjust values as needed
before saving.

If the USDA data includes multiple density measurements (different ways to
convert volume to weight), the editor shows them as options so you can pick
the one that fits best.

## Omit from lists

Check **Omit from grocery list and nutrition data** if you don't want this
ingredient tracked at all — useful for things like "water" or "ice" that
don't need to be on a shopping list or in nutrition calculations.

## Recipe check

Under the Conversions section of the editor, a **Recipe Check** list shows
every unit your recipes use for this ingredient and whether each one can be
converted to grams. This helps you spot gaps — if a recipe calls for "1
bunch" and there's no conversion for "bunch," it'll be flagged here.

## Derived conversions

After entering a volume conversion (e.g., 1 cup = 120 g), the editor
automatically shows what that works out to for other volume units (tablespoons,
teaspoons, etc.). This is a quick way to sanity-check your numbers.

## Saving

Click **Save** to apply changes. Updated nutrition data takes effect on all
recipes that use this ingredient.

## Resetting an ingredient

If you've customized an ingredient and want to go back to the built-in
catalog data, click **Reset to built-in** at the bottom of the editor.
This removes your custom values and restores the defaults.
