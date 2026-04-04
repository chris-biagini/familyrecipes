# Expert Scoring Rubric Design

**Date:** 2026-04-04
**Status:** Draft

## Problem

The AI import evaluation pipeline (`test/ai_import/runner_v3.rb`) currently
scores output against the faithful prompt only. The expert prompt produces
condensed, editorially-voiced output that the faithful scoring layers
penalize incorrectly — text fidelity judges flag successful condensation as
information loss, and no layer evaluates whether the output matches the
familyrecipes expert style.

We need:
1. A **style judge** that scores how well output matches the sample recipe voice
2. An **outcome fidelity judge** that asks "would an expert produce the same
   dish?" instead of "was the text preserved?"
3. Runner support for mode-specific scoring pipelines and aggregate formulas

## Design Decisions

- **Two separate LLM judge calls** (outcome fidelity and style), not one
  combined call. Each judge is focused, independently tunable, and produces
  clear failure attribution for the Ralph Loop.
- **Outcome fidelity assumes a highly competent reader.** Only flag genuine
  information loss (missing ingredients, wrong temperatures, unique technique
  dropped). Successful condensation of generic/obvious material scores 100.
- **Style rubric is rule-based with exemplar supplement.** 8 concrete
  dimensions distilled from the sample recipes, plus 2 short recipe snippets
  as calibration anchors. No full example recipes in the judge prompt.
- **Same corpus for both modes.** `corpus_v3` inputs work for faithful and
  expert — the input recipes don't change, just the expected output style.

## Aggregate Formula

```
Expert:  0.10 * format + 0.40 * ((outcome_fid + det) / 2) + 0.25 * step_structure + 0.25 * style
```

For comparison, faithful mode:
```
Faithful: 0.20 * format + 0.50 * ((fid + det) / 2) + 0.30 * step_structure
```

Rationale: format rules are shared and should score high out of the gate
(low weight). Outcome fidelity is the most important dimension — don't lose
the recipe. Step structure and style are equally weighted secondary signals.

## Style Judge

### Prompt Structure

The style judge receives the OUTPUT only (no need for the original). It
scores against 8 dimensions, returns per-dimension scores and issue arrays.

### Dimensions (0-100 total)

| # | Dimension              | Points | Checks                                                                                                  |
|---|------------------------|--------|---------------------------------------------------------------------------------------------------------|
| 1 | Voice                  | 0-13   | Imperative mood. Articles dropped. No "you/your". No hedging ("you may want to", "feel free to").       |
| 2 | Condensation           | 0-13   | Obvious basics omitted (how to preheat, how to knead, what simmering looks like). Generic technique     |
|   |                        |        | tutorials stripped. No "preferably homemade" type editorializing.                                       |
| 3 | Specificity preserved  | 0-13   | Temperatures, times, visual cues, recipe-specific techniques retained. Non-obvious warnings kept.       |
|   |                        |        | Things that distinguish THIS recipe from the default approach.                                          |
| 4 | Title quality          | 0-12   | Short, descriptive, no superlatives ("The Best"), no clickbait, no "Recipe for" prefix. Title case.     |
| 5 | Description quality    | 0-12   | Punchy, casual, under ~10 words. Kitchen Post-it tone. Absent is OK for very simple recipes.            |
| 6 | Instruction prose      | 0-13   | Reads as natural prose, not bullet points or numbered steps. Sequences flow. Terse but human, not       |
|   |                        |        | telegraphic or robotic.                                                                                 |
| 7 | Footer discipline      | 0-12   | No invented tips or substitutions. Attribution preserved. Useful source context kept. No repackaging     |
|   |                        |        | of inline content as footer notes.                                                                      |
| 8 | Economy                | 0-12   | Remaining prose is lean — no filler words, no repetition, no over-explanation. Distinct from             |
|   |                        |        | condensation (what to cut); economy is about whether what remains is tight.                              |

### Exemplar Snippets

Two short excerpts included in the judge prompt as calibration anchors:

1. **Multi-step** (Fried Rice-style): shows terse instructions, phase-based
   steps, ingredient grouping, "Correct for salt, sweetness, acid, and heat.
   Serve."
2. **Implicit-step** (Toast-style): shows the minimal end — ingredients,
   one sentence of instructions, done.

These are trimmed excerpts, not full recipes. Enough to show the voice
without bloating the prompt.

### Output Schema

```json
{
  "voice_score": 13,
  "voice_issues": [],
  "condensation_score": 13,
  "condensation_issues": [],
  "specificity_score": 13,
  "specificity_issues": [],
  "title_score": 12,
  "title_issues": [],
  "description_score": 12,
  "description_issues": [],
  "prose_score": 13,
  "prose_issues": [],
  "footer_score": 12,
  "footer_issues": [],
  "economy_score": 12,
  "economy_issues": [],
  "style_score": 100
}
```

`style_score` is the sum of all dimension scores (0-100).

## Outcome Fidelity Judge

### Prompt Structure

