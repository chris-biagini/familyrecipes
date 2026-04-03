# Iteration iteration_001

| Recipe | Parse | Format | Fidelity | Detritus | Aggregate |
|--------|-------|--------|----------|----------|-----------|
| 01_blog_simple | PASS | 100.0% | 95 | 97 | 97.1 |
| 02_blog_medium | PASS | 100.0% | 95 | 82 | 92.6 |
| 03_blog_complex | PASS | 100.0% | 95 | 92 | 95.6 |
| 04_card_simple | PASS | 100.0% | 95 | 82 | 92.6 |
| 05_card_medium | PASS | 100.0% | 95 | 78 | 91.4 |
| 06_card_complex | FAIL | 100.0% | 82 | 97 | 0.0 |
| 07_ocr_simple | PASS | 100.0% | 97 | 92 | 96.4 |
| 08_ocr_medium | PASS | 100.0% | 95 | 98 | 97.4 |
| 09_clean_simple | PASS | 100.0% | 97 | 90 | 95.8 |
| 10_clean_medium | PASS | 100.0% | 82 | 100 | 92.8 |

**Overall:** 85.2 avg, 0.0 worst

### 01_blog_simple — issues
- FIDELITY: prep_in_name: Butter (unsalted), 4 tbsp: Softened., Garlic, 3 cloves: Minced., Parsley (fresh), 2 tbsp: Chopped.

### 02_blog_medium — issues
- FIDELITY: detritus_retained: Brief blog intro phrase retained: 'Comes together in about 30 minutes with a good marinade and a screaming hot pan.', Tags field added (weeknight, easy, quick) not present in original recipe block, Tamari/gluten-free substitution note sourced from comment section, not the recipe itself

### 03_blog_complex — issues
- FIDELITY: instructions_dropped: Don't overbake — they'll firm up as they cool. (from baking step), While the dough rises (timing note for mixing filling)
- FIDELITY: detritus_retained: Soft, gooey, and perfect for Christmas morning. (subtitle/tagline retained, though minor), Category: Breakfast (original says Breakfast but reference uses Baking), Tags: make-ahead (original has no tags; reference uses 'holiday')
- FIDELITY: prep_in_name: Flour (all-purpose), 3 cups: Plus more for dusting — prep note about dusting is in the ingredient entry, which is acceptable but differs from reference omitting it from ingredient

### 04_card_simple — issues
- FIDELITY: detritus_retained: Tags: vegetarian, quick, comfort-food — not present in original recipe
- FIDELITY: prep_in_name: Basil (fresh): For garnish. — 'for garnish' is a usage note embedded in the ingredient entry

### 05_card_medium — issues
- FIDELITY: ingredients_added: weeknight (tag, not an ingredient, but output added it without basis from original)
- FIDELITY: detritus_retained: Slow cooker tip sourced from a reader comment thread and author reply, not from the recipe itself — included as a footer note
- FIDELITY: prep_in_name: Beef chuck roast, 2 lbs: Cut into 1 1/2-inch cubes (prep instruction in ingredient name field), Onion, 1 large: Diced (prep instruction in ingredient name field), Garlic, 4 cloves: Minced (prep instruction in ingredient name field), Potatoes (Yukon Gold), 3 medium: Cut into 1-inch cubes (prep instruction in ingredient name field), Carrots, 3 large: Peeled and sliced into 1/2-inch rounds (prep instruction in ingredient name field), Celery, 2 stalks: Sliced (prep instruction in ingredient name field)

### 06_card_complex — issues
- PARSE FAILED: Only 5 ingredients (expected >= 8)
- FIDELITY: ingredients_missing: Sesame seeds (10 g) not listed as a formal ingredient with quantity, Flaky sea salt (2 g) not listed as a formal ingredient with quantity, Rolled oats (15 g) not listed as a formal ingredient with quantity
- FIDELITY: prep_in_name: Water (warm), 350 g: Around 100°F — 'warm' is a prep descriptor in the ingredient name, Rice flour, 30 g: For dusting the banneton — prep note embedded as inline annotation on ingredient

### 07_ocr_simple — issues
- FIDELITY: detritus_retained: Category: Bread — hallucinated/incorrect category label (should be Baking per reference, and not present in original)

### 08_ocr_medium — issues
- FIDELITY: quantities_changed: Serves listed as '4' instead of '4 to 6'
- FIDELITY: prep_in_name: Basil (fresh): For garnish. — preparation/serving note placed in ingredient name field rather than as a separate prep note

### 09_clean_simple — issues
- FIDELITY: detritus_retained: Preamble line 'A go-to dressing for any salad. Adjust the ratio to taste.' retained (minor — also in reference)

### 10_clean_medium — issues
- FIDELITY: quantities_changed: Olive oil: original says 'generous pour', output omits quantity descriptor, Cumin: original says 'a big pinch', output omits quantity descriptor, Cilantro: original says 'a big handful', output omits quantity descriptor, Flank steak: original says 'about 2 lbs, give or take', output says '2 lbs' dropping the approximation language
- FIDELITY: instructions_dropped: 'Slice the steak thin against the grain' moved from instructions into an ingredient prep note rather than appearing as a standalone instruction step, 'Cook til you run out of steak' closing line omitted entirely
- FIDELITY: instructions_rewritten: 'room temp' changed to 'room temperature'
- FIDELITY: prep_in_name: Steak: Sliced thin against the grain — slicing instruction placed as ingredient prep note rather than in instructions
