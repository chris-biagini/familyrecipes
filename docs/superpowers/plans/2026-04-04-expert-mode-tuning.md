# Expert Mode Tuning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the expert mode AI import by harmonizing the prompt with the collection's actual voice, building expert-specific scoring judges, reorganizing scorer files by mode, and wiring up the Ralph Loop for iterative tuning.

**Architecture:** Scorer directory split (`scorers/faithful/`, `scorers/expert/`) with shared algorithmic gates in `scorers/`. Runner resolves judge prompts from mode-specific subdirectories. Expert step structure judge evaluates quality (not source-matching). Ralph Loop targets expert prompt with mode-specific loop instructions.

**Tech Stack:** Ruby (standalone scripts, no Rails), Anthropic Claude CLI, Markdown prompt files, JSON metadata

---

### Task 1: Reorganize scorer directory structure

Move LLM judge prompts into mode-specific subdirectories. Algorithmic scorers stay in `scorers/`.

**Files:**
- Move: `test/ai_import/scorers/fidelity_judge_prompt.md` → `test/ai_import/scorers/faithful/fidelity_judge_prompt.md`
- Move: `test/ai_import/scorers/step_structure_judge_prompt.md` → `test/ai_import/scorers/faithful/step_structure_judge_prompt.md`
- Move: `test/ai_import/scorers/outcome_fidelity_judge_prompt.md` → `test/ai_import/scorers/expert/outcome_fidelity_judge_prompt.md`
- Move: `test/ai_import/scorers/style_judge_prompt.md` → `test/ai_import/scorers/expert/style_judge_prompt.md`

- [ ] **Step 1: Create subdirectories and move faithful judges**

```bash
mkdir -p test/ai_import/scorers/faithful
git mv test/ai_import/scorers/fidelity_judge_prompt.md test/ai_import/scorers/faithful/
git mv test/ai_import/scorers/step_structure_judge_prompt.md test/ai_import/scorers/faithful/
```

- [ ] **Step 2: Create expert directory and move expert judges**

```bash
mkdir -p test/ai_import/scorers/expert
git mv test/ai_import/scorers/outcome_fidelity_judge_prompt.md test/ai_import/scorers/expert/
git mv test/ai_import/scorers/style_judge_prompt.md test/ai_import/scorers/expert/
```

- [ ] **Step 3: Verify directory structure**

```bash
find test/ai_import/scorers -type f | sort
```

Expected:
```
test/ai_import/scorers/expert/outcome_fidelity_judge_prompt.md
test/ai_import/scorers/expert/style_judge_prompt.md
test/ai_import/scorers/faithful/fidelity_judge_prompt.md
test/ai_import/scorers/faithful/step_structure_judge_prompt.md
test/ai_import/scorers/format_checker.rb
test/ai_import/scorers/parse_checker.rb
test/ai_import/scorers/system_compat_checker.rb
```

- [ ] **Step 4: Commit**

```bash
git add -A test/ai_import/scorers/
git commit -m "Reorganize scorer directory: faithful/ and expert/ subdirectories"
```

---

### Task 2: Update runner to load judges from mode-specific directories

**Files:**
- Modify: `test/ai_import/runner_v3.rb:516-532` (rubric loading in `run_evaluation`)
- Modify: `test/ai_import/runner_v3.rb:258-277` (metadata swap in `process_recipe`)

- [ ] **Step 1: Update rubric loading in `run_evaluation`**

In `runner_v3.rb`, replace the rubric loading block (lines 527-532):

```ruby
  fidelity_prompt = expert_mode?(opts) ? 'outcome_fidelity_judge_prompt.md' : 'fidelity_judge_prompt.md'
  rubrics = {
    fidelity: File.read(File.join(BASE_DIR, 'scorers', fidelity_prompt)),
    step: File.read(File.join(BASE_DIR, 'scorers', 'step_structure_judge_prompt.md'))
  }
  rubrics[:style] = File.read(File.join(BASE_DIR, 'scorers', 'style_judge_prompt.md')) if expert_mode?(opts)
```

with:

