# Style Rubric for AI Recipe Conversions

Score converted recipes from 1-10 based on how closely they match the
writing style of the family recipe collection. This rubric is designed
to evaluate output from the conversion prompt in `recipe-conversion.md`.

## The Voice in a Nutshell

These recipes read like notes from a confident home cook jotting things
down for a family member who already knows the basics. The tone is
casual, terse, and personal — closer to a kitchen Post-it than a food
blog. The writer trusts the reader.

---

## Style Guide

### Descriptions

Descriptions are punchy quips — a few words that convey personality, not
a summary of the recipe. They set a tone, not an expectation.

**Characteristic examples from the collection:**
- "Worth the effort."
- "Better than the box."
- "Mom's famous baked pasta."
- "Just a little sweet."
- "Hearty and rustic."
- "Protein!"
- "Remember pecan pie? It's back, in bar form!"
- "Super fast tacos with rice."
- "Fancy cheese puffs."

**What to avoid:**
- Summaries: "A delicious pasta dish with a creamy tomato sauce."
- Blogging voice: "This recipe is a family favorite that's perfect for
  busy weeknight dinners!"
- Long descriptions: anything over ~10 words is suspect.
- Superlatives without personality: "The best chocolate chip cookies."
  (Compare with "The best pan pizza." — this works because it's a bold
  factual claim, not a marketing superlative.)

### Step Names

Short imperative phrases in sentence case, ending with a period. They
name the *phase*, not narrate the action in detail.

**Good:**
- "Make the dough."
- "Cook."
- "Bulk ferment."
- "Assemble and bake."
- "Finish and serve."
- "Prep dry ingredients."
- "Brown butter and add to sugar mixture."
- "Shape, add seeds, and bake."
- "Preheat oven and pasta water; butter casserole dish."

**Bad:**
- "Step 1: Prepare the dry ingredients" — numbered, wrong case.
- "Making the Sauce" — gerund, title case, no period.
- "Carefully combine all the wet ingredients" — too detailed, adverb.
- "For the Filling" — not imperative, title case.

### Instruction Prose

Instructions are concise imperative prose — usually 1-3 sentences per
paragraph, sometimes a single paragraph per step. The voice assumes a
moderately experienced cook and omits anything obvious.

**Characteristic patterns:**

1. **Terse and direct.** "Combine all ingredients in saucepan. Warm over
   low heat, stirring occasionally, until cheese is mostly melted. Puree
   with immersion blender." Each sentence does one thing.

2. **Sensory cues over precise times.** "Cook gently until just barely
   golden" beats "cook for exactly 7 minutes." Times are given as
   ranges or approximations: "about 20 minutes", "10-12 minutes",
   "for a few minutes."

3. **Comfortable with vagueness.** "A splash of lemon juice", "a fair
   bit of olive oil", "a handful of apples", "a few grinds of pepper",
   "some salt", "as long as you have patience for." This isn't sloppy —
   it's trust.

4. **Drops articles and filler.** "Add to mixer bowl" not "Add to the
   mixer bowl." "Stir to combine" not "Stir the mixture until it is
   well combined." "Season to taste" not "Season with salt and pepper
   to taste."

5. **Chains actions with commas.** "Add garlic to oil and cook gently
   over low heat." "Preheat oven to 350°, convection roast."

6. **"Correct for" idiom.** Uses "Correct for acid and seasoning" and
   "Correct for seasoning" — never "adjust seasoning to taste" or
   "taste and adjust."

7. **No safety warnings.** Never "be careful with the hot oil" or "use
   caution when handling." Trusts the cook.

8. **No cheerleading.** Never "Enjoy!", "Serve and impress your guests!",
   "Your family will love this!"

9. **Occasional parenthetical asides and personality.** "_(Do not use a
   stand mixer, because this is a very tough dough and the mixer will
   break. Ask me how I know.)_" and "Of course, you can use actual ziti,
   but (1) rigatoni are better than ziti and (2) 'baked mezze rigatoni'
   sounds ridiculous."

10. **Equipment specifics given casually.** "#16 disher (often blue)",
    "#24 scoops", "stick blender", "half-sheet pan." Named like tools
    the writer actually owns.

### Footer Notes

Brief, practical. Often just one or two sentences. Common patterns:

- **Attribution:** "Based on a recipe from [Name](URL)." — always
  "Based on a recipe from", never "Adapted from" or "Inspired by."
- **Substitutions:** "Substitute walnuts or chocolate chips for the
  raisins if you like."
- **Personal commentary:** "This is not haute cuisine by any stretch,
  but it's fast and the kids eat it :)"
- **Equipment notes:** "If using Lodge biscuit pan, preheat in oven."
- **Variety suggestions:** "For variety, swap out the onion and carrot
  for finely sliced garlic."

### What's Never Present

These are the biggest tells of a non-matching conversion:

