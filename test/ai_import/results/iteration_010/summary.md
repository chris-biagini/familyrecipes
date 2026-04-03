# Iteration iteration_010

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-----------|
| 01_blog_serious_eats_a | PASS | PASS | 76.9% | 88 | 95 | 100 | 91.1 |
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 90 | 97 | 100 | 96.8 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 90 | 95 | 100 | 96.3 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 92 | 95 | 98 | 96.2 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 91 | 95 | 100 | 96.5 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 92 | 85 | 100 | 94.3 |
| 08_agg_allrecipes | PASS | PASS | 100.0% | 84 | 95 | 100 | 94.8 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 90 | 95 | 100 | 96.3 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 82 | 95 | 100 | 94.3 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 95 | 100 | 100 | 98.8 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 88 | 100 | 100 | 97.0 |
| 15_clean_text_message | PASS | PASS | 100.0% | 90 | 100 | 100 | 97.5 |
| 16_clean_email | PASS | PASS | 100.0% | 95 | 100 | 100 | 98.8 |

**Overall:** 96.1 avg, 91.1 worst

### 01_blog_serious_eats_a — issues
- FORMAT: prep_notes_formatted — 2 cups roughly chopped, 1 cup left whole.
- FORMAT: single_divider
- FORMAT: step_splitting_appropriate — Expected explicit (2+ named steps) but got 1 steps, headers=false
- FIDELITY: quantities_changed: Pie dough flour: imperial footer omits '12.5 ounces' equivalent, only shows '2 3/4 cups', Pie dough butter: imperial footer omits '10 ounces' equivalent, only shows '2 1/2 sticks', Pie dough water: imperial footer omits '3 ounces' equivalent, only shows '6 tablespoons'
- FIDELITY: prep_leaked_into_name: Sugar (white) - original says 'sugar' only, 'white' is an assumption added to the name

### 03_blog_serious_eats_c — issues
- FIDELITY: instructions_dropped: Original note 'Alternatively, make your own using this recipe' for puff pastry is lost, Puff pastry descriptor 'frozen or homemade' dropped from ingredient and not fully captured in footer
- FIDELITY: instructions_rewritten: Shallots missing 'medium' descriptor from original ('2 medium shallots' → '2')

### 04_blog_smitten_kitchen — issues
- FIDELITY: quantities_changed: Butter: added 'Divided' note not explicitly stated in original, Sugar: 'granulated' changed to 'white', Yield: '10 3-inch (big!) biscuits' simplified to '10 biscuits' (lost size descriptor)

### 05_blog_budget_bytes — issues
- FIDELITY: instructions_rewritten: Notes slightly condensed: removed 'I suggest using' phrasing and 'But I know ketchup is already pretty sweet, so' from the sugar note
- STEPS: flow_issues: The final baking instruction ('Bake the meatloaf for 50-55 minutes...') is placed under 'Make the glaze.' but it concerns the entire meatloaf, not the glaze. Ideally it would be in its own step or under the meatloaf step.

### 07_blog_bon_appetit — issues
- FIDELITY: quantities_changed: Dijon mustard: original says '1 Tbsp. (or more)' → output says '1 tbsp: Plus more to taste.' — rewording of '(or more)'
- FIDELITY: detritus_retained: Footer contains a repackaged summary of the headnote popover technique tips — 'For the loftiest popover topper: blend eggs on the highest speed...' is repackaged blog preamble content

### 08_agg_allrecipes — issues
- FIDELITY: quantities_changed: Ham missing weight info '(18 ounces)' from original, Cuban bread missing size '(8-ounce)' per loaf from original, Ham missing 'deli' descriptor from original
- FIDELITY: instructions_dropped: Movie tip about testing skillet readiness by sprinkling water on surface (from description/preamble)
- FIDELITY: instructions_rewritten: '2 Tbsp.' normalized to '2 tablespoons' in step 3

### 10_agg_epicurious — issues
- FIDELITY: instructions_dropped: Specialized Hardware: Griddle section is omitted entirely
- FIDELITY: instructions_rewritten: '2 to 3 minutes' changed to '2-3 minutes', '250 degrees F' changed to '250°F'

### 11_agg_nyt_style — issues
- FIDELITY: ingredients_missing: Wheat bran as a standalone ingredient option (original lists 'Cornmeal or wheat bran, as needed' as one item)
- FIDELITY: quantities_changed: Yeast: 'Generous 1/4 teaspoon/1 gram' → '1 g' drops 'generous' qualifier on metric quantity (preserved in imperial footer), Yield: 'One 1 1/2-pound loaf' → '1 loaf' drops weight detail
- FIDELITY: instructions_rewritten: 'about 70 degrees' → 'about 70°F' (minor formatting), '6- to 8-quart' → '6-8-quart' (minor formatting), '15 to 30 minutes' → '15-30 minutes' (minor formatting)

### 12_ocr_biscuits — issues
- FIDELITY: quantities_changed: Makes 'about 10' simplified to '10' — dropped qualifier 'about'

### 13_ocr_beef_stew — issues
- FIDELITY: quantities_changed: Pepper changed to 'Black pepper' — original just says 'pepper', Tomatoes: original '1 can (14.5 oz)' became '14.5 oz' — lost '1 can' framing
- FIDELITY: instructions_rewritten: Section headers changed from 'For the beef' / 'For the stew' to 'Prepare the beef.' / 'Make the stew.', '1 1/2 to 2 hours' changed to '1 1/2-2 hours' (dash instead of 'to')

### 15_clean_text_message — issues
- FIDELITY: quantities_changed: Cilantro: original says 'some cilantro if u have it' (conditional), output says 'some' quantity with 'Optional' note - reasonable interpretation, Jalapeño: original says 'half a jalapeño or less if u dont like spicy', output says '1/2 or less' with 'Optional' - the original implies it's included by default but adjustable for spice preference, not truly optional
- FIDELITY: instructions_rewritten: 'dont overmix it should be chunky' slightly cleaned up to 'Don't overmix it should be chunky' (capitalization/punctuation only)

### 16_clean_email — issues
- FIDELITY: quantities_changed: Pepper changed to 'Black pepper' — original just says 'pepper'
