# Iteration iteration_009

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-----------|
| 01_blog_serious_eats_a | PASS | PASS | 83.3% | 93 | 97 | 100 | 94.2 |
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 92 | 93 | 100 | 96.3 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 0 | 0 | 100 | 50.0 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 93 | 95 | 100 | 97.0 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 90 | 95 | 100 | 96.3 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 91 | 97 | 100 | 97.0 |
| 08_agg_allrecipes | PASS | PASS | 100.0% | 91 | 95 | 100 | 96.5 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 93 | 97 | 100 | 97.5 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 87 | 91 | 100 | 94.5 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 93 | 100 | 100 | 98.3 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 95 | 100 | 100 | 98.8 |
| 15_clean_text_message | PASS | PASS | 100.0% | 90 | 100 | 100 | 97.5 |
| 16_clean_email | PASS | PASS | 100.0% | 95 | 100 | 100 | 98.8 |

**Overall:** 93.3 avg, 50.0 worst

### 01_blog_serious_eats_a — issues
- FORMAT: single_divider
- FORMAT: step_splitting_appropriate — Expected explicit (2+ named steps) but got 1 steps, headers=false
- FIDELITY: quantities_changed: Easy Pie Dough water imperial equivalent missing '3 ounces' (original: '6 tablespoons (3 ounces; 85 ml)')

### 03_blog_serious_eats_c — issues
- FIDELITY: quantities_changed: Serves changed from '6 to 8 servings' to '8' — drops the lower end of the range, Foie gras sizing detail '(about 2 1/2-inch slabs)' dropped from ingredient line and not noted elsewhere
- FIDELITY: instructions_dropped: 'using this recipe' link reference dropped from puff pastry note (original: 'make your own using this recipe'), Puff pastry descriptor 'frozen or homemade' dropped from ingredient line and not preserved in footer
- FIDELITY: instructions_rewritten: Notes rewrite 'skip step 7' and 'In step 9' to 'skip the foie gras searing step' and 'When assembling' — reasonable adaptation since steps are unnumbered, not a real issue
- FIDELITY: detritus_retained: Footer substitution notes ('Or canola oil in place of vegetable oil', 'Or spicy brown or hot English mustard in place of Dijon', etc.) repackage inline ingredient alternatives into invented prose — these are summary notes that repackage inline information

### 06_blog_pioneer_woman — issues
- FIDELITY: quantities_changed: Serves changed from '6 - 8' to '8' — lost the lower bound of the range

### 07_blog_bon_appetit — issues
- FIDELITY: quantities_changed: Serves changed from '4-6 servings' to '6' — dropped the range, Potatoes: '(about 2 large)' descriptor dropped from ingredient line (still present in instructions), Dijon mustard: original says '(or more)', output rewrites to 'Plus more to taste' — 'to taste' not in original

### 08_agg_allrecipes — issues
- FIDELITY: quantities_changed: Pork: original includes '(12 ounces)' weight equivalent, output drops it, Ham: original includes '(18 ounces)' weight equivalent, output drops it
- FIDELITY: instructions_rewritten: '6 to 8 minutes' changed to '6-8 minutes' (minor formatting)

### 10_agg_epicurious — issues
- FIDELITY: instructions_dropped: Specialized Hardware section listing 'Griddle' is omitted entirely
- FIDELITY: instructions_rewritten: '250 degrees F' changed to '250°F' (trivial formatting), '2 to 3 minutes' changed to '2-3 minutes' (trivial formatting), 'parsley leaves' simplified to 'Parsley (fresh)' dropping 'leaves'

### 11_agg_nyt_style — issues
- FIDELITY: quantities_changed: Yield changed from 'One 1 1/2-pound loaf' to '1 loaf' — weight specification lost
- FIDELITY: instructions_rewritten: 'about 70 degrees' changed to 'about 70°F' — Fahrenheit unit added where original just said 'degrees'
- FIDELITY: detritus_retained: Historical note from blog preamble retained in footer: 'The original recipe called for 3 cups flour; adjusted to 3 1/3 cups (430 grams) after reader feedback.'

### 13_ocr_beef_stew — issues
- FIDELITY: instructions_rewritten: Section headers changed from 'For the beef:' / 'For the stew:' to 'Brown the beef.' / 'Make the stew.'

### 15_clean_text_message — issues
- FIDELITY: instructions_rewritten: Jalapeño note 'or less if u dont like spicy' was reduced to just 'Optional', losing the spice-preference context and implying it can be skipped entirely rather than adjusted downward

### 16_clean_email — issues
- FIDELITY: ingredients_added: Lemon (extracted from an optional serving suggestion attributed to 'Dad', not listed as a recipe ingredient in the original)
