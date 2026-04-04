# Iteration iteration_001

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Style | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-------|-----------|
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 97 | 95 | 98 | 96 | 96.9 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 93 | 88 | 94 | 94 | 93.2 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 95 | 95 | 99 | 98 | 97.3 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 95 | 90 | 94 | 96 | 94.5 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 94 | 93 | 95 | 100 | 96.2 |
| 08_agg_allrecipes | PASS | PASS | 100.0% | 97 | 95 | 99 | 98 | 97.7 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 93 | 97 | 90 | 92 | 93.5 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 90 | 90 | 98 | 96 | 94.5 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 98 | 96 | 97 | 96 | 97.1 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 88 | 82 | 99 | 98 | 93.3 |
| 15_clean_text_message | PASS | PASS | 100.0% | 84 | 82 | 100 | 98 | 92.7 |
| 16_clean_email | PASS | PASS | 100.0% | 95 | 88 | 93 | 94 | 93.4 |

**Overall:** 95.0 avg, 92.7 worst

### 03_blog_serious_eats_c — issues
- STEPS: ownership_issues: Egg is listed in Step 4 and referenced as 'remaining egg' in Step 5 without being re-listed — minor, since introducing it once at first use is the better call.
- STEPS: phase_design_issues: Step 2 combines two distinct cooking operations (making duxelles and searing foie gras) — the rendered-fat connection justifies it, but a case could be made for separation since they use different pans and techniques.
- STYLE: condensation: Minor: 'Transfer to paper towels' is slightly generic, though brief enough to not be a real problem
- STYLE: footer: References 'Step 2' and 'Step 3' in footer but recipe uses named sections, not numbered steps — inconsistent with the recipe's own structure, Quality editorializing: 'Use high-quality all-butter puff pastry if possible' — though likely from source, still reads as quality advice
- STYLE: economy: 'stir to combine' after 'Pour rendered fat into mushroom mixture' — the stirring instruction is fine but 'to combine' is slightly redundant given context

### 04_blog_smitten_kitchen — issues
- FIDELITY: detritus_retained: Freezing tip ('Freeze unbaked rounds and thaw briefly before baking') is sourced from blog preamble personal narrative, not the recipe itself — author's anecdote converted into a recipe recommendation
- OUTCOME: technique_lost: 'Freshly ground' specification dropped from black pepper — original says 'Freshly ground black pepper', output just says 'Black pepper'
- STEPS: naming_issues: 'Make dough; assemble.' — 'assemble' is vague; the step is entirely about making the dough (dry + butter + cheese + wet). 'Assemble' typically implies putting finished components together, which is closer to what step 3 does. A name like 'Make dough.' or 'Make dough; add onion mixture.' would be more precise.
- STEPS: phase_design_issues: Oven preheat instruction placed in 'Caramelize onions' step, though the oven isn't needed until 'Shape and bake' — practical but slightly misplaced for the phase.
- STEPS: disentanglement_issues: Preheat oven is tangled into the onion caramelization step rather than standing alone or appearing in the baking step; source had minimal interleaving so this is a minor concern.
- STYLE: voice: "A few floury spots are fine" borders on reassurance/hand-holding but is recipe-specific enough to pass
- STYLE: condensation: "or pulse in a food processor" is a slight technique tutorial alternative, "Re-roll scraps as needed" is somewhat obvious for biscuit-making
- STYLE: footer: "Make your own buttermilk if needed" is vague and generic — sounds potentially invented rather than from source, "Use coarse or kosher salt in the dough" may be an invented substitution suggestion
- STYLE: economy: Double em-dash parenthetical for food processor alternative is slightly wordy — could be tightened, "Stir" appears twice in consecutive sentences ("Stir buttermilk..." then "Stir to combine") — minor repetition

### 05_blog_budget_bytes — issues
- STYLE: condensation: "Combine breadcrumbs, Italian seasoning, garlic powder, salt, and pepper in a separate bowl" — the separate bowl step is slightly over-detailed; an experienced cook would toss dry ingredients directly into the main bowl
- STYLE: footer: "Reduce brown sugar to 1/2 tbsp if you prefer a less sweet glaze" — specific substitution that may be invented rather than from the source

