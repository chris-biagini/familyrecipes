# AI Import: Haiku Pure-Transcription Redesign

## Problem

The current AI import uses Sonnet with a 343-line prompt that aggressively
rewrites recipes (voice transformation, article dropping, description
generation). Users can't trust the output without manually comparing it to the
source, which defeats the purpose of an import tool.

## Goal

Replace the Sonnet editorial-rewrite approach with a Haiku
pure-transcription approach. Haiku strips non-recipe detritus and maps the
recipe into our Markdown format without changing the author's words. Fidelity
is the core value — the user should be able to trust that the imported recipe
matches the original.

A prompt-tuning ralph loop iterates on the Haiku prompt using a test corpus
and a three-layer scoring pipeline (algorithmic format checks + Sonnet
fidelity judge).

## Design Decisions

- **Haiku over Sonnet**: cheaper (future paid-user feature), simpler task
  (transcription not rewriting), less room for unwanted creativity.
- **Pure transcription**: preserve the original's wording. Only
  transformations are structural (ingredient line syntax, step grouping) and
  mechanical (ASCII fractions, unit abbreviation normalization, prep note
  capitalization).
- **Drop multi-turn feedback**: one-shot pipeline. User edits the output
  directly if needed.
- **Dynamic categories/tags**: interpolated from the kitchen at call time,
  not hard-coded in the prompt.
- **Hybrid scoring**: algorithmic for format compliance, Sonnet judge for
  fidelity. Haiku never scores itself.

## Prompt Design

### Structure

The prompt template (~150-180 lines) has three sections:

1. **Job description** (~20 lines): identify the recipe, strip detritus,
   preserve fidelity. Explicit "do not rewrite" constraint.
2. **Format specification** (~80 lines): ingredient syntax, step headers,
   front matter, footer, formatting rules (ASCII fractions, ranges, units,
   prep notes). Carried over from the current prompt with voice directives
   stripped.
3. **Examples** (~50 lines): the Detroit Pizza example (full recipe) plus
   5-6 ingredient decomposition examples.

### Dynamic Slots

The template contains two placeholder markers interpolated at call time:

- `{{CATEGORIES}}` — the kitchen's current category names plus
  "Miscellaneous" as fallback. Rendered as a comma-separated list.
- `{{TAGS}}` — the kitchen's current tag names. Rendered as a
  comma-separated list with the instruction: "Apply tags only when they are
  an obvious match. Do not stretch. Omit tags entirely if nothing fits."

### What Stays from Current Prompt

- Ingredient line syntax: `- Name, qty unit: Prep note.`
- Step header format: `## Imperative phrase.` (sentence case, period)
- Front matter fields: Makes, Serves, Category, Tags
- Footer conventions: single `---`, attribution, substitutions
- Formatting rules: ASCII fractions, mixed numbers, ranges, unit spacing,
  prep note capitalization, metric decimals vs imperial fractions
- Common mistakes checklist (format-level items only)
- Detroit Pizza complete example

### What Gets Stripped

