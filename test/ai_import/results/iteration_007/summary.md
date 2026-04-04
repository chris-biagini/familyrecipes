# Iteration iteration_007

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Style | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-------|-----------|
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 97 | 97 | 96 | 89 | 95.1 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 95 | 93 | 95 | 93 | 94.6 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 95 | 90 | 99 | 96 | 95.8 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 96 | 100 | 96 | 94 | 96.7 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 93 | 97 | 99 | 99 | 97.5 |
| 08_agg_allrecipes | PASS | PASS | 100.0% | 93 | 95 | 99 | 97 | 96.6 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 95 | 97 | 90 | 94 | 94.4 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 90 | 97 | 91 | 97 | 94.4 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 97 | 95 | 100 | 97 | 97.7 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 95 | 100 | 99 | 94 | 97.3 |
| 15_clean_text_message | PASS | PASS | 100.0% | 92 | 95 | 100 | 98 | 96.9 |
| 16_clean_email | PASS | PASS | 100.0% | 93 | 100 | 96 | 89 | 94.9 |

**Overall:** 96.0 avg, 94.4 worst

### 03_blog_serious_eats_c — issues
- STEPS: naming_issues: 'Assemble roll.' is slightly generic — a more descriptive name like 'Roll tenderloin in prosciutto and duxelles.' would better convey the phase of work.
- STEPS: ownership_issues: Egg is listed in step 4 (Wrap in pastry) but also used in step 5 ('remaining beaten egg' for the final egg wash before baking). The beat-once-use-twice approach is practical, but the egg serves a distinct finishing role in step 5 that could warrant listing there as well.
- STEPS: phase_design_issues: Step 2 is quite dense — it contains both duxelles preparation (pulse, sauté, deglaze, finish with cream) and foie gras searing, making it the longest step by far. These are linked by the rendered fat going into the duxelles, which justifies the combination, but it's a lot of work in one phase.
- STYLE: condensation: "a small cast iron or stainless steel skillet" for foie gras sear repeats pan material guidance already established in the first step — experienced cook doesn't need this twice, "with a sharp knife" when trimming puff pastry is borderline common-sense
- STYLE: description: No description for a complex, multi-phase recipe — something like "Worth the effort." or "The full production." would fit the target style
- STYLE: footer: "For best results, use a high-quality all-butter puff pastry such as Dufour" — quality editorializing language ("For best results", "high-quality"), "Maldon or fleur de sel recommended" — brand/quality recommendation
- STYLE: economy: "stir to combine" in "Pour rendered fat into duxelles and stir to combine" — could be tighter ("Stir rendered fat into duxelles")

### 04_blog_smitten_kitchen — issues
- FIDELITY: detritus_retained: 'Tags: freezer-friendly' is invented metadata — original has no tags; freezing is mentioned only in the blog preamble
- OUTCOME: outcome_affected: 'Flaky sea salt' simplified to 'Salt (flaky)' — loses 'sea' specification, 'Freshly ground black pepper' simplified to 'Black pepper' — loses freshly-ground note, Silicone mat dropped as alternative to parchment paper
- STEPS: phase_design_issues: Step 2 is heavily loaded — preheat, mix dry, cut butter, stir in cheese, combine wet, knead, roll, cut, top, and bake all in one step. A three-step split (caramelize onions / make dough / shape and bake) would better match the natural phases, though the current two-step version is defensible since everything after onions flows sequentially.
- STYLE: condensation: "Line a baking sheet with parchment" is generic boilerplate, "A few floury spots are fine" borders on hand-holding, though it does convey a recipe-specific 'don't overwork' cue
- STYLE: description: No description for a non-trivial recipe — a punchy one-liner (e.g. 'Cheesy, caramelized, flaky.') would add personality
- STYLE: footer: Cannot fully verify substitution notes (Swiss-style cheese, coarse/kosher salt) and storage tips originate from the source rather than being AI-added
- STYLE: economy: "stir to combine" appears twice in quick succession in the dough paragraph — the second instance could be replaced (e.g. 'stir until dough just comes together')