```ruby
  mode_dir = File.join(BASE_DIR, 'scorers', expert_mode?(opts) ? 'expert' : 'faithful')
  fidelity_prompt = expert_mode?(opts) ? 'outcome_fidelity_judge_prompt.md' : 'fidelity_judge_prompt.md'
  rubrics = {
    fidelity: File.read(File.join(mode_dir, fidelity_prompt)),
    step: File.read(File.join(mode_dir, 'step_structure_judge_prompt.md'))
  }
  rubrics[:style] = File.read(File.join(mode_dir, 'style_judge_prompt.md')) if expert_mode?(opts)
```

- [ ] **Step 2: Add expert step structure schema**

After the existing `STEP_STRUCTURE_SCHEMA` constant (around line 120), add:

```ruby
EXPERT_STEP_STRUCTURE_SCHEMA = {
  type: 'object',
  properties: {
    split_decision: { type: 'string' },
    phase_design_issues: { type: 'array', items: { type: 'string' } },
    disentanglement_issues: { type: 'array', items: { type: 'string' } },
    ownership_issues: { type: 'array', items: { type: 'string' } },
    naming_issues: { type: 'array', items: { type: 'string' } },
    step_structure_score: { type: 'integer' }
  },
  required: %w[step_structure_score]
}.freeze
```

- [ ] **Step 3: Update `judge_step_structure` to accept a schema parameter**

Replace the `judge_step_structure` function (around line 219-225):

```ruby
def judge_step_structure(rubric, original, output)
  user_msg = "## ORIGINAL\n\n#{original}\n\n## OUTPUT\n\n#{output}"
  result = call_claude(user_msg, system_prompt: rubric, json_schema: STEP_STRUCTURE_SCHEMA)
  return default_step_error(result[:error]) if result[:error]

  result[:json] || default_step_error('structured response missing')
end
```

with:

```ruby
def judge_step_structure(rubric, original, output, schema: STEP_STRUCTURE_SCHEMA)
  user_msg = "## ORIGINAL\n\n#{original}\n\n## OUTPUT\n\n#{output}"
  result = call_claude(user_msg, system_prompt: rubric, json_schema: schema)
  return default_step_error(result[:error]) if result[:error]

  result[:json] || default_step_error('structured response missing')
end
```

- [ ] **Step 4: Pass expert schema in `process_recipe`**

In `process_recipe`, update the step structure judge call (around line 287):

```ruby
  step = judge_step_structure(rubrics[:step], input_text, output_text)
```

to:

```ruby
  step_schema = expert ? EXPERT_STEP_STRUCTURE_SCHEMA : STEP_STRUCTURE_SCHEMA
  step = judge_step_structure(rubrics[:step], input_text, output_text, schema: step_schema)
```

- [ ] **Step 5: Update `collect_issues` to read expert step fields**

In the `collect_issues` function (around line 486-491), replace:

```ruby
  %w[split_issues naming_issues ownership_issues flow_issues].each do |key|
```

with:

```ruby
  %w[split_issues naming_issues ownership_issues flow_issues
     phase_design_issues disentanglement_issues].each do |key|
```

- [ ] **Step 6: Add metadata key swap in `process_recipe`**

In `runner_v3.rb`, after `metadata = load_metadata(dir)` (line 261) and `expert = expert_mode?(opts)` (line 262), add:

```ruby
  metadata['expected_steps'] = metadata['expected_steps_expert'] if expert && metadata.key?('expected_steps_expert')
```

- [ ] **Step 7: Verify runner parses without errors**

```bash
ruby -c test/ai_import/runner_v3.rb
```

Expected: `Syntax OK`

- [ ] **Step 8: Commit**

```bash
git add test/ai_import/runner_v3.rb
git commit -m "Update runner to load judges from mode-specific scorer directories"
```

---

### Task 3: Write expert step structure judge

New quality-based judge that evaluates structural decisions rather than source-matching.

**Files:**
- Create: `test/ai_import/scorers/expert/step_structure_judge_prompt.md`

- [ ] **Step 1: Write the expert step structure judge prompt**

Create `test/ai_import/scorers/expert/step_structure_judge_prompt.md` with the following content:

