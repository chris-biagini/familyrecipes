# AI Import Haiku Pure-Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Sonnet editorial-rewrite AI import with a Haiku pure-transcription import, tuned via a ralph loop with algorithmic + Sonnet-judge scoring.

**Architecture:** A standalone runner script orchestrates test corpus evaluation (Haiku generation + algorithmic scoring + Sonnet fidelity judging). The ralph loop agent iterates on the prompt template. Once converged, the tuned prompt replaces the current one and the service switches to Haiku.

**Tech Stack:** Ruby, Anthropic Ruby SDK, FamilyRecipes parser pipeline (plain Ruby), Minitest (service tests only)

---

## File Map

### New Files

| File | Responsibility |
|------|---------------|
| `test/ai_import/corpus/01_blog_simple/input.txt` | Blog preamble + simple recipe |
| `test/ai_import/corpus/01_blog_simple/expected.md` | Gold-standard output |
| `test/ai_import/corpus/02_blog_medium/input.txt` | Blog + multi-step recipe with CTAs |
| `test/ai_import/corpus/02_blog_medium/expected.md` | Gold-standard output |
| `test/ai_import/corpus/03_blog_complex/input.txt` | Blog + multi-component recipe |
| `test/ai_import/corpus/03_blog_complex/expected.md` | Gold-standard output |
| `test/ai_import/corpus/04_card_simple/input.txt` | Recipe card widget, simple |
| `test/ai_import/corpus/04_card_simple/expected.md` | Gold-standard output |
| `test/ai_import/corpus/05_card_medium/input.txt` | Recipe card widget, multi-step |
| `test/ai_import/corpus/05_card_medium/expected.md` | Gold-standard output |
| `test/ai_import/corpus/06_card_complex/input.txt` | Recipe card, metric+imperial |
| `test/ai_import/corpus/06_card_complex/expected.md` | Gold-standard output |
| `test/ai_import/corpus/07_ocr_simple/input.txt` | Clean OCR scan |
| `test/ai_import/corpus/07_ocr_simple/expected.md` | Gold-standard output |
| `test/ai_import/corpus/08_ocr_medium/input.txt` | Noisy OCR scan |
| `test/ai_import/corpus/08_ocr_medium/expected.md` | Gold-standard output |
| `test/ai_import/corpus/09_clean_simple/input.txt` | Clean handwritten recipe |
| `test/ai_import/corpus/09_clean_simple/expected.md` | Gold-standard output |
| `test/ai_import/corpus/10_clean_medium/input.txt` | Informal handwritten multi-step |
| `test/ai_import/corpus/10_clean_medium/expected.md` | Gold-standard output |
| `test/ai_import/prompt_template.md` | Haiku system prompt (iterable) |
| `test/ai_import/runner.rb` | Orchestrator: Haiku calls + scoring pipeline |
| `test/ai_import/scorers/parse_checker.rb` | Layer 1: parser pass/fail |
| `test/ai_import/scorers/format_checker.rb` | Layer 2: formatting rule checks |
| `test/ai_import/scorers/fidelity_judge_prompt.md` | Layer 3: Sonnet judge system prompt |
| `test/ai_import/README.md` | Usage docs for runner + ralph loop |

### Modified Files

| File | Change |
|------|--------|
| `lib/familyrecipes/ai_import_prompt.md` | Replaced with tuned prompt after ralph loop |
| `app/services/ai_import_service.rb` | Single-turn, Haiku, dynamic categories/tags |
| `app/models/kitchen.rb` | `AI_MODEL` → `claude-haiku-4-5` |
| `test/services/ai_import_service_test.rb` | Updated for new interface |

---

### Task 1: Create the Haiku prompt template

The initial prompt template that the ralph loop will iterate on. Derived from
the current `ai_import_prompt.md` with voice directives stripped and new
sections added.

**Files:**
- Create: `test/ai_import/prompt_template.md`

- [ ] **Step 1: Write the prompt template**

Create `test/ai_import/prompt_template.md` with three sections:

**Section 1 — Job description (~20 lines):**

```markdown
# Recipe Transcription

You transcribe recipes into a specific Markdown format. The user will give you
text — copied from a website, a cookbook scan, or typed by hand. Your job:

1. **Find the recipe.** Identify the title, ingredients, instructions, and
   metadata. Ignore everything else.
2. **Format it.** Map what you found into the structure described below.
3. **Preserve fidelity.** Use the original's wording. Do not rephrase
   instructions, add ingredients, drop items, or invent quantities.

The ONLY transformations you may make:
- Restructure ingredient lines into the required syntax
- Group ingredients under their step
- Normalize formatting (ASCII fractions, unit abbreviations, prep note
  capitalization)
- Pick a category and tags from the provided lists

**Strip non-recipe content:** blog preamble, life stories, navigation text,
"Print" / "Pin" / "Save" / "Jump to Recipe" buttons, star ratings, comment
sections, SEO paragraphs, newsletter signups, affiliate links, nutrition
panels, "Did you make this?" prompts, video embed placeholders.

**Do NOT rewrite.** Do not paraphrase, condense, expand, or editorialize
the recipe's instructions. If the source says "Cook the chicken over medium
heat until the internal temperature reaches 165°F", write exactly that. Do
not shorten it to "Cook chicken to 165°F."

Output ONLY the Markdown recipe. No commentary, no explanation, no code
fences.
```

**Section 2 — Format specification (~80 lines):**