### 05_blog_budget_bytes — issues
- FIDELITY: detritus_retained: Fabricated source website name 'Budget Bytes' and URL not present in original text
- OUTCOME: outcome_affected: Attribution changed from 'Beth Moncel' to fabricated 'Budget Bytes' with invented URL — embellished attribution
- STEPS: phase_design_issues: Step 1 is relatively dense — it covers three sub-bowls (wet, dry, main) plus shaping — but this maps to a single natural 'build the loaf' phase, so it's a very minor density concern rather than a structural flaw.
- STYLE: condensation: Preheat instruction is borderline but justified by timing (oven needs to be ready when shaping is done)
- STYLE: description: No description present — acceptable but a punchy one-liner would add character for a recipe with two distinct phases and a glaze
- STYLE: footer: 'Use 80/20 ground beef' note somewhat restates what's already specified in the ingredient list — the explanation of why is useful but the repetition is slight

### 06_blog_pioneer_woman — issues
- OUTCOME: outcome_affected: 'Ground cumin' and 'ground oregano' shortened to 'Cumin' and 'Oregano' — an experienced cook would infer ground in this context, but the specification is technically less precise
- STEPS: ownership_issues: Toppings (shredded cheddar, crumbled bacon, sliced jalapeños) were listed as ingredients in the original but are omitted from all step ingredient lists and only mentioned in the footer note. While they are optional garnishes, they could reasonably appear under 'Finish and serve.'
- STYLE: condensation: "Rinse canned beans before using" in footer is redundant — ingredient line already says "Drained and rinsed", "Chili powder, salt, and cayenne may all be adjusted to taste" is generic cooking advice
- STYLE: footer: Bean rinsing note duplicates information already encoded in the ingredient annotation, "may all be adjusted to taste" reads as generic AI-added advice rather than source-specific guidance
- STYLE: economy: "they can be slimy straight out of the can" is editorial filler in the footer, "may all be adjusted" — "may all be" is slack; "Adjust chili powder, salt, and cayenne to taste" is tighter

### 07_blog_bon_appetit — issues
- FIDELITY: quantities_changed: Extra-virgin olive oil simplified to 'olive oil' — loses the extra-virgin specification
- OUTCOME: technique_lost: 'Place a rack in middle of oven' — specific rack positioning omitted
- STEPS: naming_issues: "Make the filling." and "Make the batter." are clear but slightly generic — could be more descriptive of the specific work (e.g., "Cook the filling; rest to thicken." or "Blend the popover batter.")
- STYLE: voice: "adjust mustard, salt, and pepper as needed" — mild hedging; exemplar style would be "Correct for mustard, salt, and pepper" with no "as needed"

### 08_agg_allrecipes — issues
- OUTCOME: outcome_affected: Oregano listed without 'dried' qualifier — original specifies 'dried oregano'; an experienced cook would likely default to dried in a marinade but the distinction is dropped
- STEPS: naming_issues: "Assemble and press." is slightly underspecified — "Assemble sandwiches; press and toast." would capture both the assembly and the final cooking, but "press" is understood idiom for cubanos.
- STYLE: condensation: Footer contains a generic skillet temperature test ('sprinkle a few drops of water') — generic technique an experienced cook already knows
- STYLE: footer: Skillet water-drop test is generic cooking technique that reads like an AI-added 'helpful tip' — uncertain whether it was in the source

### 10_agg_epicurious — issues
- STEPS: phase_design_issues: Step 3 combines vegetable cooking, meat prep, assembly, and serving — the meat-from-bone prep could justify its own step or at minimum be separated from the vegetable cook phase
- STEPS: disentanglement_issues: 'Meanwhile, cut meat from bone' is left interleaved in step 3 alongside the potato cooking — this parallel operation should be separated into its own step (e.g., 'Prep the meat.') as in the Veggie Hash calibration pattern
- STYLE: condensation: "carefully poke a hole" — "carefully" is mild hand-holding, "reserve the rest for another use" is generic cooking advice an experienced cook doesn't need
- STYLE: description: No description for a non-trivial recipe — a punchy one-liner like "Short ribs braised low and slow in foil." would add value
- STYLE: economy: "carefully" in "carefully poke a hole" adds little for the target audience, "reserve the rest for another use" is a redundant aside — implicit to an experienced cook

