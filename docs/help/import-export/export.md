---
layout: page
title: Export
section: import-export
prev: /import-export/markdown-import/
next: /settings/
---

# Export

Export downloads all your kitchen data as a ZIP file.

## How to export

On the homepage, click **Export All Data**. Your browser downloads a
`.zip` file immediately.

## What's included

- **All recipes** — one `.md` file per recipe, in the [recipe format]({{ site.baseurl }}/recipes/format/)
- **Ingredient catalog** — nutrition data, aisle assignments, unit aliases
- **Meal plan state** — current menu selections, grocery list state, pantry history

## What's not included

- API keys — these are stored encrypted and are not exported. You'll need
  to re-enter your USDA and Anthropic API keys after importing on a new install.
- User accounts — authentication is handled externally (Authelia) and is
  not part of the export.

## Using the export

The ZIP is [re-importable]({{ site.baseurl }}/import-export/markdown-import/)
on any familyrecipes installation. Use it for:

- **Backups** — keep a copy of your data outside the app
- **Migration** — move to a new server or installation
- **Editing offline** — the `.md` files are plain text and can be edited
  in any text editor
