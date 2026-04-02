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

On the homepage, click the **edit** button next to Categories to open the
category editor:

- **Reorder**: use the arrow buttons to move categories up or down
- **Rename**: click a category name to edit it — all recipes in that category update automatically
- **Delete**: click the × on a category to remove it — its recipes move to Miscellaneous

## Tags

Recipes can have multiple tags. Tags appear as clickable pills on the recipe
page and can be used to filter the homepage.

Set tags in front matter:

```
Tags: quick, vegetarian, weeknight
```

Tags are:
- **Single-word** only — letters and hyphens (`gluten-free` is fine, but no spaces).
- **Comma-separated** in front matter.
- **Stored lowercase** — `Quick` and `quick` are the same tag.

### Managing tags

On the homepage, click the **edit** button next to Tags to manage your tags.
Renaming a tag updates every recipe that uses it. You can also delete tags
you no longer need. New tags are created by adding them to a recipe's front
matter.

### Smart tag decorations

Some tags get automatic emoji and color treatment:

| Tag examples | Decoration |
|---|---|
| `vegetarian`, `vegan`, `plant-based` | green plant-based badge |
| `gluten-free`, `dairy-free`, `keto` | amber dietary restriction badge |
| `italian`, `mexican`, `thai` | cuisine flag badge |
| `quick`, `easy`, `weeknight` | blue effort/speed badge |
| `grilled`, `braised`, `slow-cooker` | rose cooking method badge |
| `holiday`, `comfort-food`, `thanksgiving` | purple occasion/season badge |

Smart tag decorations can be turned off in [Settings]({{ site.baseurl }}/settings/).

### Filtering by tag

On a recipe page, click any tag pill to open the recipe search pre-filtered
to that tag.
