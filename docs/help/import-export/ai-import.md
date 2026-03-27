---
layout: page
title: AI Import
section: import-export
prev: /import-export/
next: /import-export/markdown-import/
---

# AI Import

AI Import uses Claude to parse recipe text and convert it into the
[recipe format]({{ site.baseurl }}/recipes/format/) automatically.

## Requirements

An Anthropic API key must be set in [Settings]({{ site.baseurl }}/settings/).
Once configured, an **AI Import** button appears on the homepage.

## How to use it

1. Click **AI Import** on the homepage.
2. Paste any recipe text into the dialog — from a website, a photo (as text),
   notes you've dictated, a cookbook scan, or anything else.
3. Click **Import**.
4. Claude parses the text and opens the result in the recipe editor.
5. Review the recipe, make any corrections, then click **Save**.

## What it can handle

AI Import is flexible about input format. You can paste:

- Web page text copied from a recipe site (including extra navigation and ads — Claude ignores the noise)
- A recipe dictated or typed in plain prose
- A recipe in a foreign language (Claude will translate)
- Multiple recipes at once (Claude imports the first one it finds)

## Important: always review before saving

AI import produces a starting point, not a finished recipe. Check that
ingredient names, quantities, and steps look right before saving. Claude
is good at this task but not infallible.
