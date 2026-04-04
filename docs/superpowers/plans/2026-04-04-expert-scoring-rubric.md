# Expert Scoring Rubric Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add expert-mode scoring to the AI import evaluation runner — an outcome fidelity judge, a style judge, and mode-aware aggregate scoring.

**Architecture:** Two new LLM judge prompts (outcome fidelity, style) with JSON schemas, runner branching on prompt filename to select the right scoring pipeline and aggregate formula. Expert prompt gets baseline fixes synced from faithful prompt work.

**Tech Stack:** Ruby (standalone script, no Rails), Claude CLI (`claude -p`), JSON schemas for structured output.

---

### Task 1: Create outcome fidelity judge prompt

**Files:**
- Create: `test/ai_import/scorers/outcome_fidelity_judge_prompt.md`

- [ ] **Step 1: Write the outcome fidelity judge prompt**

Create the file with this content:

```markdown
You are a recipe outcome quality judge. You will receive two texts: ORIGINAL
(the source recipe) and OUTPUT (an AI-converted version written for
experienced cooks).

Your job is to evaluate whether an expert cook following the OUTPUT would
produce the same dish as the ORIGINAL describes. The OUTPUT may condense,
rephrase, or omit obvious instructions — that is expected and correct. You
are ONLY checking whether the final dish would be the same.

## Outcome Fidelity (0-100)

Would a competent home cook following the OUTPUT produce the same dish?

- 100: All ingredients present, quantities correct, essential techniques
  preserved. The dish would be identical.
- 80-99: Minor issues that probably wouldn't affect the outcome.
- 50-79: Missing elements that would noticeably change the dish.
- 20-49: Major ingredients or techniques missing — different dish.
- 0-19: Unrecognizable as the same recipe.

### Penalize

- Missing ingredients that affect the dish (not garnishes marked optional)
- Changed quantities (wrong amounts, incorrect unit conversions)
- Wrong temperatures or times
- Dropped technique unique to THIS recipe (e.g., "don't use a stand mixer"
  for a stiff dough, "fold gently" for a delicate batter) — anything that
  distinguishes this recipe from the default approach
- Hallucinated ingredients or instructions not in the source
- Invented footer notes (substitutions or tips not in the source)

### Do NOT Penalize

- Condensed phrasing (3 paragraphs compressed to 1 sentence is fine if
  the meaning survives)
- Dropped generic technique tutorials (how to knead, how to judge when oil
  is hot, what simmering looks like)
- Dropped common-sense notes (open a window, use homemade stock, don't
  crowd the pan)
- Omitted "obvious" steps an expert would do anyway (wash hands, gather
  ingredients, preheat unless timing matters)
- Reworded instructions that preserve the outcome
- Serves/Makes range collapsed to a single number: the lower bound of the
  range. "Serves 6-8" → "Serves: 6" is CORRECT.
- Temperature format normalization ("350 degrees" → "350°F")
- Dropping "about" from Makes/Serves lines
- Range normalization ("2 to 3 minutes" → "2-3 minutes")
- Informal quantities preserved from source ("a generous pour", "a handful")
- Extracting water or other ingredients from instructions into the
  ingredient list when the source clearly uses them as ingredients

## Detritus Removal (0-100)

How well does the OUTPUT strip non-recipe content?

- 100: All blog preamble, navigation, ads, comments, ratings, CTAs, and
  other non-recipe content removed. Only the recipe remains.
- 80-99: Trace amounts of non-recipe content remain.
- 50-79: Some detritus leaked through (a CTA line, a comment, etc.).
- 20-49: Significant non-recipe content present.
- 0-19: Most of the blog/page content was retained.

**Do NOT penalize these — they are expected:**
- A `Category:` line
- A `Makes:` or `Serves:` line
- A brief attribution in the footer like "Recipe from [Author]."
- A one-line description after the title
These are part of the output format, not retained detritus.

Respond with ONLY this JSON — no other text:

```json
{
  "ingredients_missing": ["ingredient from original not in output"],
  "ingredients_added": ["ingredient in output not in original"],
  "quantities_changed": ["description of change"],
  "technique_lost": ["unique-to-this-recipe technique that was dropped"],
  "outcome_affected": ["any other way the output would produce a different dish"],
  "detritus_retained": ["any non-recipe content that leaked through"],
  "outcome_fidelity_score": 85,
  "detritus_score": 95
}
```

Be precise. Empty arrays mean no issues found. Scores must be integers 0-100.
```

