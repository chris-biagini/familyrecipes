# Iteration iteration_011

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Style | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-------|-----------|
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 96 | 97 | 93 | 91 | 94.6 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 96 | 92 | 97 | 96 | 95.9 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 97 | 100 | 99 | 96 | 98.2 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 96 | 98 | 96 | 95 | 96.6 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 97 | 97 | 99 | 100 | 98.6 |
| 08_agg_allrecipes | PASS | PASS | 100.0% | 93 | 97 | 98 | 98 | 97.0 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 92 | 97 | 97 | 95 | 95.8 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 95 | 95 | 97 | 95 | 96.0 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 100 | 100 | 97 | 97 | 98.5 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 96 | 100 | 98 | 92 | 96.7 |
| 15_clean_text_message | PASS | PASS | 100.0% | 85 | 95 | 100 | 99 | 95.8 |
| 16_clean_email | PASS | PASS | 100.0% | 93 | 95 | 99 | 95 | 96.1 |

**Overall:** 96.6 avg, 94.6 worst

### 03_blog_serious_eats_c — issues
- STEPS: naming_issues: Step 1 name 'Sear beef; make duxelles.' omits foie gras searing, which is a significant sub-operation within that phase.
- STEPS: phase_design_issues: Step 1 is extremely dense — packs 7 of the original 14 steps into one phase with 14 ingredients and 4 paragraphs covering searing beef, mustard rub, full duxelles preparation, AND foie gras searing. A 4th phase splitting beef searing from duxelles/foie gras would better match this recipe's complexity.
- STYLE: condensation: Footer contains quality editorializing: "Use high-quality all-butter puff pastry such as Dufour for best results"
- STYLE: description: No description present; Beef Wellington is a complex, multi-step recipe that would benefit from a punchy one-liner like "Worth the effort."
- STYLE: footer: "for best results" is minor quality editorializing
- STYLE: economy: "and stir to combine" after pouring rendered fat into mushroom mixture is functional but slightly formulaic

### 04_blog_smitten_kitchen — issues
- FIDELITY: detritus_retained: Fabricated one-line description 'Big, cheesy, worth the onion time.' — not present in original
- STEPS: phase_design_issues: Step 2 encompasses preheating, mixing dry ingredients, cutting in butter, adding cheese, combining wet/dry, kneading, rolling, cutting, and baking — it's a lot for one step, though for experienced cooks it reads as one continuous workflow.
- STYLE: condensation: "Line a baking sheet with parchment" is borderline generic but brief enough to not be a real problem
- STYLE: footer: Substitution suggestions (Swiss-style cheese, coarse salt) may be AI-invented rather than from the source — cannot verify without the original

### 05_blog_budget_bytes — issues
- STEPS: phase_design_issues: First step handles several sub-operations (whisk egg mixture, combine breadcrumb mixture, combine all, shape) — a lot of work in one phase, but reasonable for experienced cooks and mirrors the original's MEATLOAF/GLAZE ingredient grouping.
- STYLE: condensation: Preheat instruction is placed in the 'Mix and shape' step, which is reasonable for timing but borderline
- STYLE: footer: 80/20 beef note in footer is partially redundant with ingredient list already specifying '(80/20)', Brown sugar reduction tip may be an invented substitution not present in the source
- STYLE: economy: 'Stir glaze ingredients together' is slightly wordy — ingredients are listed directly above, 'Stir together' would suffice

### 06_blog_pioneer_woman — issues
- STEPS: naming_issues: "Build and simmer." — "Build" is slightly vague; something like "Brown beef; build and simmer." would better describe the browning sub-action that starts the step.
- STYLE: condensation: Footer note "Canned beans can be slimy straight from the can — rinse well" is generic cooking advice, not recipe-specific
- STYLE: footer: "Canned beans can be slimy straight from the can — rinse well" reads as generic added advice rather than source content, "Substitute cornmeal for masa harina" may be AI-invented — unclear if from source
- STYLE: economy: "Drain most of the fat, leaving a little" — "leaving a little" is implied by "most", slightly redundant, "stir" appears twice in quick succession in "Stir beans into chili, then stir in masa slurry"

### 07_blog_bon_appetit — issues
- STEPS: phase_design_issues: Filling step is dense with 17 ingredients and two substantial instruction paragraphs, but this is defensible since it's one continuous stovetop process

### 08_agg_allrecipes — issues
- OUTCOME: technique_lost: Cut each bread loaf in half crosswise (3 loaves become 6 sandwich portions) — OUTPUT says only 'Split' but omits the crosswise cut that yields 6 servings
- OUTCOME: outcome_affected: Without the crosswise cut instruction, a cook could make 3 long sandwiches instead of 6 shorter ones, though an experienced cook could infer this from the 12 cheese slices / 2 per sandwich math
- STEPS: naming_issues: 'Assemble and press.' is slightly generic — a semicolon variant like 'Assemble sandwiches; press and toast.' would better convey that the pressing step involves further cooking, but the current name is concise and acceptable.
- STEPS: phase_design_issues: The advance prep step is fairly long with two paragraphs of instruction, but this is justified for a roasting operation with marination and overnight chill. Three phases map cleanly to the natural workflow: long-lead roast, skillet prep, and final assembly.
- STYLE: footer: Cannot verify whether the pulled pork substitution note originated from the source or was added by the AI