### 11_agg_nyt_style — issues
- FIDELITY: ingredients_missing: wheat bran as equal alternative to cornmeal (demoted to footer substitution instead of listed as equal option in ingredient list and instructions)
- FIDELITY: quantities_changed: Yield changed from 'One 1 1/2-pound loaf' to '1 loaf' — weight dropped, 'At least a half-hour before' changed to 'About 30 minutes before' — original implies a minimum, output implies an approximation
- OUTCOME: outcome_affected: Wheat bran dropped from Step 2 instructions ('flour, wheat bran or cornmeal' → 'flour or cornmeal') — the original presents three equal dusting options but the output only offers two in-line, relegating wheat bran to a footer substitution note
- STEPS: naming_issues: "Shape; second rise." — 'second rise' is a noun phrase rather than imperative; 'Shape dough; let rise.' would be more consistent, "Bake." is functional but generic; a more descriptive name like "Bake in covered pot." would better describe the phase
- STEPS: disentanglement_issues: Oven preheat must begin 30 minutes before the second rise ends (a parallel operation), but it's placed in the 'Bake.' step rather than flagged at the end of 'Shape; second rise.' — minor timing overlap preserved
- STYLE: voice: "it may look messy, that's fine" is slightly conversational/reassuring — addresses the reader indirectly, "carefully remove pot" — mild hand-holding via adverb
- STYLE: condensation: "carefully remove pot" — "carefully" is common-sense for a 450°F pot, "it may look messy, that's fine" — borderline reassurance, though recipe-specific
- STYLE: economy: "beautifully browned" — "beautifully" is ornamental; "deep golden" or just "browned" would be tighter, "it may look messy, that's fine" — could be tightened to "it will look messy" or omitted

### 12_ocr_biscuits — issues
- STYLE: condensation: "lightly floured surface" is mildly hand-holding for an experienced cook
- STYLE: description: No description present — acceptable for simple recipes but a punchy one-liner would suit a recipe with specific technique notes

### 13_ocr_beef_stew — issues
- FIDELITY: quantities_changed: Onion: original says '1 large onion' but output says 'Onion, 1' — dropped 'large' size qualifier
- STEPS: naming_issues: "Build and simmer." — "Build" lacks a direct object; "Build stew; simmer." or "Add vegetables and simmer." would be slightly more descriptive.
- STYLE: condensation: "Remove bay leaves before serving" is common sense for an expert cook who just added bay leaves, Ingredient prep notes like "Peeled and sliced" (peeling carrots is obvious), "Diced", "Minced" are basic knowledge for experienced cooks
- STYLE: description: No description present — acceptable but a punchy one-liner would add character to a classic recipe
- STYLE: prose: Second paragraph has a slightly mechanical cadence with four consecutive "Add/Return" sentences, though still reads as prose

### 15_clean_text_message — issues
- FIDELITY: quantities_changed: Jalapeño listed as fixed '1/2' — original says 'half a jalapeño or less if u dont like spicy' (range/flexibility lost from ingredient line, partially compensated by footer note)
- OUTCOME: outcome_affected: 'Chunky, not fussy' description — 'not fussy' is invented editorial characterization not in the original
- STYLE: footer: "Use less jalapeño for less heat" is self-evident and reads like an AI-added helpful tip rather than source-provided context

### 16_clean_email — issues
- FIDELITY: quantities_changed: Onion: original says '1 large onion', output says 'Onion, 1' — dropped 'large' qualifier
- OUTCOME: outcome_affected: Carrots: original specifies 'peeled and sliced', output says only 'Sliced' — minor, experienced cooks would peel anyway, 'Black pepper' specified in output where original just says 'pepper' — trivial specification, not a meaningful change
- STEPS: naming_issues: "Build the soup." is slightly generic — a semicolon name like "Cook vegetables; finish the soup." would better describe the phase of work (adding veg, returning chicken, seasoning, noodle strategy).
- STYLE: voice: "Strain broth if desired" — hedging with "if desired"
- STYLE: condensation: "discard skin and bones" — obvious to experienced cook, "cool slightly" — common-sense advice, "to prevent mushiness" — quality editorializing / tutorial explanation
- STYLE: description: No description present — multi-step recipe would benefit from a punchy one-liner (cf. "Mom's famous baked pasta.")
- STYLE: footer: "is optional" is hedging — tighter as just "A squeeze of lemon at the table."
- STYLE: economy: "to prevent mushiness" — explanatory padding; the instruction to cook separately is sufficient, "if desired" — filler hedge
