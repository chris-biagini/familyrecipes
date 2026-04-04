# Iteration iteration_baseline_expert_v2

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Style | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-------|-----------|
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 96 | 100 | 97 | 94 | 97.0 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 96 | 95 | 98 | 92 | 95.7 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 98 | 100 | 97 | 94 | 97.4 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 95 | 100 | 94 | 95 | 96.3 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 97 | 100 | 98 | 100 | 98.9 |
| 08_agg_allrecipes | PASS | PASS | 100.0% | 94 | 95 | 97 | 99 | 96.8 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 92 | 100 | 90 | 100 | 95.9 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 92 | 95 | 96 | 96 | 95.4 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 98 | 100 | 97 | 96 | 97.9 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 93 | 100 | 100 | 99 | 98.4 |
| 15_clean_text_message | PASS | PASS | 100.0% | 98 | 100 | 100 | 98 | 99.1 |
| 16_clean_email | PASS | PASS | 100.0% | 95 | 100 | 97 | 94 | 96.8 |

**Overall:** 97.1 avg, 95.4 worst

### 03_blog_serious_eats_c — issues
- STEPS: ownership_issues: Egg listed in step 4 but also used in step 5 ('remaining beaten egg') — minor, since it's the same beaten egg used across two steps and listing it twice would be incorrect.
- STEPS: phase_design_issues: Step 2 is dense, combining two distinct cooking operations (duxelles + foie gras searing), though the logical connection (rendered fat into duxelles) and shared chilling period justify the grouping.
- STYLE: voice: Slightly more formal article retention than the tersest exemplars (e.g., 'Heat oil in a cast iron or stainless steel skillet' vs exemplar's 'Add oil to large pan'), though still natural and never robotic
- STYLE: condensation: 'Use a high-quality all-butter puff pastry' in footer is quality editorializing, 'stirring occasionally' and 'stirring frequently' are mildly generic cooking cues, though they serve as timing indicators here
- STYLE: prose: Assembly paragraphs in 'Wrap in puff pastry' section are dense and slightly stiff, though the complexity of the technique justifies it
- STYLE: footer: 'high-quality' in puff pastry recommendation is quality editorializing, Substitutions are detailed and plausibly from Serious Eats source but cannot fully verify all are source-originated
- STYLE: economy: 'stir to combine' after 'Pour rendered fat into mushroom mixture' is mild filler, 'Season with salt and pepper' appears three times for different components — technically not redundant but slightly formulaic

### 04_blog_smitten_kitchen — issues
- STEPS: phase_design_issues: Step 2 covers a large amount of work (combine dry, cut butter, add cheese, mix wet/dry, knead, roll, cut, season, bake), but it's all continuous with no natural stopping point, so collapsing it is defensible.
- STYLE: voice: "a few floury spots are fine" is slightly reassuring/editorial — borderline hand-holding, though it is recipe-specific guidance for biscuit dough
- STYLE: condensation: "by hand or in a food processor" is a generic technique option an experienced cook doesn't need, "a few floury spots are fine" is hand-holding — an experienced baker knows not to overwork biscuit dough, "space apart on prepared baking sheet" — spacing biscuits is common sense
- STYLE: footer: "Make your own buttermilk if needed" is vague and feels potentially invented — no method or ratio given, Substitution notes (kosher salt, Swiss-style cheese) may not originate from source — cannot verify
- STYLE: economy: "stir to combine, then add to flour mixture and stir together" — double 'stir' is slightly redundant; could tighten, "prepared baking sheet" is redundant — we already instructed to line it with parchment

### 05_blog_budget_bytes — issues
- STEPS: phase_design_issues: Preheat moved to step 2 — an experienced cook reading linearly would start mixing before turning on the oven. Original places preheat first so oven is ready by bake time. Very minor since experienced cooks know to preheat early.
- STYLE: voice: Very minor: 'don't overwork' is imperative but slightly conversational in tone — borderline
- STYLE: condensation: Preheat reminder is present but justified by recipe flow (glaze made first, then oven needed)
- STYLE: title: 'Classic' is mild filler — 'Meatloaf' alone would be cleaner
- STYLE: footer: 'the fat adds flavor and keeps the loaf from drying out' reads like an AI-added explanation — may not be from the source, Sugar reduction tip ('Reduce sugar to 1/2 tbsp if preferred') could be an invented substitution
- STYLE: economy: Three-bowl approach adds words ('In a separate bowl', 'to a large bowl') — could be streamlined to fewer vessels and fewer prepositional phrases

### 06_blog_pioneer_woman — issues
- STEPS: naming_issues: "Simmer; add beans and thickener." omits the initial action of adding tomato sauce, paste, and spices — the step begins with that assembly before any simmering. Something like "Build and simmer chili; add beans and thicken." would better describe the full phase.
- STEPS: phase_design_issues: Second step carries 9 ingredients and two distinct temporal sub-phases (1-hour simmer then 10-minute bean/thickener addition), but combining them is defensible since it's all sequential work in the same pot. Two steps is a reasonable fit for this recipe's complexity.
- STYLE: voice: "leaving a little for flavor" is slightly conversational/explanatory — could be tighter as "leave a little"
- STYLE: condensation: "stirring occasionally" is generic cooking advice an experienced cook would assume, "Drained and rinsed" on beans is common-sense prep for canned beans, "leaving a little for flavor" is mild hand-holding
- STYLE: footer: Cannot fully verify that topping suggestions and cornmeal substitution are from the source rather than AI-added; attribution to Ree Drummond is present
- STYLE: economy: "Drain off most of the fat, leaving a little for flavor" — "leaving a little for flavor" adds words; "leave a little" suffices, "Add up to 1 1/2 cups water if the level runs low" — "as needed" would be more economical than "if the level runs low"

### 07_blog_bon_appetit — issues
- FIDELITY: quantities_changed: extra-virgin olive oil simplified to olive oil — minor flavor specification lost

### 08_agg_allrecipes — issues
- OUTCOME: technique_lost: "pressing slightly" when weighting down sandwiches with heavy skillet was dropped
- OUTCOME: outcome_affected: "Cut each bread loaf in half crosswise" instruction not explicitly stated — an experienced cook would infer 6 portions from 3 loaves, but the explicit crosswise cut direction is missing
- STEPS: phase_design_issues: Second step is dense — covers three distinct phases (cook meat, toast bread and assemble, press-cook sandwiches) in one step with three paragraphs and 6 ingredients. Splitting assembly/pressing from the initial meat cook could improve clarity, though keeping them together as one continuous skillet session is defensible for experienced cooks.
- STYLE: economy: "Working in batches" preamble is slightly redundant — the batch size is implied by skillet capacity and clarified later, "place on a rack in a roasting pan" — "in a roasting pan" is implicit for an expert audience

### 10_agg_epicurious — issues
- OUTCOME: outcome_affected: 'yellow onion' simplified to 'Onion' — could lead to using a different onion variety, 'fresh parsley leaves' simplified to 'Parsley' — could lead to using dried parsley, 'freshly ground black pepper' simplified to 'Black pepper' — minor flavor difference
- STEPS: naming_issues: Step 1 ('Sear and braise ribs.') omits the paste-making sub-action; 'Make paste; sear and braise ribs.' would be more complete, though this is a minor quibble.
- STEPS: disentanglement_issues: Step 3 preserves the original's 'Meanwhile, remove meat from bones' interleaved with the potato cooking. The meat prep could have been a separate step or folded into step 2 (ribs are already resting at room temperature during the liquid cooling).

### 11_agg_nyt_style — issues
- FIDELITY: quantities_changed: Makes: '1 loaf' drops the '1 1/2-pound' weight from original 'One 1 1/2-pound loaf'
- OUTCOME: outcome_affected: Bread flour presented as equal alternative in original ingredient list ('all-purpose or bread flour') but relegated to a footer substitution note in output; similarly wheat bran listed as equal option in original but moved to footer substitution — these are reformulations of source info, not truly invented, but the framing as 'substitutions' is new
- STEPS: disentanglement_issues: Oven preheat ('at least 30 minutes before dough is ready') is a parallel operation during proofing but is placed in the Bake step, requiring the reader to look ahead — minor issue, standard for bread recipes
- STYLE: voice: "Carefully remove hot pot" — "carefully" is mild hedging/hand-holding, "it may look uneven, but it straightens as it bakes" — reassurance tone, slightly conversational
- STYLE: condensation: "Carefully" before "remove hot pot" is slightly hand-holdy — an experienced cook knows a 450°F pot requires care, "Cool on rack" is borderline generic but brief enough to not matter much
- STYLE: footer: Wheat bran substitution for cornmeal is partially redundant — the body already lists "flour, cornmeal, or wheat bran" as towel-coating options
- STYLE: economy: "it may look uneven, but it straightens as it bakes" is a reassurance sentence that could be trimmed, "Carefully remove hot pot" — adverb adds a word without much value

### 12_ocr_biscuits — issues
- STYLE: voice: "don't overmix" is borderline direct address but acceptable as kitchen shorthand
- STYLE: condensation: "with a pastry cutter or two knives" is a minor technique tutorial — an experienced cook knows how to cut in butter
- STYLE: economy: "stir just until dough comes together — don't overmix" is mildly redundant — "just until" already implies restraint, "with a pastry cutter or two knives" adds words for a technique an experienced cook already knows

### 13_ocr_beef_stew — issues
- FIDELITY: quantities_changed: Onion: 'l large onion' changed to 'Onion, 1' — 'large' descriptor dropped, Thyme: 'dried thyme' changed to 'Thyme' — 'dried' qualifier dropped
- OUTCOME: outcome_affected: Dropping 'dried' from thyme could lead an experienced cook to use fresh thyme, which has different potency and flavor intensity
- STYLE: condensation: "Remove bay leaves before serving" is borderline common-sense for experienced cooks

### 15_clean_text_message — issues
- STYLE: footer: "Use less jalapeño for milder heat" reads like a generic AI-added tip rather than source-provided content — common-sense advice an experienced cook wouldn't need

### 16_clean_email — issues
- FIDELITY: quantities_changed: Onion: '1 large onion' → '1 onion' — 'large' qualifier dropped
- STEPS: phase_design_issues: The 'Cook noodles; serve.' step is a bit thin — one ingredient and two short sentences. It could reasonably be folded into the previous step as a serving note, though the separate-pot technique does justify the split.
- STYLE: voice: "Strain broth if desired" — mild hedging with "if desired", "they turn mushy if left in the soup" — explanatory/justifying rather than purely imperative, though recipe-specific
- STYLE: condensation: "Strain broth if desired" borders on optional hand-holding
- STYLE: specificity: All key details preserved — times, visual cues, quantities. Minor: no explicit note on heat level for the initial boil-to-simmer transition, though 'reduce to a simmer' is clear enough.
- STYLE: footer: "A squeeze of lemon at the table is optional" — "is optional" is unnecessary; could be tighter as just "A squeeze of lemon at the table.", Cannot verify whether the lemon note was in the source or AI-invented
