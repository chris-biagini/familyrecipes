---
layout: page
title: Settings
section: settings
prev: /import-export/export/
---

# Settings

Open Settings by clicking the gear icon in the top-right of the navigation bar.

## Site

**Site title** — the browser tab title and the app's name across pages.

**Homepage heading** — the large heading on the Recipes homepage.

**Homepage subtitle** — a line of smaller text beneath the heading.

## Recipes

**Display nutrition information under recipes** — when on, recipes with
enough catalog data show an FDA-style nutrition label below the recipe.
See [Nutrition]({{ site.baseurl }}/recipes/nutrition/) for details.

**Decorate special tags** — when on, recognized tags (dietary, cuisine,
speed) get automatic emoji and color treatment. See
[Tags & categories]({{ site.baseurl }}/recipes/tags-and-categories/) for the full list.
When off, all tags appear as plain gray pills.

## API Keys

**USDA API key** — enables USDA ingredient search in the nutrition editor.
Get a free key at [fdc.nal.usda.gov](https://fdc.nal.usda.gov/api-guide.html).

**Anthropic API key** — enables [AI Import]({{ site.baseurl }}/import-export/ai-import/)
on the homepage. Get a key at [console.anthropic.com](https://console.anthropic.com).

Keys are stored encrypted. Use the **Show** button to reveal a key you've
already entered.

## Multi-kitchen support

Multi-kitchen mode (where different households each have their own recipe
collection under one installation) is configured at install time via an
environment variable — it's not a setting you can change here. See the
deployment documentation for your installation.
