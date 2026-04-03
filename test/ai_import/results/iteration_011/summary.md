# Iteration iteration_011

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-----------|
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 92 | 95 | 100 | 96.8 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 88 | 95 | 100 | 95.8 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 90 | 97 | 100 | 96.8 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 90 | 92 | 100 | 95.5 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 95 | 97 | 100 | 98.0 |
| 08_agg_allrecipes | PASS | PASS | 100.0% | 94 | 95 | 90 | 94.3 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 95 | 97 | 100 | 98.0 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 82 | 95 | 100 | 94.3 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 95 | 100 | 100 | 98.8 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 90 | 95 | 100 | 96.3 |
| 15_clean_text_message | PASS | PASS | 100.0% | 90 | 100 | 100 | 97.5 |
| 16_clean_email | PASS | PASS | 100.0% | 92 | 100 | 100 | 98.0 |
| _01_blog_serious_eats_a_disabled | PASS | PASS | 76.9% | 92 | 97 | 100 | 92.6 |

**Overall:** 96.4 avg, 92.6 worst

### 04_blog_smitten_kitchen — issues
- FIDELITY: quantities_changed: Sugar: 'granulated' changed to 'white', Pepper: 'Freshly ground black pepper' reduced to 'Pepper' — lost 'freshly ground' and 'black' descriptors, Yield: '10 3-inch (big!) biscuits' simplified to '10 biscuits' — lost size descriptor

### 05_blog_budget_bytes — issues
- FIDELITY: quantities_changed: Serves: 7 — original shows 'SERVINGS slices' with no visible number; 7 appears hallucinated or inferred
- FIDELITY: instructions_rewritten: Footer note 1 slightly condensed: removed 'Ground beef is the base for this recipe, and I suggest using' prefix, Footer note 2 slightly condensed: removed 'I know' from 'But I know ketchup is already pretty sweet'

### 06_blog_pioneer_woman — issues
- FIDELITY: detritus_retained: Footer note 'Masa harina can be substituted with regular cornmeal' is an invented substitution suggestion — the original listed 'or regular cornmeal' as part of the ingredient name, not as a separate tip

### 07_blog_bon_appetit — issues
- FIDELITY: quantities_changed: Dijon mustard: original says '1 Tbsp. (or more)' → output says '1 tbsp: Plus more to taste.' — slight semantic shift from 'or more' to 'to taste'

### 08_agg_allrecipes — issues
- STEPS: flow_issues: The roasted pork sub-recipe footnote, tips about skillet readiness, and the 'or pulled pork' note are appended after the main instructions separated by a horizontal rule, which reorders content slightly but preserves the main instruction flow, Attribution and timing info moved to the very end rather than staying near the top as metadata

### 11_agg_nyt_style — issues
- FIDELITY: ingredients_missing: Wheat bran as an alternative ingredient (listed in original as 'Cornmeal or wheat bran, as needed', only cornmeal appears in ingredient list)
- FIDELITY: quantities_changed: Makes: 'One 1 1/2-pound loaf' reduced to '1 loaf' — lost the weight descriptor

### 13_ocr_beef_stew — issues
- FIDELITY: instructions_rewritten: Section headers changed from 'For the beef:'/'For the stew:' to 'Brown the beef.'/'Make the stew.' — reworded from noun phrases to imperative verbs
- FIDELITY: detritus_retained: Tags: comfort-food — not present in original, hallucinated

### 16_clean_email — issues
- FIDELITY: ingredients_added: Lemon - was not in the original ingredient list; only mentioned as Dad's optional table addition

### _01_blog_serious_eats_a_disabled — issues
- FORMAT: prep_notes_formatted — 2 cups roughly chopped, 1 cup left whole.
- FORMAT: single_divider
- FORMAT: step_splitting_appropriate — Expected explicit (2+ named steps) but got 1 steps, headers=false
- FIDELITY: instructions_rewritten: 'vanilla' renamed to 'vanilla extract' - original just says 'vanilla', Attribution 'Serious Eats / Vicky Wasik' reduced to 'From Serious Eats' - dropped photographer credit
