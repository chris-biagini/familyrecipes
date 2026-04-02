---
layout: page
title: Scaling
section: recipes
prev: /recipes/cooking/
next: /recipes/cross-references/
---

# Scaling Recipes

Click **Scale** in the recipe header to open the scaling panel.

## Preset buttons

Four preset buttons let you scale instantly:

| Button | What it does |
|--------|-------------|
| ½× | Halves all quantities |
| 1× | Returns to the original (default) |
| 2× | Doubles all quantities |
| 3× | Triples all quantities |

## Custom scale factor

Type any number into the input field. Fractions are accepted:

- `1.5` or `3/2` → one and a half times
- `0.75` → three-quarters
- `4` → four times the recipe

## What gets scaled

- Ingredient quantities
- The Makes / Serves line in the recipe header
- Numbers in step text marked with `*` (see below)

## What doesn't get scaled

Temperatures and times are not scaled by default. A recipe that says
"bake at 200°C for 30 minutes" will still say that at 2× — those values
don't change with batch size.

## Scalable quantities in step text

Numbers in step instructions can be made scalable by appending `*`:

```
Divide the dough into 8* equal pieces.
Pour about 60* g of batter per pancake.
```

At 2×, these render as 16 and 120 g respectively. Word numbers work too:
`eight*` scales the same as `8*`.

## Resetting

Click the **Reset** button next to the input, or click the 1× preset. The
scale factor returns to normal.
