# Iteration iteration_baseline_expert

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Style | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-------|-----------|
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 95 | 95 | 79 | 94 | 91.3 |
| 04_blog_smitten_kitchen | PASS | PASS | 92.3% | 100 | 95 | 75 | 89 | 89.2 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 100 | 100 | 100 | 98 | 99.5 |
| 06_blog_pioneer_woman | PASS | PASS | 92.3% | 96 | 97 | 79 | 94 | 91.1 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 98 | 100 | 79 | 100 | 94.4 |
| 08_agg_allrecipes | PASS | PASS | 92.3% | 96 | 95 | 79 | 100 | 92.2 |
| 10_agg_epicurious | PASS | PASS | 92.3% | 93 | 100 | 78 | 96 | 91.3 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 92 | 97 | 69 | 100 | 90.1 |
| 12_ocr_biscuits | PASS | PASS | 92.3% | 100 | 100 | 73 | 96 | 91.5 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 95 | 100 | 100 | 99 | 98.8 |
| 15_clean_text_message | PASS | PASS | 100.0% | 95 | 95 | 97 | 94 | 95.8 |
| 16_clean_email | PASS | PASS | 92.3% | 93 | 95 | 80 | 96 | 90.8 |

**Overall:** 93.0 avg, 89.2 worst

### 03_blog_serious_eats_c — issues
- STEPS: split_issues: Original has a single flat ingredient list with no sub-groupings — Rule 2 requires implicit format, but output chose explicit with four ## steps
- STEPS: naming_issues: "Bake." is slightly terse compared to the other step names but still acceptable
- STEPS: ownership_issues: Salt and pepper listed only in step 1 but used throughout multiple steps, Egg listed in step 3 but also referenced in step 4 as 'remaining beaten egg'
- STYLE: voice: "as you go" in assembly section contains "you"
- STYLE: condensation: "Drain on paper towels" is borderline basic/obvious
- STYLE: prose: Assembly section is quite dense — reads naturally but pushes the limits of paragraph complexity
- STYLE: footer: Imperial temperature equivalents may be AI-added conversion convenience rather than source content, "Use high-quality all-butter puff pastry" borders on quality editorializing though likely from source
- STYLE: economy: "Refrigerate at least 30 minutes" appears three times — each contextually justified but slightly repetitive in phrasing

### 04_blog_smitten_kitchen — issues
- FORMAT: step_splitting_appropriate — Expected implicit (1 step, no headers) but got 2 steps
- STEPS: split_issues: Source has a single flat ingredient list with no grouped headings — rules require implicit format, but OUTPUT split into two explicit steps
- STEPS: ownership_issues: Minor: butter correctly split between steps by usage, but this split shouldn't exist in the first place
- STEPS: flow_issues: Oven preheat instruction moved from before onion caramelization (original paragraph 1) to after it (step 2), minor reorder
- STYLE: voice: Articles in section headers: 'Caramelize the onions', 'Make the biscuits', Scattered articles in body: 'in a large skillet', 'with a pastry blender', 'with a floured 3-inch cutter', 'to a bowl'
- STYLE: condensation: Technique tutorial: 'by hand with fingertips or a pastry blender, or pulse in food processor then transfer to bowl' — experienced cooks know how to cut in butter, Generic biscuit knowledge: 'Re-roll scraps as needed', 'Line baking sheet with parchment' is basic prep
- STYLE: prose: Second paragraph is quite dense — several sentences chained tightly, though still readable prose
- STYLE: footer: Substitution note ('Substitute another Swiss-style cheese') may be AI-invented rather than from source, Storage tips ('Best day-of; reheat on day two. Can freeze unbaked biscuits') may be AI-added, Imperial equivalents paragraph appears to be an AI-generated convenience addition not from the source
- STYLE: economy: Wordy method enumeration: 'by hand with fingertips or a pastry blender, or pulse in food processor then transfer to bowl', Two uses of 'stir' in close proximity: 'Stir buttermilk into cooled onions, then add to flour mixture and stir until combined'

