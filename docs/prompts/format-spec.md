# Recipe Format Specification

This document describes the structural rules for a valid recipe in the
familyrecipes format. Use it to judge whether a converted recipe will
parse correctly. This is about format validity, not writing style — see
`style-rubric.md` for style evaluation.

## Document Structure

A recipe file is Markdown with these sections in order:

    # Title                          ← required
                                     ← blank line
    Description sentence.            ← optional
                                     ← blank line
    Makes: 12 cookies                ← optional front matter
    Serves: 4                        ← optional front matter
    Category: Dessert                ← optional front matter
    Tags: weeknight, one-pot         ← optional front matter
                                     ← blank line
    ## Step name.                    ← at least one step required
                                     ← blank line
    - Ingredient, qty unit: Prep.    ← ingredients for this step
                                     ← blank line
    Instruction prose.               ← instructions for this step
                                     ← blank line
    ## Another step.                 ← next step
    ...
                                     ← blank line
    ---                              ← optional divider
                                     ← blank line
    Footer notes.                    ← optional

---

## Title

**Required.** Must be the first non-blank line.

- Level-one Markdown heading: `# Title Text`
- Must not be empty after the `# `.

**Parser error if missing or malformed.**

## Description

**Optional.** A prose line (or lines) between the title and front
matter/steps. Blank lines may separate it from the title.

- Typically a single short sentence.
- Multiple prose lines are joined with double newlines.
- If a front matter line immediately follows the title, there is no
  description.

## Front Matter

**Optional.** Lines matching `Key: value` where the key is one of
exactly four recognized words. Must appear before the first step.

| Key | Format | Example | Notes |
|-----|--------|---------|-------|
| `Makes` | number + unit noun | `Makes: 12 pancakes` | Unit noun required. Single number, not a range. **Parser error if unit noun is missing** (e.g., `Makes: 12` alone is invalid). |
| `Serves` | single number | `Serves: 4` | Plain integer. Not a range — `Serves: 4-6` is invalid by convention. |
| `Category` | one approved name | `Category: Baking` | Approved list: Basics, Baking, Bread, Breakfast, Dessert, Drinks, Holiday, Mains, Pizza, Sides, Snacks. |
| `Tags` | comma-separated | `Tags: quick, one-pot` | Normalized to lowercase; spaces become hyphens (`vegan friendly` → `vegan-friendly`). Empty tags are dropped. |

**Key names are case-sensitive.** `Makes` works; `makes` or `MAKES` does
not — a misspelled key becomes prose and terminates front matter parsing.

## Steps

**At least one step is required.** Parser error if the recipe has no
steps.

### Explicit Steps

Start with a level-two heading:

    ## Step name.

Followed by any combination of:
- Ingredient lines (`- ...`)
- Instruction prose (any non-ingredient, non-heading text)
- A cross-reference (`> @[...]`)

A step ends at the next `## `, the `---` divider, or end of file.

**Step name:** The text after `## `. Must not be empty.

**Step content:** Must have at least one of: ingredients, instructions,
or a cross-reference. **Parser error if a step is completely empty.**

### Implicit Steps

If the recipe has no `## ` headings, all ingredients and instructions
after front matter form a single implicit step (with no step name). Use
this for very simple recipes.

An implicit step still requires at least one ingredient, instruction, or
cross-reference.

## Ingredient Lines

**Syntax:** `- Name, quantity unit: Prep note.`

Every part after the name is optional:

    - Salt                           ← name only
    - Garlic, 3 cloves               ← name + quantity
    - Garlic: Minced.                ← name + prep note
    - Butter, 115 g: Softened.       ← all three parts

### Parsing Rules

1. The line starts with `- ` (hyphen + space).
2. Split on the **first** `:` (colon) → left side is name+quantity,
   right side is prep note.
3. Split the left side on the **first** `,` (comma) → first part is
   name, second part is quantity.
4. All parts are whitespace-trimmed.

### Name

- Anything before the first comma (or the full line if no comma and no
  colon).
- Parenthetical qualifiers disambiguate variants: `Sugar (brown)`,
  `Flour (all-purpose)`, `Butter (unsalted)`, `Tomatoes (canned)`.
- Don't over-qualify defaults: `Onion` not `Onion (yellow)`, `Egg` not
  `Egg (large)`, `Cinnamon` not `Cinnamon (ground)`.
- Always qualify sugar: `Sugar (white)` or `Sugar (brown)`, never bare
  `Sugar`.
- Always `Vanilla extract`, never bare `Vanilla`.

### Quantity

Format: `value unit` with a space between.

**Numbers:**
- Integers: `4`
- Decimals: `0.5`, `2.5` — use for metric units.
- ASCII fractions: `1/2`, `3/4`, `1/3` — use for imperial units.
- Mixed numbers: `2 1/2` (whole, space, fraction). Never `2-1/2` or
  `2½`.
