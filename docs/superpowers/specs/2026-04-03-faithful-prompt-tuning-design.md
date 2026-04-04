# Faithful Prompt Tuning — Design Spec

## Problem

The faithful AI import prompt scores well on existing corpora (96.9 avg on v1,
95.4 avg on v2) but has untested behavior around step splitting — when to use
implicit single-step format vs explicit multi-step `##` headers. The step
decision should be driven by the source recipe's ingredient structure, not by
editorial judgment. The scoring system also needs updating: the prior rounds
focused on format errors common with Haiku, but Sonnet rarely has those
issues. The emphasis should shift to system compatibility (scaling, round-trip
integrity, aggregation) and step-splitting correctness.

Additionally, the existing runner calls the Anthropic API directly. This round
replaces those calls with `claude --print` invocations to use Max plan tokens
instead of API billing.

## Design Decisions

- **Approach C1**: Ralph Loop for analysis + prompt editing; standalone Ruby
  runner script for evaluation via `claude --print`.
- **Convergence**: best-so-far with patience of 2 (exit after two consecutive
  non-improvements, restore best prompt version).
- **Corpus**: 20 new real-world recipes (scenario B inputs) as the primary
  evaluation set. Existing corpora retained for regression.
- **Scoring weights**: format 20%, fidelity 50%, step structure 30%. Parse +
  system compatibility is a binary gate.
- **Step-splitting rule**: source ingredient grouping drives the decision. Flat
  list stays implicit; grouped headings become explicit steps.

## Corpus v3

### Input Assumptions (Scenario B)

Users select the recipe section from the page — the recipe itself plus some
nearby crud (Print/Pin buttons, a nutrition panel, maybe 1-2 trailing
comments). Not the entire page with navigation, full blog post, and 50 reader
comments. The AI import dialog will include a hint:

> Copy and paste just the recipe. Try to leave out things like navigation links
> and comments. The importer will do its best to clean things up, but works
> best with clean input.

### 20 Recipes, Source Mix

| Category             | Count | Notes                                           |
|----------------------|-------|-------------------------------------------------|
| Food blogs           | 7     | Serious Eats (2-3), Smitten Kitchen, Budget Bytes, etc. |
| Recipe aggregators   | 4     | AllRecipes, Food.com, Epicurious, NYT Cooking-style |
| Cookbook OCR          | 3     | Scanned pages with OCR artifacts                |
| Clean / shared       | 3     | Text message, email, typed from memory          |
| International/metric | 3     | Metric-only, non-Western structure              |

### Step-Splitting Coverage

- 6+ flat-list recipes (should stay implicit)
- 5+ multi-component recipes (should split into explicit steps)
- 3+ ambiguous (soft groupings, no explicit headings)
- 2+ very simple (5 or fewer ingredients, definitely implicit)

### File Structure

```
test/ai_import/corpus_v3/
  01_blog_serious_eats_a/
    input.txt       # scenario B selection from page
    metadata.json   # { "source": "url", "expected_steps": "explicit" }
  02_blog_serious_eats_b/
    input.txt
    metadata.json
  ...
```

No gold-standard expected outputs. Scoring evaluates against the source text
and format rules, not a hand-crafted reference.

## Runner v3

### File

`test/ai_import/runner_v3.rb` — standalone Ruby script, no Rails boot.

### Pipeline Per Recipe

```
1. Import    claude --print --model sonnet  (faithful prompt + input)
2. Parse     Layer 1: parse checker + system compat  (local Ruby)
3. Format    Layer 2: format checker  (local Ruby)
4. Judge     Layer 3: claude --print  (fidelity rubric + original + output)
5. Steps     Layer 4: claude --print  (step structure rubric + original + output)
```

### Stage 1 — Import

The full faithful prompt template text is passed as part of the message to
`claude --print --model sonnet`. The input recipe text follows. The invocation
is self-contained — the subprocess has no reason to read project files.