```markdown
You are a recipe structure quality judge. You will receive two texts: ORIGINAL
(the source recipe) and OUTPUT (the AI-converted version in Markdown format,
written for experienced cooks).

Evaluate how well the OUTPUT organized the recipe into cooking phases. The
OUTPUT is expected to reorganize and restructure — penalize bad structure, not
reorganization.

## Evaluation Criteria

### Phase Design (0-25)

Did the model identify the right cooking phases for this recipe?

- 25: Steps map to natural cooking phases (prep, cook, assemble, finish).
  Step count fits recipe complexity. Simple recipes (few ingredients, 1-2
  sentences of instructions) use implicit format (no ## headings).
- 15-24: Reasonable phases but minor quibbles — an unnecessary split, a step
  that could merge with another, or a borderline implicit/explicit choice.
- 0-14: Too many steps (one per source instruction) or too few (everything
  crammed into one step despite multiple distinct phases). Simple recipe
  given explicit steps when implicit was appropriate.

Flag: single-instruction steps, steps with no ingredients AND only one
sentence of instruction, 6+ steps for a straightforward recipe, explicit
steps for a recipe with ≤ 5 ingredients and 1-2 sentences of instructions.

### Disentanglement (0-25)

When the source interleaves parallel operations ("while X simmers, do Y"),
did the model separate them into clean, independent phases?

- 25: Parallel operations are separated into distinct steps. No "meanwhile"
  instructions mixing unrelated work within a single step.
- 15-24: Mostly clean but one interleaved operation left tangled.
- 0-14: Source's interleaved structure preserved verbatim — parallel tasks
  still mixed together in one step.
- Auto-score 25 when the source has no interleaved operations.

### Ingredient Ownership (0-25)

Are ingredients grouped under the right step?

- 25: Each ingredient appears once, in the step where it is primarily used.
  Ubiquitous ingredients (oil, salt, pepper) may appear in multiple steps
  when they serve distinct roles (e.g., oil for searing vs. oil for
  vinaigrette).
- 15-24: Minor issues — an ingredient in a slightly wrong step.
- 0-14: Ingredients re-listed across steps or placed in wrong steps.
- For implicit-step output: auto-score 25 (not applicable).

### Step Naming (0-25)

Are step names well-formed and descriptive?

- 25: Names are imperative sentences in sentence case, ending with a period.
  Semicolons join related sub-actions when natural. Names describe the phase
  of work, not just the result.
  Good: "Finish and serve.", "Cook pasta; combine with sauce.",
  "Brown butter and add to sugar mixture.", "Advance prep: cook farro."
- 15-24: Names are acceptable but generic ("Prepare ingredients.") or miss
  a natural semicolon opportunity.
- 0-14: Names are "Step 1" / numbered, or use title case ("Make The Dough.").
- For implicit-step output: auto-score 25 (not applicable).

## Calibration Exemplars

These are excerpts from the target recipe collection. Use them to calibrate.

**Multi-phase with clean separation (Fried Rice):**

    ## Cook rice.

    - Jasmine rice, 3 gō
    - Water

    Add to rice cooker, fill with water to the appropriate mark, then set
    to cook.

    ## Prep ingredients.

    - Eggs, 4: Lightly scrambled.
    - Green onions, 1 bunch: Sliced.
    - Garlic, 4 cloves: Minced.
    - Peas and carrots (frozen)

    Prepare all ingredients, setting aside in separate bowls. For the green
    onions, separate the white and green parts.

    ## Cook.
    ...

    ## Finish and serve.

    - Salt
    - Sugar (white)
    - Limes
    - Red pepper flakes

    When everything looks about done, add green parts of onion and stir
    to incorporate.

    Correct for salt, sweetness, acid, and heat. Serve.

**Parallel operations disentangled (Veggie Hash):**

    ## Advance prep: cook farro.
    ...
    ## Roast vegetables.
    ...
    ## Poach eggs.
    ...
    ## Assemble and serve.

**Simple implicit step (Nacho Cheese — 5 ingredients, 2 sentences):**

    # Nacho Cheese

    Worth the effort.

    Makes: 1 cup
    Serves: 4

    - Cheddar, 225 g: Cut into small cubes.
    - Milk, 225 g
    - Sodium citrate, 8 g
    - Salt, 2 g
    - Pickled jalapeños, 40 g

    Combine all ingredients in saucepan.

    Warm over low heat, stirring occasionally, until cheese is mostly
    melted. Puree with immersion blender.

Respond with ONLY this JSON — no other text:

```json
{
  "split_decision": "implicit or explicit",
  "phase_design_issues": ["any problems with phase choices"],
  "disentanglement_issues": ["any interleaved operations left tangled"],
  "ownership_issues": ["any problems with ingredient placement"],
  "naming_issues": ["any problems with step names"],
  "step_structure_score": 85
}
```

The `step_structure_score` is the sum of the four criteria (0-100). Empty
arrays mean no issues found. Scores must be integers 0-100.
```