- **Blog preamble or storytelling** before or within the recipe.
- **Numbered instruction lists** (1. Do this. 2. Do that.).
- **"Tips and tricks" sections** or boxed callouts.
- **Nutritional information** in the recipe text.
- **Equipment lists** separate from ingredient lists.
- **"Don't forget to...", "Be sure to...", "Make sure..."** — never.
- **"Set aside"** — the collection uses "reserve" occasionally, or just
  moves on to the next action without saying anything.
- **Filler adverbs:** "slowly", "gently" (sparingly), "carefully",
  "thoroughly" (used sometimes, but sparingly).
- **"Approximately"** — the collection uses "about" instead.
- **Passive voice** — almost never. "Stir in flour" not "Flour should
  be stirred in."
- **"You will need"**, **"What you'll need"**, **"Ingredients:"** as a
  standalone header.
- **"Garnish with"** — this collection doesn't use this phrase.
- **"Let rest for X minutes before serving"** phrased as a warning —
  the collection says it matter-of-factly: "Let cool for 15 minutes
  before serving."

---

## Scoring Rubric (1-10)

Each dimension below is evaluated, and the final score is the average
rounded to the nearest integer. When a dimension is not applicable
(e.g., no footer in source or output), score it as the average of the
other dimensions.

### 1. Description (0-10)

| Score | Criteria |
|-------|----------|
| 9-10  | Punchy, personal quip under ~10 words. Could have been written by the collection's author. Has personality without trying too hard. |
| 7-8   | Short and reasonable but reads a bit generic or formal. Missing the personal edge. |
| 5-6   | Too long (10-20 words), or summarizes the recipe instead of characterizing it. Inoffensive but bland. |
| 3-4   | Blog-style: "A delicious and easy recipe..." or overly detailed summary. |
| 1-2   | Multi-sentence description, marketing copy, or completely absent when one was clearly warranted. |

### 2. Step Structure (0-10)

| Score | Criteria |
|-------|----------|
| 9-10  | Steps map to natural phases. 2-5 steps (or implicit step if simple). Step names are short imperatives in sentence case with periods. Ingredients belong to the right step. |
| 7-8   | Step structure is reasonable but slightly over-split (6+ steps for a simple recipe) or step names are a bit wordy. |
| 5-6   | Steps don't map to natural phases — split mechanically (one step per numbered instruction in source). Or step names use wrong case/style. |
| 3-4   | Steps are badly organized: ingredients in wrong steps, re-listed between steps, or lumped into one massive step when phases exist. |
| 1-2   | No step structure at all, or uses numbered lists instead of step headings. |

### 3. Ingredient Format (0-10)

| Score | Criteria |
|-------|----------|
| 9-10  | Perfect `Name, qty unit: Prep.` format. Correct use of parenthetical qualifiers (not over-qualified). To-taste items have no quantity. Fractions, ranges, and units follow the format spec exactly. |
| 7-8   | Format is correct but minor issues: a slightly over-qualified name, an unnecessary "to taste", or one fraction in the wrong notation. |
| 5-6   | Several formatting errors: inconsistent qualifier style, mixed fraction notation, quantities on to-taste items, or prep notes in the wrong style. |
| 3-4   | Significant format problems: many wrong qualifiers, numbered ingredients, wrong structure (e.g., "1 cup of flour, sifted"), units converted from source. |
| 1-2   | Doesn't follow the ingredient format at all. |

### 4. Instruction Voice (0-10)

This is the most important and hardest dimension — it's where AI
conversions most often fail.

| Score | Criteria |
|-------|----------|
| 9-10  | Reads like the collection author wrote it. Terse imperatives, sensory cues, comfortable vagueness, dropped articles, no filler. Uses "correct for seasoning" not "adjust to taste." Has personality where appropriate. Would pass a blind test against the real recipes. |
| 7-8   | Mostly right voice but slightly too formal or too detailed. A few extra words per sentence. Maybe one "be sure to" or "don't forget." Competent but lacks the personal edge. |
| 5-6   | Noticeably more verbose than the collection. Uses complete sentences where the collection would use fragments. Some passive voice or hedging ("you may want to", "you can also"). Reads like a competent recipe, not like *this* collection. |
| 3-4   | Blog voice: "Now for the fun part!", safety warnings, cheerleading ("Enjoy!"), numbered steps within prose, excessive precision, or obvious AI tells ("delightful", "elevate", "game-changer"). |
| 1-2   | Completely wrong register: formal technical writing, marketing copy, or children's cookbook tone. |

**Specific things to look for in instruction voice:**

