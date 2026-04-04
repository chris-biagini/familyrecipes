# Iteration iteration_008

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Style | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-------|-----------|
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 95 | 95 | 98 | 94 | 96.0 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 96 | 95 | 99 | 95 | 96.7 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 94 | 92 | 99 | 97 | 96.2 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 95 | 95 | 99 | 92 | 95.8 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 97 | 98 | 97 | 100 | 98.3 |
| 08_agg_allrecipes | PASS | PASS | 100.0% | 96 | 97 | 98 | 98 | 97.6 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 93 | 98 | 90 | 96 | 94.7 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 93 | 97 | 91 | 96 | 94.8 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 100 | 100 | 97 | 96 | 98.3 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 93 | 100 | 99 | 95 | 97.1 |
| 15_clean_text_message | PASS | PASS | 100.0% | 92 | 88 | 100 | 94 | 94.5 |
| 16_clean_email | PASS | PASS | 100.0% | 92 | 97 | 98 | 96 | 96.3 |

**Overall:** 96.4 avg, 94.5 worst

### 03_blog_serious_eats_c — issues
- STEPS: ownership_issues: Salt and pepper are listed only in step 1 but step 2 instructions say 'Season with salt and pepper' twice (for duxelles and foie gras); ubiquitous-ingredient exception applies but re-listing in step 2 would be cleaner.
- STEPS: phase_design_issues: Step 2 is quite dense — 9 ingredients and two distinct cooking operations (duxelles ~12 min, then foie gras searing in a separate pan) — but the foie gras fat → duxelles dependency and the semicolon name justify the grouping.
- STYLE: condensation: "scraping up browned bits" is a generic deglazing instruction, though brief enough to be minor
- STYLE: description: No description present — a punchy one-liner like "Worth the effort." would be ideal for a complex holiday recipe; absence is more appropriate for simple recipes
- STYLE: footer: Some substitution suggestions (spicy brown/hot English mustard, bourbon for cognac) may be AI-invented rather than sourced from the original Serious Eats recipe
- STYLE: economy: "stir to combine" in the rendered fat instruction could be just "stir in", "Chill all components at least 30 minutes" slightly redundant after multiple preceding "refrigerate" instructions

### 04_blog_smitten_kitchen — issues
- FIDELITY: detritus_retained: "Pretty much perfect." is condensed blog commentary about the author's opinion, not a description of the dish itself
- STEPS: phase_design_issues: Step 2 is quite dense — covers preheating, mixing dry ingredients, cutting butter, combining wet/dry, kneading, rolling/cutting, and baking — but these flow as one continuous biscuit-making workflow with no natural pause point, so the 2-step split is appropriate.
- STYLE: voice: "a few floury spots are fine" is slightly reassuring/hand-holdy, though it doubles as a useful visual cue
- STYLE: condensation: "Buttermilk can be made at home" in footer is generic advice without specifics, "Line a baking sheet with parchment" is a standard step most experienced cooks don't need
- STYLE: footer: "Buttermilk can be made at home" is vague and generic — if from the source it would likely include the method (acid + milk ratio); as-is it reads like an invented addition

### 05_blog_budget_bytes — issues
- FIDELITY: quantities_changed: Egg: '1 large egg' → 'Egg, 1' — dropped 'large' size specification
- FIDELITY: detritus_retained: Fabricated budgetbytes.com URL in attribution is non-source content
- OUTCOME: outcome_affected: Fabricated URL (budgetbytes.com) added to attribution — original only names Beth Moncel with no link
- STYLE: condensation: "don't overwork" is borderline generic meatloaf advice, though it's also recipe-specific enough to justify keeping
- STYLE: footer: "Use 80/20 ground beef — the fat content keeps the loaf from drying out" is redundant with the ingredient list already specifying 80/20 and reads like an AI-added helpful tip, "Reduce brown sugar to 1/2 tbsp if you prefer a less sweet glaze" may be an invented substitution not present in the source