### 10_agg_epicurious — issues
- OUTCOME: technique_lost: Original specifies using a griddle (listed as Specialized Hardware) for searing the ribs; OUTPUT just says 'sear over medium-high heat' without mentioning the griddle
- OUTCOME: outcome_affected: 'yellow' dropped from onion descriptor — very minor since yellow is the default, but original specifies it
- STEPS: phase_design_issues: Step 2 (drain and degrease) has no ingredients — arguably could merge with step 3 since degreasing leads directly into the vegetable cooking phase
- STYLE: condensation: "save the rest for another use" is generic advice an experienced cook doesn't need
- STYLE: description: No description present; a complex multi-phase braise could benefit from a short one-liner
- STYLE: economy: "save the rest for another use" adds a few words of filler

### 11_agg_nyt_style — issues
- OUTCOME: outcome_affected: Ingredient list in step 2 shows only 'Cornmeal' whereas original lists 'Cornmeal or wheat bran, as needed' — though wheat bran is mentioned in body text and footer, so no practical impact
- STEPS: ownership_issues: Flour's 'plus more for dusting' note from the original is dropped; dusting flour is used heavily in step 2 but only listed as a measured ingredient in step 1.
- STEPS: disentanglement_issues: Oven preheating is a parallel operation that should begin during the 2-hour proof (original says 'at least a half-hour before dough is ready'), but the OUTPUT places it at the start of the Bake step. A reader following steps sequentially could miss the timing overlap, though the 'at least 30 minutes before baking' cue partially mitigates this.
- STYLE: voice: "it may look like a mess, but that's fine" is conversational reassurance — breaks the confident imperative tone
- STYLE: condensation: "but that's fine" is mild hand-holding/reassurance an experienced cook doesn't need
- STYLE: footer: "Wheat bran can be used in place of cornmeal" repackages inline information — the body already lists wheat bran as an equivalent coating option alongside cornmeal
- STYLE: economy: "it may look like a mess, but that's fine" is filler — the instruction to turn seam-side up is sufficient, "using just enough flour to prevent sticking" is slightly wordy for an implicit concept

### 12_ocr_biscuits — issues
- STYLE: condensation: "onto a lightly floured surface" is generic knowledge for an experienced baker working with biscuit dough
- STYLE: description: No description present — absence is acceptable for a simple recipe, but a punchy one-liner would add character

### 13_ocr_beef_stew — issues
- FIDELITY: quantities_changed: Onion: 'l large onion' → 'Onion, 1' — 'large' size qualifier dropped
- STEPS: phase_design_issues: 'Remove bay leaves before serving' is a finishing instruction tucked into the stew-building step; a brief 'Finish and serve.' phase could be appropriate but is not strictly necessary for this level of complexity.
- STYLE: condensation: "Remove bay leaves before serving" is common-sense advice for anyone who added bay leaves
- STYLE: description: No description present; a classic like beef stew would benefit from a punchy one-liner (e.g. "Low and slow." or "Classic.")
- STYLE: prose: Second section packs many sequential actions into a dense run — could benefit from a paragraph break between building the pot and the simmer phase
- STYLE: economy: "Remove bay leaves before serving" is a redundant reminder given the cook just added them

### 15_clean_text_message — issues
- FIDELITY: quantities_changed: Jalapeño changed from default ingredient ('half a jalapeño or less if u dont like spicy') to Optional — original presents it as included by default with a quantity adjustment, not as optional like cilantro
- OUTCOME: technique_lost: 'mix it all together' changed to 'fold in' — fold implies a gentler, more deliberate technique than casual mixing
- OUTCOME: outcome_affected: Hallucinated 'Serves: 2' — the original does not specify a serving count
- STYLE: economy: "Keep it chunky — don't overmix" in instructions slightly restates the description's "Chunky, not smooth" — the actionable instruction earns its place but the overlap is there

### 16_clean_email — issues
- FIDELITY: quantities_changed: Onion: 'large' size descriptor dropped — '1 large onion' → 'Onion, 1'
- OUTCOME: outcome_affected: Invented description 'Mom's go-to.' — original never describes it this way, Invented tag 'easy' — derived from email preamble 'It's really easy' but not part of the recipe itself
- STEPS: naming_issues: "Shred chicken; add vegetables." — "add vegetables" slightly undersells the phase; "cook vegetables" would better convey the 15-minute simmer that follows.
- STYLE: voice: "Strain broth if desired" — mild hedging with "if desired"
- STYLE: condensation: "they get mushy if left in the soup" is borderline generic advice, though it is recipe-specific enough to justify keeping
- STYLE: footer: Footer note "Lemon squeeze at the table is optional" is redundant with the ingredient list already marking lemon as "Optional"
- STYLE: economy: "Strain broth if desired" — "if desired" adds slight padding, Footer restates what the ingredient annotation already communicates
