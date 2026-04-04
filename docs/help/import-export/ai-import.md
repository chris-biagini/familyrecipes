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
3. Choose an import mode (see below).
4. Click **Import**.
5. Claude parses the text and opens the result in the recipe editor.
   You can switch between the graphical and plaintext editors to review.
6. Review the recipe, make any corrections, then click **Save**.

## Import modes

AI Import has two modes, controlled by a checkbox in the import dialog.

### Faithful (default)

Preserves the original recipe's wording and style as closely as possible.
Informal language, verbose descriptions, and the author's voice all come
through intact. Use this when you want an accurate transcription of the
source — for example, importing a family recipe where the exact phrasing
matters.

### Expert mode

Check **Expert mode — condense for experienced cooks** to get a compact
version that strips obvious basics and tutorial-style instructions. Steps
are reorganized for clarity and written in a terse, confident voice.
Use this when you already know your way around a kitchen and just want
the essential information.

Both modes preserve all ingredient quantities exactly and will not invent
missing information.

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
