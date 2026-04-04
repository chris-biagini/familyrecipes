# Iteration iteration_009

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Style | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-------|-----------|
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 96 | 97 | 99 | 91 | 96.1 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 95 | 98 | 98 | 86 | 94.6 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 96 | 97 | 97 | 98 | 97.4 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 95 | 100 | 96 | 95 | 96.8 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 97 | 97 | 96 | 99 | 97.6 |
| 08_agg_allrecipes | PASS | PASS | 100.0% | 97 | 95 | 97 | 94 | 96.2 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 90 | 100 | 88 | 97 | 94.3 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 90 | 97 | 92 | 97 | 94.7 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 100 | 100 | 100 | 93 | 98.3 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 90 | 100 | 98 | 95 | 96.3 |
| 15_clean_text_message | PASS | PASS | 100.0% | 95 | 95 | 100 | 100 | 98.0 |
| 16_clean_email | PASS | PASS | 100.0% | 95 | 95 | 99 | 87 | 94.5 |

**Overall:** 96.2 avg, 94.3 worst

### 03_blog_serious_eats_c — issues
- STEPS: phase_design_issues: Step 2 is quite dense (4 paragraphs covering both duxelles and foie gras searing), though combining them is justified by the rendered fat flowing into the duxelles mixture.
- STYLE: voice: "when you shake the pan" — uses "you" in instructions
- STYLE: condensation: "Loosen from foil with a thin spatula" is mildly hand-holdy, Specifying "cast iron or stainless steel skillet" twice reads slightly tutorial-ish
- STYLE: description: No description provided for a complex multi-step recipe — a punchy one-liner like "Worth the effort." would be ideal
- STYLE: footer: "Use high-quality all-butter puff pastry" is mild quality editorializing
- STYLE: economy: "stir to combine" after "Pour rendered fat into mushroom mixture" is slightly formulaic