### 06_blog_pioneer_woman — issues
- FIDELITY: detritus_retained: Embellished attribution: URL 'https://www.thepioneerwoman.com' added to Ree Drummond credit — original text only says 'By Ree Drummond' with no URL
- STEPS: naming_issues: "Simmer." is too generic — something like "Add sauce and spices; simmer." or "Simmer with tomato and spices." would better describe the phase of work.
- STYLE: description: No description present; a punchy one-liner would suit a multi-step recipe like this
- STYLE: footer: "Substitute cornmeal for masa harina" may be an invented substitution not from the source, "add as desired" is mildly hedging phrasing

### 07_blog_bon_appetit — issues
- FIDELITY: quantities_changed: extra-virgin olive oil → olive oil (specification dropped, not a quantity change but loses the extra-virgin distinction)
- FIDELITY: detritus_retained: 'Better than any pie crust.' is a hallucinated description not found in the original
- OUTCOME: outcome_affected: Dropping 'extra-virgin' from olive oil is a minor specification change; flavor difference would be minimal in a cooked filling
- STEPS: naming_issues: Minor article inconsistency: 'Make the filling.' vs 'Make popover batter.' — the second step drops the article.
- STEPS: phase_design_issues: 'Assemble and bake' step has no ingredients and only two sentences of instruction, making it a thin step — though it represents a genuinely distinct phase that can't logically merge with either preceding step.
- STEPS: disentanglement_issues: 'Meanwhile' is retained at the start of the batter step and 'rest until filling is ready' at the end still references the filling's timeline — the operations are structurally separated into distinct steps but the interleaving language lingers.

### 08_agg_allrecipes — issues
- STYLE: condensation: "a sprinkle of water should sizzle and evaporate immediately" is a mildly tutorial-ish hot-pan test that experienced cooks already know
- STYLE: footer: Cannot fully verify whether the pulled pork substitution originated from the source or was added by the AI

### 10_agg_epicurious — issues
- OUTCOME: outcome_affected: Onion specified as 'yellow' in original but OUTPUT says only 'Onion, 1 large' — minor, yellow is the default assumption, Original specifies 'freshly ground black pepper'; OUTPUT says only 'Black pepper, a pinch', Original specifies 'fresh parsley leaves'; OUTPUT says only 'Parsley' — an experienced cook would likely use fresh given the context
- STEPS: phase_design_issues: Step 2 ('Degrease braising liquid') has no ingredients — it's a legitimate temporal phase but borderline as a standalone step; the degreasing instructions could potentially live as a tail on step 1 or a preamble to step 3.
- STEPS: disentanglement_issues: The 'Meanwhile, cut meat from bone' parallel operation from the original is preserved verbatim inside step 3, interleaved with the potato cooking. This could have been separated — e.g., meat prep moved to the end of step 2 (ribs are already resting at room temperature) or broken into its own step.
- STYLE: voice: "Carefully poke a hole" — "Carefully" is mild hedging/hand-holding, "Melt the reserved tablespoon of fat in a large saucier" — slightly wordy with articles, could be "Melt reserved tablespoon of fat in large saucier"
- STYLE: condensation: "stir to combine" in the vegetable paragraph is slightly generic, "Let ribs rest at room temperature while liquid cools" — experienced cook would infer this
- STYLE: prose: Degreasing section has several short declarative sentences in sequence ("Remove solidified fat cap; measure out 1 tbsp and set aside. Reserve the remainder.") — slightly stiff
- STYLE: footer: No explicit attribution to Alton Brown / Good Eats TV show despite the title referencing the show, Herb and fat notes seem source-appropriate but cannot fully verify without original
- STYLE: economy: "Melt the reserved tablespoon of fat in a large saucier over medium heat" — wordy construction, "pour in the defatted braising liquid, and stir to combine" — "stir to combine" adds little