Receives ORIGINAL + OUTPUT. Evaluates whether an expert following the OUTPUT
would produce the same dish as the ORIGINAL describes.

### Penalize

- Missing ingredients that affect the dish
- Changed quantities (wrong amounts, unit conversion errors)
- Wrong temperatures or times
- Dropped technique that is unique to this recipe (e.g., "don't use a stand
  mixer" for bagel dough, "fold gently" for gnocchi)
- Hallucinated ingredients or instructions not in the source
- Invented footer notes (substitutions, tips not in the source)

### Do NOT Penalize

- Condensed phrasing (3 paragraphs to 1 sentence, if meaning survives)
- Dropped generic technique tutorials (how to knead, how to judge oil temp)
- Dropped common-sense notes (open a window, use homemade stock)
- Omitted "obvious" steps an expert would do anyway (wash hands, gather
  ingredients, season as you go)
- Reworded instructions that preserve the outcome
- Serves/Makes range collapsed to lower bound
- Temperature format normalization ("350 degrees" to "350 F")
- Dropping "about" from Makes/Serves lines
- Range normalization ("2 to 3" to "2-3")

### Output Schema

```json
{
  "ingredients_missing": [],
  "ingredients_added": [],
  "quantities_changed": [],
  "technique_lost": [],
  "outcome_affected": [],
  "detritus_retained": [],
  "outcome_fidelity_score": 85,
  "detritus_score": 95
}
```

`technique_lost` captures unique-to-this-recipe technique that was dropped.
`outcome_affected` captures any other way the output would produce a
different dish. These replace the faithful judge's `instructions_dropped`
and `instructions_rewritten`.

## Runner Changes

### Mode Detection

The runner detects mode from the prompt filename: if it contains `expert`,
use the expert scoring pipeline; otherwise, faithful.

```ruby
def expert_mode?
  @prompt_file.include?('expert')
end
```

### Scoring Pipeline by Mode

| Layer | Faithful                       | Expert                              |
|-------|--------------------------------|-------------------------------------|
| 1     | Parse + Compat (hard gate)     | same                                |
| 2     | FormatChecker                  | same                                |
| 3     | `fidelity_judge_prompt.md`     | `outcome_fidelity_judge_prompt.md`  |
| 4     | `step_structure_judge_prompt.md` | same                              |
| 5     | *(n/a)*                        | `style_judge_prompt.md`             |

### Aggregate Function

```ruby
def aggregate_score(gate_pass, format_result, fidelity, step, style = nil)
  return 0.0 unless gate_pass

  fmt = format_result.score * 100.0
  det = (fidelity['detritus_score'] || 0).to_f
  stp = (step['step_structure_score'] || 0).to_f

  if expert_mode?
    fid = (fidelity['outcome_fidelity_score'] || 0).to_f
    sty = (style['style_score'] || 0).to_f
    (0.10 * fmt) + (0.40 * ((fid + det) / 2.0)) + (0.25 * stp) + (0.25 * sty)
  else
    fid = (fidelity['fidelity_score'] || 0).to_f
    (0.20 * fmt) + (0.50 * ((fid + det) / 2.0)) + (0.30 * stp)
  end
end
```

### Summary Output

Expert mode adds a `style` column to the results table. Failure details
include new issue categories: STYLE (with sub-dimensions), TECHNIQUE_LOST,
OUTCOME_AFFECTED.

### State Tracking

No changes needed. `state.json` already tracks prompt SHA and label. Expert
and faithful runs produce separate state since they reference different
prompt files.

## New Files

| File | Purpose |
|------|---------|
| `test/ai_import/scorers/outcome_fidelity_judge_prompt.md` | LLM rubric for outcome-based fidelity |
| `test/ai_import/scorers/style_judge_prompt.md` | LLM rubric for expert style scoring |

Schema constants `OUTCOME_FIDELITY_SCHEMA` and `STYLE_SCHEMA` are added to
the runner alongside the existing `FIDELITY_SCHEMA` and
`STEP_STRUCTURE_SCHEMA`.

## Expert Prompt Baseline Adjustments

Before running the Ralph Loop, sync the expert prompt with fixes from the
faithful prompt work and sharpen the condensation guidance:

1. **Condensation examples.** Add a concrete list of things that "go without
   saying": technique tutorials (how to knead), common-sense advice (open a
   window, use homemade stock), generic cooking advice (don't crowd the pan).
2. **Title guidance.** Add: no clickbait, keep short and descriptive.
3. **Sugar qualification.** Change from "always qualify" to "only qualify
   when the source specifies type" (matches faithful prompt fix).
4. **Serves/Makes range.** Clarify: use the lower bound of ranges (matches
   faithful prompt).
5. **Sync other faithful fixes.** Descriptor preservation, "or more"
   verbatim, weight equivalents in parentheses.

## Out of Scope

- Changes to the faithful scoring pipeline
- New corpus recipes
- FormatChecker changes (same algorithmic checks apply to both modes)
- Changes to the step structure judge prompt
