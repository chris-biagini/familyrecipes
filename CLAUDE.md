# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goals

This project is designed with an eye toward simplicity and elegance. 

Recipe source files should be perfectly readable in plaintext form, and look like they're written for a person, not a parsing script (hence the use of Markdown as a base). The source files follow a relatively strict format to make parsing easier.

HTML should be valid, minimal, and semantic. JavaScript should be used very sparingly, and only for optional features (e.g., scaling, state preservation) that progressively enhance the base content. Every page should be readable with both JavaScript and CSS disabled. HTML, CSS, and JavaScript should be minimal so that the pages load as fast as possible, without going overboard by doing things like stripping whitespace and shortening variable names. The code should be indented nicely and human-readable. Third-party libraries, scripts, stylesheets, fonts, etc. should be avoided unless they're clearly the best solution to a problem--but you should ask before resorting to them. An exception to all this is the grocery list builder (groceries-template.html.erb)--for that page, you can have a little more fun, and go a little heavier on the JavaScript, but you should still try to avoid third-party stuff.

## Build Command

```bash
bin/generate
```

This parses all recipes, generates HTML files in `output/web/`, and copies static resources. Dependencies are managed via `Gemfile` (Ruby, Bundler, and `bundle install` required).

## Test Command

```bash
rake test
```

Runs all tests in `test/` via Minitest (90 tests across 7 files).

## Dev Server

```bash
bin/serve [port]
```

Starts a WEBrick server (default port 8888) that serves `output/web/` with clean/extensionless URLs and the custom 404 page, matching the GitHub Pages behavior in production. Binds to `0.0.0.0` so it's accessible across the LAN. The typical dev workflow is:

```bash
bin/generate && bin/serve
```

## Deployment

The site is hosted on **GitHub Pages** at `biaginifamily.recipes`. Pushing to `main` automatically triggers a build and deploy via GitHub Actions (`.github/workflows/deploy.yml`). The workflow:

1. Runs `bundle exec rake test` (build fails if tests don't pass)
2. Runs `bin/generate` to build the site
3. Deploys `output/web/` to GitHub Pages

The custom domain is configured in the repo's GitHub Pages settings, not in the workflow file, so forks don't need to modify the workflow.

## URL Portability

All templates use relative paths resolved via an HTML `<base>` tag, so the site works regardless of deployment root (e.g., `biaginifamily.recipes/` or `username.github.io/familyrecipes/`). Root-level pages use `<base href="./">` and subdirectory pages (`index/`, `groceries/`) use `<base href="../">`. When adding new links or asset references in templates, use relative paths (e.g., `style.css`, not `/style.css`).

## Architecture

**Core Classes** (`lib/familyrecipes/`):
- `SiteGenerator` - Orchestrates the full build: parsing, rendering, resource copying, and validation
- `Recipe` - Parses markdown recipe files into structured data (title, description, steps, footer)
- `Step` - A recipe step containing a tldr summary, ingredients list, and instructions
- `Ingredient` - Individual ingredient with name, quantity, and prep note
- `QuickBite` - Simple recipe from Quick Bites.txt (name and ingredients only)

**Data Flow**:
1. `bin/generate` creates a `SiteGenerator` and calls `generate`
2. `SiteGenerator` reads `.txt` files from `recipes/` subdirectories
3. Each file is parsed by `Recipe` class using markdown conventions
4. ERB templates in `templates/web/` render HTML output
5. Static assets from `resources/web/` are copied to output

**Output Pages**:
- Individual recipe pages (from recipe-template.html.erb)
- Homepage with recipes grouped by category (homepage-template.html.erb)
- Ingredient index (index-template.html.erb)
- Grocery list builder (groceries-template.html.erb)

**Resources**:
- `resources/grocery-info.yaml` contains mappings between ingredients and grocery store aisles
- `resources/web/groceries.css` - page-specific styles for the grocery list builder
- `resources/web/groceries.js` - client-side logic for the grocery list builder (selections, localStorage, print layout)

## Recipe Format

Recipes are plain text files using this markdown structure:

```
# Recipe Title

Optional description line.

## Step Name (short summary)

- Ingredient name, quantity: prep note
- Another ingredient

Instructions for this step as prose.

## Another Step

- More ingredients

More instructions.

---

Optional footer content (notes, source, etc.)
```

**Ingredient syntax**: `- Name, Quantity: Prep note` where quantity and prep note are optional. Examples:
- `- Eggs, 4: Lightly scrambled.`
- `- Salt`
- `- Garlic, 4 cloves`

## Quick Bites

`recipes/Quick Bites.txt` uses a different format for simple recipes:
```
## Category Name
  - Recipe Name: Ingredient1, Ingredient2
```