**Output snippet (first 20 lines):**
```
# Caramelized Onion and Gruyère Biscuits

Worth the wait on those onions.

Makes: 10 biscuits
Category: Baking
Tags: baked, vegetarian

## Caramelize the onions.

- Butter (unsalted), 1 tbsp
- Olive oil, 1 tbsp
- Onions, 2 small: Halved and thinly sliced.

Melt butter with olive oil in a large skillet over medium. Add onions, reduce to low, cover, and let steam about 10 minutes, stirring occasionally. Uncover; cook until deep brown, 10-20 minutes more. Cool completely.

## Make the biscuits.

- Butter (unsalted), 8 tbsp: Cold, cut into 1/2-inch pieces.
- Flour (all-purpose), 345 g

```

### 05_blog_budget_bytes — issues
- STYLE: condensation: "Preheat oven to 350°F" is a borderline preheat reminder, though justified by bake timing
- STYLE: footer: "Brown sugar can be reduced by half if preferred" may be an invented substitution not present in the source

### 06_blog_pioneer_woman — issues
- FORMAT: step_splitting_appropriate — Expected implicit (1 step, no headers) but got 2 steps
- STEPS: split_issues: Original has a single flat ingredient list under one 'Ingredients' heading with no subgroup headings. Per the rules, this should use implicit-step format. The model incorrectly split it into two explicit steps.
- STEPS: ownership_issues: Toppings (cheddar, bacon, jalapeños) are listed as regular ingredients in step 2 rather than being kept as a garnish note, but each ingredient appears only once and grouping is logical for the chosen (incorrect) format.
- STYLE: condensation: Footer says 'Rinse canned beans — they can be slimy right out of the can' — common-sense advice an experienced cook doesn't need, and the ingredient line already says 'Drained and rinsed'
- STYLE: footer: 'Rinse canned beans' note is redundant — ingredient prep already says 'Drained and rinsed', 'they can be slimy right out of the can' is hand-holding explanation that adds no value for an experienced cook
- STYLE: economy: Redundancy between ingredient prep 'Drained and rinsed' and footer 'Rinse canned beans', 'they can be slimy right out of the can' is filler explanation

### 07_blog_bon_appetit — issues
- STEPS: split_issues: Source has a single flat ingredient list with no grouping headings — Rule 2 requires implicit format. The 'divided' annotations on flour/salt/pepper/dill indicate split usage but are not source-level group headings. The model incorrectly split into two explicit steps.
- STEPS: ownership_issues: Given the incorrect explicit split, ingredients are well-placed under their respective steps with correct divided amounts.

### 08_agg_allrecipes — issues
- FORMAT: step_splitting_appropriate — Expected implicit (1 step, no headers) but got 2 steps
- STEPS: split_issues: Source has a single flat ingredient list with no grouping headings. The 'Roasted Pork, Cuban-Style' section is a footnote/sub-recipe, not an ingredient group heading. Rule 2 requires implicit format for flat-list recipes, but the output incorrectly split into two explicit steps.
- STEPS: naming_issues: Names are good — 'Cook the meats.' and 'Assemble and press.' are descriptive, sentence case, with periods. No issues here, though the steps shouldn't exist.
- STEPS: ownership_issues: Given the (incorrect) explicit format, the ingredient grouping is logical — meats under cooking step, bread/cheese/pickles/mustard/butter under assembly. No misplacement within the chosen structure.
- STEPS: flow_issues: Instruction order faithfully follows the original: cook meats first, then toast bread, assemble, press. The roasted pork footnote is preserved at the end. No reordering issues.

### 10_agg_epicurious — issues
- FORMAT: step_splitting_appropriate — Expected implicit (1 step, no headers) but got 3 steps
- FIDELITY: quantities_changed: Onion: '1 large yellow onion' → 'Onion, 1' — missing 'large' size and 'yellow' type
- OUTCOME: outcome_affected: Parsley listed as just 'Parsley' — original specifies 'fresh parsley leaves'; an experienced cook could default to dried, Black pepper missing 'freshly ground' qualifier from original
- STEPS: split_issues: Original has a single flat ingredient list under 'Software' with no sub-group headings — Rule 2 requires implicit format, but the output splits into three explicit steps
- STEPS: ownership_issues: Salt is split across steps (1 tbsp in step 1, 1 tsp in step 3) — reasonable given the 'divided' note in the original, but this splitting only exists because of the incorrect explicit format choice
- STYLE: voice: A few articles could be dropped more aggressively: 'a metal pan', 'a heatproof container', 'a large saucier', 'a cold oven'
- STYLE: condensation: 'Carefully poke a hole' — 'carefully' is mild hand-holding
- STYLE: footer: 'Reserve remaining fat from the cap for another use' may be an added tip not from the source — hard to verify

