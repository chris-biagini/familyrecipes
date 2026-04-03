# AI Import Haiku Round 2: Real-World Corpus Tuning

## Problem

Round 1 tuned the Haiku prompt against synthetic test recipes, reaching 96.9
avg score. Synthetic inputs can't capture the full variety of real-world
recipe page copy-pastes — messy HTML artifacts, unexpected formatting, diverse
recipe structures, and noise patterns we didn't anticipate.

## Goal

Run a second ralph loop iteration using real-world recipes fetched from
actual food websites. Improve the prompt, scoring pipeline, and judge
prompt based on lessons learned from round 1.

## Changes from Round 1

### Prompt Changes

**Remove tags entirely.** Tags were the #1 source of errors across all
iterations — Haiku consistently invented tags from blog metadata, SEO
keywords, and subjective impressions. Since tags are optional and easily
added by the user later, remove the `{{TAGS}}` placeholder and all tag
guidance from the prompt.

**Allow "Optional." as a prep note.** Optional ingredients should remain as
proper ingredient lines with `Optional.` as the prep note:
`- Sesame seeds, 10 g: Optional.` This keeps them parseable and visible
on the grocery list. The prompt's prep note definition broadens to include
ingredient-specific notes beyond strict mise en place (e.g., brief
substitution hints, "Optional.", temperature notes).

**Preserve informal quantities in the quantity field.** The parser handles
strings like `- Olive oil, a generous pour` cleanly (name: "Olive oil",
quantity: "a generous pour"). Nothing downstream breaks — display works,
scaling is skipped, grocery list shows the ingredient (without quantity,
which is acceptable). The prompt should instruct Haiku to keep informal
quantities as-is in the quantity position rather than omitting them or
moving them to instructions.

### Corpus Changes

**Real-world recipes.** 10 recipes fetched from actual food websites via
WebFetch. The raw text (as a user would get from select-all + copy) becomes
`input.txt`. No `expected.md` gold-standard files.

**Corpus directory:** `test/ai_import/corpus_v2/` (preserves round 1
corpus in `corpus/`).

**Target variety:**
- 3-4 food blog posts (varying preamble length and cruft)
- 2-3 recipe card widget pages
- 2-3 clean/structured recipe sites (e.g., NYT Cooking style, AllRecipes)
- 1 scan/OCR-style if available, otherwise another blog variant

### Scoring Changes

**Layer 1 — Parse check:** Remove the ingredient count comparison (no gold
standard to compare against). Check only: does it parse without errors?
Does it produce a title? Does it have at least 1 ingredient?

**Layer 2 — Format check:** Add two new algorithmic checks:

1. **Informal quantity preservation.** Scan the input for patterns like
   "generous", "handful", "about", "pinch", "or so", "give or take",
   "to taste" (as a phrase, not in our format). If any appear near an
   ingredient context, verify the informal language survives somewhere in
   the output (ingredient quantity field or instructions).

2. **Comment section pattern detection.** Scan the output (excluding
   footer) for patterns suggesting comment section bleed: `says:`,
   `Reply`, `★` followed by reviewer text, "I made this", "loved it".

**Layer 3 — Sonnet judge prompt improvements:**

1. **Add ingredient syntax spec.** Teach the judge the format
   `- Name, quantity: Prep note.` so it can distinguish "prep in the
   name field" (before the comma — bad) from "prep in the prep note
   field" (after the colon — correct). Rename `prep_in_name` to
   `prep_leaked_into_name` and define it precisely.

2. **Add `tags_invented` field.** Detect if Haiku sneaks in a `Tags:`
   front matter line despite tags being removed from the prompt.

3. **Remove gold-standard reference.** The judge prompt changes from
   three-input (original + output + reference) to two-input (original +
   output). Scoring rubric stays the same: fidelity 0-100, detritus
   removal 0-100.

4. **Clarify fidelity scoring for informal quantities.** The judge
   should NOT penalize informal quantities appearing in the quantity
   field — `- Olive oil, a generous pour` is correct if the source
   says "a generous pour of olive oil."

### Runner Changes

**Corpus directory configurable.** The runner accepts an optional
`--corpus` flag to point at `corpus_v2/` instead of the default `corpus/`.
Default remains `corpus/` for backward compatibility.

**No expected.md loading.** When no `expected.md` exists in a corpus
directory, the runner skips the ingredient count check and passes only
original + output to the Sonnet judge (no reference).

**Summary includes raw Haiku output snippets for failing recipes.** When
a recipe scores below 90, the summary includes the first 20 lines of the
Haiku output to help the ralph loop agent diagnose issues without reading
separate files.

## Convergence Criteria

Same as round 1: overall > 85 AND worst > 70, OR 8 iterations. Given
we're starting from a prompt that already scores 96.9 on synthetic data,
the real-world corpus may expose new failure modes that pull scores down
initially.

## Files Changed

| File | Change |
|------|--------|
| `test/ai_import/prompt_template.md` | Remove tags, add Optional prep note, informal quantity guidance |
| `test/ai_import/runner.rb` | Configurable corpus dir, optional expected.md, output snippets in summary |
| `test/ai_import/scorers/parse_checker.rb` | Remove ingredient count check when no expected count provided |
| `test/ai_import/scorers/format_checker.rb` | Add informal quantity + comment section checks |
| `test/ai_import/scorers/fidelity_judge_prompt.md` | Two-input mode, ingredient syntax spec, tags_invented field |
| `test/ai_import/corpus_v2/*/input.txt` | 10 real-world recipe inputs (new) |
| `lib/familyrecipes/ai_import_prompt.md` | Updated with tuned prompt after convergence |
| `app/services/ai_import_service.rb` | Remove `{{TAGS}}` interpolation |
