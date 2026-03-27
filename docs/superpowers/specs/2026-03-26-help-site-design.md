# Help Site Design

**Date:** 2026-03-26

## Goal

Build comprehensive user-facing documentation for familyrecipes as a static Jekyll site
deployed to GitHub Pages via GitHub Actions. The docs serve as a contract: if something
isn't working as described, we check the docs and the code to decide which one needs to change.

---

## Visual Design

**Style:** Clean modern documentation site — not a duplicate of the app's aesthetic.

**Fonts (web fonts via Google Fonts):**
- Body/UI: Inter (400, 500, 600)
- Headings: Source Serif 4 (400, 600, italic)
- Code: system monospace stack

**Colors:**
- Background: `#f9fafb` (page), `#ffffff` (sidebar + content card)
- Text: `#111827` (primary), `#374151` (body), `#6b7280` (secondary)
- Accent: `#c0522a` (terracotta) for active nav, links, callout borders, inline code
- Borders: `#e5e7eb`
- Code block background: `#1e1b18` (borrows the app's dark-mode ground — a small nod)
- Callout background: `#fef3ee`, border: `#c0522a`

**Logo:** Favicon SVG from `app/assets/images/favicon.svg`, copied into Jekyll assets at
build time by the GitHub Actions workflow. Displayed at 26×26px in the topbar.

**Layout:** Sticky topbar (52px) + left sidebar (220px, sticky) + main content area
(max-width 780px). Prev/Next navigation at the bottom of each page. Breadcrumb at top.

---

## Information Architecture

Jekyll source lives in `docs/help/`. Each section is a subdirectory with an `index.md`.

```
docs/help/
  _layouts/
    default.html        # full page shell: topbar + sidebar + content
    page.html           # extends default, adds breadcrumb + prev/next
  _includes/
    sidebar.html        # nav tree, marks active page
    topbar.html
  assets/
    style.css           # all styles (single file, no build tool)
    favicon.svg         # copied from app/assets/images/favicon.svg by CI
  _config.yml
  index.md              # Getting Started / overview

  recipes/
    index.md            # section landing
    format.md
    editing.md
    cooking.md
    scaling.md
    cross-references.md
    tags-and-categories.md
    nutrition.md

  menu/
    index.md
    selecting-recipes.md
    quickbites.md
    dinner-picker.md

  groceries/
    index.md
    how-it-works.md
    three-sections.md
    learning.md
    custom-items.md
    aisles.md

  ingredients/
    index.md
    catalog.md
    nutrition-data.md

  import-export/
    index.md
    ai-import.md
    markdown-import.md
    export.md

  settings/
    index.md            # all settings on one page (short enough)
```

**Navigation order** (sidebar, top to bottom):
1. Getting Started
2. Recipes (7 pages)
3. Menu (3 pages)
4. Groceries (5 pages)
5. Ingredients (2 pages)
6. Import & Export (3 pages)
7. Settings (1 page)

---

## Content Scope

Each page documents what the feature *should* do from the user's perspective.
Technical implementation details are omitted. Tone: clear, direct, friendly —
like a well-written README, not marketing copy.

### Getting Started (`index.md`)
- What familyrecipes is: self-hosted recipe organizer
- How the four main pages connect (Recipes → Menu → Groceries → Ingredients)
- Quick orientation: "start here if you're new"

### Recipes

**format.md** — The full recipe Markdown syntax:
- Title (`# Title`)
- Optional description paragraph
- Front matter: `Category:`, `Tags:`, `Makes:`, `Serves:`
- Steps (`## Step Name`)
- Ingredient bullets: `- Name, quantity: prep note`
- Footer (after `---`)
- How quantities work (fractions, ranges: "1-2 eggs")
- Brief mention of cross-references (`> @[Title]` and `@[Title]`) with link to cross-references.md

**editing.md** — Two editors, same result:
- Plaintext editor (CodeMirror, syntax highlighting)
- Graphical editor (form-based, no Markdown knowledge needed)
- Switching between modes mid-edit
- Creating a new recipe from the homepage
- Editing an existing recipe
- Deleting a recipe

**cooking.md** — Using recipes while cooking:
- Crossing off steps (click a `##` step heading to strike through the whole step)
- Crossing off individual ingredients (click to toggle)
- State is preserved in the browser across page loads
- Wake lock: screen stays on automatically while viewing a recipe (also applies on the groceries page)

**scaling.md** — Adjusting recipe quantities:
- ½×, 1×, 2×, 3× preset buttons
- Custom scale factor (fractions accepted: "3/2")
- What gets scaled (ingredient quantities, makes/serves line)
- What doesn't (step text, temperatures — those are intentional)

**cross-references.md** — Linking and embedding other recipes:
- `> @[Recipe Title]` — embeds the referenced recipe's steps inline
- `@[Recipe Title]` in prose or footer — renders as a clickable link
- How grocery quantities work across cross-referenced recipes
- What happens if the referenced recipe is deleted (broken reference UI)

**tags-and-categories.md** — Organizing recipes:
- Categories: one per recipe, shown on homepage grouped sections
- Tags: multiple per recipe, comma-separated in front matter, single-word
- Smart tag decorations (emoji/color for dietary, cuisine tags) — what triggers them, how to disable
- Editing categories from the homepage (reorder, rename, add, delete)
- Editing tags from the homepage

**nutrition.md** — Per-serving nutrition facts:
- Where nutrition facts appear (under the recipe when enabled in Settings)
- How nutrition is calculated (from ingredient catalog entries + quantity)
- What "partial" and "missing" mean in the ingredient editor
- Enabling/disabling display in Settings

### Menu

**selecting-recipes.md** — Building a weekly plan:
- Checking/unchecking recipes and QuickBites
- How selections drive the grocery list
- Ingredient availability indicators next to each recipe:
  - Single dot (filled = have it, hollow = missing) for single-ingredient recipes
  - `x/y` fraction (expandable) for multi-ingredient recipes — click to see Have/Missing breakdown
  - Opacity of the indicator reflects the fraction on-hand (dimmer = fewer ingredients available)

**quickbites.md** — Grocery bundles:
- What a QuickBite is (title + ingredient list, not a full recipe)
- Format: `## Category` heading, then `- Title: Ingredient, Ingredient`
  - Bare `- Title` (no colon) is valid for a single-item bundle
- QuickBites appear in a labeled "Quick Bites" zone within each category on the Menu page
- Each zone has an edit button that opens the editor focused on that category
  (the global "Edit QuickBites" button in the page header remains, opens all sections)
- How QuickBite ingredients appear on the grocery list

**dinner-picker.md** — Random recipe suggestion:
- How to open it ("What Should We Make?" button on the Menu page)
- How the weighting works (recently cooked recipes deprioritized)
- Tag filters: three-state cycle per tag — neutral → boost (2×) → suppress (0.25×) → neutral
  - Shows thumbs-up / thumbs-down indicators as you cycle

### Groceries

Content already drafted in `docs/help/groceries.md`. Split across these pages:

**how-it-works.md** — "Your shopping list, built from the Menu":
- Quantities combined across recipes
- Grouped by aisle
- Live updates (shared with other household members)
- Wake lock (screen stays on while shopping — same as recipe view)

**three-sections.md** — Inventory Check / To Buy / On Hand:
- What each section means
- Have It / Need It buttons
- All Stocked shortcut
- Checking off items (To Buy → On Hand)
- Unchecking items (On Hand → To Buy)
- Same-day undo behavior
- Visual freshness fading on On Hand items

**learning.md** — How the system learns your pantry:
- SM-2-inspired adaptive schedule (explained in plain terms)
- First-week behavior ("the list will be long at first")
- What happens when you confirm "Have It"
- What happens when you run out
- Pruning: what it is, what it preserves, why it's different from running out

**custom-items.md** — Non-recipe items:
- Adding custom items via the input at the bottom of the page
- Quick-add via the search overlay (press `/` or the search icon in the nav)
- `Name @ Aisle` syntax for aisle placement
- Custom items are not subject to scheduling or pruning
- Removing custom items

**aisles.md** — Managing aisles:
- Where aisle assignments come from (ingredient catalog)
- Editing aisle order (reorder, rename, add, delete)
- Uncategorized items land in "Miscellaneous"

### Ingredients

**catalog.md** — The ingredient database:
- Where ingredients come from (extracted from recipes and QuickBites automatically)
- Search and filter (the "Not Resolvable" filter)
- What "resolvable" means (can nutrition be calculated for this ingredient?)
- Coverage summary bar

**nutrition-data.md** — Entering nutrition data:
- Opening the nutrition editor (click any ingredient)
- Manual entry (nutrient fields, density, portions)
- USDA search (requires API key in Settings)
- Importing a USDA result
- Aisle assignment (also done here)
- Unit aliases

### Import & Export

**ai-import.md** — Paste any recipe text:
- Requires Anthropic API key in Settings
- Paste anything: website text, scanned recipe, dictated notes
- Claude normalizes it to the recipe format and opens the editor
- Review before saving — it's a starting point, not a finished import

**markdown-import.md** — File import:
- Import a single `.md` or `.txt` file
- Import a `.zip` (from Export or manually assembled)
- What happens to categories, tags, nutrition data on import
- Conflict behavior (existing recipe with same title)

**export.md** — Downloading your data:
- What's included (all recipes as `.md` files, ingredient catalog, meal plan state)
- The ZIP is re-importable
- Use for backups, migration, or editing recipes in a text editor
- API keys are not included — re-enter them after importing on a new install

### Settings

**index.md** — All settings on one page:
- Site title, homepage heading, homepage subtitle
- Show nutrition information (toggle)
- Decorate special tags (toggle, explains what smart tags are)
- USDA API key (link to USDA API registration)
- Anthropic API key (link to console.anthropic.com)
- Note: multi-kitchen support is configured at install time (env var), not in Settings

---

## Jekyll Configuration

**`_config.yml`:**
```yaml
title: familyrecipes help
# If repo is github.com/<org>/familyrecipes, baseurl is "/familyrecipes"
# If this is a user/org site at <user>.github.io, set baseurl to ""
baseurl: "/familyrecipes"
url: "https://<org>.github.io"
markdown: kramdown
kramdown:
  input: GFM               # enable GitHub Flavored Markdown (code fences, tables)
theme: null                 # no gem theme — fully custom CSS
exclude:
  - "*.sh"
  - ".gitignore"
```

**Frontmatter on each page:**
```yaml
---
layout: page
title: Recipe Format
section: recipes
prev: /recipes/
next: /recipes/editing/
---
```

**Sidebar generation:** `_includes/sidebar.html` iterates a hardcoded nav tree
(not auto-discovered) so order is always explicit. Active page highlighted by
comparing `page.url` to each link's href.

---

## GitHub Actions Workflow

**File:** `.github/workflows/docs.yml`

**Trigger:** Push to `main` when files under `docs/help/` change, or manual
`workflow_dispatch`.

**Steps:**
1. Checkout repo
2. Copy `app/assets/images/favicon.svg` → `docs/help/assets/favicon.svg`
3. Setup Ruby (same version as app; gems installed directly — no Gemfile needed)
4. Install Jekyll and kramdown: `gem install jekyll kramdown-parser-gfm`
5. Build: `jekyll build --source docs/help --destination _site`
6. Upload artifact via `actions/upload-pages-artifact@v3`
7. Deploy via `actions/deploy-pages@v4`

**Permissions required on the workflow:**
```yaml
permissions:
  contents: read
  pages: write
  id-token: write
```

GitHub Pages must be configured to deploy from **GitHub Actions** (not from a branch)
in the repo Settings → Pages → Source.

---

## Existing Content Migration

`docs/help/groceries.md` is already well-written. It maps to:
- `groceries/how-it-works.md` (intro + How the Shopping List Works sections)
- `groceries/three-sections.md` (The Three Sections + Before You Shop + While Shopping)
- `groceries/learning.md` (How the System Learns + What Happens When Recipes Change)
- `groceries/custom-items.md` (Custom Items section)

`docs/help/index.md` becomes the Getting Started overview with light expansion.

---

## Out of Scope

- Search (no client-side search for v1 — the sidebar + browser Cmd+F is enough)
- Dark mode on the help site
- Mobile-responsive sidebar (hamburger menu) — the groceries page is heavily mobile-used,
  so a CSS-only collapsed sidebar for narrow viewports is worth adding in a follow-up; deferred for now
- Versioned docs
- Comments or feedback widgets