- [ ] **Step 2: Commit**

```bash
git add test/ai_import/scorers/expert/step_structure_judge_prompt.md
git commit -m "Add expert step structure judge: quality-based phase evaluation"
```

---

### Task 4: Enrich the style judge with collection-calibrated exemplars

**Files:**
- Modify: `test/ai_import/scorers/expert/style_judge_prompt.md`

- [ ] **Step 1: Update Voice dimension (lines 10-25)**

Replace the Voice dimension section:

```markdown
### 1. Voice (0-13)

Instructions should use imperative mood with articles dropped aggressively.
No hedging, no addressing the reader.

- 13: Pure imperative, articles dropped, confident tone throughout.
- 7-12: Mostly good but some lapses (stray articles, occasional "you").
- 0-6: Conversational tone, frequent articles, hedging language.

BAD: "You will want to add the butter to the pan and stir it until melted."
GOOD: "Add butter to pan. Stir until melted."

Flag: any instance of "you/your/you'll", "feel free to", "you may want to",
"if you like" (in instructions, not in footer notes), "be sure to",
"don't forget to", "go ahead and".
```

with:

```markdown
### 1. Voice (0-13)

Instructions should use imperative mood. Drop articles where natural, but
retain where dropping would sound robotic. Terse but human, not telegraphic.
No hedging, no addressing the reader.

- 13: Confident imperative throughout. Articles dropped naturally — reads
  like a skilled cook's notes, not a telegram.
- 7-12: Mostly good but some lapses (stray "you", hedging, or articles
  retained where they clearly should drop). OR over-corrected to robotic
  single-word sentence chains.
- 0-6: Conversational tone, frequent articles, hedging language. OR
  telegraphic — reads like a robot, not a person.

BAD (too chatty): "You will want to add the butter to the pan and stir it
until melted."
BAD (too robotic): "Heat. Add. Stir. Season. Serve."
GOOD: "Add butter to pan. Stir until melted."
GOOD: "Correct for salt, sweetness, acid, and heat. Serve."
GOOD: "Form into a neat ball, return to bowl, and cover."
GOOD: "Allow to rest and spread again, repeating as necessary."

Flag: any instance of "you/your/you'll", "feel free to", "you may want to",
"if you like" (in instructions, not in footer notes), "be sure to",
"don't forget to", "go ahead and". Also flag single-word sentence chains
(three or more consecutive one-verb sentences).
```

- [ ] **Step 2: Update Description quality dimension (lines 67-78)**

Replace the Description quality section:

```markdown
### 5. Description Quality (0-12)

A punchy, casual one-liner — kitchen Post-it tone. Absent is acceptable
for very simple recipes.

- 12: Punchy, casual, under ~10 words, or appropriately absent.
- 6-11: Present but slightly long or generic.
- 0-5: Food-blog style ("A delicious recipe the whole family will love"),
  or excessively long.

Flag: descriptions over 15 words, food-blog cliches, SEO-style language.
```

with:

