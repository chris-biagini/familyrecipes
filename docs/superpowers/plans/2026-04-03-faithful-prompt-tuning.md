# Faithful Prompt Tuning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the faithful AI import prompt's step-splitting behavior and build a `claude --print` based evaluation pipeline with convergence-driven Ralph Loop.

**Architecture:** Ruby runner script orchestrates `claude -p` calls (Sonnet for import, Opus for judging). 4-layer scoring: parse/system-compat gate, format rules (20%), fidelity judge (50%), step structure judge (30%). Ralph Loop reads scores, analyzes failures, edits prompt, re-runs until convergence (patience of 2).

**Tech Stack:** Ruby (standalone, no Rails), Claude Code CLI (`claude -p`), existing parser pipeline (`lib/familyrecipes/`).

---

## File Structure

**Create:**
- `test/ai_import/corpus_v3/` — 20 recipe directories, each with `input.txt` + `metadata.json`
- `test/ai_import/scorers/system_compat_checker.rb` — round-trip + scaling gate checks
- `test/ai_import/scorers/step_structure_judge_prompt.md` — Layer 4 rubric
- `test/ai_import/runner_v3.rb` — evaluation pipeline using `claude -p`
- `test/ai_import/loop_prompt.md` — Ralph Loop instructions

**Modify:**
- `lib/familyrecipes/ai_import_prompt_faithful.md` — step-splitting rules + detritus calibration
- `test/ai_import/scorers/format_checker.rb` — add `step_splitting_appropriate` check + `metadata:` param
- `app/views/homepage/show.html.erb:179-183` — UI hint below textarea

---

### Task 1: Update Faithful Prompt — Step-Splitting Rules + Detritus Calibration

**Files:**
- Modify: `lib/familyrecipes/ai_import_prompt_faithful.md:107-155`

- [ ] **Step 1: Replace the step-splitting guidance block**

In `lib/familyrecipes/ai_import_prompt_faithful.md`, replace lines 107-155 (from `### Steps` through the end of the implicit steps paragraph) with:

```markdown
### Steps

Each step groups **the ingredients needed for that phase** together with **the
instructions that use them**.

This is NOT the same as numbered steps in a conventional recipe. Think of each
step as a *phase* — "Make the dough.", "Cook the sauce.", "Assemble and bake."

**The source's ingredient grouping drives the step structure. If the source
didn't group its ingredients, neither do you.**

**How to decide:**

1. **Source groups ingredients under headings** ("For the dough:", "Filling:",
   "Sauce ingredients:", "To serve:") — each group becomes a `## Step Name.`
   The source already made the structural decision; map it.
2. **Source has a single flat ingredient list** — use the implicit-step format
   (no `##` heading). This applies regardless of how many numbered instructions
   follow. Do NOT reorganize a flat ingredient list into phases.
3. **Very simple recipes** (5 or fewer ingredients with brief instructions) —
   always use implicit-step format.
4. **Ambiguous groupings** (blank lines between ingredient clusters, but no
   explicit headings) — lean toward implicit. Only split if the groupings are
   unmistakably distinct components with different preparation methods.

Each step starts with a level-two heading:

    ## Make the dough.

Step names: short imperative phrases, sentence case, ending with a period. "Make
the sauce." not "Make the Sauce."

**Ingredient ownership:** Each ingredient belongs to ONE step — the step where
it's first introduced and primarily used. Don't re-list ingredients from earlier
steps. The reader understands that ingredients carry forward through the recipe.

Exception: ubiquitous ingredients (oil, salt, pepper) that serve *distinct
roles* in multiple phases — e.g., oil for searing in one step and oil for a
vinaigrette in another. List these in each step with per-step quantities.