Output cleaning: strip code fences, trim preamble before `# Title` (carried
forward from existing runner).

### Stages 2-3 — Algorithmic Scoring

Existing `Scorers::ParseChecker` and `Scorers::FormatChecker` from
`test/ai_import/scorers/`, plus new system compatibility checks (see Scoring
System section).

### Stages 4-5 — Judge Calls

Default model (Opus) via `claude --print`. Self-contained rubric in the
message. Returns JSON scorecard, parsed by the runner.

### Parallelism

Recipes are independent — run N in parallel via background processes.
Configurable concurrency flag (`--concurrency=5` default).

### CLI

```bash
ruby test/ai_import/runner_v3.rb [label]
ruby test/ai_import/runner_v3.rb --corpus=corpus_v3 [label]
ruby test/ai_import/runner_v3.rb --prompt=ai_import_prompt_faithful.md [label]
ruby test/ai_import/runner_v3.rb --concurrency=8 [label]
```

### Output Structure

```
test/ai_import/results/
  state.json        # convergence tracking (shared across iterations)
  iteration_LABEL/
    outputs/        # one .md per recipe
    scores.json     # per-recipe breakdown
    summary.md      # human-readable table + failure details
```

## Scoring System

### Layer 1 — Parse + System Compatibility (Gate)

Binary pass/fail. Any failure scores the recipe at 0.

| Check         | What it tests                                                |
|---------------|--------------------------------------------------------------|
| Parse         | `LineClassifier` + `RecipeBuilder` without `ParseError`      |
| Title present | Non-empty title                                              |
| Has ingredients | At least 1 ingredient parsed                               |
| Round-trip    | Parse, serialize via `RecipeSerializer.to_markdown`, re-parse. Compare title, ingredient count, step count — must match |
| Scaling       | All numeric quantities multiply by 2 without errors. Non-numeric quantities ("a handful") get a pass |

### Layer 2 — Format Rules (20% of Score)

Existing 11 checks from `FormatChecker` carried forward:

1. ASCII fractions only
2. Prep notes capitalized + period
3. Valid categories
4. No detritus (outside footer)
5. Single `---` divider
6. Step headers: sentence case + period
7. No code fences
8. Ingredient names ≤40 chars
9. No en-dashes
10. No comment bleed (outside footer)
11. Informal quantities preserved

Plus one new check:

12. **step_splitting_appropriate** — reads `metadata.json` for expected step
    behavior. If `implicit`: output has exactly 1 step with no `tldr`. If
    `explicit`: output has 2+ steps, each with a `tldr`. If `ambiguous`: pass
    regardless.

### Layer 3 — Fidelity Judge (50% of Score)

Existing rubric from `fidelity_judge_prompt.md`, invoked via `claude --print`
instead of API. Returns `fidelity_score` (0-100) and `detritus_score` (0-100).
Layer 3 value = average of the two.

Two-input mode (original + output, no reference) since corpus v3 has no gold
standards.

### Layer 4 — Step Structure Judge (30% of Score)

New rubric. Given original recipe text and AI output, evaluates:

| Criterion           | What it evaluates                                           |
|---------------------|-------------------------------------------------------------|
| Split decision      | Implicit vs explicit chosen appropriately for this source?  |
| Ingredient ownership| Ingredients grouped under the right step? No re-listing?    |
| Step naming         | Step names are meaningful phase descriptions, not "Step 1"? |
| Instruction flow    | Instructions follow the source's order? No reorganization?  |

Returns a single `step_structure_score` (0-100).

### Aggregate Formula

```
if layer1_fails: score = 0
else: score = (0.20 * format_pct) + (0.50 * fidelity_avg) + (0.30 * step_structure)
```

Where `fidelity_avg = (fidelity_score + detritus_score) / 2`.

### Convergence Tracking

`state.json` tracks iteration history and convergence:

```json
{
  "iterations": [
    { "label": "001", "avg": 92.3, "worst": 85.1, "prompt_sha": "abc123" }
  ],
  "best_iteration": "001",
  "best_avg": 92.3,
  "patience": 0
}
```

