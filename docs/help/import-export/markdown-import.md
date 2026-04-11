---
layout: page
title: Markdown Import
section: import-export
prev: /import-export/ai-import/
next: /import-export/export/
---

# Markdown Import

You can import recipes directly as Markdown files, or import a ZIP archive
exported from another mirepoix installation.

## How to import

On the homepage, click **Import**. A file picker opens.

Select one or more `.md`, `.txt`, `.text`, or `.zip` files to import.

## Single files (`.md` / `.txt`)

Each file is imported as one recipe. The file must use the
[recipe format]({{ site.baseurl }}/recipes/format/) and include a
`# Title` heading — files without one will fail to import.

## ZIP archives

A `.zip` file is expected to come from mirepoix [Export]({{ site.baseurl }}/import-export/export/).
It can contain recipe files, QuickBites, the ingredient catalog, and
aisle/category ordering.

You can also assemble a ZIP manually from `.md` recipe files if you're
migrating from another system.

## What happens on import

- Recipes are created or updated based on their title.
- QuickBites are imported if the ZIP includes them.
- Categories and tags from front matter are created if they don't exist.
- Ingredient catalog data in the ZIP replaces existing entries with the
  same name.
- Aisle and category ordering is restored.

## Conflicts

If a recipe with the same title already exists, the imported version
replaces it — there's no merge, the existing recipe is overwritten.
