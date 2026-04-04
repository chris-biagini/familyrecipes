# Expert Mode Tuning — Prompt, Scoring, and Ralph Loop

**Date:** 2026-04-04
**Status:** Draft
**Supersedes:** Parts of `2026-04-04-expert-scoring-rubric-design.md` (scorer
directory structure, step structure judge design, style judge calibration,
prompt harmonization, loop configuration). The earlier spec established the
outcome fidelity + style two-judge architecture, aggregate formula, and runner
mode detection — those decisions carry forward unchanged.

## Problem

The expert mode scoring pipeline is functional but has two systemic issues:

1. **Step structure scoring is the weakest dimension** (69-79 across 10 of 12
   corpus recipes). The step structure judge was written for faithful mode —
   it penalizes reorganization and expects flat-list sources to produce
   implicit steps. Expert mode should REWARD intelligent reorganization and
   evaluate structural quality, not source-matching.

2. **The expert prompt needs harmonization** with a prior, more detailed prompt
   that captures the recipe collection's actual voice more precisely — sugar
   qualification, attribution format, unit steering, step splitting
   philosophy, and a richer common mistakes list.

Additionally, the scorer files are currently mixed together in a flat
`scorers/` directory. As we add expert-specific judges, we need clean
separation so that faithful and expert scoring can evolve independently.

## Constraints

- **No metric conversion.** The prompt must NOT instruct the model to convert
  units. AI conversions are unreliable. Instead, steer toward
  system-recognized unit abbreviations (`tbsp`, `tsp`, `cup`, `g`, `oz`,
  `lb`, `ml`, `fl oz`, `pt`, `qt`, `gal`).
- **Faithful mode untouched.** All changes to scoring infrastructure must
  leave the faithful pipeline working identically.
- **Parse/serialize round-trip preserved.** The algorithmic gates
  (ParseChecker, SystemCompatChecker) run on both modes — expert output must
  survive the same round-trip that faithful output does.

## File Structure

```
test/ai_import/
├── scorers/                              # Shared (algorithmic, mode-agnostic)
│   ├── parse_checker.rb
│   ├── format_checker.rb
│   └── system_compat_checker.rb
├── scorers/faithful/                     # Faithful LLM judges
│   ├── fidelity_judge_prompt.md              (moved from scorers/)
│   └── step_structure_judge_prompt.md        (moved from scorers/)
├── scorers/expert/                       # Expert LLM judges
│   ├── outcome_fidelity_judge_prompt.md      (moved from scorers/)
│   ├── step_structure_judge_prompt.md        (new)
│   └── style_judge_prompt.md                 (moved from scorers/, enriched)
├── loop_prompt.md                        # Faithful loop (unchanged)
├── loop_prompt_expert.md                 # Expert loop (new)
└── runner_v3.rb                          # Loads judges from scorers/<mode>/
```

**Rule:** `scorers/` = shared algorithmic gates. `scorers/<mode>/` = LLM
judge prompts. The runner resolves the subdirectory from the mode flag.

## Expert Prompt Harmonization

Changes to `lib/familyrecipes/ai_import_prompt_expert.md`:

### Sugar qualification

Change from "bare `Sugar` OK when source doesn't specify" to: always qualify
sugar — `Sugar (white)` or `Sugar (brown)`. Never bare `Sugar`. This matches
the collection's actual practice.

### Attribution format

Add explicit rule: always use "Based on a recipe from [Source](URL)." Never
"Adapted from" or "Inspired by."

### Unit steering

Replace the current unit-preservation guidance with:

> Normalize unit abbreviations to system-recognized forms: `tbsp`, `tsp`,
> `cup`, `oz`, `lb`, `g`, `ml`, `fl oz`, `pt`, `qt`, `gal`. Write `1 tbsp`
> not `1 tablespoon`, `2 cups` not `2 C.` Do not convert between unit
> systems — if the source says cups, keep cups; if grams, keep grams.

This steers output toward parseable units without risking bad conversions.

### Step splitting guidance

Significantly expand with patterns drawn from the collection:

- Steps are **phases of work**, not individual actions. A single step chains
  multiple actions in prose.
- **Disentangle interleaved operations.** If a source says "while the beans
  simmer, cook rice," separate into distinct steps. Parallel operations get
  their own phases.
- **Semicolons in headings** join related sub-actions:
  `## Cook pasta; combine with sauce.`
- **`## Finish and serve.`** is the standard final-step pattern when there's
  last-minute seasoning or plating.
