# Iteration iteration_005

| Recipe | Parse | Format | Fidelity | Detritus | Aggregate |
|--------|-------|--------|----------|----------|-----------|
| 01_blog_simple | PASS | 100.0% | 98 | 99 | 98.9 |
| 02_blog_medium | PASS | 100.0% | 97 | 92 | 96.4 |
| 03_blog_complex | PASS | 100.0% | 97 | 95 | 97.3 |
| 04_card_simple | PASS | 100.0% | 96 | 85 | 93.9 |
| 05_card_medium | PASS | 100.0% | 93 | 97 | 96.3 |
| 06_card_complex | PASS | 100.0% | 93 | 97 | 96.3 |
| 07_ocr_simple | PASS | 100.0% | 97 | 95 | 97.3 |
| 08_ocr_medium | PASS | 100.0% | 93 | 99 | 96.9 |
| 09_clean_simple | PASS | 100.0% | 97 | 95 | 97.3 |
| 10_clean_medium | PASS | 100.0% | 97 | 97 | 97.9 |

**Overall:** 96.9 avg, 93.9 worst

### 01_blog_simple — issues
- FIDELITY: prep_in_name: Butter (unsalted), 4 tbsp: Softened., Garlic, 3 cloves: Minced., Parsley (fresh), 2 tbsp: Chopped.

### 02_blog_medium — issues
- FIDELITY: detritus_retained: Tags: weeknight, quick (minor metadata not in original recipe)

### 03_blog_complex — issues
- FIDELITY: detritus_retained: Soft, gooey, and perfect for Christmas morning. (subtitle retained — minor)
- FIDELITY: prep_in_name: Flour (all-purpose), 3 cups: Plus more for dusting — prep note in ingredient field (minor), Sugar (brown), 2/3 cup: Packed — prep note in ingredient field (minor)

### 04_card_simple — issues
- FIDELITY: detritus_retained: Tags: vegetarian, weeknight — not present in original
- FIDELITY: prep_in_name: Fresh basil: For garnish. — garnish note in ingredient name

### 05_card_medium — issues
- FIDELITY: ingredients_added: Set aside the vegetables for later use in the stew (instructional text added without basis)
- FIDELITY: prep_in_name: Yukon Gold potatoes, 3 medium: Cut into 1-inch cubes., Carrots, 3 large: Peeled and sliced into 1/2-inch rounds., Celery, 2 stalks: Sliced., Onion, 1 large: Diced., Garlic, 4 cloves: Minced., Beef chuck roast, 2 lbs: Cut into 1 1/2-inch cubes., Tomatoes (canned, diced), 1 can (14.5 oz), Red wine (dry), 1 cup, Thyme (dried), 1 tsp

### 06_card_complex — issues
- FIDELITY: prep_in_name: Water (warm), 350 g: Around 100°F. — 'warm' in name and temp note as inline annotation rather than separate prep note, Rice flour, 30 g: For dusting the banneton. — usage note leaked into ingredient annotation

### 07_ocr_simple — issues
- FIDELITY: detritus_retained: Category: Bread — hallucinated metadata not in original (original has no category label); minor but fabricated
- FIDELITY: prep_in_name: Butter (cold), 1/3 cup: Cut into small pieces.

### 08_ocr_medium — issues
- FIDELITY: instructions_dropped: Introductory sentence 'This is the kind of Sunday supper that fills the whole house with the most incredible smell.' omitted from description
- FIDELITY: instructions_rewritten: Serves '4 to 6' changed to 'Serves: 4'

### 09_clean_simple — issues
- FIDELITY: detritus_retained: Introductory tagline 'A go-to dressing for any salad. Adjust the ratio to taste.' retained (though reference also keeps it, so minor concern)
- FIDELITY: prep_in_name: Garlic, 1 small clove: Finely minced. — preparation note embedded in ingredient name/line

### 10_clean_medium — issues
- FIDELITY: detritus_retained: Blog preamble: 'So this is my go-to taco situation when we have people over. It's dead simple but everyone always asks for the recipe.' — omitted, which is correct, but the section header 'Marinate the steak.' differs slightly from reference's 'Make the marinade.' — minor structural difference, not detritus
- FIDELITY: prep_in_name: Garlic, 3 cloves: Smashed. — prep note folded into ingredient name field, White onion, 1: Diced. — prep note folded into ingredient name field, Lime, 1: Cut into wedges. — prep note folded into ingredient name field