- [ ] **Step 2: Verify the file was created correctly**

Run: `wc -l test/ai_import/scorers/outcome_fidelity_judge_prompt.md`
Expected: approximately 75-85 lines

- [ ] **Step 3: Commit**

```bash
git add test/ai_import/scorers/outcome_fidelity_judge_prompt.md
git commit -m "Add outcome fidelity judge prompt for expert mode"
```

---

### Task 2: Create style judge prompt

**Files:**
- Create: `test/ai_import/scorers/style_judge_prompt.md`

- [ ] **Step 1: Write the style judge prompt**

Create the file with this content. Note the two exemplar snippets embedded at the end — these are trimmed excerpts from the sample recipes, used as calibration anchors for the judge.

```markdown
You are a recipe style judge. You will receive one text: OUTPUT (an
AI-converted recipe). Evaluate how well it matches the target style for an
expert home-cooking recipe collection.

Score each dimension independently. The total style score is the sum of all
dimension scores (0-100).

## Dimensions

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

### 2. Condensation (0-13)

Obvious basics should be omitted. Generic technique tutorials that an
experienced cook already knows should be stripped.

- 13: Only recipe-specific information remains. No hand-holding.
- 7-12: Mostly condensed but a few generic instructions survived.
- 0-6: Reads like a tutorial — explains basics, includes common-sense advice.

Flag: technique tutorials (explaining how to knead, how to judge oil
temperature, what al dente means), common-sense advice ("open a window",
"use a sharp knife", "be careful not to burn yourself"), generic cooking
advice ("don't crowd the pan", "season as you go"), quality editorializing
("preferably homemade", "use the best quality you can find"), unnecessary
preheat reminders (unless timing matters for the recipe flow).

### 3. Specificity Preserved (0-13)

Temperatures, times, visual cues, and recipe-specific techniques must be
retained. Things that distinguish THIS recipe from the default approach
should not be condensed away.

- 13: All specific details preserved — temps, times, cues, unique technique.
- 7-12: Minor specific detail lost but nothing that affects the outcome.
- 0-6: Important specifics removed — temperatures, key visual cues, or
  unique technique that makes this recipe different.

Flag: missing temperatures, missing cook times, dropped visual cues ("until
golden", "until bubbling"), removed technique notes that are specific to
this recipe (not generic advice).

### 4. Title Quality (0-12)

Short, descriptive, no clickbait.

- 12: Clean recipe name, title case, concise.
- 6-11: Acceptable but slightly long or has minor issues.
- 0-5: Clickbait, superlatives, "Recipe for" prefix, excessive length.

Flag: "The Best", "Amazing", "Easy", "Perfect", "Ultimate", "Recipe for",
"How to Make", titles over 6 words.

### 5. Description Quality (0-12)

A punchy, casual one-liner — kitchen Post-it tone. Absent is acceptable
for very simple recipes.

- 12: Punchy, casual, under ~10 words, or appropriately absent.
- 6-11: Present but slightly long or generic.
- 0-5: Food-blog style ("A delicious recipe the whole family will love"),
  or excessively long.

Flag: descriptions over 15 words, food-blog cliches, SEO-style language.

### 6. Instruction Prose (0-13)

Instructions should read as natural prose paragraphs, not bullet points or
numbered steps. The writing should be terse but human — not telegraphic or
robotic.

- 13: Flows naturally. Terse but readable. Sequences connect logically.
- 7-12: Mostly prose but occasional stiffness or awkward transitions.
- 0-6: Bullet-point style, numbered steps, or robotic/telegraphic.

Flag: numbered instruction steps in the output, bullet-pointed instructions,
single-word-sentence chains that read like a telegram.

### 7. Footer Discipline (0-12)

Footer should contain only content from the source — attribution,
substitutions, tips that the source provided. No invented content.

- 12: Footer is clean — only source content, properly attributed.
- 6-11: Minor invented note or missing attribution.
- 0-5: Invented substitutions, tips, or "helpful" additions not in source.
  Or missing footer when source had useful context.

Flag: substitution suggestions not in the source, "helpful tips" the AI
added, summary notes that repackage inline information, missing attribution
when source named an author.

### 8. Economy (0-12)

The remaining prose should be lean — no filler words, no repetition, no
over-explanation. This is distinct from condensation (what to cut); economy
is about whether what remains is tight.

- 12: Every word earns its place. No filler, no repetition.
- 6-11: Mostly lean but some slack — redundant phrases or wordy constructions.
- 0-6: Verbose, repetitive, or padded with filler.

Flag: "stir to combine" followed by "mix until combined", redundant
restatements of the same instruction, wordy constructions ("in order to"
instead of "to", "make sure that" instead of just the instruction).

## Calibration Exemplars

These are excerpts from the target style. Use them to calibrate your scoring.

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

**Simple recipe (minimal, implicit-step):**

    # Toast

    Dead simple.

    Serves: 2

    - Bread, 2 slices
    - Butter

    Toast bread until golden. Butter while warm.

Respond with ONLY this JSON — no other text:

```json
{
  "voice_score": 13,
  "voice_issues": ["any voice problems"],
  "condensation_score": 13,
  "condensation_issues": ["any condensation problems"],
  "specificity_score": 13,
  "specificity_issues": ["any specificity problems"],
  "title_score": 12,
  "title_issues": ["any title problems"],
  "description_score": 12,
  "description_issues": ["any description problems"],
  "prose_score": 13,
  "prose_issues": ["any prose problems"],
  "footer_score": 12,
  "footer_issues": ["any footer problems"],
  "economy_score": 12,
  "economy_issues": ["any economy problems"],
  "style_score": 100
}
```

`style_score` MUST equal the sum of all eight dimension scores.
Empty arrays mean no issues found. Scores must be integers within the stated
ranges.
```

