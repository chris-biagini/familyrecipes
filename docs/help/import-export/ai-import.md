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

An Anthropic API key must be configured on the deployment. Homelab users set
`ANTHROPIC_API_KEY` in their `docker-compose.yml` or `.env` file. Hosted users
get this automatically if the operator has enabled it. Once a key is present,
an **AI Import** button appears on the homepage.

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
source — for example, importing a recipe handed down in your family
where the exact phrasing matters.

### Expert mode

Check **Expert mode — condense for experienced cooks** to get a compact
version that strips obvious basics and tutorial-style instructions. Steps
are reorganized for clarity.
Use this when you already know your way around a kitchen and just want
the essential information.

## What it can handle

AI Import is flexible about input format. You can paste:

- Web page text copied from a recipe site (including extra navigation and ads — Claude ignores the noise)
- A recipe dictated or typed in plain prose
- A recipe in a foreign language (Claude translates it to English)

## Important: always review before saving

AI import produces a starting point, not a finished recipe. Check that
ingredient names, quantities, and steps look right before saving. Claude
is good at this task but not infallible.