### 06_blog_pioneer_woman — issues
- OUTCOME: outcome_affected: 'ground cumin' simplified to 'cumin' and 'ground oregano' simplified to 'oregano' — an expert cook might use dried oregano leaves instead of ground, slightly changing texture
- STEPS: phase_design_issues: Minor: the first step encompasses both browning (active work) and a 1-hour simmer (passive), which could justify a split, but combining them is defensible since the spice addition follows immediately in the same pot with no other work to do during the simmer.
- STYLE: voice: "leaving a little for flavor" is slightly explanatory/editorial, though still natural
- STYLE: condensation: "Taste and adjust seasoning" is generic cooking advice, "leaving a little for flavor" explains a common-sense rationale an experienced cook wouldn't need
- STYLE: description: No description present — chili is self-explanatory enough to justify absence, but a punchy one-liner (e.g. "Ree Drummond's classic.") would strengthen it
- STYLE: footer: Cornmeal substitution may be AI-invented rather than from source, Attribution is clean and properly placed
- STYLE: economy: "leaving a little for flavor" adds 5 words of rationale that could be cut — just "Drain most fat" implies keeping some

### 07_blog_bon_appetit — issues
- STEPS: naming_issues: Both filling and batter steps use the generic 'Make the X' pattern; slightly more descriptive names like 'Cook vegetables; build the filling.' or 'Blend the popover batter.' would better convey the work involved.
- STEPS: phase_design_issues: The 'Pour and bake' step has no ingredients and is relatively brief (two sentences), though it represents a genuinely distinct assembly/baking phase so this is a minor quibble.

### 08_agg_allrecipes — issues
- FIDELITY: quantities_changed: ground coriander → Coriander (dropped 'ground' qualifier)
- STEPS: phase_design_issues: Step 1 is an optional sub-recipe (original offers 'or pulled pork' as alternative) presented as a regular mandatory step; the substitution note at the bottom partially mitigates this but the step itself gives no indication it can be skipped.
- STYLE: condensation: "for easier slicing" is a minor explanatory aside, though it's recipe-specific (thin slicing requires chilled pork)
- STYLE: footer: Cannot confirm the pulled pork substitution originates from the source recipe; may be invented

### 10_agg_epicurious — issues
- FIDELITY: quantities_changed: Onion: '1 large yellow onion' → 'Onion, 1' — missing 'large' size and 'yellow' variety
- OUTCOME: outcome_affected: 'freshly ground' dropped from black pepper descriptor — minor
- STEPS: phase_design_issues: Step 1 covers a very long arc (paste → sear → 4-hour braise → drain → 2-hour cooling/freezing cycle) with multiple distinct sub-phases; separating the fat-separation/cooling into its own step or folding the meat prep into it would better match the natural rhythm of the recipe.
- STEPS: disentanglement_issues: 'Meanwhile, cut meat from bone' in step 2 preserves the source's interleaved structure — meat prep during the 30-minute potato simmer is a parallel operation that could have been placed at the end of step 1 (ribs are resting at room temperature) or given its own brief step.
- STYLE: description: No description present; this is a complex multi-hour braise-to-stew recipe that would benefit from a punchy one-liner (e.g. 'Short ribs braised into stew.')

### 11_agg_nyt_style — issues
- FIDELITY: quantities_changed: Yield changed from 'One 1 1/2-pound loaf' to '1 loaf' — weight specification dropped
- OUTCOME: technique_lost: Original allows flour, wheat bran, or cornmeal for coating the towel and dusting the dough; OUTPUT narrows to only cornmeal (wheat bran offered as footer substitute, but flour option for towel coating is dropped)
- STEPS: naming_issues: "Shape; proof." and "Bake." are well-formed but quite terse — slightly more descriptive names like "Shape dough; proof." or "Bake in Dutch oven." would better describe the phase of work.
- STEPS: disentanglement_issues: Preheating the oven ("at least 30 minutes before dough is ready") is a parallel operation that should begin during the 2-hour proof, but it's placed entirely in the Bake step. A cook reading linearly would finish the Shape/Proof step, wait 2 hours, then discover they should have started preheating 30 minutes ago. A note at the end of the proof step or a separate preheat mention would fully disentangle this.
- STYLE: voice: "it may look like a mess" is slightly conversational/reassuring — borderline hedging
- STYLE: condensation: "carefully remove pot" — "carefully" is hand-holding, "to prevent sticking" explains the obvious, "Cool on rack" is generic/basic
- STYLE: economy: "carefully" in "carefully remove pot" is filler, "to prevent sticking" is an unnecessary explanation, "beautifully browned" — "beautifully" is slightly editorializing