```markdown
### 5. Description Quality (0-12)

A punchy, casual one-liner — kitchen Post-it tone. Absent is acceptable
for very simple recipes.

- 12: Punchy, casual, under ~10 words, or appropriately absent.
- 6-11: Present but slightly long or generic.
- 0-5: Food-blog style ("A delicious recipe the whole family will love"),
  or excessively long.

Good descriptions from the collection: "Vaguely Thai egg-fried rice.",
"Mom's roasted vegetables on farro with a poached egg", "Just a little
sweet.", "Worth the effort.", "Pasta and beans in a simple broth.",
"The best pan pizza.", "Mom's famous baked pasta."

Flag: descriptions over 15 words, food-blog cliches, SEO-style language.
```

- [ ] **Step 3: Replace calibration exemplars section (lines 121-167)**

Replace the entire "Calibration Exemplars" section (from `## Calibration Exemplars` through the Toast example) with:

```markdown
## Calibration Exemplars

These are excerpts from the target recipe collection. Use them to calibrate
your scoring. This is the voice to match — terse but human, economical but
not robotic.

**Multi-step recipe (terse, phase-based):**

    ## Cook.

    - Olive oil (mild)
    - Soy sauce
    - Bouillon

    Add oil to large pan over high heat. Add garlic and white parts of
    onion, and cook until fragrant.

    Add rice and stir to distribute onion and garlic.

    Make a well in rice to expose bottom of pan. Add a bit more oil, then
    add eggs. Scramble briefly, then stir into rice.

    Stir in seasonings to taste.

    ## Finish and serve.

    - Salt
    - Sugar (white)
    - Limes
    - Red pepper flakes

    When everything looks about done, add green parts of onion and stir
    to incorporate.

    Correct for salt, sweetness, acid, and heat. Serve.

**Mid-range voice (economical but not maximally terse):**

    ## Make dough and bulk ferment.

    - Honey, 20 g
    - Olive oil, 20 g
    - Salt, 10 g
    - Water, 300 g
    - Yeast, 5 g
    - Flour (all-purpose), 400 g

    Add all ingredients except flour to bowl. Add half the flour and whisk
    together. Add remaining flour, then mix until thoroughly combined.

    Let rest for 20-30 minutes, then knead until smooth. Form into a neat
    ball, return to bowl, and cover.

    Bulk ferment until doubled in size.

**Concise technique prose with semicolon naming:**

    ## Brown butter and add to sugar mixture.

    - Butter (unsalted), 140 g

    Add butter to small saucepan. Cook gently over medium heat until solids
    are browned, then immediately add to sugar mixture in mixer bowl and
    allow to cool slightly.

**Ideal final step (two sentences):**

    ## Finish and serve.

    - Salt
    - Black pepper

    Correct for seasoning. Serve.

**Simple recipe (minimal, implicit-step):**

    # Toast

    Dead simple.

    Serves: 2

    - Bread, 2 slices
    - Butter

    Toast bread until golden. Butter while warm.
```

- [ ] **Step 4: Commit**

```bash
git add test/ai_import/scorers/expert/style_judge_prompt.md
git commit -m "Enrich style judge: voice calibration, description exemplars, 5 collection snippets"
```

---

### Task 5: Update outcome fidelity judge

**Files:**
- Modify: `test/ai_import/scorers/expert/outcome_fidelity_judge_prompt.md`

- [ ] **Step 1: Add unit normalization to "Do NOT Penalize" list**

After the line `- Extracting water or other ingredients from instructions into the` / `  ingredient list when the source clearly uses them as ingredients` (around line 50), add:

```markdown
- Unit abbreviation normalization to system-recognized forms (e.g.,
  "tablespoon" → "tbsp", "Cups" → "cups", "ounces" → "oz")
```

- [ ] **Step 2: Commit**

```bash
git add test/ai_import/scorers/expert/outcome_fidelity_judge_prompt.md
git commit -m "Outcome fidelity judge: do not penalize unit abbreviation normalization"
```

---

### Task 6: Update corpus metadata with expert step expectations

