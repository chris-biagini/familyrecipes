# Implicit Step Support

**Date:** 2026-02-28
**Issue:** GH #58 — Support list of ingredients + list of steps format

## Problem

The current recipe format requires L2 headers (`## Step Name`) to demarcate steps.
Simple recipes like Nacho Cheese end up with a dummy `## Prepare.` header that adds
no information. The app should support an optional headerless format where ingredients
and instructions form a single implicit step.

## Approach

Approach A: implicit step detection in `RecipeBuilder#parse_steps`. When the first
non-blank token after front matter isn't a `:step_header`, collect all content up to
the `:divider` (or end) into a single step with `tldr: nil`. Single-pass, no rewinding.

## Changes

### Parser (`RecipeBuilder#parse_steps`)

Before the existing loop, check if the first non-blank token is a `:step_header`.
If not, collect all `:ingredient` and `:prose` tokens into one step hash with
`tldr: nil`, stopping at `:divider` or end-of-tokens. If yes, existing loop runs
unchanged. Uses the same ingredient/prose collection logic as `parse_step`.

### Domain (`FamilyRecipes::Step`)

Remove the "must have a tldr" guard. Allow `tldr` to be nil. The second validation
(must have ingredients or instructions) stays.

### AR model (`Step`)

Drop `validates :title, presence: true`. A step either has a real title (explicit
header) or nil (implicit step). Blank strings remain invalid by convention.

### View (`_step.html.erb`)

Wrap the `<h2>` in a nil check — skip rendering when `step.title` is nil. Ingredients
and instructions render identically regardless.

### Seed data

Rewrite `Nacho Cheese.md` to drop the `## Prepare.` header, matching the format from
the issue description.

### Tests

- Parser: headerless recipe produces one step with nil tldr
- Parser: recipes with explicit headers still work
- Domain `FamilyRecipes::Step`: nil tldr accepted
- Integration: import headerless recipe, verify DB round-trip and rendering
