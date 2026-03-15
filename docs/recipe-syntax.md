# Recipe Syntax Specification

This document describes the Markdown-based syntax used to author recipes in
familyrecipes. It is **descriptive** — the parser pipeline is the authoritative
implementation. If this document and the parser disagree, the parser wins and
this document should be updated.

Parser source: `lib/familyrecipes/line_classifier.rb` (tokenization),
`recipe_builder.rb` (assembly), `ingredient_parser.rb` (ingredients),
`cross_reference_parser.rb` (cross-references). Seed files in
`db/seeds/recipes/` are working examples.

## Document Structure

A recipe is a Markdown document with this overall shape:

    # Title

    Optional description.

    Optional front matter (Serves, Makes, Category, Tags)

    Steps (implicit or explicit)

    ---

    Optional footer

Here is a complete example demonstrating most features:

    # Pasta with Tomato Sauce

    The weeknight classic.

    Serves: 4
    Category: Basics
    Tags: quick, weeknight, pasta

    ## Make the sauce.

    > @[Simple Tomato Sauce]

    ## Cook the pasta.

    - Spaghetti, 400 g
    - Salt
    - Parmesan: Grated, for serving.

    Bring a large pot of well-salted water to a boil. Cook spaghetti until
    al dente. Reserve a cup of pasta water before draining. Toss pasta with
    the sauce, adding a splash of pasta water to loosen if needed.

    ---

    This pairs well with @[Simple Salad].

The sections below describe each part in detail.

## Title

The first line of the document must be a level-one Markdown header:

    # Oatmeal Cookies

This is the recipe's title. It is required — the parser rejects documents that
do not start with `# `.

## Description

An optional single line of prose immediately after the title. If present, it
becomes the recipe's description:

    # Toast

    The simplest recipe there is.

Only one line is captured as the description. If multiple prose lines appear
before front matter or steps, only the first is the description — subsequent
lines become part of the first step.

## Front Matter

Optional metadata lines that appear after the title (and description, if
present) but before any steps. Each line uses `Key: value` format. The
recognized keys are case-insensitive:

**Serves** — an integer serving count:

    Serves: 4

**Makes** — a yield with a unit noun. The unit noun is required:

    Makes: 24 cookies
    Makes: 2 loaves

`Makes: 12` alone (without a unit noun) is invalid.

**Category** — a free-text category name:

    Category: Baking

When present, this overrides any category supplied through other means (e.g.,
the directory name during import).

**Tags** — a comma-separated list of tags:

    Tags: quick, weeknight, vegan-friendly

Tags are normalized: lowercased, whitespace trimmed, internal spaces replaced
with hyphens. The resulting tags match `[a-z-]+`.

Front matter lines can appear in any order. All are optional.

## Steps

Steps are the body of the recipe. They contain ingredients, instructions, or
cross-references. There are two forms: **explicit** and **implicit**.

### Explicit Steps

Use level-two Markdown headers (`##`) to define named steps:

    ## Make the dough.

    - Flour, 250 g
    - Butter, 115 g: Softened.
    - Sugar, 200 g

    Beat butter with sugar until fluffy. Mix in flour.

    ## Bake.

    Preheat oven to 175°C. Bake 10-12 minutes.

Each explicit step can contain:

- **Ingredients** (bullet lines)
- **Instructions** (prose paragraphs)
- **A cross-reference** (see below)

A step must contain at least one of these — empty steps are invalid.

### Implicit Steps

When a recipe has no `##` headers, all ingredients and instructions are
collected into a single unnamed step:

    # Toast

    Serves: 2

    - Bread, 2 slices
    - Butter

    Toast the bread until golden. Spread butter while still warm.

### Constraints

- A step cannot mix a cross-reference with ingredients or instructions. A
  cross-reference step contains only the cross-reference line.
- Prose paragraphs within a step are separated by blank lines.

## Ingredients

Ingredient lines are Markdown bullet items inside a step:

    - Name
    - Name, Quantity
    - Name, Quantity: Prep note.
    - Name: Prep note.

### Name