**Files:**
- Modify: `test/ai_import/corpus_v3/03_blog_serious_eats_c/metadata.json`
- Modify: `test/ai_import/corpus_v3/04_blog_smitten_kitchen/metadata.json`
- Modify: `test/ai_import/corpus_v3/05_blog_budget_bytes/metadata.json`
- Modify: `test/ai_import/corpus_v3/06_blog_pioneer_woman/metadata.json`
- Modify: `test/ai_import/corpus_v3/07_blog_bon_appetit/metadata.json`
- Modify: `test/ai_import/corpus_v3/08_agg_allrecipes/metadata.json`
- Modify: `test/ai_import/corpus_v3/10_agg_epicurious/metadata.json`
- Modify: `test/ai_import/corpus_v3/11_agg_nyt_style/metadata.json`
- Modify: `test/ai_import/corpus_v3/12_ocr_biscuits/metadata.json`
- Modify: `test/ai_import/corpus_v3/13_ocr_beef_stew/metadata.json`
- Modify: `test/ai_import/corpus_v3/15_clean_text_message/metadata.json`
- Modify: `test/ai_import/corpus_v3/16_clean_email/metadata.json`

- [ ] **Step 1: Add `expected_steps_expert` to each metadata.json**

Add the `expected_steps_expert` field to each file. The values:

| Directory | `expected_steps_expert` |
|-----------|------------------------|
| `03_blog_serious_eats_c` | `"explicit"` |
| `04_blog_smitten_kitchen` | `"explicit"` |
| `05_blog_budget_bytes` | `"explicit"` |
| `06_blog_pioneer_woman` | `"explicit"` |
| `07_blog_bon_appetit` | `"explicit"` |
| `08_agg_allrecipes` | `"explicit"` |
| `10_agg_epicurious` | `"explicit"` |
| `11_agg_nyt_style` | `"explicit"` |
| `12_ocr_biscuits` | `"ambiguous"` |
| `13_ocr_beef_stew` | `"explicit"` |
| `15_clean_text_message` | `"implicit"` |
| `16_clean_email` | `"ambiguous"` |

For example, `03_blog_serious_eats_c/metadata.json` becomes:

```json
{
  "source": "https://www.seriouseats.com/ultimate-beef-wellington-recipe",
  "expected_steps": "ambiguous",
  "expected_steps_expert": "explicit",
  "category": "blog"
}
```

Apply this pattern to all 12 files, each with its value from the table above.

- [ ] **Step 2: Commit**

```bash
git add test/ai_import/corpus_v3/*/metadata.json
git commit -m "Add expected_steps_expert to corpus metadata"
```

---

### Task 7: Harmonize expert prompt

The largest single task. Merges the old prompt's strengths with the current prompt.

**Files:**
- Modify: `lib/familyrecipes/ai_import_prompt_expert.md`

- [ ] **Step 1: Update sugar qualification rule**

Find the sugar qualification lines (around line 163-165):

```markdown
- Qualify sugar when the source specifies the type: "Sugar (brown)",
  "Sugar (powdered)". If the source just says "sugar" with no qualifier,
  write `- Sugar` — do not add "(white)".
```

Replace with:

```markdown
- Always qualify sugar: "Sugar (white)" or "Sugar (brown)". Never bare
  "Sugar". If the source just says "sugar" with no qualifier, use
  "Sugar (white)".
```

- [ ] **Step 2: Add attribution rule to Footer section**

Find the footer section (around line 270-275). After "If the source names an author or publication, credit them in the footer.", add:

```markdown
Always use this exact phrasing: "Based on a recipe from [Source](URL)."
Never "Adapted from" or "Inspired by."
```

- [ ] **Step 3: Update unit steering guidance**

Find the unit guidance section starting with `**Units — preserve the source's units:**` (around line 215). Replace the entire units subsection (through line 225) with:

```markdown
**Units — steer toward recognized forms:**
- Normalize abbreviations to system-recognized forms: `tbsp`, `tsp`, `cup`,
  `oz`, `lb`, `g`, `ml`, `fl oz`, `pt`, `qt`, `gal`. Write `1 tbsp` not
  `1 tablespoon`, `2 cups` not `2 C.`, `8 oz` not `8 ounces`.
- Do NOT convert between unit systems — if the source says cups, keep cups;
  if grams, keep grams. If the source gives both, use whichever appears
  first.
- Always put a space before the unit: "115 g" not "115g".
- Use `g` not `kg` — write `1350 g` not `1.35 kg`.
```