After each run: compare `avg` to `best_avg`. If improved, update best and
reset patience. If not, increment patience. At patience 2, stop and restore
the prompt from `best_iteration`'s `prompt_sha`.

The `prompt_sha` is computed by `git hash-object` on the prompt file before
each run. To restore: `git show <sha> > path/to/prompt.md`. This is more
precise than a commit hash — it identifies the exact file content regardless
of what else was committed alongside it.

## Faithful Prompt Updates

### Step-Splitting Rules

Replace the current "How to split steps" block (lines 119-129 of the faithful
prompt) with these rules:

**Rule 1 — Source groups ingredients, use explicit steps.** If the source
organizes ingredients under headings ("For the dough:", "Filling:", "Sauce
ingredients:", "To serve:"), each group becomes a `##` step. The source
already made the structural decision.

**Rule 2 — Source has a flat ingredient list, use implicit step.** If all
ingredients are in one undivided list, use the implicit-step format (no `##`
headers) regardless of how many numbered instructions follow. Do not
reorganize ingredients into phases.

**Rule 3 — Very simple recipes, use implicit step.** Five or fewer ingredients
with brief instructions — always implicit.

**Rule 4 — Ambiguous middle ground.** If the source has soft groupings (blank
lines between ingredient clusters, but no explicit headings), lean toward
implicit. Only split if the groupings are unmistakably distinct components
with different preparation methods.

**Key principle:** "The source's ingredient grouping drives the step structure.
If the source didn't group its ingredients, neither do you."

### Detritus Calibration

Update the detritus section to match scenario B expectations: "The user has
selected the recipe section from the page. You may see nearby buttons, a
nutrition panel, or a few trailing comments — strip these. You will not
typically see entire blog posts or dozens of reader comments."

### No Other Changes

Ingredient syntax, front matter, footer, OCR recovery, and decomposition
sections are well-tuned and unchanged.

## Ralph Loop

### Loop Prompt

A file containing instructions for each iteration:

1. Read `state.json` for current iteration count, best score, patience.
2. If not the first iteration, read the latest `summary.md` to analyze
   failures.
3. Make targeted edits to `lib/familyrecipes/ai_import_prompt_faithful.md`
   based on the failure analysis. Changes should be surgical — tweak a rule,
   add a clarification, adjust an example. Never rewrite from scratch.
4. Run `ruby test/ai_import/runner_v3.rb --corpus=corpus_v3 iteration_NNN`.
5. Read the new `summary.md` and `state.json`.
6. If patience reached 2: restore the best prompt version via `prompt_sha`,
   emit `<promise>FAITHFUL TUNED</promise>`.
7. Otherwise: let the loop continue.

### Constraints

- Do not change the scoring system or runner script.
- Do not add rules that help one recipe at the expense of others — watch the
  worst score, not just the average.
- Max iterations cap of 10 as a hard stop.
- Each prompt version is committed to git before running.

### First Iteration

The prompt edits from the "Faithful Prompt Updates" section above are applied
before starting the loop. Iteration 1 establishes a baseline by running the
runner against this updated prompt — no failure analysis needed.

### Invocation

```
/ralph-loop "path/to/loop_prompt.md" --max-iterations 10 --completion-promise "FAITHFUL TUNED"
```

## UI Hint

Add helper text below the textarea in the AI import dialog:

> Copy and paste just the recipe. Try to leave out things like navigation links
> and comments. The importer will do its best to clean things up, but works
> best with clean input.

Muted text styling, matching existing dialog hint patterns. Single line
addition to the import dialog partial.

## Out of Scope

- Expert prompt tuning (separate round, same infrastructure)
- Changes to `AiImportService` or `AiImportController` (prompt file is the
  only production artifact that changes)
- Corpus v1/v2 updates (retained as-is for regression)
- Changes to the parser or serializer
