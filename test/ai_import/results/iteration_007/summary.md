# Iteration iteration_007

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-----------|
| 01_blog_serious_eats_a | PASS | PASS | 83.3% | 92 | 97 | 100 | 93.9 |
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 88 | 95 | 100 | 95.8 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 90 | 97 | 100 | 96.8 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 95 | 98 | 100 | 98.3 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 87 | 90 | 100 | 94.3 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 88 | 82 | 100 | 92.5 |
| 08_agg_allrecipes | PASS | PASS | 100.0% | 90 | 95 | 100 | 96.3 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 95 | 100 | 100 | 98.8 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 90 | 93 | 100 | 95.8 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 95 | 100 | 100 | 98.8 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 93 | 90 | 100 | 95.8 |
| 15_clean_text_message | PASS | PASS | 100.0% | 90 | 88 | 100 | 94.5 |
| 16_clean_email | PASS | PASS | 100.0% | 89 | 100 | 100 | 97.3 |

**Overall:** 96.1 avg, 92.5 worst

### 01_blog_serious_eats_a — issues
- FORMAT: single_divider
- FORMAT: step_splitting_appropriate — Expected explicit (2+ named steps) but got 1 steps, headers=false

### 03_blog_serious_eats_c — issues
- FIDELITY: quantities_changed: Serves changed from '6 to 8 servings' to '8' — lost the range, Foie gras missing 'about 2 1/2-inch slabs' descriptor from original, Puff pastry listed as '(frozen)' but original says 'frozen or homemade' — lost the 'or homemade' option
- FIDELITY: instructions_dropped: Active time (90 mins) and Total time (3 hrs 40 mins) dropped from footer timing notes, Puff pastry note 'Alternatively, make your own using this recipe' dropped (was a link to a recipe)
- FIDELITY: instructions_rewritten: Foie gras pate note rephrased from 'skip step 7. In step 9, spread...' to 'skip the foie gras searing step. When assembling, spread...' — reasonable adaptation since output has no numbered steps, '35 to 45 minutes' changed to '35-45 minutes' — trivial formatting

### 04_blog_smitten_kitchen — issues
- FIDELITY: quantities_changed: Yield simplified from '10 3-inch (big!) biscuits' to '10 biscuits' — lost '3-inch' size and '(big!)' note

### 06_blog_pioneer_woman — issues
- FIDELITY: quantities_changed: Yields '6 - 8 serving(s)' simplified to 'Serves: 8' — the low end of the range is dropped
- FIDELITY: detritus_retained: Footer note 'Or regular cornmeal in place of masa harina.' repackages the ingredient-line alternative into a separate summary note, Footer note 'Cheddar, bacon, and jalapeños are for topping — shredded, crumbled, and sliced, respectively.' repackages the original ingredient line into a summary note

### 07_blog_bon_appetit — issues
- FIDELITY: quantities_changed: Serves changed from '4-6 servings' to '6' — should be '4-6' or '4 to 6', Potatoes: '(about 2 large)' descriptor dropped from ingredient line, Salt: 'Diamond Crystal' brand name dropped from ingredient line — original specifies 'Diamond Crystal' as the primary brand, Dijon mustard: '(or more)' changed to 'Plus more to taste' — slightly different meaning
- FIDELITY: detritus_retained: Popover tip paragraph from the blog preamble ('To get the loftiest popover topper...') included in footer — this was pre-recipe editorial content, not part of the recipe instructions

### 08_agg_allrecipes — issues
- FIDELITY: quantities_changed: Ham: original specifies '18 slices deli smoked ham (18 ounces)' but output drops the '(18 ounces)' weight, Cuban bread: original specifies '3 (8-ounce) loaves' but output drops the '(8-ounce)' size descriptor
- FIDELITY: instructions_rewritten: Step 3: '2 Tbsp.' normalized to '2 tablespoons' (minor), Step 3: '6 to 8 minutes' changed to '6-8 minutes' (minor formatting)

### 10_agg_epicurious — issues
- FIDELITY: instructions_rewritten: "2 to 3 minutes" changed to "2-3 minutes", "250 degrees F" changed to "250°F"

### 11_agg_nyt_style — issues
- FIDELITY: quantities_changed: Makes line says '1 loaf' but original yield is 'One 1 1/2-pound loaf' — weight detail lost
- FIDELITY: instructions_rewritten: 'about 70 degrees' changed to 'about 70°F' (unit label added), '15 to 30 minutes' compressed to '15-30 minutes'
- FIDELITY: detritus_retained: Footer line 'Or bread flour in place of all-purpose flour. Or wheat bran in place of cornmeal.' repackages inline ingredient alternatives as substitution-style notes

### 12_ocr_biscuits — issues
- FIDELITY: quantities_changed: Makes line: 'about 10 biscuits' → '10 biscuits' (dropped 'about' qualifier), Unit abbreviations: 'tablespoon' → 'tbsp', 'teaspoon' → 'tsp' (standard normalization)

### 13_ocr_beef_stew — issues
- FIDELITY: instructions_rewritten: Section headers 'For the beef' / 'For the stew' reworded to 'Sear the beef.' / 'Build the stew.', '1 1/2 to 2 hours' changed to '1 1/2-2 hours' (dash instead of 'to')
- FIDELITY: detritus_retained: Tags line 'comfort-food, american' invented without basis in original

### 15_clean_text_message — issues
- FIDELITY: instructions_dropped: Jalapeño note 'if u dont like spicy' context dropped — only 'or less' retained without the reasoning
- FIDELITY: detritus_retained: Tags line 'vegan, quick, easy' is hallucinated — none of these tags appear in the original

### 16_clean_email — issues
- FIDELITY: ingredients_added: Lemon (extracted from a casual serving suggestion attributed to Dad, not listed as a recipe ingredient)
- FIDELITY: quantities_changed: Chicken: original '1 whole chicken (about 3-4 lbs)' → output 'Chicken (whole), about 3-4 lbs' (dropped the quantity '1'), Pepper: original 'pepper' → output 'Black pepper' (added 'black' descriptor not in original)