- [ ] **Step 2: Verify the file was created correctly**

Run: `wc -l test/ai_import/scorers/style_judge_prompt.md`
Expected: approximately 160-180 lines

- [ ] **Step 3: Commit**

```bash
git add test/ai_import/scorers/style_judge_prompt.md
git commit -m "Add style judge prompt for expert mode"
```

---

### Task 3: Add expert mode schemas and judge function to runner

**Files:**
- Modify: `test/ai_import/runner_v3.rb`

- [ ] **Step 1: Add OUTCOME_FIDELITY_SCHEMA constant**

After the existing `FIDELITY_SCHEMA` constant (line 62), add:

```ruby
OUTCOME_FIDELITY_SCHEMA = {
  type: 'object',
  properties: {
    ingredients_missing: { type: 'array', items: { type: 'string' } },
    ingredients_added: { type: 'array', items: { type: 'string' } },
    quantities_changed: { type: 'array', items: { type: 'string' } },
    technique_lost: { type: 'array', items: { type: 'string' } },
    outcome_affected: { type: 'array', items: { type: 'string' } },
    detritus_retained: { type: 'array', items: { type: 'string' } },
    outcome_fidelity_score: { type: 'integer' },
    detritus_score: { type: 'integer' }
  },
  required: %w[outcome_fidelity_score detritus_score]
}.freeze
```

- [ ] **Step 2: Add STYLE_SCHEMA constant**

After the new `OUTCOME_FIDELITY_SCHEMA`, add:

