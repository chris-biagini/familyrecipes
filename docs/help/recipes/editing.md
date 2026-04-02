---
layout: page
title: Adding & Editing
section: recipes
prev: /recipes/format/
next: /recipes/cooking/
---

# Adding & Editing Recipes

## Adding a recipe

From the homepage, click **Add Recipe** in the top-right action row.
An editor dialog opens with a starter template.

Fill in the template, then click **Save**. You'll be taken directly to the
new recipe page.

## Two editors, same result

The editor has two modes — switch between them with the toggle at the top of
the dialog. Both produce identical recipes; choose whichever you prefer.

**Plaintext editor** — a text editor with syntax highlighting. Write the
recipe in the [recipe format]({{ site.baseurl }}/recipes/format/).
Good if you're comfortable with Markdown or pasting from another source.

**Graphical editor** — a form-based interface. Fill in title, description,
and front matter fields; add steps and ingredients with buttons.
No Markdown knowledge needed.

You can switch modes at any point — the editor converts back and forth
without losing anything.

## AI import

If an [Anthropic API key]({{ site.baseurl }}/settings/) is configured, an
**AI Import** button appears on the homepage. Click it, paste any recipe
text (from a website, a photo, dictated notes — anything), and Claude will
parse it into the recipe format and open it in the editor for review.

Always review the result before saving. AI import is a fast starting point,
not a finished import.

## Editing an existing recipe

Open the recipe, then click **Edit** below the recipe header. The same
editor dialog opens with the recipe's current content.

Changes are saved when you click **Save** and take effect immediately.

## Deleting a recipe

Open the recipe editor, scroll to the bottom of the editor dialog, and click
**Delete**. You'll be asked to confirm. Deletion cannot be undone.

Deleting a recipe removes it from the recipe list, from the menu, and from
the grocery list. Any recipes that cross-reference the deleted recipe will
show a broken reference notice.
