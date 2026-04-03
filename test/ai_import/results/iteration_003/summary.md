# Iteration iteration_003

| Recipe | Parse | Format | Fidelity | Detritus | Aggregate |
|--------|-------|--------|----------|----------|-----------|
| 01_blog_simple | PASS | 100.0% | 97 | 98 | 98.2 |
| 02_blog_medium | PASS | 100.0% | 95 | 82 | 92.6 |
| 03_blog_complex | PASS | 100.0% | 97 | 95 | 97.3 |
| 04_card_simple | FAIL | 100.0% | 93 | 85 | 0.0 |
| 05_card_medium | PASS | 100.0% | 97 | 78 | 92.2 |
| 06_card_complex | FAIL | 100.0% | 95 | 97 | 0.0 |
| 07_ocr_simple | PASS | 100.0% | 98 | 99 | 98.9 |
| 08_ocr_medium | FAIL | 100.0% | 93 | 90 | 0.0 |
| 09_clean_simple | PASS | 100.0% | 97 | 90 | 95.8 |
| 10_clean_medium | PASS | 100.0% | 97 | 95 | 97.3 |

**Overall:** 67.2 avg, 0.0 worst

### 01_blog_simple — issues
- FIDELITY: prep_in_name: Butter (unsalted), 4 tbsp: Softened., Garlic, 3 cloves: Minced., Parsley (fresh), 2 tbsp: Chopped.

### 02_blog_medium — issues
- FIDELITY: detritus_retained: Blog preamble snippet retained: 'Comes together in about 30 minutes.', Extraneous metadata retained: 'Tags: weeknight, quick'

### 03_blog_complex — issues
- FIDELITY: detritus_retained: Subtitle 'Soft, gooey, and perfect for Christmas morning' retained (minor, borderline acceptable), Category listed as 'Breakfast' instead of recipe content — minor metadata issue
- FIDELITY: prep_in_name: Flour (all-purpose), 3 cups: Plus more for dusting — 'plus more for dusting' is prep/usage info in the ingredient entry, which is acceptable contextually but reference omits it from the name

### 04_card_simple — issues
- PARSE FAILED: Only 9 ingredients (expected >= 10)
- FIDELITY: detritus_retained: Pure comfort in a bowl. Rich, velvety, and ready in under 40 minutes. (intro/marketing copy from blog)
- FIDELITY: prep_in_name: Onion (medium), 1: Diced. — 'medium' is a size descriptor but acceptable; prep note style is fine, Tomatoes (canned, whole peeled), 1 can (28 oz) — 'canned' is an added descriptor not in original ingredient name

### 05_card_medium — issues
- FIDELITY: detritus_retained: Slow cooker tip from author comment included in output (though presented as a recipe note rather than a comment, this content originated from the comments section, not the recipe itself)
- FIDELITY: prep_in_name: Beef chuck roast, 2 lbs: Cut into 1 1/2-inch cubes., Onion, 1 large: Diced., Garlic, 4 cloves: Minced., Potatoes (Yukon Gold), 3 medium: Cut into 1-inch cubes., Carrots, 3 large: Peeled and sliced into 1/2-inch rounds., Celery, 2 stalks: Sliced.

### 06_card_complex — issues
- PARSE FAILED: Only 5 ingredients (expected >= 8)
- FIDELITY: prep_in_name: Water (warm), 350 g: Around 100°F — 'warm' folded into ingredient name; prep note placed in annotation, Rice flour, 30 g: For dusting the banneton — usage instruction placed in ingredient annotation rather than body text

### 07_ocr_simple — issues
- FIDELITY: prep_in_name: Butter (cold), 1/3 cup: Cut into small pieces.

### 08_ocr_medium — issues
- PARSE FAILED: Only 13 ingredients (expected >= 15)
- FIDELITY: detritus_retained: 'SUNDAY SUPPERS' section header retained as part of headnote framing is fine, but 'Parmesan cheese and fresh basil are for serving and garnish.' footer note is a minor structural oddity rather than detritus

### 09_clean_simple — issues
- FIDELITY: detritus_retained: "A go-to dressing for any salad. Adjust the ratio to taste." — preamble/description retained (though reference also keeps it, so borderline acceptable)
- FIDELITY: prep_in_name: Garlic, 1 small clove: Finely minced. — preparation note embedded in ingredient name/line (consistent with reference style, so acceptable)

### 10_clean_medium — issues
- FIDELITY: detritus_retained: Blog preamble sentence retained implicitly via ingredient note 'give or take' kept in ingredient name, though this is minor
- FIDELITY: prep_in_name: Lime juice, juice of 2 limes — 'juice of' is redundant phrasing from original prose leaked into the ingredient name rather than being normalized