```ruby
STYLE_SCHEMA = {
  type: 'object',
  properties: {
    voice_score: { type: 'integer' },
    voice_issues: { type: 'array', items: { type: 'string' } },
    condensation_score: { type: 'integer' },
    condensation_issues: { type: 'array', items: { type: 'string' } },
    specificity_score: { type: 'integer' },
    specificity_issues: { type: 'array', items: { type: 'string' } },
    title_score: { type: 'integer' },
    title_issues: { type: 'array', items: { type: 'string' } },
    description_score: { type: 'integer' },
    description_issues: { type: 'array', items: { type: 'string' } },
    prose_score: { type: 'integer' },
    prose_issues: { type: 'array', items: { type: 'string' } },
    footer_score: { type: 'integer' },
    footer_issues: { type: 'array', items: { type: 'string' } },
    economy_score: { type: 'integer' },
    economy_issues: { type: 'array', items: { type: 'string' } },
    style_score: { type: 'integer' }
  },
  required: %w[style_score]
}.freeze
```

- [ ] **Step 3: Add judge_outcome_fidelity function**

After the existing `judge_step_structure` function (line 177), add:

```ruby
def judge_outcome_fidelity(rubric, original, output)
  user_msg = "## ORIGINAL\n\n#{original}\n\n## OUTPUT\n\n#{output}"
  result = call_claude(user_msg, system_prompt: rubric, json_schema: OUTCOME_FIDELITY_SCHEMA)
  return default_outcome_fidelity_error(result[:error]) if result[:error]

  result[:json] || default_outcome_fidelity_error('structured response missing')
end

def judge_style(rubric, output)
  result = call_claude(output, system_prompt: rubric, json_schema: STYLE_SCHEMA)
  return default_style_error(result[:error]) if result[:error]

  result[:json] || default_style_error('structured response missing')
end

def default_outcome_fidelity_error(msg)
  { 'error' => msg, 'outcome_fidelity_score' => 0, 'detritus_score' => 0 }
end

def default_style_error(msg)
  { 'error' => msg, 'style_score' => 0 }
end
```

- [ ] **Step 4: Verify syntax**

Run: `ruby -c test/ai_import/runner_v3.rb`
Expected: `Syntax OK`

- [ ] **Step 5: Commit**

```bash
git add test/ai_import/runner_v3.rb
git commit -m "Add expert mode schemas and judge functions to runner"
```

---

### Task 4: Add expert mode detection and branching to the scoring pipeline

**Files:**
- Modify: `test/ai_import/runner_v3.rb`

- [ ] **Step 1: Add expert_mode? helper**

After the `parse_args` function (after line 95), add:

```ruby
def expert_mode?(opts)
  opts[:prompt].include?('expert')
end
```

- [ ] **Step 2: Update process_recipe to accept and use mode**

Replace the `process_recipe` method signature and body (lines 187-222) with:

```ruby
def process_recipe(dir, system_prompt, rubrics, opts)
  name = File.basename(dir)
  input_text = File.read(File.join(dir, 'input.txt'))
  metadata = load_metadata(dir)

  puts "[#{name}] Importing..."
  import = import_recipe(system_prompt, input_text)
  return error_scores(import[:error], expert: expert_mode?(opts)) if import[:error]

  output_text = import[:text]

  puts "  [#{name}] Layer 1: parse + compat..."
  parse = Scorers::ParseChecker.check(output_text)
  compat = Scorers::SystemCompatChecker.check(output_text)

  puts "  [#{name}] Layer 2: format..."
  format = Scorers::FormatChecker.check(output_text, valid_categories: CATEGORIES,
                                                     valid_tags: TAGS,
                                                     input_text: input_text, metadata: metadata)

  puts "  [#{name}] Layer 3: fidelity judge..."
  fidelity = if expert_mode?(opts)
               judge_outcome_fidelity(rubrics[:fidelity], input_text, output_text)
             else
               judge_fidelity(rubrics[:fidelity], input_text, output_text)
             end

  puts "  [#{name}] Layer 4: step structure judge..."
  step = judge_step_structure(rubrics[:step], input_text, output_text)

  style = nil
  if expert_mode?(opts)
    puts "  [#{name}] Layer 5: style judge..."
    style = judge_style(rubrics[:style], output_text)
  end

  gate_pass = parse.pass && compat.pass
  agg = aggregate_score(gate_pass, format, fidelity, step, style, expert: expert_mode?(opts))
  puts "  [#{name}] Aggregate: #{agg.round(1)}"

  result = { output_text: output_text,
             parse: { pass: parse.pass, details: parse.details },
             compat: { pass: compat.pass, details: compat.details },
             format: { score: (format.score * 100).round(1), checks: format.checks },
             fidelity: fidelity, step_structure: step, aggregate: agg.round(1) }
  result[:style] = style if style
  result
end
```