### 12_ocr_biscuits — issues
- STEPS: phase_design_issues: Borderline implicit/explicit — recipe has exactly 5 ingredients, but the two distinct paragraphs of instructions (mix vs. shape/bake) justify explicit steps. Two steps is a reasonable fit.
- STYLE: condensation: "do not overmix" is generic baking advice — an experienced cook knows not to overwork biscuit dough, "lightly floured surface" is standard/obvious for shaping any dough
- STYLE: description: No description present — acceptable for a simple classic, but a punchy one-liner would elevate it
- STYLE: economy: "stir just until dough comes together — do not overmix" is slightly redundant — "just until" already implies minimal mixing

### 13_ocr_beef_stew — issues
- FIDELITY: quantities_changed: Onion: 'l large onion' → 'Onion, 1' — dropped 'large' size qualifier, Thyme: 'l teaspoon dried thyme' → 'Thyme, 1 tsp' — dropped 'dried' qualifier, ambiguous between fresh and dried
- STEPS: phase_design_issues: Minor: 'Remove bay leaves before serving' tacked onto the end of step 2 could justify a brief 'Finish and serve.' step (cf. calibration exemplar), but it's a single trivial instruction so folding it in is defensible.
- STYLE: condensation: "Remove bay leaves before serving" is mild hand-holding — experienced cooks know to remove bay leaves
- STYLE: description: No description present — beef stew is a multi-step recipe with enough character to warrant a punchy one-liner (e.g. "Classic Dutch oven comfort.")

### 15_clean_text_message — issues
- FIDELITY: detritus_retained: Footer note "Use less jalapeño for milder heat" — while traceable to the original's "or less if u dont like spicy", it's reformatted as a standalone tip/advice line rather than kept as part of the ingredient specification
- STYLE: condensation: Footer tip 'Use less jalapeño for milder heat' is common-sense advice — anyone who knows what a jalapeño is knows this
- STYLE: footer: 'Use less jalapeño for milder heat' reads like an AI-added common-sense tip rather than source content
- STYLE: economy: 'keep it chunky' appears in both the description and the instructions — redundant restatement

### 16_clean_email — issues
- FIDELITY: quantities_changed: Onion: '1 large onion' → 'Onion, 1' — dropped 'large' qualifier
- OUTCOME: outcome_affected: Dill listed as 'Dill, a few sprigs' instead of 'fresh dill' — though 'sprigs' implies fresh, the explicit 'fresh' qualifier was dropped
- STEPS: ownership_issues: Lemon is listed as an ingredient in Step 3 but its only usage instruction appears in the footer note below the separator, slightly disconnecting the ingredient from its serving context.
- STEPS: phase_design_issues: Step 2 packs several distinct operations (remove chicken, cool, shred, discard bones, optionally strain broth, add vegetables, cook, return chicken) — could arguably split 'shred chicken' from 'build soup', though they do flow as one continuous post-simmer phase.
- STYLE: voice: "Strain broth if desired" — "if desired" is hedging language, similar to flagged patterns like "if you like"
- STYLE: condensation: "to prevent mushiness" is borderline explanatory, though it is recipe-specific advice about serving noodles separately
- STYLE: footer: "Lemon is squeezed at the table" uses passive voice — imperative "Squeeze lemon at the table" would match the recipe's voice better