### 11_agg_nyt_style — issues
- FIDELITY: quantities_changed: Yield 'One 1 1/2-pound loaf' simplified to 'Makes: 1 loaf' — weight specification dropped
- FIDELITY: detritus_retained: Footer note 'Substitute wheat bran for cornmeal' reframes the original's equal-option listing into advice-style substitution tip, Footer note 'Bread flour works equally well' reframes the original's equal listing ('all-purpose or bread flour') into an editorial tip
- OUTCOME: outcome_affected: Wheat bran demoted from equal option (original: 'Cornmeal or wheat bran, as needed' in ingredients; 'flour, wheat bran or cornmeal' in instructions) to a footer substitution note — an expert cook following the OUTPUT would default to cornmeal only unless they read the footer
- STEPS: ownership_issues: Wheat bran from the original ingredient list ('Cornmeal or wheat bran, as needed') is not listed as an ingredient in any step — it appears only in the footer substitution note.
- STEPS: disentanglement_issues: Oven preheat is a parallel operation during proofing but is kept in the Bake step with a timing reference back to the proof ('before dough is ready') — minor tangle, but conventional for bread recipes.
- STYLE: voice: "it may look like a mess, that's OK" is slightly chatty/reassuring — reads as addressing the reader, "Carefully remove pot" — mild hedging; the imperative alone suffices
- STYLE: condensation: "it may look like a mess, that's OK" is mild reassurance/hand-holding, "Cool on rack" is basic but acceptably brief
- STYLE: economy: "Carefully remove pot" — "carefully" is a filler adverb; hot pot is self-evident, "it may look like a mess, that's OK" uses 9 words for reassurance; could be trimmed or cut, "Turn dough in seam side up" — stray "in" adds a word (likely typo)

### 12_ocr_biscuits — issues
- STEPS: naming_issues: "Make the dough." is acceptable but slightly generic — could be more specific (e.g., "Mix biscuit dough."), though this is a very minor quibble.
- STYLE: voice: "don't overmix" is mildly advisory but acceptable as recipe-specific guidance
- STYLE: condensation: "with a pastry cutter or two knives" is a minor technique tutorial — an experienced cook knows how to cut in butter
- STYLE: economy: "stir just until dough comes together — don't overmix" is slightly redundant — "just until comes together" already implies not overmixing

### 13_ocr_beef_stew — issues
- FIDELITY: quantities_changed: Onion: 'l large onion' → 'Onion, 1' — dropped 'large' qualifier
- FIDELITY: detritus_retained: Hallucinated description line: 'Better the next day.', Hallucinated tags: 'Tags: comfort-food'
- OUTCOME: outcome_affected: Hallucinated description 'Better the next day.' — not in original, invented tip, Hallucinated 'Tags: comfort-food' — no tags in original
- STEPS: phase_design_issues: Very minor: 'Remove bay leaves before serving' tacked onto the simmer step rather than a brief 'Finish and serve' phase, but for a simple stew this is a reasonable merge.
- STYLE: condensation: "Remove bay leaves before serving" is common-sense advice for experienced cooks

### 15_clean_text_message — issues
- OUTCOME: technique_lost: Cilantro should be chopped 'real small' — OUTPUT marks jalapeño as 'Minced' but gives no prep instruction for cilantro, just 'fold in'
- OUTCOME: outcome_affected: Hallucinated 'Tags: vegan' — original never mentions dietary labels, Hallucinated 'Category: Snacks' — original provides no category, Hallucinated 'bright' in description — 'chunky' traces to source but 'bright' is invented
- STYLE: footer: "Use less jalapeño for milder heat" is common-sense advice — anyone adding jalapeño knows less means milder

### 16_clean_email — issues
- FIDELITY: quantities_changed: Onion lost 'large' size qualifier: '1 large onion' → 'Onion, 1'
- FIDELITY: detritus_retained: Invented description 'Liquid comfort.' not traceable to original, Footer storage advice 'Keep noodles separate from leftover soup — they get mushy stored in the broth' embellishes the original's parenthetical about noodles getting mushy by adding a leftovers/storage angle not in the source
- STEPS: naming_issues: "Add vegetables; finish." — "finish" is vague; it covers cooking vegetables, returning chicken, seasoning, and cooking noodles separately. Something like "Cook vegetables; season and serve." would be more descriptive of the phase's actual work.
- STYLE: voice: "Strain broth if desired" — minor hedge with "if desired"
- STYLE: condensation: "let cool" before shredding is somewhat obvious, though brief
- STYLE: footer: "Lemon squeeze at the table is optional" introduces a new ingredient/suggestion not present anywhere in the recipe body — likely invented by the AI, Noodle separation tip partially restates what instructions already say ("Cook noodles separately; add to each bowl at serving")
- STYLE: economy: Minor redundancy: instructions say "Cook noodles separately; add to each bowl at serving" and footer restates "Keep noodles separate from leftover soup" — the footer adds the WHY (mushiness) but the separation point is made twice
