# Permissive Recipe Parser

## Problem

`RecipeBuilder` silently drops content that doesn't fit the expected position.
The main gap is in `parse_explicit_steps()` line 112: any token that isn't a
`:step_header` before the first `##` header (but after front matter) is consumed
and discarded via `advance`. A secondary gap is in `collect_step_body()` where
the `case` statement doesn't handle all token types — stray `:front_matter` or
`:title` tokens inside a step body fall through unprocessed.

With AR records as the sole source of truth (no `markdown_source` column),
silently dropping input means permanent data loss.

## Approach

Make the parser permissive: instead of dropping unrecognized content, place it
in the nearest reasonable location. No warnings, no errors — just normalization.

- Prose between front matter and first step → appended to description
- Other tokens before first step → reconstructed as text, appended to description
- Unrecognized token types inside step body → reconstructed as text, treated as
  instruction prose

Round-trips normalize order without losing data: parse → serialize → re-parse
produces stable output.

## Changes

### 1. `token_as_text` helper

New private method on `RecipeBuilder` that reconstructs a line of text from a
token's type and content:

- `:prose` → `content` (already text)
- `:ingredient` → `"- #{content[0]}"`
- `:front_matter` → `"#{content[0]}: #{content[1]}"`
- `:title` → `"# #{content[0]}"`
- `:step_header` → `"## #{content[0]}"`
- Other → `Array(content).join(' ')`

### 2. `@description` instance variable

`parse_description()` currently returns inline. Change to set `@description`
ivar so that `parse_explicit_steps()` can append to it later. `build()` reads
`@description` instead of calling the method inline.

### 3. `parse_explicit_steps()` — absorb stray tokens

Replace `else advance` (line 112) with logic that appends stray token text to
`@description`. Specifically:

```ruby
else
  append_to_description(advance)
```

Where `append_to_description` joins with double-newline separator.

### 4. `collect_step_body()` — fallback for unrecognized tokens

Add `else` branch to the `case` statement that appends `token_as_text(token)`
to `instruction_lines`. This handles stray `:front_matter`, `:title`, etc.
inside step bodies.

## What doesn't change

- `LineClassifier` — unchanged
- `MarkdownValidator` — unchanged
- `RecipeSerializer` — unchanged
- Editor UI — no warnings flow needed
- `parse_description()` stays single-line — appending happens via ivar
- Well-formed recipes parse identically to today

## Testing

- Prose between front matter and first step → appears in description
- Ingredient before first step → appears in description as text
- Front matter inside step body → appears in step instructions as text
- Existing tests pass unchanged
- Round-trip: parse → serialize → re-parse produces stable output
