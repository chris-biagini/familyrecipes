---
layout: page
title: Markdown Import
section: import-export
prev: /import-export/ai-import/
next: /import-export/export/
---

# Markdown Import

You can import recipes directly as Markdown files, or import a ZIP archive
exported from another familyrecipes installation.

## How to import

On the homepage, click **Import**. A file picker opens.

Select one or more `.md`, `.txt`, or `.zip` files to import.

## Single files (`.md` / `.txt`)

Each file is imported as one recipe. The file must use the
[recipe format]({{ site.baseurl }}/recipes/format/). The filename is used
as the recipe title if no `#` title is present.

## ZIP archives

A `.zip` file is expected to come from familyrecipes [Export]({{ site.baseurl }}/import-export/export/).
It can contain multiple recipe files, the ingredient catalog, and meal plan state.

You can also assemble a ZIP manually from `.md` recipe files if you're
migrating from another system.

## What happens on import

- Recipes are created or updated based on their title.
- Categories and tags in the front matter are created if they don't exist.
- Nutrition catalog data in the ZIP is merged with existing entries —
  existing entries are not overwritten.
- Meal plan selections are restored if the ZIP includes them.

## Conflicts

If a recipe with the same title already exists, the imported version
replaces it. There's no merge — the existing recipe is overwritten.
