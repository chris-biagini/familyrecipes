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

API keys are deployment-level configuration — they are not stored in the
database and cannot be changed here.

- **Homelab installs:** set `USDA_API_KEY` and/or `ANTHROPIC_API_KEY` in your
  `docker-compose.yml` environment section or `.env` file. See
  `.env.example` and `docker-compose.example.yml` for the full list of
  supported variables.
- **Hosted installs:** keys are configured by the operator. Features that
  require a key are automatically available if the operator has enabled them.

When a key is present, it applies to all kitchens on that deployment.

## Multi-kitchen support

Multi-kitchen mode (where different households each have their own recipe
collection under one installation) is configured at install time via an
environment variable — it's not a setting you can change here. See the
deployment documentation for your installation.