**Ingredient alternatives and substitutions:** If the source offers
alternatives (e.g., "butter or ghee", "1 large onion or 2 small", "apricot jam
or orange marmalade"), list the primary option in the ingredient line and note
alternatives in the footer — do not silently drop any. If an ingredient is
marked optional, still list it as a proper ingredient line (with quantity if
given) and note in the footer that it is optional. Example footer: "Substitute
orange marmalade for the apricot jam. Walnuts are optional."

**Implicit steps:** If the recipe uses implicit-step format (rule 2, 3, or 4
above), omit the `## Heading` and list ingredients and instructions directly
after the front matter. Example:

    # Toast

    Serves: 2

    - Bread, 2 slices
    - Butter

    Toast the bread until golden. Spread butter on each slice while still warm.
```

- [ ] **Step 2: Update detritus section**

In the same file, find the paragraph starting with `**Strip non-recipe content:**` (around line 19) and replace it with:

```markdown
**Strip non-recipe content:** The user has selected the recipe section from the
page. You may see nearby buttons, a nutrition panel, or a few trailing
comments — strip these. You will not typically see entire blog posts or dozens
of reader comments. Strip: "Print" / "Pin" / "Save" / "Jump to Recipe"
buttons, star ratings, comment sections, SEO paragraphs, newsletter signups,
affiliate links, nutrition panels, "Did you make this?" prompts, video embed
placeholders.
```

- [ ] **Step 3: Commit**

```bash
git add lib/familyrecipes/ai_import_prompt_faithful.md
git commit -m "Update faithful prompt: sharper step-splitting rules + scenario B detritus"
```

---

### Task 2: Build Corpus v3 — 20 Real-World Recipes

**Files:**
- Create: `test/ai_import/corpus_v3/01_*` through `20_*`, each with `input.txt` + `metadata.json`

Each recipe is a "scenario B" selection — the recipe section plus some nearby crud, not the full page. Use WebFetch to grab real recipes, then trim to simulate what a user would select. For OCR and clean recipes, hand-craft the content.

The `metadata.json` for each recipe:
```json
{
  "source": "URL or description",
  "expected_steps": "implicit|explicit|ambiguous",
  "category": "blog|aggregator|ocr|clean|international"
}
```

- [ ] **Step 1: Create corpus_v3 directory**

```bash
mkdir -p test/ai_import/corpus_v3
```

- [ ] **Step 2: Fetch blog recipes (7 recipes)**

Use WebFetch to find and save recipes. For each:
1. Fetch the page
2. Extract the recipe section (ingredients + instructions + nearby elements)
3. Trim to scenario B (recipe card, some buttons/ratings, maybe 1-2 comments — NOT the full blog post)
4. Save as `input.txt`
5. Write `metadata.json`

**Slots:**

| Dir | Source | Type | Expected Steps | Notes |
|-----|--------|------|----------------|-------|
| `01_blog_serious_eats_a` | Serious Eats | Multi-component | `explicit` | Recipe with distinct sections (e.g., sauce + main) |
| `02_blog_serious_eats_b` | Serious Eats | Simple technique | `implicit` | Single flat ingredient list |
| `03_blog_serious_eats_c` | Serious Eats | Medium | `ambiguous` | May or may not have ingredient groups |
| `04_blog_smitten_kitchen` | Smitten Kitchen | Baking, multi-component | `explicit` | E.g., cake with frosting |
| `05_blog_budget_bytes` | Budget Bytes | Weeknight dinner | `implicit` | Budget-friendly, flat list |
| `06_blog_pioneer_woman` | Pioneer Woman | Comfort food | `implicit` | Personality in writing, flat list |
| `07_blog_bon_appetit` | Bon Appétit or similar | Technique-heavy | `ambiguous` | Chef-driven, might have component groups |

**Search strategy:** Go to each site, pick a popular recipe that fits the profile. For Serious Eats, search for "best [dish]" to find feature recipes. When fetching, capture from the recipe title through the end of the recipe card, including any "Print" buttons or nutrition info that's adjacent.

- [ ] **Step 3: Fetch aggregator recipes (4 recipes)**

| Dir | Source | Type | Expected Steps | Notes |
|-----|--------|------|----------------|-------|
| `08_agg_allrecipes` | AllRecipes | Simple, flat list | `implicit` | Star ratings, nutrition panel adjacent |
| `09_agg_food_com` | Food.com | Medium, flat list | `implicit` | Review count and comment snippets |
| `10_agg_epicurious` | Epicurious | Multi-component | `explicit` | Often has component sections |
| `11_agg_nyt_style` | NYT Cooking or similar | Chef recipe | `ambiguous` | Professional recipe format |

- [ ] **Step 4: Hand-craft OCR recipes (3 recipes)**

Write simulated OCR text with realistic artifacts.

**`12_ocr_biscuits/input.txt`:**
```
Buttermilk Biscuits

Makes about l0 biscuits

2 cups all-purpose f1our
l tablespoon baking powder
l/2 teaspoon salt
l/3 cup cold butter, cut into smal1 pieces
3/4 cup buttermilk

Preheat oven to 425oF. Whlsk together flour, baking
powder, and sa1t in a large bowl. Cut in butter using
a pastry cutter or two knives until mixture resembIes
coarse crumbs. Add buttermllk and stir just until dough
comes together — do not overmix.

Turn dough out onto a lightly floured surface. Pat to
3/4 inch thickness. Cut with a 2-inch biscuit cutter,
pressing straight down (don't twist). Place on an
ungreased baking sheet. Bake l2-l5 minutes untiI
golden brown on top.
```

`metadata.json`: `{ "source": "Simulated cookbook scan", "expected_steps": "implicit", "category": "ocr" }`

**`13_ocr_beef_stew/input.txt`:**
```
Hearty Beef Stew

Serves 6

For the beef:
2 lbs beef chuck, cut lnto l-inch cubes
2 tabIespoons olive oiI
Salt and pepper

For the stew:
l large onion, diced
3 cloves garIic, mlnced
3 carrots, peeled and sIiced
3 potatoes, cut lnto chunks
2 stalks ce1ery, sliced
l can (l4.5 oz) dlced tomatoes
4 cups beef broth
l tablespoon tomato paste
l teaspoon dried thyme
2 bay Ieaves

Season beef with sa1t and pepper. Heat oiI in a large
Dutch oven over medium-high heat. Brown beef in
batches, about 3 minutes per slde. Remove and set aslde.

Add onion to the pot and cook untlI softened, about
5 minutes. Add garIic and cook l minute more. Return
beef to pot. Add remaining ingredients and bring to
a boiI. Reduce heat, cover, and slmmer for l l/2 to
2 hours untiI beef is tender.

Remove bay Ieaves before serving.
```

`metadata.json`: `{ "source": "Simulated cookbook scan", "expected_steps": "explicit", "category": "ocr" }`

**`14_ocr_banana_muffins/input.txt`:**
```
Banana Mufflns

Makes l2

3 rlpe bananas, mashed
l/3 cup meIted butter
3/4 cup sugar
l egg, beaten
l teaspoon vanllla extract
l teaspoon baklng soda
Plnch of saIt
l l/2 cups aII-purpose flour

Preheat oven to 35OoF. Mlx mashed bananas and
meIted butter in a large bowl. Stir in sugar, egg,
and vanllla. Sprinkle in baklng soda and saIt, then
mix in flour.

Spoon batter lnto a greased muffln tln, filling
each cup about 2/3 fuII. Bake for 25-3O minutes,
untiI a toothplck lnserted ln the center comes
out cIean. Let cooI in tln for 5 mlnutes, then
transfer to a wlre rack.
```

`metadata.json`: `{ "source": "Simulated cookbook scan", "expected_steps": "implicit", "category": "ocr" }`

- [ ] **Step 5: Hand-craft clean/shared recipes (3 recipes)**

**`15_clean_text_message/input.txt`:**
```
ok so for the guac

2 avocados
half a lime
little bit of salt
some cilantro if u have it
half a jalapeño or less if u dont like spicy

mash the avocados with a fork, squeeze the lime in, chop the cilantro and jalapeño real small and mix it all together. taste it and add more salt/lime if u need to. dont overmix it should be chunky
```

`metadata.json`: `{ "source": "Text message", "expected_steps": "implicit", "category": "clean" }`

**`16_clean_email/input.txt`:**
```
Subject: Mom's Chicken Soup Recipe (as promised!)

Hey! Here's that chicken soup recipe I was telling you about. It's really easy:

- 1 whole chicken (about 3-4 lbs)
- 2 carrots, peeled and sliced
- 2 stalks celery, sliced
- 1 large onion, quartered
- 3 cloves garlic, smashed
- A few sprigs of fresh dill
- Salt and pepper
- Egg noodles (about half a bag)

Put the chicken in a big pot, cover with water (about 10-12 cups), add the onion and garlic. Bring to a boil then lower to a simmer. Skim the foam off the top. Cook about 1.5 hours until the chicken is falling apart.

Take out the chicken, let it cool a bit, then shred the meat and throw away the skin and bones. Strain the broth if you want (I usually don't bother). Add the carrots and celery to the broth and cook about 15 min until tender. Add the shredded chicken back in. Cook the egg noodles separately and add them to each bowl when serving (they get mushy if you leave them in the soup).

Season with salt, pepper, and fresh dill. Dad always adds a squeeze of lemon at the table but that's optional :)
```

`metadata.json`: `{ "source": "Email", "expected_steps": "implicit", "category": "clean" }`

**`17_clean_handwritten/input.txt`:**
```
Grandma's Pie Crust
Makes 2 crusts

2 1/2 cups flour
1 tsp salt
1 cup butter (cold!!)
6-8 tbsp ice water

Mix flour + salt. Cut butter into small pieces and work into flour with your hands until it looks like coarse meal with some pea-sized chunks. Sprinkle water 1 tbsp at a time, tossing with a fork after each one. Stop when dough just holds together when squeezed.

Divide in half, shape into discs, wrap in plastic. Refrigerate at least 1 hour (overnight is even better).

Roll out on floured surface. For a 9-inch pie.

Note: the secret is keeping everything COLD. Cold butter, ice water, cold hands. If the butter melts the crust won't be flaky.
```

`metadata.json`: `{ "source": "Handwritten card, typed", "expected_steps": "implicit", "category": "clean" }`

- [ ] **Step 6: Fetch international/metric recipes (3 recipes)**

| Dir | Source | Type | Expected Steps | Notes |
|-----|--------|------|----------------|-------|
| `18_intl_japanese` | Japanese cooking site | Metric, different structure | `ambiguous` | E.g., ramen, curry, teriyaki |
| `19_intl_indian` | Indian food blog | Metric, multi-component | `explicit` | E.g., butter chicken with rice, biryani |
| `20_intl_french` | French cooking site | Metric, precise | `implicit` | E.g., vinaigrette, crepe, quiche |

Search for popular recipes on sites like Just One Cookbook (Japanese), Hebbar's Kitchen or similar (Indian), and a French cooking blog. Trim to scenario B.

- [ ] **Step 7: Commit corpus**

```bash
git add test/ai_import/corpus_v3/
git commit -m "Add corpus v3: 20 real-world recipes for faithful prompt tuning"
```

---

### Task 3: Write System Compatibility Checker

**Files:**
- Create: `test/ai_import/scorers/system_compat_checker.rb`

- [ ] **Step 1: Write the checker**

```ruby
# frozen_string_literal: true

# Layer 1 gate check: system compatibility. Verifies the AI-generated recipe
# can survive a round-trip through the parser pipeline and that numeric
# quantities scale without errors.
#
# Collaborators:
# - LineClassifier, RecipeBuilder — parse pipeline
# - FamilyRecipes::Ingredient — quantity splitting
# - FamilyRecipes::NumericParsing — fraction parsing
# - Scorers::ParseChecker — companion gate check (structural validity)
module Scorers
  class SystemCompatChecker
    Result = Data.define(:pass, :details)

    def self.check(output_text)
      errors = []

      begin
        tokens = LineClassifier.classify(output_text)
        parsed = RecipeBuilder.new(tokens).build
      rescue FamilyRecipes::ParseError => e
        return Result.new(pass: false, details: { errors: ["Parse error: #{e.message}"] })
      end

      errors.concat(check_round_trip(parsed))
      errors.concat(check_scaling(parsed))

      Result.new(pass: errors.empty?, details: { errors: errors })
    end

    def self.check_round_trip(parsed)
      reconstructed = reconstruct_markdown(parsed)

      begin
        tokens2 = LineClassifier.classify(reconstructed)
        parsed2 = RecipeBuilder.new(tokens2).build
      rescue FamilyRecipes::ParseError => e
        return ["Round-trip re-parse failed: #{e.message}"]
      end

      errors = []
      errors << "Round-trip title mismatch" if parsed[:title] != parsed2[:title]

      orig_count = ingredient_count(parsed)
      rt_count = ingredient_count(parsed2)
      errors << "Round-trip ingredient count: #{orig_count} vs #{rt_count}" if orig_count != rt_count

      orig_steps = parsed[:steps].size
      rt_steps = parsed2[:steps].size
      errors << "Round-trip step count: #{orig_steps} vs #{rt_steps}" if orig_steps != rt_steps

      errors
    end

    def self.check_scaling(parsed)
      parsed[:steps].flat_map { |step|
        (step[:ingredients] || []).filter_map { |ing| scaling_error(ing) }
      }
    end

    def self.scaling_error(ingredient)
      return nil unless ingredient[:quantity]

      qty_str, _unit = FamilyRecipes::Ingredient.split_quantity(ingredient[:quantity])
      return nil unless qty_str

      value = FamilyRecipes::NumericParsing.parse_fraction(qty_str)
      return nil unless value

      scaled = value * 2
      return "Scaling failed for #{ingredient[:name]} (#{ingredient[:quantity]})" if scaled.nan? || scaled.infinite?

      nil
    rescue ArgumentError
      nil # Non-numeric quantity — that's fine
    end

    def self.ingredient_count(parsed)
      parsed[:steps].sum { |s| (s[:ingredients] || []).size }
    end

    def self.reconstruct_markdown(parsed)
      lines = ["# #{parsed[:title]}"]
      append_description(lines, parsed[:description])
      append_front_matter(lines, parsed[:front_matter])
      parsed[:steps].each { |step| append_step(lines, step) }
      append_footer(lines, parsed[:footer])
      lines.join("\n") + "\n"
    end

    def self.append_description(lines, desc)
      return unless desc && !desc.strip.empty?

      lines << '' << desc.strip
    end

    def self.append_front_matter(lines, fm)
      return unless fm&.any? { |_k, v| v && (v.respond_to?(:empty?) ? !v.empty? : true) }

      lines << ''
      lines << "Makes: #{fm[:makes]}" if fm[:makes]
      lines << "Serves: #{fm[:serves]}" if fm[:serves]
      lines << "Category: #{fm[:category]}" if fm[:category]
      lines << "Tags: #{fm[:tags].join(', ')}" if fm[:tags]&.size&.positive?
    end

    def self.append_step(lines, step)
      lines << ''
      lines << "## #{step[:tldr]}" if step[:tldr]
      (step[:ingredients] || []).each { |ing| lines << ingredient_line(ing) }
      return unless step[:instructions] && !step[:instructions].strip.empty?

      lines << '' << step[:instructions].strip
    end

    def self.ingredient_line(ing)
      line = "- #{ing[:name]}"
      line += ", #{ing[:quantity]}" if ing[:quantity]
      line += ": #{ing[:prep_note]}" if ing[:prep_note]
      line
    end

    def self.append_footer(lines, footer)
      return unless footer && !footer.strip.empty?

      lines << '' << '---' << '' << footer.strip
    end

    private_class_method :check_round_trip, :check_scaling, :scaling_error,
                         :ingredient_count, :reconstruct_markdown,
                         :append_description, :append_front_matter,
                         :append_step, :ingredient_line, :append_footer
  end
end
```

- [ ] **Step 2: Smoke-test against a known-good recipe**

Run in IRB or a quick script to verify the checker works against a corpus recipe that already parses:

```bash
ruby -Ilib -e "
  require 'familyrecipes'
  require_relative 'test/ai_import/scorers/system_compat_checker'

  text = File.read('test/ai_import/results/iteration_005/outputs/01_blog_simple.md')
  result = Scorers::SystemCompatChecker.check(text)
  puts \"Pass: #{result.pass}\"
  puts \"Details: #{result.details}\"
"
```

Expected: `Pass: true`, empty errors array.

- [ ] **Step 3: Commit**

```bash
git add test/ai_import/scorers/system_compat_checker.rb
git commit -m "Add system compatibility checker: round-trip + scaling gate"
```

---

### Task 4: Update Format Checker — Add Step-Splitting Check

**Files:**
- Modify: `test/ai_import/scorers/format_checker.rb`

- [ ] **Step 1: Add `metadata:` parameter and new check method**

In `format_checker.rb`, update the `check` method signature to accept `metadata:`:

```ruby
def self.check(output_text, valid_categories:, input_text: nil, metadata: nil)
```

Add the new check call in the `check` method body, after the `informal_quantities_preserved` line:

```ruby
checks << step_splitting_appropriate(parsed, metadata) if metadata
```

Add the new method before `safe_parse`:

```ruby
def self.step_splitting_appropriate(parsed, metadata)
  expected = metadata['expected_steps']
  return { name: 'step_splitting_appropriate', pass: true } unless expected
  return { name: 'step_splitting_appropriate', pass: true } if expected == 'ambiguous'

  steps = parsed[:steps] || []
  has_headers = steps.any? { |s| s[:tldr] }

  case expected
  when 'implicit'
    pass = steps.size == 1 && !has_headers
    { name: 'step_splitting_appropriate', pass: pass,
      failures: pass ? nil : ["Expected implicit (1 step, no headers) but got #{steps.size} steps"] }
  when 'explicit'
    pass = steps.size >= 2 && steps.all? { |s| s[:tldr] }
    { name: 'step_splitting_appropriate', pass: pass,
      failures: pass ? nil : ["Expected explicit (2+ named steps) but got #{steps.size} steps, headers=#{has_headers}"] }
  else
    { name: 'step_splitting_appropriate', pass: true }
  end
end
```

Add `:step_splitting_appropriate` to the `private_class_method` list.

- [ ] **Step 2: Smoke-test**

```bash
ruby -Ilib -e "
  require 'familyrecipes'
  require_relative 'test/ai_import/scorers/format_checker'

  # Test with implicit recipe
  text = \"# Toast\n\nServes: 2\n\n- Bread, 2 slices\n- Butter\n\nToast until golden.\n\"
  meta = { 'expected_steps' => 'implicit' }
  result = Scorers::FormatChecker.check(text, valid_categories: %w[Miscellaneous], metadata: meta)
  split_check = result.checks.find { |c| c[:name] == 'step_splitting_appropriate' }
  puts \"Implicit pass: #{split_check[:pass]}\"

  # Test with explicit recipe marked as implicit (should fail)
  text2 = \"# Cake\n\nCategory: Baking\n\n## Make batter.\n\n- Flour, 2 cups\n\nMix.\n\n## Make frosting.\n\n- Sugar, 1 cup\n\nWhisk.\n\"
  result2 = Scorers::FormatChecker.check(text2, valid_categories: %w[Baking], metadata: meta)
  split_check2 = result2.checks.find { |c| c[:name] == 'step_splitting_appropriate' }
  puts \"Explicit-as-implicit fail: #{!split_check2[:pass]}\"
"
```

Expected: both `true`.

- [ ] **Step 3: Commit**

```bash
git add test/ai_import/scorers/format_checker.rb
git commit -m "Add step_splitting_appropriate check to format checker"
```

---

### Task 5: Write Step Structure Judge Rubric

**Files:**
- Create: `test/ai_import/scorers/step_structure_judge_prompt.md`

- [ ] **Step 1: Write the rubric**

```markdown
You are a recipe structure quality judge. You will receive two texts: ORIGINAL
(the source recipe) and OUTPUT (the AI-converted version in Markdown format).

Evaluate how well the OUTPUT handled structural conversion — specifically
whether it chose the right step format and organized content appropriately.

## Step Structure Rules

The conversion should follow these rules:

1. **Source groups ingredients under headings** ("For the dough:", "Filling:",
   "Sauce:", etc.) — each group becomes a `## Step Name.` heading (explicit
   steps).
2. **Source has a single flat ingredient list** — the output uses implicit-step
   format: ingredients and instructions directly after front matter, no `##`
   headings. This applies regardless of how many numbered instructions follow.
3. **Very simple recipes** (5 or fewer ingredients) — always implicit format.
4. **Ambiguous groupings** (blank lines but no headings) — lean implicit.

## Evaluation Criteria

### Split Decision (0-25)
Did the model choose implicit vs explicit appropriately?
- 25: Perfect match to the rules above.
- 15-24: Close but debatable (e.g., chose explicit for a borderline case).
- 0-14: Wrong choice (split a flat-list recipe or left a clearly grouped
  recipe as a single implicit step).

### Ingredient Ownership (0-25)
Are ingredients grouped under the right step?
- 25: Each ingredient appears once, in the step where it is primarily used.
- 15-24: Minor issues (an ingredient in a slightly wrong step).
- 0-14: Ingredients re-listed across steps or placed in wrong steps.
- For implicit-step output: auto-score 25 (not applicable).

### Step Naming (0-25)
Are step names meaningful?
- 25: Names describe phases ("Make the dough.", "Cook the sauce.") in sentence
  case ending with a period.
- 15-24: Names are okay but generic ("Prepare ingredients.") or missing period.
- 0-14: Names are "Step 1", "Step 2" or mechanical numbering.
- For implicit-step output: auto-score 25 (not applicable).

### Instruction Flow (0-25)
Do instructions follow the source's order?
- 25: Instructions match the source's sequence with no reorganization.
- 15-24: Minor reordering that does not affect meaning.
- 0-14: Instructions reorganized, moved between steps, or significantly
  reordered.

Respond with ONLY this JSON — no other text:

```json
{
  "split_decision": "implicit or explicit",
  "expected_decision": "implicit, explicit, or ambiguous",
  "split_issues": ["any problems with the split choice"],
  "naming_issues": ["any problems with step names"],
  "ownership_issues": ["any problems with ingredient placement"],
  "flow_issues": ["any problems with instruction ordering"],
  "step_structure_score": 85
}
```

The `step_structure_score` is the sum of the four criteria (0-100). Empty
arrays mean no issues found. Scores must be integers 0-100.
```

- [ ] **Step 2: Commit**

```bash
git add test/ai_import/scorers/step_structure_judge_prompt.md
git commit -m "Add step structure judge rubric for Layer 4 scoring"
```

---

### Task 6: Write Runner v3

**Files:**
- Create: `test/ai_import/runner_v3.rb`

This is the main evaluation pipeline. It uses `claude -p` with `--system-prompt` and `--tools ""` to get behavior close to a bare API call.

- [ ] **Step 1: Write the runner script**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# AI Import prompt evaluation runner (v3). Standalone script — no Rails boot.
# Uses `claude -p` instead of direct API calls — runs on Max plan tokens.
#
# Key difference from runner.rb: `--system-prompt` replaces the Claude Code
# default system prompt, and `--tools ""` disables all tools. This makes
# the invocation behave like a bare API call.
#
# Usage:
#   ruby test/ai_import/runner_v3.rb [label]
#   ruby test/ai_import/runner_v3.rb --corpus=corpus_v3 [label]
#   ruby test/ai_import/runner_v3.rb --prompt=ai_import_prompt_faithful.md [label]
#   ruby test/ai_import/runner_v3.rb --concurrency=5 [label]
#
# Collaborators:
# - claude CLI (`claude -p`) for import (Sonnet) and judging (default model)
# - Scorers::ParseChecker, FormatChecker, SystemCompatChecker for algorithmic checks
# - fidelity_judge_prompt.md, step_structure_judge_prompt.md for LLM judge rubrics

require 'json'
require 'fileutils'
require 'open3'

# ActiveSupport polyfill — parser uses .presence
class Object
  def presence
    self if respond_to?(:empty?) ? !empty? : !nil?
  end
end

require_relative '../../lib/familyrecipes'
require_relative 'scorers/parse_checker'
require_relative 'scorers/format_checker'
require_relative 'scorers/system_compat_checker'

BASE_DIR = File.expand_path(__dir__)
RESULTS_DIR = File.join(BASE_DIR, 'results')
LIB_DIR = File.expand_path('../../lib/familyrecipes', BASE_DIR)

CATEGORIES = %w[Baking Bread Breakfast Dessert Drinks Holiday Mains Pizza Sides Snacks Miscellaneous].freeze
TAGS = %w[vegetarian vegan gluten-free weeknight easy quick one-pot make-ahead
          freezer-friendly grilled roasted baked comfort-food holiday american
          italian mexican french japanese chinese indian thai].freeze

# --- CLI ---

def parse_args
  opts = { corpus: 'corpus_v3', prompt: 'ai_import_prompt_faithful.md', concurrency: 5, label: nil }

  ARGV.each do |arg|
    case arg
    when /\A--corpus=(.+)/ then opts[:corpus] = $1
    when /\A--prompt=(.+)/ then opts[:prompt] = $1
    when /\A--concurrency=(\d+)/ then opts[:concurrency] = $1.to_i
    else opts[:label] = arg
    end
  end

  opts[:corpus_dir] = File.join(BASE_DIR, opts[:corpus])
  opts[:prompt_path] = File.join(LIB_DIR, opts[:prompt])
  opts
end

def load_prompt(path)
  File.read(path)
      .gsub('{{CATEGORIES}}', CATEGORIES.join(', '))
      .gsub('{{TAGS}}', TAGS.join(', '))
end

def corpus_dirs(dir)
  Dir.glob(File.join(dir, '*')).select { |f| File.directory?(f) }.sort
end

def load_metadata(dir)
  path = File.join(dir, 'metadata.json')
  File.exist?(path) ? JSON.parse(File.read(path)) : {}
end

# --- Claude CLI wrapper ---

def call_claude(user_message, system_prompt: nil, model: nil, timeout: 180)
  cmd = ['claude', '-p', '--no-session-persistence', '--tools', '']
  cmd += ['--system-prompt', system_prompt] if system_prompt
  cmd += ['--model', model] if model
  stdout, stderr, status = Open3.capture3(*cmd, stdin_data: user_message)
  unless status.success?
    return { error: "claude exited #{status.exitstatus}: #{stderr.lines.first(3).join}" }
  end
  { text: stdout }
rescue Errno::ENOENT
  { error: 'claude CLI not found on PATH' }
end

def clean_import_output(text)
  text = text.gsub(/\A```\w*\n/, '').delete_suffix("\n```")
  heading_index = text.index(/^# /)
  heading_index ? text[heading_index..].rstrip + "\n" : text.rstrip + "\n"
end

def parse_json_response(text)
  cleaned = text.strip.gsub(/\A```\w*\n/, '').delete_suffix("\n```").strip
  start_idx = cleaned.index('{')
  end_idx = cleaned.rindex('}')
  return nil unless start_idx && end_idx

  JSON.parse(cleaned[start_idx..end_idx])
rescue JSON::ParserError
  nil
end

# --- Scoring pipeline ---

def import_recipe(system_prompt, input_text)
  result = call_claude(input_text, system_prompt: system_prompt, model: 'sonnet')
  return result if result[:error]

  { text: clean_import_output(result[:text]) }
end

def judge_fidelity(rubric, original, output)
  user_msg = "## ORIGINAL\n\n#{original}\n\n## OUTPUT\n\n#{output}"
  result = call_claude(user_msg, system_prompt: rubric)
  return default_fidelity_error(result[:error]) if result[:error]

  parsed = parse_json_response(result[:text])
  parsed || default_fidelity_error('JSON parse failed')
end

def judge_step_structure(rubric, original, output)
  user_msg = "## ORIGINAL\n\n#{original}\n\n## OUTPUT\n\n#{output}"
  result = call_claude(user_msg, system_prompt: rubric)
  return default_step_error(result[:error]) if result[:error]

  parsed = parse_json_response(result[:text])
  parsed || default_step_error('JSON parse failed')
end

def default_fidelity_error(msg)
  { 'error' => msg, 'fidelity_score' => 0, 'detritus_score' => 0 }
end

def default_step_error(msg)
  { 'error' => msg, 'step_structure_score' => 0 }
end

def process_recipe(dir, system_prompt, fidelity_rubric, step_rubric)
  name = File.basename(dir)
  input_text = File.read(File.join(dir, 'input.txt'))
  metadata = load_metadata(dir)

  puts "[#{name}] Importing..."
  import = import_recipe(system_prompt, input_text)
  return error_scores(import[:error]) if import[:error]

  output_text = import[:text]

  puts "  [#{name}] Layer 1: parse + compat..."
  parse = Scorers::ParseChecker.check(output_text)
  compat = Scorers::SystemCompatChecker.check(output_text)

  puts "  [#{name}] Layer 2: format..."
  format = Scorers::FormatChecker.check(output_text, valid_categories: CATEGORIES,
                                                      input_text: input_text, metadata: metadata)

  puts "  [#{name}] Layer 3: fidelity judge..."
  fidelity = judge_fidelity(fidelity_rubric, input_text, output_text)

  puts "  [#{name}] Layer 4: step structure judge..."
  step = judge_step_structure(step_rubric, input_text, output_text)

  gate_pass = parse.pass && compat.pass
  agg = aggregate_score(gate_pass, format, fidelity, step)
  puts "  [#{name}] Aggregate: #{agg.round(1)}"

  { output_text: output_text,
    parse: { pass: parse.pass, details: parse.details },
    compat: { pass: compat.pass, details: compat.details },
    format: { score: (format.score * 100).round(1), checks: format.checks },
    fidelity: fidelity, step_structure: step, aggregate: agg.round(1) }
end

def error_scores(msg)
  { output_text: '', aggregate: 0.0,
    parse: { pass: false, details: { errors: [msg] } },
    compat: { pass: false, details: { errors: [msg] } },
    format: { score: 0.0, checks: [] },
    fidelity: { 'fidelity_score' => 0, 'detritus_score' => 0 },
    step_structure: { 'step_structure_score' => 0 } }
end

def aggregate_score(gate_pass, format_result, fidelity, step)
  return 0.0 unless gate_pass

  fmt = format_result.score * 100.0
  fid = (fidelity['fidelity_score'] || 0).to_f
  det = (fidelity['detritus_score'] || 0).to_f
  stp = (step['step_structure_score'] || 0).to_f
  (0.20 * fmt) + (0.50 * ((fid + det) / 2.0)) + (0.30 * stp)
end

# --- Concurrency ---

def parallel_map(items, concurrency)
  results = Array.new(items.size)
  queue = Queue.new
  items.each_with_index { |item, i| queue << [item, i] }
  concurrency.times { queue << nil }

  workers = concurrency.times.map do
    Thread.new do
      while (pair = queue.pop)
        item, index = pair
        results[index] = yield(item)
      end
    end
  end

  workers.each(&:join)
  results
end

# --- Output ---

def next_label
  existing = Dir.glob(File.join(RESULTS_DIR, 'iteration_*'))
                .map { |d| File.basename(d).delete_prefix('iteration_') }
                .select { |l| l.match?(/\A\d+\z/) }
                .map(&:to_i)
  format('%03d', (existing.max || 0) + 1)
end

def prompt_sha(path)
  `git hash-object #{path}`.strip
end

def update_state(label, avg, worst, prompt_path)
  state_path = File.join(RESULTS_DIR, 'state.json')
  state = File.exist?(state_path) ? JSON.parse(File.read(state_path)) : {
    'iterations' => [], 'best_iteration' => nil, 'best_avg' => 0.0, 'patience' => 0
  }

  state['iterations'] << {
    'label' => label, 'avg' => avg, 'worst' => worst,
    'prompt_sha' => prompt_sha(prompt_path)
  }

  if avg > state['best_avg']
    state['best_iteration'] = label
    state['best_avg'] = avg
    state['patience'] = 0
  else
    state['patience'] += 1
  end

  File.write(state_path, JSON.pretty_generate(state))
  state
end

def write_summary(iter_dir, scores, output_dir)
  lines = summary_header(iter_dir, scores)
  append_failure_details(lines, scores, output_dir)
  File.write(File.join(iter_dir, 'summary.md'), lines.join("\n"))

  avg = (scores.values.sum { |s| s[:aggregate] } / scores.size.to_f).round(1)
  worst = scores.values.map { |s| s[:aggregate] }.min.round(1)
  [avg, worst]
end

def summary_header(iter_dir, scores)
  lines = ["# Iteration #{File.basename(iter_dir)}\n"]
  lines << '| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Aggregate |'
  lines << '|--------|-------|--------|--------|----------|----------|-------|-----------|'

  scores.each do |name, data|
    p = data[:parse][:pass] ? 'PASS' : 'FAIL'
    c = data[:compat][:pass] ? 'PASS' : 'FAIL'
    f = "#{data[:format][:score]}%"
    fi = data[:fidelity]['fidelity_score'] || 0
    d = data[:fidelity]['detritus_score'] || 0
    s = data[:step_structure]['step_structure_score'] || 0
    lines << "| #{name} | #{p} | #{c} | #{f} | #{fi} | #{d} | #{s} | #{data[:aggregate]} |"
  end

  avg = (scores.values.sum { |s| s[:aggregate] } / scores.size.to_f).round(1)
  worst = scores.values.map { |s| s[:aggregate] }.min.round(1)
  lines << '' << "**Overall:** #{avg} avg, #{worst} worst" << ''
  lines
end

def append_failure_details(lines, scores, output_dir)
  scores.each do |name, data|
    issues = collect_issues(data)
    next if issues.empty?

    lines << "### #{name} — issues"
    issues.each { |i| lines << "- #{i}" }
    append_output_snippet(lines, output_dir, name) if data[:aggregate] < 90
    lines << ''
  end
end

def collect_issues(data)
  issues = []
  issues << "PARSE: #{data[:parse][:details][:errors].join(', ')}" unless data[:parse][:pass]
  issues << "COMPAT: #{data[:compat][:details][:errors].join(', ')}" unless data[:compat][:pass]

  (data[:format][:checks] || []).each do |check|
    next if check[:pass]

    detail = check[:failures] ? " — #{Array(check[:failures]).join(', ')}" : ''
    issues << "FORMAT: #{check[:name]}#{detail}"
  end

  %w[ingredients_missing ingredients_added quantities_changed instructions_dropped
     instructions_rewritten detritus_retained prep_leaked_into_name].each do |key|
    items = data[:fidelity][key]
    next if items.nil? || (items.respond_to?(:empty?) && items.empty?)

    issues << "FIDELITY: #{key}: #{Array(items).join(', ')}"
  end

  %w[split_issues naming_issues ownership_issues flow_issues].each do |key|
    items = data[:step_structure][key]
    next if items.nil? || (items.respond_to?(:empty?) && items.empty?)

    issues << "STEPS: #{key}: #{Array(items).join(', ')}"
  end

  issues
end

def append_output_snippet(lines, output_dir, name)
  path = File.join(output_dir, "#{name}.md")
  return unless File.exist?(path)

  snippet = File.readlines(path).first(20).join
  lines << '' << '**Output snippet (first 20 lines):**' << '```' << snippet << '```'
end

# --- Main ---

def run_evaluation
  opts = parse_args
  opts[:label] ||= next_label
  label = opts[:label]

  puts "Corpus:      #{opts[:corpus_dir]}"
  puts "Prompt:      #{opts[:prompt_path]}"
  puts "Concurrency: #{opts[:concurrency]}"
  puts "Label:       #{label}"

  system_prompt = load_prompt(opts[:prompt_path])
  fidelity_rubric = File.read(File.join(BASE_DIR, 'scorers', 'fidelity_judge_prompt.md'))
  step_rubric = File.read(File.join(BASE_DIR, 'scorers', 'step_structure_judge_prompt.md'))

  iter_dir = File.join(RESULTS_DIR, "iteration_#{label}")
  output_dir = File.join(iter_dir, 'outputs')
  FileUtils.mkdir_p(output_dir)

  dirs = corpus_dirs(opts[:corpus_dir])
  puts "Processing #{dirs.size} recipes...\n\n"

  results = parallel_map(dirs, opts[:concurrency]) do |dir|
    process_recipe(dir, system_prompt, fidelity_rubric, step_rubric)
  end

  scores = {}
  dirs.each_with_index do |dir, i|
    name = File.basename(dir)
    File.write(File.join(output_dir, "#{name}.md"), results[i][:output_text])
    scores[name] = results[i].except(:output_text)
  end

  File.write(File.join(iter_dir, 'scores.json'), JSON.pretty_generate(scores))
  avg, worst = write_summary(iter_dir, scores, output_dir)
  state = update_state(label, avg, worst, opts[:prompt_path])

  puts "\nResults: #{iter_dir}/"
  puts "Overall: #{avg} avg, #{worst} worst"
  puts "Best: #{state['best_avg']} (iteration #{state['best_iteration']}), patience: #{state['patience']}/2"
end

run_evaluation if $PROGRAM_NAME == __FILE__
```

- [ ] **Step 2: Smoke-test with 1-2 corpus recipes**

Test with a small subset to verify the pipeline works end-to-end:

```bash
mkdir -p test/ai_import/corpus_smoke
cp -r test/ai_import/corpus_v3/15_clean_text_message test/ai_import/corpus_smoke/
ruby test/ai_import/runner_v3.rb --corpus=corpus_smoke --concurrency=1 smoke_test
```

Verify:
- `test/ai_import/results/iteration_smoke_test/` directory created
- `outputs/15_clean_text_message.md` contains a recipe
- `scores.json` has all scoring layers
- `summary.md` has the results table
- `state.json` exists in `test/ai_import/results/`

If `claude -p --tools ""` fails (tools flag format issue), try `--tools ""` with different quoting or omit it.

- [ ] **Step 3: Clean up smoke test and commit**

```bash
rm -rf test/ai_import/corpus_smoke test/ai_import/results/iteration_smoke_test
git add test/ai_import/runner_v3.rb
git commit -m "Add runner v3: claude --print evaluation pipeline with 4-layer scoring"
```

---

### Task 7: Write Ralph Loop Prompt

**Files:**
- Create: `test/ai_import/loop_prompt.md`

- [ ] **Step 1: Write the loop instructions**

```markdown
# Faithful Prompt Tuning — Ralph Loop

You are iteratively improving the faithful AI import prompt. Each iteration:
analyze what went wrong, make ONE targeted prompt edit, re-evaluate, check
convergence.

## Step 1: Read State

Read `test/ai_import/results/state.json`. Note the iteration count,
`best_avg`, and `patience`.

If `state.json` does not exist, this is the first iteration — skip to Step 3
and just run the baseline (no prompt edits needed).

## Step 2: Analyze Failures

Read the most recent `test/ai_import/results/iteration_*/summary.md`.

Focus on:
- Recipes with aggregate < 90 (priority targets)
- Common patterns across failures (format, fidelity, step structure)
- The worst-scoring recipe — what specifically went wrong?
- Layer 4 step structure issues — are split decisions correct?

## Step 3: Edit the Prompt

Edit `lib/familyrecipes/ai_import_prompt_faithful.md`. Rules:
- Make ONE targeted change per iteration (a rule tweak, a clarification, an
  example). Small changes are easier to attribute to score changes.
- Never rewrite the prompt from scratch.
- Never add a rule that only helps one recipe — check if it could hurt others.
- Do not change the scoring system, runner script, or judge rubrics.

If this is the first iteration, verify the prompt already has the
step-splitting rules from the spec and make no edits.

Commit the change:
```
git add lib/familyrecipes/ai_import_prompt_faithful.md
git commit -m "Ralph loop: [brief description of change]"
```

## Step 4: Run Evaluation

```bash
ruby test/ai_import/runner_v3.rb --corpus=corpus_v3
```

This takes several minutes. Wait for it to complete.

## Step 5: Check Convergence

Read the updated `test/ai_import/results/state.json`.

If `patience >= 2`:
1. Read the `best_iteration` label and its `prompt_sha`.
2. Restore the best prompt:
   ```
   git show <prompt_sha> > lib/familyrecipes/ai_import_prompt_faithful.md
   ```
3. Commit:
   ```
   git add lib/familyrecipes/ai_import_prompt_faithful.md
   git commit -m "Ralph loop: restore best prompt (iteration <label>, avg <score>)"
   ```
4. Output: <promise>FAITHFUL TUNED</promise>

If `patience < 2`: let the loop continue — the stop hook will feed this
prompt again and you will start from Step 1 with updated state.
```

- [ ] **Step 2: Commit**

```bash
git add test/ai_import/loop_prompt.md
git commit -m "Add Ralph Loop prompt for faithful prompt tuning"
```

---

### Task 8: Add UI Hint to Import Dialog

**Files:**
- Modify: `app/views/homepage/show.html.erb:183`

- [ ] **Step 1: Add hint text below the textarea**

In `app/views/homepage/show.html.erb`, after the closing `</textarea>` tag (line 183), add:

```erb
    <p class="editor-hint">Copy and paste just the recipe. Try to leave out things like navigation links and comments. The importer will do its best to clean things up, but works best with clean input.</p>
```

The full `editor-body` div should now read:

```erb
  <div class="editor-body">
    <textarea class="editor-textarea"
              data-ai-import-target="textarea"
              placeholder="Paste a recipe from any source&#x2026;"
              rows="16" autofocus></textarea>
    <p class="editor-hint">Copy and paste just the recipe. Try to leave out things like navigation links and comments. The importer will do its best to clean things up, but works best with clean input.</p>
  </div>
```

- [ ] **Step 2: Add the `.editor-hint` style if needed**

Check `app/assets/stylesheets/editor.css` for an existing `.editor-hint` class. If it doesn't exist, add:

```css
.editor-hint {
  margin: var(--space-xs) 0 0;
  font-size: var(--font-sm);
  color: var(--color-text-muted);
}
```

Use existing tokens from `base.css` — check `:root` for the actual variable names and adjust if `--font-sm` or `--color-text-muted` don't exist (use whatever the project's equivalents are).

- [ ] **Step 3: Commit**

```bash
git add app/views/homepage/show.html.erb app/assets/stylesheets/editor.css
git commit -m "Add UI hint to AI import dialog: paste just the recipe"
```

---

### Task 9: Baseline Verification Run

**Files:** None (verification only)

- [ ] **Step 1: Run the full evaluation**

```bash
ruby test/ai_import/runner_v3.rb --corpus=corpus_v3 baseline
```

- [ ] **Step 2: Review results**

Read `test/ai_import/results/iteration_baseline/summary.md`. Verify:
- All 20 recipes pass the parse gate (Layer 1)
- All 20 pass system compat (round-trip + scaling)
- Format scores are 80%+
- No catastrophic fidelity failures (< 50)
- Step structure scores reflect appropriate split decisions

If any recipe fails to parse, inspect the output and either:
- Fix the corpus input (if it's a bad selection)
- Note it as a known issue for the Ralph Loop to address

- [ ] **Step 3: Record baseline and commit state**

```bash
git add test/ai_import/results/
git commit -m "Record baseline evaluation: corpus v3 with updated faithful prompt"
```

The Ralph Loop starts from this baseline. Invoke with:

```
/ralph-loop "test/ai_import/loop_prompt.md" --max-iterations 10 --completion-promise "FAITHFUL TUNED"
```