- Ranges: `2-3`, `1/2-1`, `7/8-1 1/8` — hyphen, no spaces around it.
  Both sides must be numbers.

**Never use vulgar fraction characters** (`½`, `¾`, `⅓`) in output.
The parser accepts them on input and normalizes them, but correct output
uses ASCII fractions only.

**Never use en-dashes** in ranges. The parser normalizes `–` to `-`, but
correct output uses hyphens.

**Units:** Preserved from source — don't convert between systems. Common
abbreviations are normalized: `tbsp`, `tsp`, `g`, `mL`, `oz`, `cups` →
`cup`, etc.

**Omit quantity entirely** for to-taste seasonings, oil for greasing,
and similar unquantified ingredients. Never write `to taste`.

### Prep Note

- Text after the colon.
- Capitalized first letter, ends with period: `Minced.`, `Roughly
  chopped.`, `Softened to room temperature.`
- Describes physical preparation (cutting, melting, grating) — not
  serving context, substitutions, or "divided."

### Ingredient Line Errors

- Starting an ingredient line with `@[` raises a parser error with a
  hint to use the `> @[...]` cross-reference syntax instead.

## Cross-References

**Syntax:** `> @[Recipe Title], multiplier: Prep note.`

Embeds another recipe's ingredients into a step.

    > @[Simple Tomato Sauce]
    > @[Pizza Dough], 2
    > @[Simple Tomato Sauce], 2: Can make the night before.

### Parsing Rules

- Line starts with `>` (optionally preceded by spaces), followed by
  `@[...]`.
- Inside the brackets: recipe title (non-greedy match).
- After `]`: optional period, then optional `, multiplier`, then
  optional `: prep note`.

**Multiplier formats:** integer (`2`), fraction (`1/2`), decimal
(`0.5`). Defaults to `1.0` if absent.

### Constraints — Parser Errors

| Rule | Error |
|------|-------|
| Cross-reference outside an explicit step (`## `) | "must appear inside an explicit step" |
| Mixed with ingredients in the same step | "cannot be mixed with ingredients" |
| Mixed with instructions in the same step | "cannot be mixed with instructions" |
| Multiple cross-references in one step | "Only one cross-reference is allowed per step" |
| Old syntax: `2 @[Title]` (multiplier before reference) | "Use @[Title], quantity" |
| Malformed `@[...]` | "Invalid cross-reference syntax" |

A cross-reference step must contain **only** the cross-reference line
and nothing else.

## Instructions

Prose paragraphs following ingredients within a step. Any line that
isn't a heading, ingredient, cross-reference, divider, or blank is
instruction prose.

- Multiple prose lines/paragraphs are joined with double newlines.
- Imperative mood, concise.

## Footer

**Optional.** Everything after the `---` divider.

- The divider is exactly `---` (three hyphens, optional trailing spaces)
  on its own line.
- Footer content is plain prose — no structural requirements.
- Leading/trailing blank lines around the divider are fine.
- Returns nil if no divider or no content after divider.

## Validation Summary

A format critic should check for these errors, roughly in order of
severity:

### Hard Errors (recipe will not parse)

1. **No title** — first non-blank line is not `# ...`.
2. **No steps** — no ingredients, instructions, or cross-references
   after front matter.
3. **Empty step** — a `## ` heading with no content before the next
   heading or divider.
4. **Makes without unit noun** — `Makes: 12` instead of
   `Makes: 12 cookies`.
5. **Cross-reference outside explicit step** — `> @[...]` appears
   before any `## ` heading.
6. **Cross-reference mixed with ingredients or instructions** — a step
   has both `> @[...]` and `- ...` lines or prose.
7. **Multiple cross-references in one step.**
8. **Ingredient line starting with `@[`** — should use `> @[...]`.
9. **Old cross-reference syntax** — `2 @[Title]` instead of
   `@[Title], 2`.

### Soft Errors (parseable but incorrect)

1. **Vulgar fraction characters** — `½` instead of `1/2`.
2. **En-dashes in ranges** — `2–3` instead of `2-3`.
3. **Category not in approved list.**
4. **Bare `Sugar`** without `(white)` or `(brown)`.
5. **Bare `Vanilla`** without `extract`.
6. **`to taste`** on an ingredient line.
7. **Prep note not capitalized or missing period.**
8. **Front matter key misspelled** — becomes prose, silently ignored.
9. **Mixed number with hyphen** — `2-1/2` parsed as a range, not a
   mixed number.
10. **Serves as a range** — `Serves: 4-6` instead of `Serves: 4`.
11. **Makes as a range** — `Makes: 3-4 loaves` instead of single number.
12. **Over-qualified ingredient names** — `Onion (yellow)`,
    `Egg (large)`, `Cinnamon (ground)`.
13. **Unit conversion** — source says `1 cup`, output says `128 g`.
