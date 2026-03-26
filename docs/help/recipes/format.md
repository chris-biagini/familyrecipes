---
layout: page
title: Recipe Format
section: recipes
prev: /recipes/
next: /recipes/editing/
---

# Recipe Format

Recipes are plain text files using a simple Markdown format. You can write
them by hand or use the [graphical editor]({{ site.baseurl }}/recipes/editing/).

## Basic structure

A recipe has four parts: a title, an optional description, front matter
lines, and one or more steps.

~~~
# Pancakes

Fluffy weekend pancakes.

Category: Breakfast
Tags: quick, weekend
Makes: 12 pancakes
Serves: 4

## Mix the batter.

- Flour (all-purpose), 190 g
- Milk, 240 g
- Eggs, 2
- Butter, 2 tbsp: Melted.

Whisk dry ingredients. Add wet ingredients and stir until just combined.

## Cook the pancakes.

- Butter: A small pat per batch.

Pour about 60 g of batter per pancake onto a hot buttered pan.
Cook until bubbles form and edges look set. Flip and cook 1 minute more.

---

Try adding blueberries or chocolate chips to the batter.
~~~

## Title

The first line is the recipe title, marked with `#`.

## Description

An optional paragraph immediately after the title and before the front matter.
Appears as a subtitle on the recipe page.

## Front matter

Optional lines before the first step:

| Line | Example | Notes |
|------|---------|-------|
| `Category:` | `Category: Breakfast` | One category per recipe. Overrides the category chosen when creating. |
| `Tags:` | `Tags: quick, vegetarian` | Comma-separated. Single words only (`[a-zA-Z-]`). Stored lowercase. |
| `Makes:` | `Makes: 12 pancakes` | What the recipe produces. Used for nutrition scaling. |
| `Serves:` | `Serves: 4` | Number of servings. Used for per-serving nutrition. |

`Makes:` and `Serves:` can appear together if both make sense (e.g., "Makes: 1 loaf" and "Serves: 12").

## Steps

Each step starts with a `##` heading. The heading text is a short label —
it appears as a section header on the recipe page. The heading should end
with a period.

## Ingredients

Ingredient lines start with `- `. The format is:

```
- Name, quantity: prep note
```

- **Name** — the ingredient name. Matched against the ingredient catalog for grocery tracking.
- **Quantity** — optional. Examples: `190 g`, `2 tbsp`, `1-2`, `½ cup`.
- **Prep note** — optional. Appears in smaller text below the ingredient line.

Examples:

```
- Butter                          ← name only
- Flour (all-purpose), 190 g      ← name + quantity
- Eggs, 2                         ← name + count
- Butter, 2 tbsp: Melted.         ← name + quantity + prep note
```

Quantities from multiple recipes that use the same ingredient are combined
on the grocery list. "Flour, 190 g" in two recipes becomes one entry with 380 g total.

## Footer

An optional section after a `---` horizontal rule at the end of the recipe.
Good for notes, sources, and variations. Rendered as plain Markdown.

## Cross-references

You can embed another recipe's steps or link to it from prose.
See [Cross-references]({{ site.baseurl }}/recipes/cross-references/) for details.
