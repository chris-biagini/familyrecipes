# AI Import Haiku Round 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tune the Haiku AI import prompt against real-world recipes with improved scoring pipeline.

**Architecture:** Fetch 10 real recipes via WebFetch, update prompt/scorers/runner for tagless two-input evaluation, run ralph loop iterations.

**Tech Stack:** Ruby, Anthropic SDK, WebFetch for corpus sourcing

---

### Task 1: Fetch real-world recipe corpus

**Files:**
- Create: `test/ai_import/corpus_v2/01_blog_*` through `10_*/input.txt` (10 dirs)

- [ ] **Step 1: Fetch 10 real-world recipes via WebFetch**

Fetch these URLs and save the text content as input.txt files:
- 3-4 food blog posts (e.g., seriouseats.com, smittenkitchen.com, budgetbytes.com)
- 2-3 recipe card widget pages (e.g., allrecipes.com, food.com)
- 2-3 clean structured pages (e.g., simplyrecipes.com, bonappetit.com)
- 1 additional blog variant

Save to `test/ai_import/corpus_v2/NN_descriptive_name/input.txt`.

- [ ] **Step 2: Commit**

### Task 2: Update prompt template

**Files:**
- Modify: `test/ai_import/prompt_template.md`

- [ ] **Step 1: Remove all tag references**

Remove the `{{TAGS}}` placeholder, the Tags front matter line from examples,
and all tag guidance. Remove `Tags: quick, weeknight` from the front matter
example block.

- [ ] **Step 2: Add Optional prep note guidance**

In the prep notes section, add that "Optional." is a valid prep note for
optional ingredients. Broaden the prep note definition to include
ingredient-specific notes beyond strict mise en place.

- [ ] **Step 3: Add informal quantity preservation guidance**

Reinforce that informal quantities like "a generous pour" should be kept in
the quantity position: `- Olive oil, a generous pour`.

- [ ] **Step 4: Commit**

### Task 3: Update parse checker for optional expected count

**Files:**
- Modify: `test/ai_import/scorers/parse_checker.rb`

- [ ] **Step 1: Make expected_ingredient_count optional**

Change signature to `expected_ingredient_count: nil`. When nil, skip the
ingredient count check entirely. Still require at least 1 ingredient.

- [ ] **Step 2: Commit**

### Task 4: Update format checker with new checks

**Files:**
- Modify: `test/ai_import/scorers/format_checker.rb`

- [ ] **Step 1: Add informal quantity preservation check**

Scan input for informal quantity patterns (generous, handful, about, pinch,
"or so", "give or take"). If found, verify the language survives in the
output text.

- [ ] **Step 2: Add comment section pattern check**

Scan output (excluding footer) for comment bleed patterns: `says:`, `Reply`,
reviewer-style text.

- [ ] **Step 3: Add tags_invented check**

Scan output for `Tags:` front matter line — since tags are removed from the
prompt, any Tags line is hallucinated.

- [ ] **Step 4: Pass input_text to check method**

The informal quantity check needs the original input. Add `input_text:` as
an optional keyword argument.

- [ ] **Step 5: Commit**

### Task 5: Update fidelity judge prompt

**Files:**
- Modify: `test/ai_import/scorers/fidelity_judge_prompt.md`

- [ ] **Step 1: Rewrite for two-input mode**

Remove REFERENCE from the prompt. Judge receives only ORIGINAL and OUTPUT.
Add the ingredient syntax spec so judge understands `- Name, qty: Prep.`
format. Rename `prep_in_name` to `prep_leaked_into_name` with precise
definition. Add `tags_invented` field. Clarify that informal quantities
in the quantity field are correct.

- [ ] **Step 2: Commit**

### Task 6: Update runner for corpus_v2

**Files:**
- Modify: `test/ai_import/runner.rb`

- [ ] **Step 1: Add --corpus flag**

Parse ARGV for `--corpus=path` to override CORPUS_DIR. Default to `corpus/`.

- [ ] **Step 2: Handle missing expected.md**

When `expected.md` doesn't exist in a corpus dir, pass
`expected_ingredient_count: nil` to ParseChecker and send only
original+output to the Sonnet judge (no REFERENCE section). Pass
`input_text:` to FormatChecker.

- [ ] **Step 3: Remove TAGS from template interpolation**

Remove the `{{TAGS}}` gsub from `load_prompt_template`.

- [ ] **Step 4: Add output snippets for low-scoring recipes**

When a recipe scores below 90, include the first 20 lines of output in
the summary.

- [ ] **Step 5: Update fidelity_keys for renamed fields**

Change `prep_in_name` to `prep_leaked_into_name`, add `tags_invented`.

- [ ] **Step 6: Commit**

### Task 7: Update AiImportService

**Files:**
- Modify: `app/services/ai_import_service.rb`
- Modify: `test/services/ai_import_service_test.rb`

- [ ] **Step 1: Remove {{TAGS}} interpolation**

Remove the tags pluck and gsub from `build_system_prompt`. Remove the
`interpolates kitchen tags` test.

- [ ] **Step 2: Run tests**

`rake test` — all must pass.

- [ ] **Step 3: Commit**

### Task 8: Run ralph loop and copy tuned prompt

- [ ] **Step 1: Run iteration 001 against corpus_v2**
- [ ] **Step 2: Analyze failures, edit prompt**
- [ ] **Step 3: Iterate until convergence (overall > 85, worst > 70)**
- [ ] **Step 4: Copy tuned prompt to production**
- [ ] **Step 5: Run rake test, commit**