- [ ] **Step 3: Update aggregate_score for dual-mode support**

Replace the `aggregate_score` method (lines 233-241) with:

```ruby
def aggregate_score(gate_pass, format_result, fidelity, step, style = nil, expert: false)
  return 0.0 unless gate_pass

  fmt = format_result.score * 100.0
  det = (fidelity['detritus_score'] || 0).to_f
  stp = (step['step_structure_score'] || 0).to_f

  if expert
    fid = (fidelity['outcome_fidelity_score'] || 0).to_f
    sty = (style&.dig('style_score') || 0).to_f
    (0.10 * fmt) + (0.40 * ((fid + det) / 2.0)) + (0.25 * stp) + (0.25 * sty)
  else
    fid = (fidelity['fidelity_score'] || 0).to_f
    (0.20 * fmt) + (0.50 * ((fid + det) / 2.0)) + (0.30 * stp)
  end
end
```

- [ ] **Step 4: Update error_scores for dual-mode support**

Replace the `error_scores` method (lines 224-231) with:

```ruby
def error_scores(msg, expert: false)
  result = { output_text: '', aggregate: 0.0,
             parse: { pass: false, details: { errors: [msg] } },
             compat: { pass: false, details: { errors: [msg] } },
             format: { score: 0.0, checks: [] },
             step_structure: { 'step_structure_score' => 0 } }
  if expert
    result[:fidelity] = { 'outcome_fidelity_score' => 0, 'detritus_score' => 0 }
    result[:style] = { 'style_score' => 0 }
  else
    result[:fidelity] = { 'fidelity_score' => 0, 'detritus_score' => 0 }
  end
  result
end
```

- [ ] **Step 5: Update run_evaluation to load rubrics and pass opts**

Replace the rubric-loading and processing section in `run_evaluation` (lines 406-419). Find:

```ruby
  system_prompt = load_prompt(opts[:prompt_path])
  fidelity_rubric = File.read(File.join(BASE_DIR, 'scorers', 'fidelity_judge_prompt.md'))
  step_rubric = File.read(File.join(BASE_DIR, 'scorers', 'step_structure_judge_prompt.md'))
```

Replace with:

```ruby
  system_prompt = load_prompt(opts[:prompt_path])
  rubrics = {
    fidelity: File.read(File.join(BASE_DIR, 'scorers',
                                  expert_mode?(opts) ? 'outcome_fidelity_judge_prompt.md' : 'fidelity_judge_prompt.md')),
    step: File.read(File.join(BASE_DIR, 'scorers', 'step_structure_judge_prompt.md'))
  }
  rubrics[:style] = File.read(File.join(BASE_DIR, 'scorers', 'style_judge_prompt.md')) if expert_mode?(opts)
```

Then find the `parallel_map` call:

```ruby
  results = parallel_map(dirs, opts[:concurrency]) do |dir|
    process_recipe(dir, system_prompt, fidelity_rubric, step_rubric)
  end
```

Replace with:

```ruby
  results = parallel_map(dirs, opts[:concurrency]) do |dir|
    process_recipe(dir, system_prompt, rubrics, opts)
  end
```

- [ ] **Step 6: Verify syntax**

Run: `ruby -c test/ai_import/runner_v3.rb`
Expected: `Syntax OK`

- [ ] **Step 7: Commit**

```bash
git add test/ai_import/runner_v3.rb
git commit -m "Add expert mode branching to scoring pipeline and aggregate formula"
```

---

### Task 5: Update summary output for expert mode

**Files:**
- Modify: `test/ai_import/runner_v3.rb`

- [ ] **Step 1: Update summary_table to include style column for expert mode**

Replace the `summary_table` method (lines 325-342) with:

