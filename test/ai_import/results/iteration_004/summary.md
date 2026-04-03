# Iteration iteration_004

| Recipe | Parse | Format | Fidelity | Detritus | Aggregate |
|--------|-------|--------|----------|----------|-----------|
| 01_blog_simple | PASS | 100.0% | 98 | 97 | 98.3 |
| 02_blog_medium | PASS | 100.0% | 92 | 82 | 91.4 |
| 03_blog_complex | PASS | 100.0% | 97 | 98 | 98.2 |
| 04_card_simple | PASS | 100.0% | 95 | 82 | 92.6 |
| 05_card_medium | PASS | 100.0% | 95 | 92 | 95.6 |
| 06_card_complex | FAIL | 100.0% | 93 | 97 | 0.0 |
| 07_ocr_simple | PASS | 100.0% | 97 | 95 | 97.3 |
| 08_ocr_medium | PASS | 100.0% | 92 | 97 | 95.9 |
| 09_clean_simple | PASS | 100.0% | 98 | 98 | 98.6 |
| 10_clean_medium | PASS | 100.0% | 96 | 95 | 96.9 |

**Overall:** 86.5 avg, 0.0 worst

### 02_blog_medium — issues
- FIDELITY: detritus_retained: Tags: weeknight, quick (metadata not in original recipe), Chicken breasts can be substituted footer includes gluten-free tamari note drawn from blog comments, not the recipe itself

### 04_card_simple — issues
- FIDELITY: detritus_retained: Tags: vegetarian, quick, one-pot — not present in original

### 05_card_medium — issues
- FIDELITY: detritus_retained: Tags: comfort-food, one-pot (minor metadata from original keyword field), Category: Mains (minor metadata)
- FIDELITY: prep_in_name: Beef chuck roast, 2 lbs: Cut into 1 1/2-inch cubes., Onion, 1 large: Diced., Garlic, 4 cloves: Minced., Yukon Gold potatoes, 3 medium: Cut into 1-inch cubes., Carrots, 3 large: Peeled and sliced into 1/2-inch rounds., Celery, 2 stalks: Sliced., Tomatoes (canned, diced), 1 can (14.5 oz)

### 06_card_complex — issues
- PARSE FAILED: Only 5 ingredients (expected >= 6, gold standard has 8)
- FIDELITY: instructions_dropped: The proofing step (step 5 in original) was placed under 'Shape the dough' section rather than 'Proof and bake' section, misaligning the structure slightly, but content is present
- FIDELITY: prep_in_name: Water (warm), 350 g: Around 100°F. — 'warm' is a prep descriptor in the ingredient name; the temperature note is placed as a sub-note which is acceptable, but 'warm' in the name is minor, Rice flour, 30 g: For dusting the banneton. — usage note leaked into ingredient entry rather than being omitted or placed in footer

### 07_ocr_simple — issues
- FIDELITY: detritus_retained: Category: Bread — hallucinated/incorrect category label (reference uses 'Baking'); the page number '— 83 —' and section header 'QUICK BREADS' were correctly omitted, but the category value is wrong
- FIDELITY: prep_in_name: Butter (cold), 1/3 cup: Cut into small pieces.

### 08_ocr_medium — issues
- FIDELITY: quantities_changed: Serves 4 to 6 changed to Serves: 4
- FIDELITY: detritus_retained: 'SUNDAY SUPPERS' chapter header omitted (acceptable), but '— 47 —' page number correctly omitted

### 10_clean_medium — issues
- FIDELITY: detritus_retained: Blog preamble retained implicitly via 'however many you need' on tortillas (minor), Small corn tortillas described as 'small' in original — output drops 'small' qualifier
- FIDELITY: prep_in_name: Garlic, 3 cloves: Smashed., Onion (white), 1: Diced., Lime, 1: Cut into wedges.
