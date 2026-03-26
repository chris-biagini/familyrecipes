---
layout: page
title: QuickBites
section: menu
prev: /menu/selecting-recipes/
next: /menu/dinner-picker/
---

# QuickBites

QuickBites are grocery bundles — a title plus a flat list of ingredients.
They're for things that aren't full recipes: snacks, breakfast staples,
pantry restocks, meal-prep items.

## How they appear on the Menu page

QuickBites appear in an indented **Quick Bites** zone beneath each
category's recipes. Check or uncheck them just like recipes.

Each zone has a small **edit** button that opens the QuickBites editor
focused on that category. There's also a global **Edit QuickBites** button
in the page header that opens all categories at once.

## Format

QuickBites are written in a simple text format, grouped by category:

~~~
## Snacks
- Apples and Honey: Apples, Honey
- Crackers and Cheese: Ritz crackers, Cheddar

## Breakfast
- Cereal and Milk: Rolled oats, Milk
- Toast and Butter: Bread, Butter
~~~

Each entry is `- Title: Ingredient, Ingredient, ...`. For a single-ingredient
bundle, you can use `- Title` without a colon:

~~~
## Produce
- Bananas
~~~

## Editing QuickBites

Click **Edit QuickBites** in the page header, or click the **edit** button
next to any category's Quick Bites zone. The editor opens with two modes:

- **Plaintext**: edit the text format directly
- **Graphical**: a card-based form for each category

Switch between modes at any time — the editor converts back and forth.

## On the grocery list

When a QuickBite is selected, its ingredients appear on the
[Groceries]({{ site.baseurl }}/groceries/how-it-works/) page and go through
the same inventory check process as recipe ingredients.