```ruby
def summary_table(iter_dir, scores, avg, worst, expert: false)
  lines = ["# Iteration #{File.basename(iter_dir)}\n"]
  if expert
    lines << '| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Style | Aggregate |'
    lines << '|--------|-------|--------|--------|----------|----------|-------|-------|-----------|'
  else
    lines << '| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Aggregate |'
    lines << '|--------|-------|--------|--------|----------|----------|-------|-----------|'
  end

  scores.each do |name, data|
    p = data[:parse][:pass] ? 'PASS' : 'FAIL'
    c = data[:compat][:pass] ? 'PASS' : 'FAIL'
    f = "#{data[:format][:score]}%"
    fi = data[:fidelity][expert ? 'outcome_fidelity_score' : 'fidelity_score'] || 0
    d = data[:fidelity]['detritus_score'] || 0
    s = data[:step_structure]['step_structure_score'] || 0
    if expert
      sty = data[:style]&.dig('style_score') || 0
      lines << "| #{name} | #{p} | #{c} | #{f} | #{fi} | #{d} | #{s} | #{sty} | #{data[:aggregate]} |"
    else
      lines << "| #{name} | #{p} | #{c} | #{f} | #{fi} | #{d} | #{s} | #{data[:aggregate]} |"
    end
  end

  lines << '' << "**Overall:** #{avg} avg, #{worst} worst" << ''
  lines
end
```

- [ ] **Step 2: Update collect_issues to handle expert-mode fields**

Replace the fidelity issue collection block in `collect_issues` (lines 368-374) with:

```ruby
  %w[ingredients_missing ingredients_added quantities_changed instructions_dropped
     instructions_rewritten detritus_retained prep_leaked_into_name
     technique_lost outcome_affected].each do |key|
    items = data[:fidelity][key]
    next if items.nil? || (items.respond_to?(:empty?) && items.empty?)

    label = %w[technique_lost outcome_affected].include?(key) ? 'OUTCOME' : 'FIDELITY'
    issues << "#{label}: #{key}: #{Array(items).join(', ')}"
  end
```

Then, after the step_structure issue block (after line 381), add:

```ruby
  if data[:style]
    %w[voice_issues condensation_issues specificity_issues title_issues
       description_issues prose_issues footer_issues economy_issues].each do |key|
      items = data[:style][key]
      next if items.nil? || (items.respond_to?(:empty?) && items.empty?)

      issues << "STYLE: #{key.delete_suffix('_issues')}: #{Array(items).join(', ')}"
    end
  end
```

- [ ] **Step 3: Update write_summary to pass expert flag**

Find the `write_summary` method and update the `summary_table` call. Replace:

```ruby
def write_summary(iter_dir, scores, output_dir)
  avg, worst = compute_overall(scores)
  lines = summary_table(iter_dir, scores, avg, worst)
```

With:

```ruby
def write_summary(iter_dir, scores, output_dir, expert: false)
  avg, worst = compute_overall(scores)
  lines = summary_table(iter_dir, scores, avg, worst, expert: expert)
```

Then find where `write_summary` is called in `run_evaluation` and update it. Find:

```ruby
  avg, worst = write_summary(iter_dir, scores, output_dir)
```

Replace with:

```ruby
  avg, worst = write_summary(iter_dir, scores, output_dir, expert: expert_mode?(opts))
```

- [ ] **Step 4: Verify syntax**

Run: `ruby -c test/ai_import/runner_v3.rb`
Expected: `Syntax OK`

- [ ] **Step 5: Commit**

```bash
git add test/ai_import/runner_v3.rb
git commit -m "Update summary output to include style scores in expert mode"
```

---

### Task 6: Sync expert prompt with faithful prompt fixes

**Files:**
- Modify: `lib/familyrecipes/ai_import_prompt_expert.md`

These are baseline fixes to sync the expert prompt with changes made during the faithful prompt tuning work. Each fix is a specific text replacement.

- [ ] **Step 1: Fix sugar qualification rule**

Find in the expert prompt:

```
- Always qualify sugar — "Sugar (white)" or "Sugar (brown)".
```