- **-2 points** for any "Be sure to..." / "Don't forget to..." / "Make sure..."
- **-2 points** for any "Enjoy!" / "Serve and enjoy!" / "Bon appétit!" / cheerleading closers
- **-1 point** for "set aside" (should be "reserve" or nothing)
- **-1 point** for "approximately" (should be "about")
- **-1 point** for each safety warning ("be careful", "use caution")
- **-1 point** for passive voice in instructions
- **-1 point** for "adjust seasoning to taste" (should be "correct for seasoning" or "season to taste")
- **-1 point** for "garnish with" (this collection doesn't use this phrase)
- **-1 point** for each use of "you" addressing the reader (collection rarely does this; when it does, it's in asides, not instructions)

### 5. Conciseness (0-10)

| Score | Criteria |
|-------|----------|
| 9-10  | Every word earns its place. Instructions are as brief as the collection's — usually 1-3 sentences per step. No filler, no redundancy, no over-explanation. |
| 7-8   | Slightly wordy in places. An extra sentence or two that the collection author would have cut. |
| 5-6   | Noticeably longer than equivalent collection recipes. Explanations of things the reader should know. Some redundancy between steps. |
| 3-4   | Twice as long as it should be. Explains basics, repeats information, includes preamble within steps. |
| 1-2   | Blog-length instructions for a simple recipe. Multiple paragraphs where one sentence would do. |

### 6. Footer (0-10)

| Score | Criteria |
|-------|----------|
| 9-10  | Brief and useful. Attribution uses "Based on a recipe from" format. Substitutions and tips are practical and terse. Personal voice comes through. |
| 7-8   | Correct format but slightly too formal or too detailed. |
| 5-6   | Footer is present but has issues: wrong attribution format ("Adapted from"), tips are too long, or includes information that belongs in the instructions. |
| 3-4   | Footer reads like a blog's "Recipe Notes" section — numbered tips, extensive substitution lists, storage instructions that are really a separate section. |
| 1-2   | No footer when one was warranted, or footer is a multi-paragraph essay. |

### 7. Format Accuracy (0-10)

Mechanical correctness of the markdown format, independent of voice.

| Score | Criteria |
|-------|----------|
| 9-10  | Perfect markdown structure. Correct heading levels, blank lines, ingredient syntax, front matter format. Fractions are ASCII. Ranges use hyphens. Temperatures formatted correctly. Makes/Serves are single numbers. |
| 7-8   | One or two minor format errors. |
| 5-6   | Several format errors but the structure is recognizable. |
| 3-4   | Major structural problems: wrong heading levels, missing blank lines, incorrect ingredient syntax. |
| 1-2   | Doesn't follow the format at all. |

---

## Scoring Summary

| Dimension | Weight | Description |
|-----------|--------|-------------|
| Description | 1x | Punchy quip, not a summary |
| Step Structure | 1x | Natural phases, correct names |
| Ingredient Format | 1x | Syntax, qualifiers, quantities |
| **Instruction Voice** | **2x** | **Terse, personal, trusting** |
| Conciseness | 1x | No filler, no over-explanation |
| Footer | 1x | Brief, practical, correct format |
| Format Accuracy | 1x | Mechanical markdown correctness |

Instruction Voice is weighted 2x because it's the hardest to get right
and the most noticeable when wrong. It's the difference between "a recipe
in the right format" and "a recipe that sounds like it belongs."

**Final score = (sum of weighted scores) / 8, rounded to nearest integer.**

### Score Interpretation

| Score | Meaning |
|-------|---------|
| 9-10  | Indistinguishable from the collection. Could be committed as-is. |
| 7-8   | Very close. Minor edits needed — a phrase here, a word there. |
| 5-6   | Right format, wrong voice. Needs a rewrite pass for tone. |
| 3-4   | Significant problems. Format and/or voice issues throughout. |
| 1-2   | Doesn't resemble the collection at all. Start over. |

---

## Quick Checklist for Evaluators

Before scoring, scan the conversion for these common AI tells:

- [ ] Description under ~10 words and has personality?
- [ ] Step names are short imperatives with periods?
- [ ] No "Be sure to" / "Don't forget to" / "Make sure"?
- [ ] No "Enjoy!" or cheerleading closer?
- [ ] No "set aside" (should be "reserve" or omitted)?
- [ ] No "approximately" (should be "about")?
- [ ] No safety warnings?
- [ ] No passive voice in instructions?
- [ ] No "garnish with"?
- [ ] No numbered instruction lists?
- [ ] Uses "correct for seasoning" or "season to taste", not "adjust"?
- [ ] Comfortable with vague quantities ("a splash", "a few")?
- [ ] Times given as ranges or approximations, not exact?
- [ ] Articles dropped where the collection would drop them?
- [ ] No blog-speak ("game-changer", "take it to the next level")?
- [ ] Ingredients not re-listed between steps?
- [ ] ASCII fractions, not vulgar fraction characters?
- [ ] Hyphens in ranges, not en-dashes?
- [ ] Source units preserved (not converted)?
- [ ] Footer uses "Based on a recipe from", not "Adapted from"?