- **`## Advance prep:`** prefix for things done ahead (e.g.,
  `## Advance prep: cook farro.`).
- **Simple recipes** (few ingredients, 1-2 sentences of instructions) get no
  headings — implicit step format.
- Typical recipe: 2-5 steps. Fewer is fine. More than 5 is a smell.
- **When in doubt, fewer steps.** A step represents a genuinely distinct
  phase.

### Voice tuning

Dial back "drop articles aggressively" to: "Drop articles where natural,
retain where dropping would sound robotic. Terse but human, not telegraphic."

Add these positive exemplars inline:
- "Correct for seasoning" / "Correct for salt, sweetness, acid, and heat."
- "Form into a neat ball"
- "Allow to rest and spread again, repeating as necessary"

### Common mistakes — expanded

Merge the old prompt's longer list. New entries not in current prompt:
- `kg` should be `g` (always use grams, not kilograms)
- "Ground cinnamon" → just "Cinnamon". "Fresh parsley" → just "Parsley".
  Default-form adjectives are unnecessary.
- Storage/make-ahead tips belong in the footer, not step instructions.
- Bare "Vanilla" → always "Vanilla extract".
- `Makes: 6 cups` without a noun → must be `Makes: 6 cups granola`.
- "Adapted from" or "Inspired by" → always "Based on a recipe from".

## Expert Step Structure Judge

New file: `scorers/expert/step_structure_judge_prompt.md`

**Philosophy:** Evaluate structural quality — "did the model create good
phases for this recipe?" Not source-matching.

### Dimensions (4 × 0-25 = 0-100)

**1. Phase Design (0-25)** — Did the model identify the right phases?
- 25: Steps map to natural cooking phases. Step count fits recipe complexity.
  Simple recipes use implicit format.
- 15-24: Reasonable phases but minor quibbles (an unnecessary split, a step
  that could merge with another).
- 0-14: Too many steps (one per source instruction) or too few (everything
  crammed together). Simple recipe given explicit steps when implicit was
  appropriate.
- Flag: single-instruction steps, steps with no ingredients AND only one
  sentence, 6+ steps for a straightforward recipe.

**2. Disentanglement (0-25)** — When the source interleaves parallel
operations, did the model separate them cleanly?
- 25: Parallel operations separated into distinct phases. No "meanwhile"
  instructions mixing unrelated work within a step.
- 15-24: Mostly clean but one interleaved operation left tangled.
- 0-14: Source's interleaved structure preserved verbatim — parallel tasks
  still mixed together.
- Auto-score 25 when the source has no interleaved operations.

**3. Ingredient Ownership (0-25)** — Same criteria as faithful version. Each
ingredient in one step, the step where it's primarily used. Ubiquitous
ingredients (oil, salt, pepper) OK in multiple steps with distinct roles.
- For implicit-step output: auto-score 25.

**4. Step Naming (0-25)** — Format AND quality.
- 25: Imperative sentences, sentence case, ending with period. Semicolons
  join related sub-actions. Names describe what you're doing, not the result.
  Examples: "Finish and serve.", "Cook pasta; combine with sauce.",
  "Brown butter and add to sugar mixture."
- 15-24: Acceptable but generic ("Prepare ingredients.") or miss a semicolon
  opportunity.
- 0-14: "Step 1" / numbered, or title-cased ("Make The Dough.").
- For implicit-step output: auto-score 25.

**Dropped from faithful version:** "Instruction Flow" (source-order
preservation). Expert mode deliberately reorganizes — penalizing reordering
is wrong.

### Calibration Exemplars

Three snippets from the collection:

1. **Fried Rice** — 4 clean phases (Cook rice / Prep / Cook / Finish and
   serve), shows "Correct for salt, sweetness, acid, and heat."
2. **Veggie Hash** — parallel operations cleanly separated (Advance prep:
   cook farro / Roast vegetables / Poach eggs / Assemble and serve).
3. **Nacho Cheese** — simple implicit step (5 ingredients, 2 sentences).

## Style Judge Enrichment

Changes to `scorers/expert/style_judge_prompt.md`:

### Voice dimension (0-13) — calibration refinement

Add flags for OVER-correction (telegraphic/robotic):
- Single-word sentence chains: "Heat. Add. Stir. Season."
- Stripped articles where retention is natural

Add positive target exemplars:
- "Correct for seasoning" / "Correct for salt, sweetness, acid, and heat."
- "Form into a neat ball"
- "Allow to rest and spread again, repeating as necessary"