Replace with:

```
- Qualify sugar when the source specifies the type: "Sugar (brown)",
  "Sugar (powdered)". If the source just says "sugar" with no qualifier,
  write `- Sugar` — do not add "(white)".
```

- [ ] **Step 2: Fix the "Bare Sugar" common mistake**

Find in the Common Mistakes section:

```
- Bare `Sugar` → always `Sugar (white)` or `Sugar (brown)`.
```

Replace with:

```
- `Sugar (granulated)` → use `Sugar (white)` when the source specifies granulated.
```

Note: This removes the "always qualify" rule since bare `Sugar` is now valid when the source doesn't specify.

- [ ] **Step 3: Fix Makes range in Common Mistakes**

Find:

```
- `Makes: 3-4 loaves` → single number: `Makes: 4 loaves`.
```

Replace with:

```
- `Makes: 3-4 loaves` → use the lower bound: `Makes: 3 loaves`.
```

- [ ] **Step 4: Fix Makes range in front matter section**

Find:

```
- **Makes** — yield with a unit noun: "12 pancakes", "2 loaves", "1 loaf".
  Must be a single number, not a range — "Makes: 4 loaves" not
  "Makes: 3-4 loaves".
```

Replace with:

```
- **Makes** — yield with a unit noun: "12 pancakes", "2 loaves", "1 loaf".
  Must be a single number, not a range — "Makes: 3 loaves" not
  "Makes: 3-4 loaves". Use the lower bound of ranges.
```

- [ ] **Step 5: Fix Serves range in front matter section**

Find:

```
- **Serves** — a single plain number: "Serves: 4" not "Serves: 4-6".
  Only include if the source specifies servings. Don't fabricate a number.
```

Replace with:

```
- **Serves** — a single plain number: "Serves: 4" not "Serves: 4-6".
  If the source gives a range, use the lower number. Only include if the
  source specifies servings. Don't fabricate a number.
```

- [ ] **Step 6: Add condensation guidance**

After the "Keep what matters" block in the Instructions section (after line 237 — "Anything that distinguishes this recipe from the default approach"), add:

```
**Strip what goes without saying:**
- Technique tutorials: how to knead, how to dice an onion, how to judge
  when oil is hot, what "al dente" means
- Common-sense advice: open a window, use a sharp knife, be careful with
  hot oil, wash your hands
- Quality editorializing: "preferably homemade", "use the best quality you
  can find", "freshly ground pepper is best"
- Generic cooking advice: don't crowd the pan, season as you go, taste
  before serving
- Unnecessary preamble: "gather your ingredients", "read through the
  recipe first"
```

- [ ] **Step 7: Add title guidance about clickbait**

Find in the Title section:

```
A level-one heading. Use the recipe's name — clean, concise, no "Recipe for"
prefix, no superlatives ("The Best", "Amazing", "Easy"). Capitalize naturally
(title case).
```

Replace with:

```
A level-one heading. Use the recipe's name — clean, concise, no "Recipe for"
prefix, no superlatives ("The Best", "Amazing", "Easy", "Ultimate",
"Perfect"), no clickbait ("How to Make", "You Won't Believe"). Keep it short
— the recipe name, nothing more. Capitalize naturally (title case).
```

- [ ] **Step 8: Add descriptor preservation note**

In the Name rules section, after the line about "Pick one name for a cut of meat" (line 168), add:

```
- Preserve the source's descriptors when they affect purchasing. If the
  source says "bone-in, skin-on chicken thighs", keep both:
  `Chicken thighs (bone-in, skin-on)`. If the source says "low-moisture
  mozzarella", keep it: `Mozzarella (low-moisture)`.
```

- [ ] **Step 9: Add weight equivalent preservation**

In the Quantity and units section, after the line about informal quantities (line 174), add:

```
- Preserve weight equivalents in parentheses — if the source says
  "18 slices ham (18 ounces)" or "3 (8-ounce) loaves", keep the weight:
  `- Ham, 18 slices (18 oz)` or `- Bread, 3 loaves (8 oz each)`.
```

