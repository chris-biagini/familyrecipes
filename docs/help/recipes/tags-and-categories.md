---
layout: page
title: Tags & Categories
section: recipes
prev: /recipes/cross-references/
next: /recipes/nutrition/
---

# Tags & Categories

## Categories

Each recipe belongs to one category. Categories appear as section headings
on the homepage and the Menu page.

Set a recipe's category in its front matter:

```
Category: Breakfast
```

Or by choosing a category when you create the recipe (the graphical editor
has a dropdown). If the front matter category and the chosen category differ,
the front matter value wins.

### Managing categories

On the homepage, click **Edit Categories** to open the category editor:

- **Reorder**: drag categories up or down to change the order they appear on the homepage
- **Rename**: click a category name to edit it — all recipes in that category update automatically
- **Add**: type a name in the input at the bottom and press Enter or click the + button
- **Delete**: click the × on a category to remove it — its recipes move to Miscellaneous

## Tags

Recipes can have multiple tags. Tags appear as clickable pills on the recipe
page and are used to filter suggestions in the dinner picker.

Set tags in front matter:

```
Tags: quick, vegetarian, weeknight
```

Tags are:
- **Single-word** only: `[a-zA-Z-]`. Hyphens are allowed (`gluten-free`).
- **Comma-separated** in front matter.
- **Stored lowercase** — `Quick` and `quick` are the same tag.

### Managing tags

On the homepage, click **Edit Tags** to see all tags across your recipes.
Add new tags or delete unused ones. Renaming a tag updates all recipes
that use it.

### Smart tag decorations

Some tags get automatic emoji and color treatment:

| Tag examples | Decoration |
|---|---|
| `vegetarian`, `vegan`, `gluten-free` | green dietary badge |
| `spicy`, `hot` | amber heat badge |
| `italian`, `mexican`, `thai` | cuisine badge |
| `quick`, `30-minutes` | blue speed badge |

Smart tag decorations can be turned off in [Settings]({{ site.baseurl }}/settings/).

### Filtering by tag

On a recipe page, click any tag pill to open the recipe search pre-filtered
to that tag.
