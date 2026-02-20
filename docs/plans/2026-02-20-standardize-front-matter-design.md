# Standardize Front Matter — Design

GitHub issue: #57

## Summary

Replace the implicit prose-based yield line with explicit, structured front matter fields in recipe markdown files. Add a required `Category` field and separate `Makes`/`Serves` fields with clear semantics.

## Syntax

Front matter lives between the description and the first `## Step` header. Fields use `Key: value` syntax.

```
# Pizza Dough

Basic, versatile pizza dough.

Category: Pizza
Makes: 6 dough balls
Serves: 4

## Advance Prep: Make dough.
```

### Field definitions

- **Category** (required) — must match the recipe's subdirectory name. Build error if missing or mismatched.
- **Makes** (optional) — `Makes: <number> <unit noun>`. Unit noun is required when present. Represents countable units produced (dough balls, pancakes, cookies).
- **Serves** (optional) — `Serves: <number>`. People count only, no unit noun.

A recipe can have both Makes and Serves, just one, or neither (Category is always required). The old prose yield lines (`Makes 30 gougeres.` / `Serves 4.`) are retired.

Quick Bites is unchanged.

## Parsing (Approach A: Extend LineClassifier + RecipeBuilder)

**LineClassifier** — new pattern:

```ruby
front_matter: /^(Category|Makes|Serves):\s+(.+)$/
```

Checked after existing patterns, before the `:prose` fallback.

**RecipeBuilder** — new `parse_front_matter` method replaces `parse_yield_line`. Runs after `parse_description`, consumes `:front_matter` tokens until hitting a step header or end of input. Returns structured hash.

The `Makes` value is further parsed into quantity and unit noun by splitting on the first space boundary between the number and the rest.

**Recipe** class:
- `yield_line` replaced by `makes` and `serves`
- New accessors: `makes_quantity`, `makes_unit_noun`
- `category` validated against front matter value

**Validation errors:**
- Missing `Category:` → build error
- Category mismatch with directory → build error
- `Makes:` with bare number (no unit noun) → build error
- Unknown front matter key → build error (catches typos)

## HTML Presentation

Inline metadata line in the recipe header, replacing the yield-line paragraph:

```html
<header>
  <h1>Pizza Dough</h1>
  <p>Basic, versatile pizza dough.</p>
  <p class="recipe-meta">
    <a href="index.html#pizza">Pizza</a> · Makes <span class="scalable">6</span> dough balls · Serves <span class="scalable">4</span>
  </p>
</header>
```

- Category always present (required field), links to homepage section
- Makes/Serves appended with `·` separator when present
- Numbers wrapped in `<span class="scalable">` for client-side scaling
- Styled as subtle metadata: smaller text, muted color, replaces `.yield-line`

Homepage template unchanged — still groups by `recipe.category`.

## Migration

A subagent converts all existing recipe files:

1. Determine category from directory name
2. Parse existing yield line and convert: `Makes 30 gougeres.` → `Makes: 30 gougeres`
3. Remove old yield line, insert front matter block
4. Build validation catches mistakes immediately

## Test changes

- Update existing tests referencing `yield_line` to use `makes`/`serves`
- New tests for front matter parsing, validation errors, and display rendering