### 11_agg_nyt_style — issues
- FIDELITY: quantities_changed: Yield changed from 'One 1 1/2-pound loaf' to '1 loaf' — weight specification dropped
- OUTCOME: outcome_affected: Wheat bran demoted from co-equal ingredient option ('Cornmeal or wheat bran') to a footer substitution note — an experienced cook would default to cornmeal only unless they read the footer, but the information is present
- STEPS: split_issues: Source has a single flat ingredient list with no sub-groupings — rule 2 requires implicit format, Only 4-5 ingredients — rule 3 (≤5 ingredients) independently requires implicit format, Both applicable rules converge on implicit; choosing explicit is clearly wrong
- STEPS: naming_issues: Names are well-formed but should not exist — implicit format has no step headings
- STEPS: ownership_issues: Water (345 g) added as an explicit ingredient — it appeared only in instructions, not in the original ingredient list, Cornmeal separated into 'Shape and proof' step away from the other ingredients, breaking the original's single flat list, 'Flour, plus more for dusting' nuance lost — dusting flour used in steps 2-3 but flour only listed in step 1
- STEPS: flow_issues: Minor consolidation of original steps 2-3 into single 'Shape and proof' section, but sequence preserved

### 12_ocr_biscuits — issues
- FORMAT: step_splitting_appropriate — Expected implicit (1 step, no headers) but got 2 steps
- STEPS: split_issues: Source has a single flat ingredient list with exactly 5 ingredients. Both Rule 2 (flat list → implicit) and Rule 3 (≤5 ingredients → always implicit) require implicit format. The output incorrectly split into two explicit steps ('Make the dough.' and 'Shape and bake.').
- STEPS: flow_issues: 'Preheat oven to 425°F' appears at the very start of the original instructions but was moved to the second step in the output, reordering it after the dough-making instructions.
- STYLE: condensation: "with pastry cutter or two knives" is mildly tutorial-ish — experienced cooks know how to cut in butter
- STYLE: economy: "just until dough comes together — don't overmix" is slightly redundant — both halves say the same thing

### 13_ocr_beef_stew — issues
- FIDELITY: quantities_changed: Onion: 'l large onion' → 'Onion, 1' — 'large' descriptor dropped
- OUTCOME: outcome_affected: Carrots: 'peeled' dropped from description, though an expert would peel by default
- STYLE: condensation: "Remove and set aside" is borderline generic — experienced cook infers this from the batch-browning context

### 15_clean_text_message — issues
- OUTCOME: outcome_affected: Serves: 2 is invented — the original does not specify a serving count
- STEPS: flow_issues: Minor reordering: 'don't overmix' moved before 'taste and adjust' whereas original has tasting first then the chunky note, Chopping instructions moved from the instruction body into ingredient annotations ('Finely chopped'), slightly altering the instruction flow, Optional/spice-level notes separated into a footer section rather than staying inline with instructions
- STYLE: voice: "a fork" retains article, though natural in this context
- STYLE: footer: "Cilantro is optional" restates annotation already on the ingredient line ("Optional."), "Use less jalapeño to taste" repackages the "1/2 or less" already in the ingredient list
- STYLE: economy: Footer repeats information already encoded in ingredient annotations, adding words without new content

### 16_clean_email — issues
- FORMAT: step_splitting_appropriate — Expected implicit (1 step, no headers) but got 2 steps
- FIDELITY: quantities_changed: Onion: '1 large onion' → 'Onion, 1' (dropped 'large' qualifier)
- STEPS: split_issues: Source has a single flat ingredient list with no group headings — rule 2 requires implicit format, but the output split into two explicit steps
- STEPS: ownership_issues: Minor: salt and pepper placed only in step 2 though they could apply during broth cooking as well, but this matches the source's instruction order
- STYLE: voice: "Strain broth if desired" — minor hedging with "if desired"
- STYLE: condensation: "discard skin and bones" is arguably obvious to an experienced cook
- STYLE: footer: "is a nice addition" is slightly editorializing — could tighten to just "A squeeze of lemon at the table.", Cannot verify lemon tip was in the source
