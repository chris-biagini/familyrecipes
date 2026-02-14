# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goals

This project is designed with an eye toward simplicity and elegance. 

Recipe source files should be perfectly readable in plaintext form, and look like they're written for a person, not a parsing script (hence the use of Markdown as a base). The source files follow a relatively strict format to make parsing easier.

HTML should be valid, minimal, and semantic. JavaScript should be used very sparingly, and only for optional features (e.g., scaling, state preservation) that progressively enhance the base content. Every page should be readable with both JavaScript and CSS disabled. HTML, CSS, and JavaScript should be minimal so that the pages load as fast as possible, without going overboard by doing things like stripping whitespace and shortening variable names. The code should be indented nicely and human-readable. Third-party libraries, scripts, stylesheets, fonts, etc. should be avoided unless they're clearly the best solution to a problem--but you should ask before resorting to them. An exception to all this is the grocery list builder (groceries-template.html.erb)--for that page, you can have a little more fun, and go a little heavier on the JavaScript, but you should still try to avoid third-party stuff.

Ruby code should be relatively simple and readable to a novice (i.e., me).

## Build Command

```bash
bin/generate
```

This parses all recipes, generates HTML files in `output/web/`, and copies static resources. Requires Ruby with the `redcarpet` gem.

## Dev Server

```bash
bin/serve [port]
```

Starts a WEBrick server (default port 8888) that serves `output/web/` with clean/extensionless URLs and the custom 404 page, matching the Apache behavior in production. Binds to `0.0.0.0` so it's accessible across the LAN. The typical dev workflow is:

```bash
bin/generate && bin/serve
```

## Architecture

**Core Classes** (`lib/familyrecipes/`):
- `Recipe` - Parses markdown recipe files into structured data (title, description, steps, footer)
- `Step` - A recipe step containing a tldr summary, ingredients list, and instructions
- `Ingredient` - Individual ingredient with name, quantity, and prep note
- `QuickBite` - Simple recipe from Quick Bites.txt (name and ingredients only)

**Data Flow**:
1. `bin/generate` reads `.txt` files from `recipes/` subdirectories
2. Each file is parsed by `Recipe` class using markdown conventions
3. ERB templates in `templates/web/` render HTML output
4. Static assets from `resources/web/` are copied to output

**Output Pages**:
- Individual recipe pages (from recipe-template.html.erb)
- Homepage with recipes grouped by category (homepage-template.html.erb)
- Ingredient index (index-template.html.erb)
- Grocery list builder (groceries-template.html.erb)

**Resources**:
- `resources/grocery-info.yaml` contains mappings between ingredients and grocery store aisles

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