### 04_blog_smitten_kitchen — issues
- FIDELITY: quantities_changed: Butter gram weight (127 grams) dropped; tablespoon measure retained, Gruyère volume measure ('about 1 cup') dropped; weight (4 oz / 115g) retained
- OUTCOME: outcome_affected: 'Freshly ground black pepper' simplified to 'Black pepper' — drops freshness specification, Silicone mat dropped as alternative to parchment paper for lining baking sheet
- STEPS: phase_design_issues: Step 2 is quite dense — preheating, mixing dry ingredients, cutting butter, incorporating wet, rolling, cutting, and baking — but for an experienced cook these form one continuous workflow after the onions cool, so this is a minor quibble rather than a real problem.
- STYLE: voice: "using hands to bring it together if needed" borders on addressing the reader, though technically imperative
- STYLE: condensation: "use fingertips, a pastry blender, or food processor pulses" is a technique tutorial — experienced cooks know how to cut butter into flour, "a few floury spots are fine" is mild hand-holding (though it does serve as a 'don't overmix' cue), "Buttermilk can be made at home" in footer is generic cooking advice
- STYLE: description: No description present — a punchy one-liner would suit a recipe with this much character (e.g. 'Savory biscuits with sweet onion and melty cheese.')
- STYLE: prose: Second paragraph of step 2 is quite dense — a lot packed into one paragraph, though it still reads as natural prose
- STYLE: footer: "Buttermilk can be made at home" feels like generic AI-added advice rather than source content, Substitution notes (kosher salt, Swiss-style cheese) may be AI-invented rather than from the source
- STYLE: economy: "In a bowl or food processor" followed by "Transfer to bowl if using a processor" creates branching wordiness — pick one path or streamline, "use fingertips, a pastry blender, or food processor pulses" — listing three tool options adds bulk, "stir to combine, using hands to bring it together if needed" is slightly wordy

### 05_blog_budget_bytes — issues
- STYLE: voice: "In a separate bowl" retains article where dropping might be slightly more natural, though it reads fine
- STYLE: condensation: "in a large bowl" is borderline hand-holding (experienced cook would size the bowl), though it also communicates practical info
- STYLE: economy: "together" in "Stir glaze ingredients together" is slightly redundant

### 06_blog_pioneer_woman — issues
- OUTCOME: outcome_affected: 'Ground cumin' and 'ground oregano' shortened to 'Cumin' and 'Oregano' — an expert would default to ground, but the specificity is lost
- STEPS: naming_issues: 'Build chili' in the first step name is slightly vague — 'simmer with spices' or similar would more precisely describe the hour-long cooking phase.
- STEPS: phase_design_issues: First step covers both browning beef and a 1-hour simmer with spices — borderline heavy for one step, though defensible since it's sequential one-pot work.
- STYLE: condensation: "In a large heavy pot" is borderline generic, though heavy pot is arguably recipe-relevant for long simmering
- STYLE: footer: Footer note about toppings largely restates what's already in the instructions ('Top with cheddar, bacon, and jalapeños'), Cornmeal substitution for masa harina cannot be verified as originating from the source
- STYLE: economy: Redundancy between instructions ('Top with cheddar, bacon, and jalapeños') and footer ('Cheddar, bacon, and jalapeños are suggested toppings')

### 07_blog_bon_appetit — issues
- STEPS: naming_issues: "Bake." is generic — doesn't capture the assembly action (pouring batter over filling). "Assemble and bake." would better describe the phase of work.
- STEPS: phase_design_issues: The 'Bake' step has no ingredients and only two brief sentences — it's a legitimate assembly+oven phase but borders on thin. Could merge the pour-over action into the batter step, leaving only a one-liner bake note, or keep as-is with a more descriptive name.
- STYLE: economy: "Let sit undisturbed ... do not stir" — "undisturbed" and "do not stir" overlap slightly; "on the surface" in the same sentence is also filler (where else would a skin form?)

### 08_agg_allrecipes — issues
- STYLE: voice: "when ready to use" is slightly soft/vague phrasing, though it communicates a legitimate timing instruction
- STYLE: condensation: "To test: sprinkle water on surface — it should sizzle and evaporate immediately" is a generic technique tutorial for judging skillet heat — an experienced cook doesn't need this
- STYLE: footer: Cannot fully verify the pulled-pork substitution originated from the source rather than being AI-added
- STYLE: economy: The skillet water-test sentence adds ~15 words of generic technique that could be cut entirely

### 10_agg_epicurious — issues
- FIDELITY: quantities_changed: Onion: '1 large yellow onion' → 'Onion, 1' — missing 'large' size qualifier and 'yellow' variety
- OUTCOME: outcome_affected: Parsley: 'fresh parsley leaves' → 'Parsley' — missing 'fresh' qualifier; an experienced cook would likely assume fresh for a garnish, but dried parsley is a different product, Black pepper: 'freshly ground' qualifier dropped — trivial for an experienced cook
- STEPS: naming_issues: 'Cook vegetables.' is slightly generic — something like 'Cook onions and potatoes in braising liquid.' would better describe the phase of work.
- STEPS: phase_design_issues: Step 1 is overloaded: it covers making the paste, searing, 4-hour braise, draining liquid, 1-hour refrigeration, and 1-hour freezing — multiple distinct activities spanning ~6 hours crammed into one phase. The fat separation/defatting is a distinct waiting phase that could stand alone or be folded into the top of step 2., Fat separation process is awkwardly split: refrigerating/freezing described in step 1, but removing the fat cap is the opening instruction of step 2.
- STEPS: disentanglement_issues: Step 3 retains interleaved language: 'While potatoes cook, cut meat from bone' — the meat cutting happens during step 2's cook time but is written as a sequential instruction in step 3. Ideally the meat prep would be its own step or placed during the 2-hour resting period in step 1.
- STYLE: description: No description present; a complex recipe with a named source (Good Eats / Alton Brown) would benefit from a punchy one-liner like 'Alton Brown's braised short rib stew.'
- STYLE: footer: No explicit author attribution beyond the title — a 'From Alton Brown / Good Eats' line would be cleaner

### 11_agg_nyt_style — issues
- FIDELITY: quantities_changed: Flour: gram weight (430g) dropped, volume (3 1/3 cups) preserved, Yeast: gram weight (1g) dropped, volume (generous 1/4 tsp) preserved, Salt: gram weight (8g) dropped, volume (2 tsp) preserved, Water: gram weight (345g) dropped, volume (1 1/2 cups) preserved
- OUTCOME: outcome_affected: Wheat bran demoted from equal alternative (used interchangeably with flour/cornmeal for dusting towel and dough in original) to a footer substitution note for cornmeal only — an experienced cook following the OUTPUT would default to cornmeal rather than choosing freely among three options, Step 3 dusting instruction 'dust with more flour, bran or cornmeal' simplified to just 'dust top' — loses specificity of what to dust with, though context implies flour or cornmeal
- STEPS: ownership_issues: Flour is used for dusting in step 2 (work surface, shaping, towel) but is only listed as an ingredient in step 1; the original explicitly notes 'plus more for dusting' — a small dusting flour note in step 2 would clarify ownership.
- STEPS: disentanglement_issues: Oven preheat is a parallel operation that begins during the proofing phase ('at least 30 minutes before dough is ready') but is placed in the Bake step rather than being noted at the end of the proof step or given its own phase — the cook must read ahead to start preheating on time.
- STYLE: voice: "it may look like a mess but will straighten as it bakes" is slightly conversational/reassuring — borderline editorializing rather than pure imperative instruction
- STYLE: condensation: "cast iron, enamel, Pyrex, or ceramic" — listing acceptable pot materials is mildly tutorial-like, though arguably recipe-specific since the covered-pot technique is the key innovation, "Cool on a rack" is a generic instruction most experienced cooks would assume
- STYLE: economy: "it may look like a mess but will straighten as it bakes" is slightly wordy — the reassurance is useful but could be tighter (e.g., "will look messy; it'll even out")

### 12_ocr_biscuits — issues
- STYLE: voice: "don't overmix" is borderline advisory but acceptable as recipe-specific technique for biscuit dough
- STYLE: condensation: "using a pastry cutter or two knives" is a technique tutorial — an experienced cook knows how to cut in butter, "Preheat oven to 425°F" is a generic preheat reminder; could be folded into the bake step or omitted
- STYLE: description: No description present — acceptable for simple recipes but a punchy one-liner like "Flaky, buttery, classic." would elevate it
- STYLE: economy: "using a pastry cutter or two knives" adds words an expert doesn't need — "Cut in butter until mixture resembles coarse crumbs" is sufficient

### 13_ocr_beef_stew — issues
- FIDELITY: quantities_changed: Onion: '1 large onion' → 'Onion, 1' — dropped 'large' size qualifier, Thyme: '1 teaspoon dried thyme' → 'Thyme, 1 tsp' — dropped 'dried' qualifier; an experienced cook seeing just 'Thyme, 1 tsp' could use fresh, which behaves differently at the same volume
- STYLE: condensation: "Remove bay leaves before serving" is borderline common-sense for an experienced cook, though defensible since bay leaves are in the ingredient list
- STYLE: description: No description present; absent is acceptable for very simple recipes but beef stew is a multi-step dish that could benefit from a punchy one-liner

### 16_clean_email — issues
- FIDELITY: quantities_changed: Onion: '1 large onion' changed to '1' — lost 'large' size descriptor
- OUTCOME: outcome_affected: 'fresh dill' simplified to 'dill' — 'sprigs' implies fresh but the explicit 'fresh' qualifier was dropped, which could lead an experienced cook to consider dried dill acceptable, Pepper specified as 'Black pepper' where original just says 'pepper' — minor addition of specificity not in source
- STEPS: phase_design_issues: Egg noodles require their own cooking (boil separately) but are grouped under 'Finish and serve' alongside seasoning — a minor mismatch since cooking noodles is an active cooking task, not a finishing garnish. Borderline acceptable since it's just 'boil and add to bowls.'
- STYLE: voice: "if desired" is mild hedging language, "they get mushy if left in the soup" is a conversational aside explaining rationale to the reader
- STYLE: condensation: "they get mushy if left in the soup" is common-sense advice an experienced cook already knows, "Strain broth if desired" is generic cooking advice
- STYLE: description: No description present; a personal recipe like "Mom's Chicken Soup" would benefit from a punchy one-liner (cf. "Mom's famous baked pasta.")
- STYLE: prose: Parenthetical explanation "(they get mushy if left in the soup)" slightly interrupts prose flow
- STYLE: footer: Lemon footer note is slightly redundant — already marked "Optional" in the ingredient list
- STYLE: economy: "in a large pot" is implicit for a whole chicken recipe, "they get mushy if left in the soup" adds words to explain something the instruction already handles ("Cook noodles separately; add to each bowl when serving")