- All voice directives (article dropping, "terse, confident, personal")
- Description-writing guidelines (use original's description or omit)
- Instruction rewriting guidance ("compress equipment setup", "strip
  obvious basics")
- Substitution reorganization rules
- "Moderately experienced home cook" audience framing

### What's New

**Do-not-rewrite constraint**: a strong negative instruction at the top of
the prompt. Haiku needs explicit guardrails against paraphrasing.

**Detritus removal guidance**: a short list of things to strip — blog
preamble/life stories, navigation text, "Print/Pin/Save/Jump to Recipe"
buttons, star ratings, comment sections, SEO paragraphs, newsletter signups,
affiliate links, nutrition panels. If in doubt, strip it.

**Ingredient decomposition examples**: 5-6 before/after pairs teaching Haiku
to split complex ingredient descriptions into name + qualifier + quantity +
prep note + footer:

```
Source: "2 boneless chicken breasts, skin removed, cut into strips
        (can substitute thighs if desired)"
Result:
  - Chicken breasts (boneless, skinless), 2: Cut into strips.
  Footer: Can substitute thighs for chicken breasts.

Source: "1 cup Greek yogurt (full-fat works best), strained"
Result:
  - Yogurt (Greek), 1 cup: Strained.
  Footer: Full-fat yogurt works best.

Source: "3 large ripe tomatoes, roughly chopped"
Result:
  - Tomatoes, 3: Roughly chopped.

Source: "Salt and pepper to taste"
Result:
  - Salt
  - Black pepper

Source: "1/2 stick (4 tbsp) unsalted butter, melted and cooled"
Result:
  - Butter (unsalted), 4 tbsp: Melted and cooled.

Source: "2 lbs bone-in, skin-on chicken thighs (about 6)"
Result:
  - Chicken thighs (bone-in, skin-on), 2 lbs
```

The guiding principle for ingredient names: **the words you'd scan the
grocery aisle for, plus the parenthetical that tells you which variant to
grab.** Everything else fans out to quantity, prep note, or footer.

**Tag guidance**: instruction to apply only obvious-match tags from the
kitchen's list. Never invent tags not in the list. When in doubt, omit.

**OCR recovery hints**: basic guidance for handling garbled text —
reconstruct fractions (`l/2` -> `1/2`), fix run-together words, infer
missing line breaks between ingredients.

## Test Corpus

Ten test recipes stored in `test/ai_import/corpus/`, each as an
`input.txt` + `expected.md` pair:

| # | Dir Name | Input Type | Complexity | Description |
|---|----------|-----------|------------|-------------|
| 1 | `01_blog_simple` | Food blog | Simple | Short recipe buried in 500+ words of blog preamble, life story, SEO |
| 2 | `02_blog_medium` | Food blog | Medium | Multi-step recipe with "Jump to Recipe", newsletter CTAs, affiliate links |
| 3 | `03_blog_complex` | Food blog | Complex | Multi-component recipe (dough + filling + glaze), tips scattered between paragraphs, print footer cruft |
| 4 | `04_card_simple` | Recipe card widget | Simple | Clean structured recipe with "Print", "Pin", "Save" buttons, star ratings, nutrition panel |
| 5 | `05_card_medium` | Recipe card widget | Medium | Multi-step with equipment list, "Did you make this?" prompt, comment bleed-through |
| 6 | `06_card_complex` | Recipe card widget | Complex | Both metric and imperial, video embed placeholder, "Recipe Notes" section |
| 7 | `07_ocr_simple` | OCR / cookbook | Simple | Clean scan with minor artifacts — missing line breaks, run-together words |
| 8 | `08_ocr_medium` | OCR / cookbook | Medium | Noisier — garbled punctuation, `l/2` fractions, lost section headers |
| 9 | `09_clean_simple` | Handwritten | Simple | Already well-structured, just needs formatting |
| 10 | `10_clean_medium` | Handwritten | Medium | Multi-step, informal ("a big handful of cheese", "cook til done") |

All inputs are synthetic but realistic. Blog inputs include plausible
preamble text, navigation elements, and ad copy. OCR inputs include
realistic scan artifacts. Expected outputs are hand-written gold standards
in the app's Markdown format.

The corpus uses a fixed category list (Baking, Bread, Breakfast, Dessert,
Drinks, Holiday, Mains, Pizza, Sides, Snacks, Miscellaneous) and a fixed
tag subset for consistent scoring across iterations.

## Scoring Pipeline

### Layer 1: Parse Check (pass/fail)

Feed output through `LineClassifier` -> `RecipeBuilder`:

- Does it parse without errors?
- Does it produce a valid `FamilyRecipes::Recipe` with a title?
- Does it have at least as many ingredients as the gold standard?

A parse failure zeros out the recipe's entire score.

### Layer 2: Format Rules (points-based)

Algorithmic checks, each pass/fail:

| Check | Method |
|-------|--------|
| ASCII fractions only | Regex scan for vulgar fraction chars |
| Prep notes capitalized + period | Regex on parsed prep fields |
| Unit normalization | Check against allowed unit strings |
| Valid front matter | Category in list, Serves is a number |
| No residual detritus | Scan for known junk: "Print", "Pin It", "Jump to Recipe", "Did you make this", star ratings, URLs outside footer, email signup language |
| Single `---` divider | Count divider tokens |
| Step headers: sentence case + period | Regex on step names |
| No code fences | Check for triple backticks |
| Ingredient names under 40 chars | Flag likely under-decomposed names |

Score: percentage of checks passed, equally weighted.

### Layer 3: Fidelity Judge (Sonnet)

A structured Sonnet API call. Sonnet receives the original input, Haiku's
output, and the gold-standard expected output. It returns a JSON scorecard:

```json
{
  "ingredients_missing": [],
  "ingredients_added": [],
  "quantities_changed": [],
  "instructions_dropped": [],
  "instructions_rewritten": [],
  "detritus_retained": [],
  "prep_in_name": [],
  "fidelity_score": 85,
  "detritus_score": 90
}
```

- **fidelity_score** (0-100): 100 = nothing lost or added, 0 =
  unrecognizable.
- **detritus_score** (0-100): 100 = perfectly clean, 0 = blog post
  untouched.
- **prep_in_name**: flags ingredient names where preparation instructions
  or substitution info leaked into the name instead of prep note/footer.

### Aggregate Score

Per recipe:

```
parse_pass ? (0.3 * format_pct + 0.4 * fidelity + 0.3 * detritus) : 0
```

Overall: mean across all 10 recipes, plus worst-recipe score tracked
separately to catch regressions.

Fidelity weighted highest — it's the core value proposition.

## Ralph Loop Structure

### Directory Layout

```
test/ai_import/
  corpus/                        # Static test recipes
    01_blog_simple/
      input.txt
      expected.md
    ...
    10_clean_medium/
  prompt_template.md             # The prompt being iterated on
  runner.rb                      # Orchestrator script
  scorers/
    parse_checker.rb             # Layer 1
    format_checker.rb            # Layer 2
    fidelity_judge_prompt.md     # Layer 3 Sonnet prompt
  results/                       # Per-iteration outputs
    iteration_001/
      outputs/                   # Haiku output per recipe
        01_blog_simple.md
        ...
      scores.json                # Per-recipe scorecards
      summary.md                 # Human-readable rollup
  README.md
```

### Runner Script

`runner.rb` is a standalone Ruby script (not a rake task). It:

1. Loads `prompt_template.md`, interpolates a fixed category/tag list
2. For each corpus recipe: calls Haiku via the Anthropic Ruby SDK, stores
   output to `results/iteration_NNN/outputs/`
3. Runs Layer 1 (parse) and Layer 2 (format) checks algorithmically by
   loading the parser classes from `lib/familyrecipes/`
4. Calls Sonnet for Layer 3 fidelity judging on each recipe
5. Writes `scores.json` and `summary.md`

Invocation: `ANTHROPIC_API_KEY=sk-... ruby test/ai_import/runner.rb [iteration_label]`

The script requires the `anthropic` gem (already in the Gemfile) and loads
the parser classes directly from `lib/familyrecipes/` (no Rails boot needed
— the parser classes are plain Ruby loaded via
`config/initializers/familyrecipes.rb`, which the runner can replicate
with a few `require` statements).

### Ralph Loop Cycle

The ralph loop agent (a Claude Code session using the ralph-loop skill):

1. Runs the runner script via Bash, reads `summary.md`
2. Identifies lowest-scoring recipes and most common failure patterns
3. Edits `prompt_template.md` to address failures
4. Runs the runner again, compares scores to previous iteration
5. Repeats until convergence

**Convergence criteria**: stop when overall score > 85 AND worst single
recipe > 70, OR after 8 iterations (whichever first). Thresholds are
tunable.

**Cost**: ~$0.10-0.20 per iteration (10 Haiku + 10 Sonnet calls). Full
8-iteration loop under $2. All calls use the user's API key via env var.

## Service Changes

After the ralph loop converges:

### AiImportService

- Model: `claude-sonnet-4-6` -> `claude-haiku-4-5`
- Remove `previous_result` and `feedback` parameters
- `build_messages` simplifies to single user message
- Prompt loading: read template, interpolate `{{CATEGORIES}}` from
  `current_kitchen.categories.pluck(:name)` + "Miscellaneous" and
  `{{TAGS}}` from `current_kitchen.tags.pluck(:name)`
- `clean_output` stays (strip code fences)
- Timeout: 90s -> 30s
- Error handling: unchanged

### Kitchen Model

- `AI_MODEL` constant: `claude-sonnet-4-6` -> `claude-haiku-4-5`

### ai_import_controller.js

- No UI changes needed. The feedback loop was supported in the service but
  never exposed in the dialog UI.

### Prompt Template

- `lib/familyrecipes/ai_import_prompt.md` replaced with the ralph-loop-tuned
  version containing `{{CATEGORIES}}` and `{{TAGS}}` placeholders.

### Tests

- `AiImportServiceTest` updated for single-turn, Haiku model, template
  interpolation with dynamic categories/tags.
- Test corpus and runner in `test/ai_import/` are development tools, not
  part of `rake test`.