The ingredient name. Parenthetical qualifiers are allowed:

    - Flour (all-purpose), 155 g
    - Sugar (brown), 150 g

### Quantity

An optional quantity after the first comma. Quantities can use several numeric
formats:

| Format | Example |
|--------|---------|
| Integer | `2` |
| Decimal | `2.5`, `0.5` |
| ASCII fraction | `1/2`, `3/4` |
| Mixed number | `2 1/2` (integer, space, fraction) |
| Vulgar fraction | `½`, `¼`, `¾`, `⅓`, `⅔`, `⅛`, `⅜`, `⅝`, `⅞` |
| Mixed vulgar | `2½` |
| Range | `2-3` (the high end is used) |

A unit may follow the numeric value, separated by a space:

    - Flour, 250 g
    - Milk, 1 cup
    - Vanilla extract, 1 tsp
    - Eggs, 2

Unit-less quantities are valid (as in `Eggs, 2`).

### Prep Note

An optional preparation instruction after the first colon:

    - Garlic, 3 cloves: Minced.
    - Butter, 115 g: Softened to room temperature.
    - Parmesan: Grated, for serving.

The prep note can itself contain colons:

    - Chocolate, 250 g: Use chips or bar: your choice.

### Examples

    - Salt                                  # name only
    - Flour, 250 g                          # name + quantity
    - Walnuts, 75 g: Roughly chop.          # name + quantity + prep note
    - Garlic: Minced                        # name + prep note (no quantity)
    - Rolled oats, 150 g                    # name + quantity (no unit qualifier)
    - Basil, a few leaves: Torn.            # non-numeric quantity

## Cross-References

A cross-reference imports another recipe's ingredients into a step. It uses
blockquote syntax with a special `@[Title]` marker:

    > @[Simple Tomato Sauce]

### Full Syntax

    > @[Recipe Title]
    > @[Recipe Title], multiplier
    > @[Recipe Title]: prep note
    > @[Recipe Title], multiplier: prep note

**Multiplier** — scales the referenced recipe's quantities. Can be an integer,
decimal, or fraction. Defaults to 1:

    > @[Pizza Dough], 2
    > @[Pizza Dough], 1/2
    > @[Pizza Dough], 0.5

**Prep note** — additional instructions for the referenced recipe:

    > @[Pizza Dough]: Let rest 30 min.
    > @[Pizza Dough], 2: Let rest 30 min.

A trailing period after the closing bracket is allowed and ignored:

    > @[Pizza Dough].

### Constraints

- Cross-references must appear inside explicit steps (with a `##` header).
  They are not valid in implicit steps.
- A step with a cross-reference cannot also contain ingredients or
  instructions.
- Only one cross-reference per step. To reference multiple recipes, use
  separate steps.

### Invalid Cross-Reference Forms

The multiplier must come after the title, not before:

    > 2 @[Pizza Dough]        # INVALID — use @[Pizza Dough], 2

Cross-references cannot appear as regular ingredient bullets:

    - @[Pizza Dough]           # INVALID — use > @[Pizza Dough]

## Footer

An optional section after a horizontal rule (`---`). Footer content is
free-form prose — it is not parsed for ingredients or steps:

    ---

    Substitute walnuts or chocolate chips for the raisins if you like.

Bare `@[Title]` references in the footer (or anywhere in prose) render as
clickable links to that recipe. These are render-time links only — they do not
create structural cross-references:

    ---

    This pairs well with @[Simple Salad].

Only the first `---` in the document marks the footer boundary.

## Error Cases

The parser rejects documents that violate these rules:

- First line is not `# Title`
- No steps (no ingredients, instructions, or cross-references)
- Cross-reference in an implicit step (no `##` header)
- Cross-reference mixed with ingredients in the same step
- Cross-reference mixed with instructions in the same step
- Multiple cross-references in the same step
- `@[Title]` used as an ingredient bullet instead of blockquote syntax
- Multiplier placed before the title (`2 @[Title]` instead of `@[Title], 2`)
- `Makes:` without a unit noun (`Makes: 12` instead of `Makes: 12 pancakes`)