Carry over from the current `ai_import_prompt.md` these sections verbatim:
- "Recipe Structure" overview block (the indented skeleton)
- "Title" (keep the "no superlatives" rule — that's detritus removal, not voice)
- "Front Matter" — but replace the hard-coded category list with: `{{CATEGORIES}}`
- "Steps" — keep the splitting guidance ("follow natural phase changes"), ingredient ownership, implicit steps. Strip the "light editorial touch" phrasing and replace with "preserve the source's structure". Strip substitution reorganization rules (just keep alternatives/substitutions in whatever section they appear in the source).
- "Ingredient Lines" — keep the full syntax spec, name rules, quantity/unit rules, fractions, prep notes. Keep "preserve the source's units" section verbatim.
- "Instructions" — replace entirely with:

```markdown
### Instructions

After the ingredients, write the source's instructions as prose paragraphs.
Preserve the original wording. Normalize temperatures to "350°F" or "175°C"
format. Use hyphens for numeric ranges: "3-5 minutes", never en-dashes.

If the source uses numbered steps, convert to prose paragraphs. If the source
addresses the reader as "you", keep it — do not rewrite to remove it.
```

- "Footer" — keep structure rules. Replace "Based on a recipe from" mandate with: "If the source names an author or publication, credit them in the footer."
- "Common Mistakes" — keep only format-level items. Remove voice items ("approximately" → "about", "your/you", "adjust seasoning").

Add after front matter section:

```markdown
**Tags** — Choose from: {{TAGS}}

Apply tags only when they are an obvious match for the recipe. Do not stretch.
Omit the Tags line entirely if nothing fits well.
```

**Section 3 — Examples (~50 lines):**

Keep the Detroit Pizza example verbatim from the current prompt. Keep the
Toast implicit-step example. Add the ingredient decomposition examples:

```markdown
## Ingredient Decomposition

Source ingredient lines are often messy. Decompose them into name + qualifier
+ quantity + prep note + footer. The ingredient name should be what you would
scan for in a grocery store, plus a parenthetical for which variant to buy.

    Source: "2 boneless chicken breasts, skin removed, cut into strips
            (can substitute thighs if desired)"
    →  - Chicken breasts (boneless, skinless), 2: Cut into strips.
       Footer: Can substitute thighs for chicken breasts.

    Source: "1 cup Greek yogurt (full-fat works best), strained"
    →  - Yogurt (Greek), 1 cup: Strained.
       Footer: Full-fat yogurt works best.

    Source: "3 large ripe tomatoes, roughly chopped"
    →  - Tomatoes, 3: Roughly chopped.

    Source: "Salt and pepper to taste"
    →  - Salt
       - Black pepper

    Source: "1/2 stick (4 tbsp) unsalted butter, melted and cooled"
    →  - Butter (unsalted), 4 tbsp: Melted and cooled.

    Source: "2 lbs bone-in, skin-on chicken thighs (about 6)"
    →  - Chicken thighs (bone-in, skin-on), 2 lbs
```

Add OCR recovery hints at the end:

```markdown
## OCR and Scan Recovery

If the input appears to be from a scan or OCR, fix obvious artifacts:
- `l/2` or `I/2` → `1/2` (letter ell/eye misread as digit one)
- Run-together words: `saltand` → `salt and`
- Missing line breaks between ingredients (infer from context)
- Garbled punctuation: `35OoF` → `350°F`
```

- [ ] **Step 2: Verify the template has `{{CATEGORIES}}` and `{{TAGS}}` placeholders**

Grep the file for both placeholders:

```
grep '{{CATEGORIES}}' test/ai_import/prompt_template.md
grep '{{TAGS}}' test/ai_import/prompt_template.md
```

Expected: one match each.

- [ ] **Step 3: Commit**

```bash
git add test/ai_import/prompt_template.md
git commit -m "Add initial Haiku prompt template for AI import ralph loop"
```

---

### Task 2: Create test corpus — blog inputs (recipes 1-3)

Write three realistic food blog inputs with their gold-standard outputs.
Each input should feel like a real copy-paste from a food blog — include
preamble text, personal stories, SEO filler, navigation elements, and
ad copy mixed in.

**Files:**
- Create: `test/ai_import/corpus/01_blog_simple/input.txt`
- Create: `test/ai_import/corpus/01_blog_simple/expected.md`
- Create: `test/ai_import/corpus/02_blog_medium/input.txt`
- Create: `test/ai_import/corpus/02_blog_medium/expected.md`
- Create: `test/ai_import/corpus/03_blog_complex/input.txt`
- Create: `test/ai_import/corpus/03_blog_complex/expected.md`

- [ ] **Step 1: Write `01_blog_simple` — garlic bread buried in blog post**

`input.txt` — a ~600-word food blog post about garlic bread. Include:
- Blog header with navigation: "HOME | RECIPES | ABOUT | CONTACT"
- A 400-word personal story preamble about making garlic bread as a kid
- The actual recipe: 4 ingredients (French bread, butter, garlic, parsley),
  simple instructions (no steps needed — implicit step format)
- SEO closing paragraph ("If you loved this garlic bread recipe...")
- "Pin It | Share | Print" footer

`expected.md`:
```markdown
# Garlic Bread

Serves: 4
Category: Sides

- French bread, 1 loaf: Split lengthwise.
- Butter (unsalted), 4 tbsp: Softened.
- Garlic, 3 cloves: Minced.
- Parsley: Chopped.

Preheat oven to 375°F. Mix butter, garlic, and parsley. Spread evenly
over both halves of the bread. Place on a baking sheet and bake for
10-12 minutes until edges are golden and crispy.
```

(Adjust the expected output to match whatever instructions you write in
the input — the expected must be a faithful transcription of the input's
recipe, not an idealized version.)

- [ ] **Step 2: Write `02_blog_medium` — chicken stir-fry with CTAs**

`input.txt` — a food blog post with:
- "Jump to Recipe | Print Recipe" at the top
- Newsletter signup CTA: "Subscribe for weekly meal ideas!"
- A multi-step recipe: marinate chicken (3-4 ingredients), cook stir-fry
  (6-7 ingredients), make sauce (4 ingredients)
- Affiliate links in ingredient names: "soy sauce (I love this brand!)"
- "Did You Make This Recipe? Tag me @foodblogger on Instagram!"
- Comments section bleed: "Karen says: I added extra ginger, so good!"

`expected.md` — the recipe faithfully transcribed into our format:
- 3 steps matching the source's natural phases
- Category: Mains
- Tags: weeknight, stir-fried (only if obviously applicable)
- Affiliate language stripped from ingredient names
- Comments and CTAs completely removed

- [ ] **Step 3: Write `03_blog_complex` — cinnamon rolls with components**

`input.txt` — a food blog post with:
- Long preamble about holiday baking traditions
- Recipe with 3 distinct components: dough (~8 ingredients), filling
  (~4 ingredients), cream cheese glaze (~4 ingredients)
- Tips scattered between instruction paragraphs (not in a dedicated section)
- Print-friendly footer with nutrition info panel text
- "More Recipes You'll Love:" section with links

`expected.md`:
- 3-4 steps matching the components
- Category: Baking
- Tags: holiday (if the blog context makes it obvious)
- Makes: line if the source specifies yield
- Footer with any useful tips from the source
- Nutrition panel text stripped

- [ ] **Step 4: Verify all files parse correctly**

Run the gold-standard expected.md files through the parser to make sure
they're valid:

```ruby
ruby -e "
  require_relative 'lib/familyrecipes'
  %w[01_blog_simple 02_blog_medium 03_blog_complex].each do |dir|
    text = File.read(\"test/ai_import/corpus/#{dir}/expected.md\")
    tokens = LineClassifier.classify(text)
    recipe = RecipeBuilder.new(tokens).build
    puts \"#{dir}: #{recipe[:title]} — #{recipe[:steps].size} steps, #{recipe[:steps].sum { |s| s[:ingredients].size }} ingredients\"
  end
"
```

Expected: all three parse without errors, producing the right number of
steps and ingredients.

- [ ] **Step 5: Commit**

```bash
git add test/ai_import/corpus/01_blog_simple/ test/ai_import/corpus/02_blog_medium/ test/ai_import/corpus/03_blog_complex/
git commit -m "Add blog test corpus for AI import ralph loop (recipes 1-3)"
```

---

### Task 3: Create test corpus — recipe card inputs (recipes 4-6)

Recipe card widget copy-pastes. These are more structured than blog posts
but include UI element text that gets copied along with the recipe.

**Files:**
- Create: `test/ai_import/corpus/04_card_simple/input.txt`
- Create: `test/ai_import/corpus/04_card_simple/expected.md`
- Create: `test/ai_import/corpus/05_card_medium/input.txt`
- Create: `test/ai_import/corpus/05_card_medium/expected.md`
- Create: `test/ai_import/corpus/06_card_complex/input.txt`
- Create: `test/ai_import/corpus/06_card_complex/expected.md`

- [ ] **Step 1: Write `04_card_simple` — tomato soup recipe card**

`input.txt` — a recipe card widget copy-paste with:
- "★★★★★ 4.8 from 127 reviews" at the top
- "Print | Pin | Rate" buttons
- Servings adjuster text: "Servings: 4  1x 2x 3x"
- A simple recipe: tomato soup, ~6 ingredients, single prep method
- Nutrition panel: "Calories: 180 | Fat: 8g | Carbs: 22g | Protein: 4g"
- "Did you make this recipe?" prompt

`expected.md`:
- Implicit step (simple recipe)
- Category: Mains or Sides
- All widget UI text stripped, recipe content preserved

- [ ] **Step 2: Write `05_card_medium` — beef stew recipe card**

`input.txt` — a recipe card with:
- Star ratings and review count
- Equipment list section: "You'll need: Dutch oven, cutting board, knife"
- Multi-step recipe: prep vegetables, brown meat, simmer stew
- "Did you make this? Leave a comment below!"
- Comment bleed: "Sandra: Made this last weekend, family loved it"

`expected.md`:
- 2-3 steps matching source phases
- Category: Mains
- Equipment list either dropped or noted in footer
- Comments stripped

- [ ] **Step 3: Write `06_card_complex` — bread recipe with dual units**

`input.txt` — a recipe card with:
- Both metric and imperial for every ingredient: "Flour, 500g (4 cups)"
- Video embed placeholder: "[Watch the Video] [00:00 / 12:34]"
- "Recipe Notes" section with substitutions and tips
- Servings scaling widget text
- Multi-step: mix, knead, proof, shape, bake

`expected.md`:
- Use metric (per the prompt rule: when both given, use metric)
- Imperial measurements noted in footer
- Video placeholder stripped
- Recipe Notes content preserved in footer
- Category: Bread

- [ ] **Step 4: Verify all files parse correctly**

```ruby
ruby -e "
  require_relative 'lib/familyrecipes'
  %w[04_card_simple 05_card_medium 06_card_complex].each do |dir|
    text = File.read(\"test/ai_import/corpus/#{dir}/expected.md\")
    tokens = LineClassifier.classify(text)
    recipe = RecipeBuilder.new(tokens).build
    puts \"#{dir}: #{recipe[:title]} — #{recipe[:steps].size} steps, #{recipe[:steps].sum { |s| s[:ingredients].size }} ingredients\"
  end
"
```

- [ ] **Step 5: Commit**

```bash
git add test/ai_import/corpus/04_card_simple/ test/ai_import/corpus/05_card_medium/ test/ai_import/corpus/06_card_complex/
git commit -m "Add recipe card test corpus for AI import ralph loop (recipes 4-6)"
```

---

### Task 4: Create test corpus — OCR and clean inputs (recipes 7-10)

**Files:**
- Create: `test/ai_import/corpus/07_ocr_simple/input.txt`
- Create: `test/ai_import/corpus/07_ocr_simple/expected.md`
- Create: `test/ai_import/corpus/08_ocr_medium/input.txt`
- Create: `test/ai_import/corpus/08_ocr_medium/expected.md`
- Create: `test/ai_import/corpus/09_clean_simple/input.txt`
- Create: `test/ai_import/corpus/09_clean_simple/expected.md`
- Create: `test/ai_import/corpus/10_clean_medium/input.txt`
- Create: `test/ai_import/corpus/10_clean_medium/expected.md`

- [ ] **Step 1: Write `07_ocr_simple` — clean cookbook scan**

`input.txt` — a cookbook page scan with minor OCR artifacts:
- Mostly clean text but some missing line breaks between ingredients
- A run-together word or two: "saltand" → should be "salt and"
- A simple recipe like drop biscuits (~6 ingredients, 1 step)
- Book-style formatting (no blog/web cruft)

`expected.md`:
- OCR artifacts fixed
- Category: Bread or Baking
- Implicit or single explicit step

- [ ] **Step 2: Write `08_ocr_medium` — noisy cookbook scan**

`input.txt` — a noisier OCR scan:
- Garbled fractions: `l/2 cup` (letter ell), `3⁄4 tsp` (Unicode fraction slash)
- Lost section headers (just a blank line where "For the sauce:" was)
- Punctuation errors: `35O°F` (letter O instead of zero), missing periods
- A medium-complexity recipe: pasta with sauce (~10 ingredients, 2 natural phases)
- Page number at bottom: "— 47 —"

`expected.md`:
- All OCR artifacts corrected
- Fractions as ASCII: `1/2 cup`, `3/4 tsp`
- Temperature fixed: `350°F`
- Page number stripped
- Category: Mains
- 2 steps matching the natural phases

- [ ] **Step 3: Write `09_clean_simple` — well-structured handwritten recipe**

`input.txt` — a cleanly typed recipe someone might send via text/email:
- Title, ingredient list, short instructions
- Already close to our format but not quite (maybe uses "Ingredients:" and
  "Directions:" headers, numbered steps instead of prose, inconsistent
  capitalization)
- A simple recipe like vinaigrette (~5 ingredients)

`expected.md`:
- Reformatted into our syntax
- "Ingredients:"/"Directions:" headers removed
- Numbered steps converted to prose
- Category: Basics
- Implicit step

- [ ] **Step 4: Write `10_clean_medium` — informal handwritten multi-step**

`input.txt` — an informal typed recipe:
- Multi-step (marinade + grill + serve)
- Informal quantities: "a big handful of cheese", "generous pour of olive
  oil", "about 2 lbs of steak, give or take"
- Informal instructions: "cook til done", "you'll know it's ready when..."
- A recipe like grilled steak tacos

`expected.md`:
- Informal quantities preserved as-is (the prompt says preserve fidelity)
- "a big handful" → keep it, don't invent "1 cup"
- "cook til done" → keep the author's words
- Category: Mains
- Tags: grilled (obvious match)
- 3 steps matching marinade/grill/serve

- [ ] **Step 5: Verify all files parse correctly**

```ruby
ruby -e "
  require_relative 'lib/familyrecipes'
  %w[07_ocr_simple 08_ocr_medium 09_clean_simple 10_clean_medium].each do |dir|
    text = File.read(\"test/ai_import/corpus/#{dir}/expected.md\")
    tokens = LineClassifier.classify(text)
    recipe = RecipeBuilder.new(tokens).build
    puts \"#{dir}: #{recipe[:title]} — #{recipe[:steps].size} steps, #{recipe[:steps].sum { |s| s[:ingredients].size }} ingredients\"
  end
"
```

- [ ] **Step 6: Commit**

```bash
git add test/ai_import/corpus/07_ocr_simple/ test/ai_import/corpus/08_ocr_medium/ test/ai_import/corpus/09_clean_simple/ test/ai_import/corpus/10_clean_medium/
git commit -m "Add OCR and clean test corpus for AI import ralph loop (recipes 7-10)"
```

---

### Task 5: Build Layer 1 scorer — parse checker

**Files:**
- Create: `test/ai_import/scorers/parse_checker.rb`

- [ ] **Step 1: Write the parse checker**

`test/ai_import/scorers/parse_checker.rb`:

```ruby
# frozen_string_literal: true

# Layer 1 scorer: feeds Haiku output through LineClassifier → RecipeBuilder
# and checks for basic structural validity. Returns pass/fail plus details.
#
# Usage:
#   result = ParseChecker.check(output_text, expected_ingredient_count: 6)
#   result.pass?        # => true/false
#   result.details      # => { title: "...", steps: 3, ingredients: 6, errors: [] }
module Scorers
  class ParseChecker
    Result = Data.define(:pass, :details)

    def self.check(output_text, expected_ingredient_count:)
      errors = []

      begin
        tokens = LineClassifier.classify(output_text)
        parsed = RecipeBuilder.new(tokens).build
      rescue FamilyRecipes::ParseError => e
        return Result.new(pass: false, details: {
          title: nil, steps: 0, ingredients: 0,
          errors: ["Parse error: #{e.message}"]
        })
      end

      title = parsed[:title]
      errors << 'Missing title' if title.nil? || title.strip.empty?

      steps = parsed[:steps] || []
      ingredient_count = steps.sum { |s| (s[:ingredients] || []).size }

      if ingredient_count < expected_ingredient_count
        errors << "Only #{ingredient_count} ingredients (expected >= #{expected_ingredient_count})"
      end

      Result.new(
        pass: errors.empty?,
        details: {
          title: title,
          steps: steps.size,
          ingredients: ingredient_count,
          errors: errors
        }
      )
    end
  end
end
```

- [ ] **Step 2: Smoke test with a sample recipe**

```bash
ruby -e "
  require_relative 'lib/familyrecipes'
  require_relative 'test/ai_import/scorers/parse_checker'

  text = File.read('test/ai_import/corpus/01_blog_simple/expected.md')
  result = Scorers::ParseChecker.check(text, expected_ingredient_count: 4)
  puts \"Pass: #{result.pass}\"
  puts \"Details: #{result.details.inspect}\"
"
```

Expected: `Pass: true` with correct title, step count, and ingredient count.

- [ ] **Step 3: Commit**

```bash
git add test/ai_import/scorers/parse_checker.rb
git commit -m "Add Layer 1 parse checker scorer for AI import evaluation"
```

---

### Task 6: Build Layer 2 scorer — format checker

**Files:**
- Create: `test/ai_import/scorers/format_checker.rb`

- [ ] **Step 1: Write the format checker**

`test/ai_import/scorers/format_checker.rb`:

```ruby
# frozen_string_literal: true

# Layer 2 scorer: algorithmic checks for formatting rule compliance.
# Each check is pass/fail. Returns percentage of checks passed plus
# per-check details.
#
# Usage:
#   result = FormatChecker.check(output_text, valid_categories: [...])
#   result.score        # => 0.89 (89% of checks passed)
#   result.checks       # => [{ name: "ascii_fractions", pass: true }, ...]
module Scorers
  class FormatChecker
    VULGAR_FRACTIONS = /[½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞]/
    EN_DASH = /–/
    CODE_FENCE = /^```/
    DETRITUS_PATTERNS = [
      /\bPrint\b/i, /\bPin It\b/i, /\bJump to Recipe\b/i,
      /\bDid you make this\b/i, /★|☆/, /\b\d+\s*reviews?\b/i,
      /\bSubscribe\b/i, /\bNewsletter\b/i, /\bTag me\b/i,
      /\bInstagram\b/i, /\bFollow\b/i, /\b\d+x\s*\d+x\b/,
      /Calories:\s*\d+/i, /\bNutrition\s*(Facts|Info)/i,
      /\bWatch the Video\b/i
    ].freeze

    Result = Data.define(:score, :checks)

    # RecipeBuilder#build returns:
    #   { title:, description:, front_matter: { category:, serves:, ... }, steps:, footer: }
    # Steps are hashes: { tldr: "Step name.", ingredients: [...], instructions: "..." }
    # Ingredients are hashes: { name:, quantity:, prep_note: }
    def self.check(output_text, valid_categories:)
      checks = []
      tokens = LineClassifier.classify(output_text)
      parsed = begin
        RecipeBuilder.new(tokens).build
      rescue FamilyRecipes::ParseError
        return Result.new(score: 0.0, checks: [{ name: 'parse', pass: false }])
      end

      checks << ascii_fractions(output_text)
      checks << prep_notes_formatted(parsed)
      checks << valid_front_matter(parsed, valid_categories)
      checks << no_detritus(output_text, parsed)
      checks << single_divider(tokens)
      checks << step_headers_format(parsed)
      checks << no_code_fences(output_text)
      checks << ingredient_names_concise(parsed)
      checks << no_en_dashes(output_text)

      passed = checks.count { |c| c[:pass] }
      Result.new(score: passed.to_f / checks.size, checks: checks)
    end

    def self.ascii_fractions(text)
      { name: 'ascii_fractions', pass: !text.match?(VULGAR_FRACTIONS) }
    end

    def self.prep_notes_formatted(parsed)
      preps = parsed[:steps].flat_map { |s| s[:ingredients] }
                            .filter_map { |i| i[:prep_note] }
      bad = preps.reject { |p| p.match?(/\A[A-Z]/) && p.end_with?('.') }
      { name: 'prep_notes_formatted', pass: bad.empty?, failures: bad }
    end

    def self.valid_front_matter(parsed, valid_categories)
      fm = parsed[:front_matter] || {}
      cat = fm[:category]
      serves = fm[:serves]
      errors = []
      errors << "Unknown category: #{cat}" if cat && !valid_categories.include?(cat)
      errors << "Serves is not a number: #{serves}" if serves && !serves.to_s.match?(/\A\d+\z/)
      { name: 'valid_front_matter', pass: errors.empty?, failures: errors }
    end

    def self.no_detritus(text, parsed)
      footer = parsed[:footer] || ''
      non_footer = text.sub(/^---\s*\n.*\z/m, '')
      hits = DETRITUS_PATTERNS.select { |p| non_footer.match?(p) }
      { name: 'no_detritus', pass: hits.empty?, failures: hits.map(&:source) }
    end

    def self.single_divider(tokens)
      count = tokens.count { |t| t[:type] == :divider }
      { name: 'single_divider', pass: count <= 1 }
    end

    def self.step_headers_format(parsed)
      headers = parsed[:steps].filter_map { |s| s[:tldr] }
      # Sentence case: starts uppercase, ends with period
      bad = headers.reject { |h| h.match?(/\A[A-Z]/) && h.strip.end_with?('.') }
      { name: 'step_headers_format', pass: bad.empty?, failures: bad }
    end

    def self.no_code_fences(text)
      { name: 'no_code_fences', pass: !text.match?(CODE_FENCE) }
    end

    def self.ingredient_names_concise(parsed)
      names = parsed[:steps].flat_map { |s| s[:ingredients] }.map { |i| i[:name] }
      long = names.select { |n| n && n.size > 40 }
      { name: 'ingredient_names_concise', pass: long.empty?, failures: long }
    end

    def self.no_en_dashes(text)
      { name: 'no_en_dashes', pass: !text.match?(EN_DASH) }
    end

    private_class_method :ascii_fractions, :prep_notes_formatted,
                         :valid_front_matter, :no_detritus, :single_divider,
                         :step_headers_format, :no_code_fences,
                         :ingredient_names_concise, :no_en_dashes
  end
end
```

- [ ] **Step 2: Smoke test with a gold-standard recipe**

```bash
ruby -e "
  require_relative 'lib/familyrecipes'
  require_relative 'test/ai_import/scorers/format_checker'

  text = File.read('test/ai_import/corpus/01_blog_simple/expected.md')
  categories = %w[Baking Bread Breakfast Dessert Drinks Holiday Mains Pizza Sides Snacks Miscellaneous]
  result = Scorers::FormatChecker.check(text, valid_categories: categories)
  puts \"Score: #{(result.score * 100).round}%\"
  result.checks.each { |c| puts \"  #{c[:name]}: #{c[:pass] ? 'PASS' : 'FAIL'}#{c[:failures] ? \" — #{c[:failures]}\" : ''}\" }
"
```

Expected: 100% on a gold-standard file (they should be perfectly formatted).

- [ ] **Step 3: Commit**

```bash
git add test/ai_import/scorers/format_checker.rb
git commit -m "Add Layer 2 format checker scorer for AI import evaluation"
```

---

### Task 7: Build Layer 3 — Sonnet fidelity judge prompt

**Files:**
- Create: `test/ai_import/scorers/fidelity_judge_prompt.md`

- [ ] **Step 1: Write the Sonnet judge prompt**

`test/ai_import/scorers/fidelity_judge_prompt.md`:

```markdown
You are a recipe transcription quality judge. You will receive three texts:

1. **ORIGINAL** — the raw input text (may include blog cruft, OCR artifacts, etc.)
2. **OUTPUT** — the transcription produced by an AI model
3. **REFERENCE** — a human-written gold-standard transcription of the same recipe

Your job is to evaluate the OUTPUT against the ORIGINAL, using the REFERENCE
as a guide for what a good transcription looks like.

Evaluate two dimensions:

## Fidelity (0-100)

How faithfully does the OUTPUT preserve the recipe content from the ORIGINAL?

- 100: Every ingredient, quantity, and instruction from the original recipe
  is present and accurate. No hallucinated additions.
- 80-99: Minor omissions or small quantity discrepancies.
- 50-79: Noticeable missing ingredients or substantially reworded instructions.
- 20-49: Major content missing or significantly altered.
- 0-19: Unrecognizable as the same recipe.

Check specifically:
- Are all ingredients from the original present?
- Are quantities accurate (not changed, rounded, or converted)?
- Are instructions preserved (not paraphrased, condensed, or expanded)?
- Were any ingredients or instructions hallucinated (added without basis)?

## Detritus Removal (0-100)

How well does the OUTPUT strip non-recipe content?

- 100: All blog preamble, navigation, ads, comments, ratings, CTAs, and
  other non-recipe content removed. Only the recipe remains.
- 80-99: Trace amounts of non-recipe content remain.
- 50-79: Some detritus leaked through (a CTA line, a comment, etc.).
- 20-49: Significant non-recipe content present.
- 0-19: Most of the blog/page content was retained.

## Ingredient Name Quality

Check whether preparation instructions or substitution notes leaked into
ingredient names instead of being placed in prep notes or the footer.

Respond with ONLY this JSON — no other text:

```json
{
  "ingredients_missing": ["ingredient from original not in output"],
  "ingredients_added": ["ingredient in output not in original"],
  "quantities_changed": ["description of change"],
  "instructions_dropped": ["significant instruction content lost"],
  "instructions_rewritten": ["cases where wording substantially changed"],
  "detritus_retained": ["any non-recipe content that leaked through"],
  "prep_in_name": ["ingredient names containing prep/substitution info"],
  "fidelity_score": 85,
  "detritus_score": 90
}
```

Be precise. Empty arrays mean no issues found. Scores must be integers 0-100.
```

- [ ] **Step 2: Commit**

```bash
git add test/ai_import/scorers/fidelity_judge_prompt.md
git commit -m "Add Layer 3 Sonnet fidelity judge prompt for AI import evaluation"
```

---

### Task 8: Build the runner script

**Files:**
- Create: `test/ai_import/runner.rb`

- [ ] **Step 1: Write the runner script**

`test/ai_import/runner.rb` — a standalone Ruby script that orchestrates
a full evaluation run. Key design:

- Requires the `anthropic` gem and the parser classes directly (no Rails boot)
- Provides an `Object#presence` polyfill for the parser's ActiveSupport dependency
- Reads `ANTHROPIC_API_KEY` from environment
- Accepts an optional iteration label as argv[0] (defaults to auto-incrementing)
- Loads `prompt_template.md` and interpolates `{{CATEGORIES}}` and `{{TAGS}}`
  with a fixed test set
- For each corpus recipe:
  1. Sends input.txt to Haiku with the interpolated prompt
  2. Stores output to `results/iteration_NNN/outputs/`
  3. Runs ParseChecker (Layer 1)
  4. Runs FormatChecker (Layer 2)
  5. Sends original + output + expected to Sonnet for fidelity judging (Layer 3)
- Writes `results/iteration_NNN/scores.json` with per-recipe scorecards
- Writes `results/iteration_NNN/summary.md` with a human-readable table

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# AI Import prompt evaluation runner. Standalone script — no Rails boot.
#
# Usage:
#   ANTHROPIC_API_KEY=sk-... ruby test/ai_import/runner.rb [iteration_label]
#
# Runs each test corpus recipe through:
#   1. Haiku generation (using current prompt_template.md)
#   2. Layer 1: parse check (structural validity)
#   3. Layer 2: format check (formatting rules)
#   4. Layer 3: Sonnet fidelity judge (content preservation)
#
# Results saved to test/ai_import/results/iteration_NNN/

require 'json'
require 'fileutils'

# ActiveSupport polyfill — parser uses .presence in a few spots
class Object
  def presence
    self if respond_to?(:empty?) ? !empty? : !nil?
  end
end

# Load parser pipeline
require_relative '../../lib/familyrecipes'
require_relative 'scorers/parse_checker'
require_relative 'scorers/format_checker'

# Anthropic SDK
require 'anthropic'

BASE_DIR = File.expand_path('..', __FILE__)
CORPUS_DIR = File.join(BASE_DIR, 'corpus')
RESULTS_DIR = File.join(BASE_DIR, 'results')

HAIKU_MODEL = 'claude-haiku-4-5-20251001'
SONNET_MODEL = 'claude-sonnet-4-6-20250514'

CATEGORIES = %w[Baking Bread Breakfast Dessert Drinks Holiday Mains Pizza Sides Snacks Miscellaneous].freeze
TAGS = %w[vegetarian vegan gluten-free weeknight easy quick one-pot make-ahead
          freezer-friendly grilled roasted baked comfort-food holiday american
          italian mexican french japanese chinese indian thai].freeze

def load_prompt_template
  template = File.read(File.join(BASE_DIR, 'prompt_template.md'))
  template.gsub('{{CATEGORIES}}', CATEGORIES.join(', '))
          .gsub('{{TAGS}}', TAGS.join(', '))
end

def corpus_dirs
  Dir.glob(File.join(CORPUS_DIR, '*')).select { |f| File.directory?(f) }.sort
end

def call_haiku(client, system_prompt, input_text)
  response = client.messages.create(
    model: HAIKU_MODEL,
    max_tokens: 8192,
    system: system_prompt,
    messages: [{ role: 'user', content: input_text }]
  )
  text = response.content.find { |block| block.type == :text }&.text || ''
  # Strip code fences and leading preamble (same as AiImportService)
  text = text.gsub(/\A```\w*\n/, '').delete_suffix("\n```")
  heading_index = text.index(/^# /)
  heading_index ? text[heading_index..] : text
end

def call_sonnet_judge(client, judge_prompt, original, output, expected)
  user_content = <<~MSG
    ## ORIGINAL

    #{original}

    ## OUTPUT

    #{output}

    ## REFERENCE

    #{expected}
  MSG

  response = client.messages.create(
    model: SONNET_MODEL,
    max_tokens: 4096,
    system: judge_prompt,
    messages: [{ role: 'user', content: user_content }]
  )
  text = response.content.find { |block| block.type == :text }&.text || '{}'
  # Strip code fences if Sonnet wraps the JSON
  text = text.gsub(/\A```\w*\n/, '').delete_suffix("\n```").strip
  JSON.parse(text)
rescue JSON::ParserError => e
  { 'error' => "JSON parse failed: #{e.message}", 'fidelity_score' => 0, 'detritus_score' => 0 }
end

def expected_ingredient_count(expected_text)
  tokens = LineClassifier.classify(expected_text)
  parsed = RecipeBuilder.new(tokens).build
  parsed[:steps].sum { |s| (s[:ingredients] || []).size }
rescue FamilyRecipes::ParseError
  0
end

def compute_aggregate(parse_result, format_result, fidelity_result)
  return 0.0 unless parse_result.pass

  fidelity = (fidelity_result['fidelity_score'] || 0).to_f
  detritus = (fidelity_result['detritus_score'] || 0).to_f
  format_score = format_result.score * 100.0

  0.3 * format_score + 0.4 * fidelity + 0.3 * detritus
end

def run_evaluation
  api_key = ENV.fetch('ANTHROPIC_API_KEY') { abort 'Set ANTHROPIC_API_KEY environment variable' }
  client = Anthropic::Client.new(api_key: api_key, timeout: 90)

  system_prompt = load_prompt_template
  judge_prompt = File.read(File.join(BASE_DIR, 'scorers', 'fidelity_judge_prompt.md'))

  # Determine iteration directory
  label = ARGV[0]
  unless label
    existing = Dir.glob(File.join(RESULTS_DIR, 'iteration_*'))
                  .map { |d| File.basename(d).delete_prefix('iteration_').to_i }
    label = format('%03d', (existing.max || 0) + 1)
  end
  iter_dir = File.join(RESULTS_DIR, "iteration_#{label}")
  output_dir = File.join(iter_dir, 'outputs')
  FileUtils.mkdir_p(output_dir)

  scores = {}
  dirs = corpus_dirs

  dirs.each_with_index do |dir, idx|
    name = File.basename(dir)
    input_text = File.read(File.join(dir, 'input.txt'))
    expected_text = File.read(File.join(dir, 'expected.md'))

    puts "[#{idx + 1}/#{dirs.size}] #{name}: calling Haiku..."
    output_text = call_haiku(client, system_prompt, input_text)
    File.write(File.join(output_dir, "#{name}.md"), output_text)

    puts "  Layer 1: parse check..."
    exp_count = expected_ingredient_count(expected_text)
    parse_result = Scorers::ParseChecker.check(output_text, expected_ingredient_count: exp_count)

    puts "  Layer 2: format check..."
    format_result = Scorers::FormatChecker.check(output_text, valid_categories: CATEGORIES)

    puts "  Layer 3: Sonnet fidelity judge..."
    fidelity_result = call_sonnet_judge(client, judge_prompt, input_text, output_text, expected_text)

    aggregate = compute_aggregate(parse_result, format_result, fidelity_result)

    scores[name] = {
      parse: { pass: parse_result.pass, details: parse_result.details },
      format: { score: (format_result.score * 100).round(1), checks: format_result.checks },
      fidelity: fidelity_result,
      aggregate: aggregate.round(1)
    }

    puts "  Aggregate: #{aggregate.round(1)}"
  end

  # Write scores.json
  File.write(File.join(iter_dir, 'scores.json'), JSON.pretty_generate(scores))

  # Write summary.md
  write_summary(iter_dir, scores)

  puts "\nResults saved to #{iter_dir}/"
  puts "Overall: #{(scores.values.sum { |s| s[:aggregate] } / scores.size).round(1)} avg, #{scores.values.map { |s| s[:aggregate] }.min.round(1)} worst"
end

def write_summary(iter_dir, scores)
  lines = ["# Iteration #{File.basename(iter_dir)}\n"]
  lines << "| Recipe | Parse | Format | Fidelity | Detritus | Aggregate |"
  lines << "|--------|-------|--------|----------|----------|-----------|"

  scores.each do |name, data|
    parse = data[:parse][:pass] ? 'PASS' : 'FAIL'
    format_s = "#{data[:format][:score]}%"
    fidelity = data[:fidelity]['fidelity_score'] || 0
    detritus = data[:fidelity]['detritus_score'] || 0
    agg = data[:aggregate]
    lines << "| #{name} | #{parse} | #{format_s} | #{fidelity} | #{detritus} | #{agg} |"
  end

  avg = (scores.values.sum { |s| s[:aggregate] } / scores.size).round(1)
  worst = scores.values.map { |s| s[:aggregate] }.min.round(1)
  lines << ""
  lines << "**Overall:** #{avg} avg, #{worst} worst"
  lines << ""

  # List failures for ralph loop agent
  scores.each do |name, data|
    failures = []
    failures << "PARSE FAILED: #{data[:parse][:details][:errors].join(', ')}" unless data[:parse][:pass]
    data[:format][:checks].each do |check|
      next if check[:pass]
      detail = check[:failures] ? " — #{check[:failures].join(', ')}" : ''
      failures << "FORMAT: #{check[:name]}#{detail}"
    end
    %w[ingredients_missing ingredients_added quantities_changed instructions_dropped
       instructions_rewritten detritus_retained prep_in_name].each do |key|
      items = data[:fidelity][key]
      next if items.nil? || items.empty?
      failures << "FIDELITY: #{key}: #{items.join(', ')}"
    end

    next if failures.empty?

    lines << "### #{name} — issues"
    failures.each { |f| lines << "- #{f}" }
    lines << ""
  end

  File.write(File.join(iter_dir, 'summary.md'), lines.join("\n"))
end

run_evaluation
```

- [ ] **Step 2: Verify it loads without errors (dry run, no API call)**

```bash
ruby -e "
  require_relative 'test/ai_import/scorers/parse_checker'
  require_relative 'test/ai_import/scorers/format_checker'
  puts 'Scorers load OK'
" && echo "Load check passed"
```

- [ ] **Step 3: Commit**

```bash
git add test/ai_import/runner.rb
git commit -m "Add runner script for AI import prompt evaluation loop"
```

---

### Task 9: Add README for the evaluation tooling

**Files:**
- Create: `test/ai_import/README.md`

- [ ] **Step 1: Write the README**

`test/ai_import/README.md`:

```markdown
# AI Import Prompt Evaluation

Tooling for iterating on the Haiku system prompt used by `AiImportService`.

## Quick Start

```bash
ANTHROPIC_API_KEY=sk-... ruby test/ai_import/runner.rb
```

This runs all 10 test corpus recipes through the current `prompt_template.md`
and writes results to `test/ai_import/results/iteration_NNN/`.

## Directory Layout

```
test/ai_import/
  corpus/           10 test recipes (input.txt + expected.md pairs)
  prompt_template.md  The Haiku system prompt being iterated on
  runner.rb         Evaluation orchestrator
  scorers/          Scoring modules (parse, format, fidelity judge)
  results/          Per-iteration outputs and scores
```

## Scoring Pipeline

1. **Layer 1 — Parse Check** (pass/fail): Feeds output through
   `LineClassifier` → `RecipeBuilder`. Checks for valid title, step
   structure, and minimum ingredient count.

2. **Layer 2 — Format Check** (percentage): Algorithmic checks for
   ASCII fractions, prep note formatting, valid categories, detritus
   patterns, step header format, ingredient name length, etc.

3. **Layer 3 — Fidelity Judge** (Sonnet): Compares original input
   vs. Haiku output vs. gold standard. Returns structured JSON with
   missing/added ingredients, changed quantities, and fidelity/detritus
   scores (0-100 each).

**Aggregate formula:**
`parse_pass ? (0.3 * format% + 0.4 * fidelity + 0.3 * detritus) : 0`

## Ralph Loop

The evaluation tooling is designed to be driven by a ralph loop agent:

1. Agent runs `runner.rb` → reads `summary.md`
2. Identifies failure patterns in lowest-scoring recipes
3. Edits `prompt_template.md` to address failures
4. Runs `runner.rb` again → compares scores
5. Repeats until convergence (overall > 85, worst > 70) or 8 iterations

## Corpus

Test recipes are static synthetic inputs spanning 4 types:
- Blog posts (recipes 1-3): varying blog noise levels
- Recipe card widgets (recipes 4-6): varying widget complexity
- OCR/cookbook scans (recipes 7-8): varying scan quality
- Clean handwritten (recipes 9-10): varying formality

Each recipe has a hand-written `expected.md` gold standard.
```

- [ ] **Step 2: Commit**

```bash
git add test/ai_import/README.md
git commit -m "Add README for AI import evaluation tooling"
```

---

### Task 10: Update AiImportService for Haiku + dynamic categories/tags

This task updates the production service. Do this AFTER the ralph loop
converges and produces a tuned prompt, but the structural changes can be
made now.

**Files:**
- Modify: `app/services/ai_import_service.rb`
- Modify: `app/models/kitchen.rb:34` (AI_MODEL constant)
- Modify: `test/services/ai_import_service_test.rb`

- [ ] **Step 1: Write the failing tests**

Replace the existing test file `test/services/ai_import_service_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class AiImportServiceTest < ActiveSupport::TestCase
  MockContent = Struct.new(:type, :text)
  MockResponse = Struct.new(:content)

  setup do
    setup_test_kitchen
    @kitchen.update!(anthropic_api_key: 'sk-test-key-123')
    Category.find_or_create_for(kitchen: @kitchen, name: 'Baking')
    Category.find_or_create_for(kitchen: @kitchen, name: 'Mains')
    Tag.find_or_create_by!(kitchen: @kitchen, name: 'easy')
    Tag.find_or_create_by!(kitchen: @kitchen, name: 'weeknight')
  end

  test 'returns markdown on successful API call' do
    result = with_anthropic_response("# Bagels\n\nStep one\n- 3 cups flour") do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_equal "# Bagels\n\nStep one\n- 3 cups flour", result.markdown
    assert_nil result.error
  end

  test 'returns error when no API key configured' do
    @kitchen.update!(anthropic_api_key: nil)

    result = AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)

    assert_nil result.markdown
    assert_equal 'no_api_key', result.error
  end

  test 'sends single user message without multi-turn' do
    captured_messages = nil
    mock_response = MockResponse.new([MockContent.new(:text, '# Simple')])

    mock_messages = Object.new
    mock_messages.define_singleton_method(:create) do |**kwargs|
      captured_messages = kwargs[:messages]
      mock_response
    end

    mock_client = Object.new
    mock_client.define_singleton_method(:messages) { mock_messages }

    Anthropic::Client.stub :new, mock_client do
      AiImportService.call(text: 'some recipe', kitchen: @kitchen)
    end

    assert_equal 1, captured_messages.size
    assert_equal 'user', captured_messages[0][:role]
  end

  test 'interpolates kitchen categories into prompt' do
    captured_system = nil
    mock_response = MockResponse.new([MockContent.new(:text, '# Test')])

    mock_messages = Object.new
    mock_messages.define_singleton_method(:create) do |**kwargs|
      captured_system = kwargs[:system]
      mock_response
    end

    mock_client = Object.new
    mock_client.define_singleton_method(:messages) { mock_messages }

    Anthropic::Client.stub :new, mock_client do
      AiImportService.call(text: 'recipe', kitchen: @kitchen)
    end

    assert_includes captured_system, 'Baking'
    assert_includes captured_system, 'Mains'
    assert_includes captured_system, 'Miscellaneous'
  end

  test 'interpolates kitchen tags into prompt' do
    captured_system = nil
    mock_response = MockResponse.new([MockContent.new(:text, '# Test')])

    mock_messages = Object.new
    mock_messages.define_singleton_method(:create) do |**kwargs|
      captured_system = kwargs[:system]
      mock_response
    end

    mock_client = Object.new
    mock_client.define_singleton_method(:messages) { mock_messages }

    Anthropic::Client.stub :new, mock_client do
      AiImportService.call(text: 'recipe', kitchen: @kitchen)
    end

    assert_includes captured_system, 'easy'
    assert_includes captured_system, 'weeknight'
  end

  test 'uses haiku model' do
    captured_model = nil
    mock_response = MockResponse.new([MockContent.new(:text, '# Test')])

    mock_messages = Object.new
    mock_messages.define_singleton_method(:create) do |**kwargs|
      captured_model = kwargs[:model]
      mock_response
    end

    mock_client = Object.new
    mock_client.define_singleton_method(:messages) { mock_messages }

    Anthropic::Client.stub :new, mock_client do
      AiImportService.call(text: 'recipe', kitchen: @kitchen)
    end

    assert_equal 'claude-haiku-4-5-20251001', captured_model
  end

  test 'strips code fences from response' do
    result = with_anthropic_response("```markdown\n# Bagels\n\n- 3 cups flour\n```") do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_equal "# Bagels\n\n- 3 cups flour", result.markdown
  end

  test 'strips leading text before first heading' do
    result = with_anthropic_response("Here is your recipe:\n\n# Bagels\n\n- 3 cups flour") do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_equal "# Bagels\n\n- 3 cups flour", result.markdown
  end

  test 'returns error on authentication failure' do
    result = with_anthropic_error(Anthropic::Errors::AuthenticationError) do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_nil result.markdown
    assert_equal 'Invalid Anthropic API key. Check your key in Settings.', result.error
  end

  test 'returns error on rate limit' do
    result = with_anthropic_error(Anthropic::Errors::RateLimitError) do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_nil result.markdown
    assert_equal 'Rate limited by Anthropic. Wait a moment and try again.', result.error
  end

  test 'returns error on connection failure' do
    result = with_anthropic_error(Anthropic::Errors::APIConnectionError) do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_nil result.markdown
    assert_equal 'Could not reach the Anthropic API. Check your connection.', result.error
  end

  test 'returns error on timeout' do
    result = with_anthropic_error(Anthropic::Errors::APITimeoutError) do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_nil result.markdown
    assert_equal 'Request timed out. Try again.', result.error
  end

  private

  def with_anthropic_response(text, &)
    mock_response = MockResponse.new([MockContent.new(:text, text)])

    mock_messages = Object.new
    mock_messages.define_singleton_method(:create) { |**_kwargs| mock_response }

    mock_client = Object.new
    mock_client.define_singleton_method(:messages) { mock_messages }

    Anthropic::Client.stub(:new, mock_client, &)
  end

  def build_error(error_class)
    if error_class <= Anthropic::Errors::APIStatusError
      error_class.new(url: 'https://api.anthropic.com', status: 400, headers: {},
                      body: nil, request: {}, response: {}, message: 'test error')
    else
      error_class.new(url: 'https://api.anthropic.com', message: 'test error')
    end
  end

  def with_anthropic_error(error_class, &)
    err = build_error(error_class)
    mock_messages = Object.new
    mock_messages.define_singleton_method(:create) { |**_kwargs| raise err }

    mock_client = Object.new
    mock_client.define_singleton_method(:messages) { mock_messages }

    Anthropic::Client.stub(:new, mock_client, &)
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
ruby -Itest test/services/ai_import_service_test.rb
```

Expected: the new tests (`sends single user message`, `interpolates kitchen categories`,
`interpolates kitchen tags`, `uses haiku model`) fail because the service still
has the old interface.

- [ ] **Step 3: Update Kitchen model**

In `app/models/kitchen.rb`, change line 34:

```ruby
# Before:
AI_MODEL = 'claude-sonnet-4-6'

# After:
AI_MODEL = 'claude-haiku-4-5-20251001'
```

- [ ] **Step 4: Update AiImportService**

Replace `app/services/ai_import_service.rb` with:

```ruby
# frozen_string_literal: true

# Sends user-pasted text to the Anthropic API for conversion into the app's
# Markdown recipe format. Pure function — no database writes or side effects.
# One-shot pipeline: text in, formatted recipe out.
#
# The system prompt is a template with {{CATEGORIES}} and {{TAGS}} placeholders
# interpolated from the kitchen's current taxonomy at call time.
#
# - Kitchen#anthropic_api_key: encrypted API key for Anthropic
# - Kitchen::AI_MODEL: model identifier (claude-haiku-4-5)
# - lib/familyrecipes/ai_import_prompt.md: prompt template with dynamic slots
class AiImportService
  Result = Data.define(:markdown, :error)

  PROMPT_TEMPLATE = Rails.root.join('lib/familyrecipes/ai_import_prompt.md').read.freeze
  MAX_TOKENS = 8192

  def self.call(text:, kitchen:)
    new(kitchen:).call(text:)
  end

  def initialize(kitchen:)
    @api_key = kitchen.anthropic_api_key
    @kitchen = kitchen
  end

  def call(text:)
    return Result.new(markdown: nil, error: 'no_api_key') if @api_key.blank?

    markdown = fetch_completion(text:)
    Result.new(markdown: clean_output(markdown), error: nil)
  rescue Anthropic::Errors::AuthenticationError
    Result.new(markdown: nil, error: 'Invalid Anthropic API key. Check your key in Settings.')
  rescue Anthropic::Errors::RateLimitError
    Result.new(markdown: nil, error: 'Rate limited by Anthropic. Wait a moment and try again.')
  rescue Anthropic::Errors::APITimeoutError
    Result.new(markdown: nil, error: 'Request timed out. Try again.')
  rescue Anthropic::Errors::APIConnectionError
    Result.new(markdown: nil, error: 'Could not reach the Anthropic API. Check your connection.')
  rescue Anthropic::Errors::APIError => error
    Result.new(markdown: nil, error: "AI import failed: #{error.message}")
  end

  private

  def fetch_completion(text:)
    response = client.messages.create(
      model: Kitchen::AI_MODEL,
      max_tokens: MAX_TOKENS,
      system: build_system_prompt,
      messages: [{ role: 'user', content: text }]
    )
    response.content.find { |block| block.type == :text }&.text || ''
  end

  def build_system_prompt
    categories = @kitchen.categories.pluck(:name).sort
    categories << 'Miscellaneous' unless categories.include?('Miscellaneous')
    tags = @kitchen.tags.pluck(:name).sort

    PROMPT_TEMPLATE
      .gsub('{{CATEGORIES}}', categories.join(', '))
      .gsub('{{TAGS}}', tags.empty? ? '(none yet)' : tags.join(', '))
  end

  def clean_output(text)
    text = strip_code_fences(text)
    strip_leading_preamble(text)
  end

  def strip_code_fences(text)
    text.gsub(/\A```\w*\n/, '').delete_suffix("\n```")
  end

  def strip_leading_preamble(text)
    heading_index = text.index(/^# /)
    heading_index ? text[heading_index..] : text
  end

  def client
    Anthropic::Client.new(api_key: @api_key, timeout: 30)
  end
end
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
ruby -Itest test/services/ai_import_service_test.rb
```

Expected: all tests pass.

- [ ] **Step 6: Run the controller tests to check nothing broke**

```bash
ruby -Itest test/controllers/ai_import_controller_test.rb
```

Expected: all tests pass. The controller calls `AiImportService.call(text:, kitchen:)`
which matches the new interface (the old `previous_result:` and `feedback:` kwargs
are simply no longer passed).

- [ ] **Step 7: Run full test suite**

```bash
rake test
```

Expected: all tests pass. No other code references the removed `previous_result`
or `feedback` parameters.

- [ ] **Step 8: Commit**

```bash
git add app/services/ai_import_service.rb app/models/kitchen.rb test/services/ai_import_service_test.rb
git commit -m "Switch AI import to Haiku with dynamic categories/tags

Drop multi-turn feedback. Prompt template uses {{CATEGORIES}} and {{TAGS}}
placeholders interpolated from the kitchen's taxonomy at call time.
Timeout reduced from 90s to 30s."
```

---

### Task 11: Copy tuned prompt to production location

This task runs AFTER the ralph loop converges. It copies the tuned prompt
template into the production location.

**Files:**
- Modify: `lib/familyrecipes/ai_import_prompt.md`

- [ ] **Step 1: Copy the tuned prompt**

```bash
cp test/ai_import/prompt_template.md lib/familyrecipes/ai_import_prompt.md
```

- [ ] **Step 2: Verify the prompt has the dynamic slots**

```bash
grep '{{CATEGORIES}}' lib/familyrecipes/ai_import_prompt.md
grep '{{TAGS}}' lib/familyrecipes/ai_import_prompt.md
```

Expected: one match each.

- [ ] **Step 3: Run full test suite**

```bash
rake test
```

- [ ] **Step 4: Commit**

```bash
git add lib/familyrecipes/ai_import_prompt.md
git commit -m "Replace AI import prompt with ralph-loop-tuned Haiku version"
```

---

### Task 12: Update html_safe allowlist if line numbers shifted

**Files:**
- Check: `config/html_safe_allowlist.yml`

- [ ] **Step 1: Run the html_safe audit**

```bash
rake lint:html_safe
```

If it reports mismatches (because editing `ai_import_service.rb` shifted
lines in other files — unlikely but check), update the allowlist.

- [ ] **Step 2: Run full lint**

```bash
rake lint
```

Expected: 0 offenses.

- [ ] **Step 3: Commit if changes needed**

```bash
# Only if allowlist needed updating:
git add config/html_safe_allowlist.yml
git commit -m "Update html_safe allowlist for shifted line numbers"
```