- [ ] **Step 10: Verify the prompt still parses sensibly**

Run: `wc -l lib/familyrecipes/ai_import_prompt_expert.md`
Expected: approximately 430-450 lines (was 408, added ~30 lines)

- [ ] **Step 11: Commit**

```bash
git add lib/familyrecipes/ai_import_prompt_expert.md
git commit -m "Sync expert prompt with faithful prompt fixes, add condensation guidance"
```

---

### Task 7: Smoke test — run expert mode evaluation

This is a manual verification step. Run the evaluation runner in expert mode on the existing corpus to verify the full pipeline works end-to-end.

**Files:**
- No file changes — verification only

- [ ] **Step 1: Run the evaluation**

```bash
cd /home/claude/familyrecipes
ruby test/ai_import/runner_v3.rb --prompt=ai_import_prompt_expert.md baseline_expert
```

This will take several minutes. Verify:
- No crashes or Ruby errors
- All 12 recipes process (11 corpus_v3 entries — the double-recipe was excluded)
- Each recipe gets all 5 scoring layers (parse, compat, format, fidelity, step, style)
- Summary table includes the Style column
- Aggregate scores are computed using the expert formula

- [ ] **Step 2: Review the summary**

```bash
cat test/ai_import/results/iteration_baseline_expert/summary.md
```

Check:
- Style scores appear in the table
- Aggregate scores look reasonable (expect 70-90 range for first run)
- Failure details include STYLE and OUTCOME issue categories where relevant
- No "error" entries in fidelity or style columns

- [ ] **Step 3: Spot-check one output recipe**

```bash
ls test/ai_import/results/iteration_baseline_expert/outputs/
```

Pick one output file and read it. Verify it looks like a condensed expert-mode recipe (terse voice, articles dropped, no tutorials).

- [ ] **Step 4: Commit results summary (not full outputs)**

The results directory is gitignored, so no commit needed. But verify the state.json was updated:

```bash
cat test/ai_import/results/state.json
```

Confirm it shows the `baseline_expert` iteration with scores.

- [ ] **Step 5: Record baseline in commit message**

```bash
git add -A && git status
```

If any tracked files changed (unlikely), commit with the baseline scores noted in the message. Otherwise, note the baseline scores for Ralph Loop reference.

---

### Task 8: Update runner header comment

**Files:**
- Modify: `test/ai_import/runner_v3.rb`

- [ ] **Step 1: Update header comment to document expert mode**

Replace the header comment (lines 1-21) with:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# AI Import prompt evaluation runner (v3). Standalone script — no Rails boot.
# Uses `claude -p` instead of direct API calls — runs on Max plan tokens.
#
# Supports two modes, detected from the prompt filename:
# - Faithful mode (default): scores text fidelity to source
# - Expert mode (prompt contains "expert"): scores outcome fidelity + style
#
# Faithful aggregate: 0.20 * format + 0.50 * ((fidelity + detritus) / 2) + 0.30 * steps
# Expert aggregate:   0.10 * format + 0.40 * ((outcome_fid + detritus) / 2) + 0.25 * steps + 0.25 * style
#
# Usage:
#   ruby test/ai_import/runner_v3.rb [label]
#   ruby test/ai_import/runner_v3.rb --prompt=ai_import_prompt_expert.md [label]
#   ruby test/ai_import/runner_v3.rb --corpus=corpus_v3 [label]
#   ruby test/ai_import/runner_v3.rb --concurrency=5 [label]
#
# Collaborators:
# - claude CLI (`claude -p`) for import (Sonnet) and judging (default model)
# - Scorers::ParseChecker, FormatChecker, SystemCompatChecker for algorithmic checks
# - fidelity_judge_prompt.md / outcome_fidelity_judge_prompt.md for fidelity judging
# - step_structure_judge_prompt.md for step structure judging
# - style_judge_prompt.md for expert style judging (expert mode only)
```

- [ ] **Step 2: Verify syntax**

Run: `ruby -c test/ai_import/runner_v3.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add test/ai_import/runner_v3.rb
git commit -m "Update runner header comment to document expert mode"
```