### Description quality (0-12) — more exemplars

Add from the collection: "Vaguely Thai egg-fried rice.", "Mom's roasted
vegetables on farro with a poached egg", "Just a little sweet.", "Worth the
effort.", "Pasta and beans in a simple broth."

### Calibration exemplars — expand from 2 to 5

1. Fried Rice "Cook" + "Finish and serve" steps (existing)
2. Toast implicit step (existing)
3. Focaccia "Make dough and bulk ferment" step — mid-range voice, not
   maximally terse but economical
4. Chocolate Chip Cookies "Brown butter and add to sugar mixture" step —
   semicolon-style naming, concise technique prose
5. Pasta e Fagioli "Finish and serve" — the ideal two-sentence final step:
   "Correct for seasoning. Serve."

### No structural changes

All 8 dimensions, point allocations, and the JSON output schema remain the
same. The changes are calibration and exemplar enrichment only.

## Outcome Fidelity Judge Update

One addition to `scorers/expert/outcome_fidelity_judge_prompt.md` "Do NOT
Penalize" list:

- Unit abbreviation normalization to system-recognized forms (e.g.,
  "tablespoon" → "tbsp", "Cups" → "cups")

Everything else carries forward unchanged.

## Format Checker Update

`scorers/format_checker.rb` — make `step_splitting_appropriate` mode-aware:

- Add `expected_steps_expert` key to corpus `metadata.json` files
- In expert mode, the runner copies `metadata['expected_steps_expert']` into
  `metadata['expected_steps']` before passing to the checker — the checker
  itself stays mode-agnostic and always reads `expected_steps`
- The check logic is unchanged

### Corpus metadata updates

| Recipe | `expected_steps` (faithful) | `expected_steps_expert` |
|--------|-----------------------------|-------------------------|
| 03_blog_serious_eats_c | ambiguous | explicit |
| 04_blog_smitten_kitchen | implicit | explicit |
| 05_blog_budget_bytes | explicit | explicit |
| 06_blog_pioneer_woman | implicit | explicit |
| 07_blog_bon_appetit | ambiguous | explicit |
| 08_agg_allrecipes | implicit | explicit |
| 10_agg_epicurious | implicit | explicit |
| 11_agg_nyt_style | ambiguous | explicit |
| 12_ocr_biscuits | implicit | ambiguous |
| 13_ocr_beef_stew | explicit | explicit |
| 15_clean_text_message | implicit | implicit |
| 16_clean_email | implicit | ambiguous |

Rationale: expert mode reorganizes most recipes into explicit phases. Only
the text message recipe (very short, few ingredients) stays implicit. The
biscuit and email recipes are borderline — could reasonably go either way.

## Runner Changes

Changes to `runner_v3.rb`:

1. **Judge directory resolution.** Load LLM judge prompts from
   `scorers/faithful/` or `scorers/expert/` based on `expert_mode?`.
2. **Format checker mode key.** Pass `expected_steps_expert` metadata key
   when in expert mode.
3. **Require paths updated** for algorithmic scorers (stay in `scorers/`).

No changes to: aggregate formula, concurrency model, state tracking, CLI
interface, summary output format, JSON schemas.

## Ralph Loop — Expert Mode

New file: `loop_prompt_expert.md`

Same 5-step structure as the faithful loop:
1. Read state
2. Analyze failures
3. Edit prompt
4. Run evaluation
5. Check convergence

### Differences from faithful loop

**Target file:** `lib/familyrecipes/ai_import_prompt_expert.md`

**Runner invocation:**
```
ruby test/ai_import/runner_v3.rb --prompt=ai_import_prompt_expert.md --corpus=corpus_v3
```

**Analysis priority order:**
1. Step structure — weakest baseline dimension. Look for phase design and
   disentanglement issues.
2. Style voice — watch for over-correction (telegraphic) and under-correction
   (chatty blog voice surviving).
3. Footer discipline — invented content is a recurring problem.
4. Outcome fidelity — dropped ingredients or technique.

**Same convergence rules:** Patience counter at 2, restore best prompt on
convergence. Same "prefer removing/simplifying over adding" philosophy.

**Same constraints:** Never change scoring system, runner, or judge rubrics.
Never add a rule that only helps one recipe.

## Out of Scope

- Changes to the faithful scoring pipeline (faithful judges, faithful loop
  prompt, faithful prompt)
- New corpus recipes
- Metric unit conversion in the expert prompt
- Changes to the aggregate formula
- Changes to ParseChecker or SystemCompatChecker
