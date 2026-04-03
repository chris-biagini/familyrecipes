# Iteration iteration_012

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-----------|
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 89 | 95 | 100 | 96.0 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 90 | 95 | 100 | 96.3 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 90 | 97 | 97 | 95.9 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 90 | 95 | 100 | 96.3 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 91 | 95 | 100 | 96.5 |
| 08_agg_allrecipes | PASS | PASS | 100.0% | 93 | 95 | 100 | 97.0 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 93 | 95 | 100 | 97.0 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 82 | 95 | 100 | 94.3 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 95 | 100 | 100 | 98.8 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 90 | 95 | 100 | 96.3 |
| 15_clean_text_message | PASS | PASS | 100.0% | 90 | 100 | 100 | 97.5 |
| 16_clean_email | PASS | PASS | 100.0% | 95 | 100 | 100 | 98.8 |

**Overall:** 96.7 avg, 94.3 worst

### 03_blog_serious_eats_c — issues
- FIDELITY: instructions_dropped: Foie gras descriptor 'about 2 1/2-inch slabs' dropped from ingredient line, Puff pastry descriptor 'frozen or homemade' dropped from ingredient line, Thyme descriptor 'leaves' dropped from ingredient line, Note about making your own puff pastry ('Alternatively, make your own using this recipe') dropped from footer
- FIDELITY: instructions_rewritten: Footer mustard substitution note awkwardly reworded as 'Or Dijon mustard: spicy brown or hot English mustard' — original listed them as equal alternatives: 'Dijon, spicy brown, or hot English mustard'

### 04_blog_smitten_kitchen — issues
- FIDELITY: quantities_changed: Sugar: 'granulated' changed to 'white' in descriptor

### 05_blog_budget_bytes — issues
- FIDELITY: instructions_rewritten: Notes slightly condensed: removed 'I suggest using' and 'But I know ketchup is already pretty sweet, so' personal language from the notes
- STEPS: flow_issues: The final baking instruction ('Bake the meatloaf for 50-55 minutes...') is placed under 'Make the glaze.' but conceptually applies to the whole meatloaf, not just the glaze step. Order is preserved but ownership is slightly off.

### 06_blog_pioneer_woman — issues
- FIDELITY: quantities_changed: Beans: '(kidney and pinto)' changed to '(mixed)' in ingredient name; specific types moved to footer note

### 07_blog_bon_appetit — issues
- FIDELITY: quantities_changed: Flour: original '1 1/2 cups (187 g)' listed as '187 g' in ingredient line (imperial moved to footer, acceptable per rules), Potatoes: dropped 'about 2 large' size descriptor from ingredient line

### 11_agg_nyt_style — issues
- FIDELITY: ingredients_missing: Wheat bran as alternative in cornmeal ingredient line (original: 'Cornmeal or wheat bran, as needed')
- FIDELITY: quantities_changed: Makes: 'One 1 1/2-pound loaf' → '1 loaf' (lost weight descriptor), Yeast: 'Generous 1/4 teaspoon/1 gram' → '1 g' (dropped 'generous' from ingredient line, though preserved in footer imperial equivalents)
- FIDELITY: instructions_rewritten: Step 1: '1 1/2 cups/345 grams water' replaced with 'water' since water extracted to ingredient list (acceptable)

### 13_ocr_beef_stew — issues
- FIDELITY: instructions_rewritten: Section header 'For the beef:' rewritten as 'Prepare the beef.', Section header 'For the stew:' rewritten as 'Make the stew.'

### 15_clean_text_message — issues
- FIDELITY: instructions_dropped: Lost 'if u dont like spicy' qualifier on jalapeño amount

### 16_clean_email — issues
- FIDELITY: ingredients_added: Lemon (extracted from instructions as optional - acceptable)
