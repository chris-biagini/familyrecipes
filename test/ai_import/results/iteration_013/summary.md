# Iteration iteration_013

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-----------|
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 91 | 90 | 100 | 95.3 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 90 | 95 | 100 | 96.3 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 90 | 100 | 100 | 97.5 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 93 | 95 | 100 | 97.0 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 90 | 100 | 100 | 97.5 |
| 08_agg_allrecipes | PASS | PASS | 100.0% | 95 | 95 | 100 | 97.5 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 95 | 95 | 100 | 97.5 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 88 | 95 | 100 | 95.8 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 95 | 100 | 100 | 98.8 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 95 | 100 | 95 | 97.3 |
| 15_clean_text_message | PASS | PASS | 100.0% | 90 | 95 | 100 | 96.3 |
| 16_clean_email | PASS | PASS | 100.0% | 88 | 95 | 100 | 95.8 |

**Overall:** 96.9 avg, 95.3 worst

### 03_blog_serious_eats_c — issues
- FIDELITY: quantities_changed: Shallots: original says '2 medium shallots, finely diced (about 1/2 cup)' — output drops 'about 1/2 cup' volume equivalent, Foie gras: original says '4 ounces fresh foie gras (about 2 1/2-inch slabs, see note)' — output drops 'about 2 1/2-inch slabs' detail
- FIDELITY: detritus_retained: Tags 'holiday, baked' are invented — not present in or derivable from the original source

### 05_blog_budget_bytes — issues
- FIDELITY: instructions_rewritten: Notes condensed: 'Ground beef is the base for this recipe, and I suggest using 80/20' → 'Use 80/20'; 'But I know ketchup is already pretty sweet, so feel free' → 'Feel free'

### 07_blog_bon_appetit — issues
- FIDELITY: quantities_changed: Salt: original '2 1/2 tsp. Diamond Crystal or 1 1/2 tsp. Morton kosher salt' simplified to '2 1/2 tsp' in ingredient line, losing the Morton equivalent (though preserved in instructions)
- FIDELITY: instructions_rewritten: Instructions condensed to use ingredient names instead of repeating full descriptions (e.g., 'Add potatoes' instead of 'Add 12 oz. Yukon Gold potatoes (about 2 large), peeled, cut into 1/2" pieces') - acceptable simplification since details are in ingredient list

### 11_agg_nyt_style — issues
- FIDELITY: quantities_changed: Yeast: 'Generous 1/4 teaspoon/1 gram' → '1 g' drops 'generous' qualifier from ingredient line (preserved in imperial footer)

### 12_ocr_biscuits — issues
- FIDELITY: quantities_changed: '1 tablespoon' → '1 tbsp' (abbreviation, minor), '1/2 teaspoon' → '1/2 tsp' (abbreviation, minor)

### 13_ocr_beef_stew — issues
- FIDELITY: instructions_rewritten: Section headers changed from 'For the beef:' / 'For the stew:' to 'Make the beef.' / 'Make the stew.'
- STEPS: naming_issues: Step names use 'Make the beef.' and 'Make the stew.' which are reasonable but 'Prepare the beef.' or 'Brown the beef.' would better describe the action; 'Make the beef' is slightly odd phrasing

### 15_clean_text_message — issues
- FIDELITY: quantities_changed: Lime: original says 'half a lime' (juice), output says 'Lime, 1/2' — could imply half a whole lime rather than juice, but reasonable interpretation

### 16_clean_email — issues
- FIDELITY: ingredients_added: Lemon, 1 - original mentions 'a squeeze of lemon' as an optional table addition, not a recipe ingredient with quantity 1
- FIDELITY: quantities_changed: Lemon listed as '1' but original only says 'a squeeze of lemon' — the quantity '1' is invented