- [ ] **Step 4: Expand step splitting guidance**

Find the step splitting section starting with `**How to split steps:**` (around line 108). Replace through `**When in doubt, split into fewer steps.**` (around line 117) with:

```markdown
**How to split steps:** Steps are phases of work, not individual actions.
A single step chains multiple actions in prose.
- Follow natural phase changes: prep vs. cook vs. assemble, or distinct
  components (dough vs. filling vs. glaze).
- If the source already groups things into sections ("For the marinade",
  "For the sauce"), those map naturally to steps.
- **Disentangle interleaved operations.** If the source says "while the
  beans simmer, cook rice" or "meanwhile, prepare the salad," separate
  these into distinct steps. Parallel operations get their own phases.
- Use **semicolons in headings** to join related sub-actions:
  `## Cook pasta; combine with sauce.`
- **`## Finish and serve.`** is the standard final-step pattern when there's
  last-minute seasoning or plating.
- **`## Advance prep:`** prefix for things done ahead of time (e.g.,
  `## Advance prep: cook farro.`).
- A typical recipe has 2-5 steps. Fewer is fine. More than 5 is a smell.
- If the recipe is straightforward with no natural breakpoints, use a single
  step or even the implicit-step format (no ## heading).
- **When in doubt, fewer steps.** A step represents a genuinely distinct
  phase, not just "the next few numbered instructions."
```

- [ ] **Step 5: Tune voice guidance**

Find the voice section starting with `**Voice — terse, confident, direct:**` (around line 232). Replace the article-dropping bullet (line 234-235):

```markdown
- Drop articles aggressively: "Add to skillet" not "Add to the skillet."
  "Melt butter in large pan" not "Melt butter in a large pan."
```

with:

```markdown
- Drop articles where natural: "Add to skillet" not "Add to the skillet."
  But retain where dropping sounds robotic — "Allow to rest" is fine,
  "Allow rest" is not. Terse but human, not telegraphic.
```

- [ ] **Step 6: Expand common mistakes list**

Find the `## Common Mistakes` section (around line 277). Add these entries before the closing line:

```markdown
- `1.35 kg` → use grams: `1350 g`. Always grams, never kilograms.
- `Ground cinnamon` → just `Cinnamon`. `Fresh parsley` → just `Parsley`.
  Default-form adjectives are unnecessary.
- Storage or make-ahead tips in step instructions → move to footer.
- `Vanilla, 1 tsp` → always `Vanilla extract, 1 tsp`.
- `Makes: 6 cups` without a noun → `Makes: 6 cups granola`. Always include
  a unit noun with Makes.
- `Adapted from` or `Inspired by` → always `Based on a recipe from`.
- `1 tablespoon` → system abbreviation: `1 tbsp`. Same for `teaspoon` →
  `tsp`, `ounces` → `oz`, `pounds` → `lb`.
```

- [ ] **Step 7: Commit**

```bash
git add lib/familyrecipes/ai_import_prompt_expert.md
git commit -m "Harmonize expert prompt: sugar, attribution, units, steps, voice, mistakes"
```

---

### Task 8: Write Ralph Loop expert prompt

**Files:**
- Create: `test/ai_import/loop_prompt_expert.md`

- [ ] **Step 1: Write the expert loop prompt**

Create `test/ai_import/loop_prompt_expert.md`:

```markdown
# Expert Prompt Tuning — Ralph Loop

You are iteratively improving the expert AI import prompt. Each iteration:
analyze what went wrong, make targeted prompt edits, re-evaluate, check
convergence.

## Step 1: Read State

Read `test/ai_import/results/state.json`. Note:
- Current iteration count
- Best score and which iteration produced it
- Patience counter (stops at 2)
- Prompt line count trend — is the prompt growing or shrinking?

If state.json does not exist, this is the first iteration. Skip to Step 3.

## Step 2: Analyze Failures

Read the most recent `test/ai_import/results/iteration_*/summary.md`.

Focus on, in priority order:
1. **Step structure** — the weakest baseline dimension. Are phases well-chosen?
   Are interleaved operations disentangled? Are simple recipes getting
   unnecessary explicit steps?
2. **Style voice** — watch for over-correction (telegraphic robot prose) AND
   under-correction (chatty blog voice surviving). The target is terse but
   human.
3. **Footer discipline** — invented substitutions, tips, or imperial
   equivalents not in the source.
4. **Outcome fidelity** — dropped ingredients, changed quantities, lost
   technique unique to this recipe.

Also look for **prompt trimming opportunities**:
- Rules that have never been violated — Sonnet may follow the convention
  naturally. These are candidates for removal.
- Redundant rules that say the same thing in different places.
- Examples that could be shorter without losing clarity.

## Step 3: Edit the Prompt

Edit `lib/familyrecipes/ai_import_prompt_expert.md`. Rules:

**Prefer removing or simplifying rules over adding new ones.** A shorter
prompt burns fewer tokens and gives the model less to misinterpret. Every
line in the prompt should earn its place.

- Bundle multiple targeted fixes per iteration when they address different,
  non-overlapping issues.
- If this is the first iteration, just verify the prompt looks correct and
  make no edits.
- Never rewrite the prompt from scratch.
- Never add a rule that only helps one recipe — check if it could hurt others.
- If adding a rule, check if an existing rule already covers the case and
  just needs tightening.
- Do not change the scoring system, runner script, or judge rubrics.

Commit the change:

    git add lib/familyrecipes/ai_import_prompt_expert.md
    git commit -m "Ralph loop: [brief description of change]"

## Step 4: Run Evaluation

    ruby test/ai_import/runner_v3.rb --prompt=ai_import_prompt_expert.md --corpus=corpus_v3

Wait for it to complete. This takes several minutes.

## Step 5: Check Convergence

Read the updated `test/ai_import/results/state.json`.

If `patience >= 2`:
1. Read the `best_iteration` label and its `prompt_sha`.
2. Restore the best prompt:

       git show <prompt_sha>:lib/familyrecipes/ai_import_prompt_expert.md > lib/familyrecipes/ai_import_prompt_expert.md

3. Commit:

       git add lib/familyrecipes/ai_import_prompt_expert.md
       git commit -m "Ralph loop: restore best prompt (iteration <label>, avg <score>)"

4. Output: <promise>EXPERT TUNED</promise>

If `patience < 2`: let the loop continue — the stop hook will feed this
prompt again and you will start from Step 1 with updated state.
```

- [ ] **Step 2: Commit**

```bash
git add test/ai_import/loop_prompt_expert.md
git commit -m "Add Ralph Loop expert prompt for iterative tuning"
```

---

### Task 9: Reset state and run baseline evaluation

Clear the old baseline (which used the pre-reorganization scorer paths) and run a fresh baseline with the new infrastructure.

**Files:**
- Modify: `test/ai_import/results/state.json`

- [ ] **Step 1: Reset state.json**

Overwrite `test/ai_import/results/state.json` with:

```json
{
  "iterations": [],
  "best_iteration": null,
  "best_avg": 0.0,
  "patience": 0
}
```

- [ ] **Step 2: Run baseline expert evaluation**

```bash
cd /home/claude/familyrecipes
ruby test/ai_import/runner_v3.rb --prompt=ai_import_prompt_expert.md --corpus=corpus_v3 baseline_expert_v2
```

This takes several minutes. Wait for completion and review output.

- [ ] **Step 3: Verify results**

```bash
cat test/ai_import/results/iteration_baseline_expert_v2/summary.md
cat test/ai_import/results/state.json
```

Check that:
- All 12 recipes pass Parse and Compat gates (round-trip works)
- Step structure scores have improved from the old 69-79 range
- Style scores remain high (89+)
- No regressions in outcome fidelity or detritus
- State.json shows the new baseline

- [ ] **Step 4: Commit results**

```bash
git add test/ai_import/results/
git commit -m "Expert mode v2 baseline: reorganized scorers, new step judge, enriched style judge"
```
