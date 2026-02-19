# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Design Philosophy

Recipes are **documents first**. Think of them as the spiritual successors to what Tim Berners-Lee was putting on his server at CERN—marked-up text that a browser can render, not an app that happens to contain text.

### Visual language

The site's visual identity draws from two things: **red-checked tablecloths** (the Better Homes and Gardens cookbook, red-sauce Italian restaurants) and **mid-century cookbooks** (dog-eared pages, serif type, warm off-white paper).

The central metaphor is a cookbook page laid on a tablecloth. The `<main>` content card is the page; the gingham background is the tablecloth peeking out around it. UI elements exist in this same physical world:

- **Nav bar and notification bar** are paired bookends — frosted glass with a gingham-stripe border, one at the top and one at the bottom. They should share the same translucent background treatment.
- **Buttons** (`.btn`) are small, practical, and warm — like a label clipped to a recipe card. Off-white background, muted border, understated hover. This is the one shared button style across the site.
- **Navigation and index links** are typographic, not widget-like. They should feel like part of the document — a table of contents, not a toolbar.
- **Section headers** on list pages (homepage, groceries) use uppercase with letter-spacing for a clean, catalog feel.

When designing new UI elements, ask: would this feel at home in a well-loved cookbook from the 1960s that somehow learned a few new tricks?

### Source files

- Recipe source files are Markdown. They should read naturally in plaintext, as if written for a person, not a parser. Some custom syntax is necessary but should be limited.
- Source files follow a strict, consistent format to keep parsing reliable.

### HTML, CSS, and JavaScript

- HTML should be valid, minimal, and semantic.
- CSS and JS are progressive enhancements. Every page must be readable and functional with both disabled.
- JavaScript is used sparingly and only for optional features (scaling, state preservation, cross-off). These are guilty indulgences—they must not interfere with the document nature of the page.
- Prefer native HTML elements that browsers already know how to handle. Introduce as close to zero custom UI as possible.
- Code should be clean and human-readable: proper indentation, clear variable names. Don't strip whitespace or minify. Fast page loads come from writing less code, not obfuscating it.
- No third-party libraries, scripts, stylesheets, or fonts unless clearly the best solution to a problem—and ask before adding any.

### The groceries page is the exception

`groceries-template.html.erb` has a looser mandate. Heavier JavaScript is fine there. Custom UI is fine there. Third-party dependencies should still be avoided, but the overall restraint is relaxed. Go ham.

## Workflow Preferences

### GitHub Issues
If I mention a GitHub issue (e.g., by referring explicitly to one, or by way of a shorthand like "gh #99" or "#99"), review the issue and start a plan to fix it. Once I confirm the fix, make sure to include a note in the commit message so that the issue is closed.

### Challenge me where appropriate
It's always welcome for you to challenge my assumptions and misconceptions, and push back on my ideas if you see opportunities to improve the end product. You should also suggest any quality-of-life, performance, or feature improvements that come to mind. In plan mode, interviewing me is highly encouraged. Make recommendations where there is an option you believe is best.  

## Build Command

```bash
bin/generate
```

This parses all recipes, generates HTML files in `output/web/`, and copies static resources. Dependencies are managed via `Gemfile` (Ruby, Bundler, and `bundle install` required).

## Test Command

```bash
rake test
```

Runs all tests in `test/` via Minitest.

## Dev Server

```bash
bin/serve [port]
```

Starts a WEBrick server (default port 8888) that serves `output/web/` with clean/extensionless URLs and the custom 404 page, matching the GitHub Pages behavior in production. Binds to `0.0.0.0` so it's accessible across the LAN. The script detects if the port is already in use and exits cleanly, so it's safe to call repeatedly. The typical dev workflow is:

```bash
bin/generate && bin/serve
```

**Only start the dev server once per session.** Before running `bin/serve`, check whether a server is already running (e.g., `ss -tlnp | grep 8888`). After `bin/generate`, the running server will already pick up changes from `output/web/` — no restart needed. Do not try alternate ports; just reuse the existing server.

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
- `QuickBite` - Simple recipe from Quick Bites.md (name and ingredients only)
- `LineClassifier` - Classifies raw recipe text lines into typed tokens (title, step header, ingredient, etc.)
- `RecipeBuilder` - Consumes LineTokens and produces a structured document hash for Recipe
- `IngredientParser` - Parses ingredient line text into structured data; also detects cross-references
- `IngredientAggregator` - Sums ingredient quantities by unit for grocery list display
- `CrossReference` - A reference from one recipe to another (e.g., `@[Pizza Dough]`), renders as a link
- `ScalableNumberPreprocessor` - Wraps numbers in `<span class="scalable">` tags for client-side scaling
- `NutritionCalculator` - Calculates per-recipe and per-serving nutrition facts from ingredient quantities
- `PdfGenerator` - Generates PDF output (uses templates in `templates/pdf/`)

**Data Flow**:
1. `bin/generate` creates a `SiteGenerator` and calls `generate`
2. `SiteGenerator` reads `.md` files from `recipes/` subdirectories
3. Each file is parsed by `Recipe` class using markdown conventions
4. ERB templates in `templates/web/` render HTML output
5. Static assets from `resources/web/` are copied to output

**Output Pages**:
- Individual recipe pages (from recipe-template.html.erb)
- Homepage with recipes grouped by category (homepage-template.html.erb)
- Ingredient index (index-template.html.erb)
- Grocery list builder (groceries-template.html.erb)

**Shared Partials**:
- `_head.html.erb` - Common HTML head (doctype, meta, base tag, stylesheet, favicon)
- `_nav.html.erb` - Site navigation bar (Home, Index, Groceries)

**Resources**:
- `resources/grocery-info.yaml` contains mappings between ingredients and grocery store aisles
- `resources/nutrition-data.yaml` contains per-100g nutrition facts and portion weights for ingredients
- `resources/web/style.css` - main site stylesheet
- `resources/web/recipe-state-manager.js` - client-side scaling, cross-off, and state persistence for recipe pages
- `resources/web/groceries.css` - page-specific styles for the grocery list builder
- `resources/web/groceries.js` - client-side logic for the grocery list builder (selections, localStorage, print layout)
- `resources/web/sw.js` - service worker for offline support and caching
- `resources/web/wake-lock.js` - keeps screen awake while cooking
- `resources/web/notify.js` - notification support (e.g., timer alerts)
- `resources/web/qrcodegen.js` - QR code generation for sharing recipes

## Recipe Format

Recipes are plain text files using this markdown structure:

```
# Recipe Title

Optional description line.

## Step Name (short summary)

- Ingredient name, quantity: prep note
- Another ingredient
- @[Different Recipe], 2: Recipe cross-reference, with optional quantity and prep note.

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

`recipes/Quick Bites.md` uses a different format for simple recipes:
```
## Category Name
  - Recipe Name: Ingredient1, Ingredient2
```

## Nutrition Data

`bin/nutrition-entry` is an interactive CLI for adding nutrition facts from package labels. It converts per-serving values to per-100g for storage in `resources/nutrition-data.yaml`. Usage:

```bash
bin/nutrition-entry "Cream cheese"   # Enter data for a specific ingredient
bin/nutrition-entry --missing         # List ingredients missing nutrition data
```

During `bin/generate`, the build validates that all recipe ingredients have nutrition data and prints warnings for any that are missing.
