# Iteration iteration_002

| Recipe | Parse | Format | Fidelity | Detritus | Aggregate |
|--------|-------|--------|----------|----------|-----------|
| 01_blog_simple | PASS | 100.0% | 97 | 98 | 98.2 |
| 02_blog_medium | PASS | 100.0% | 95 | 82 | 92.6 |
| 03_blog_complex | PASS | 100.0% | 97 | 88 | 95.2 |
| 04_card_simple | PASS | 100.0% | 97 | 85 | 94.3 |
| 05_card_medium | PASS | 100.0% | 97 | 99 | 98.5 |
| 06_card_complex | PASS | 100.0% | 93 | 88 | 93.6 |
| 07_ocr_simple | PASS | 100.0% | 97 | 95 | 97.3 |
| 08_ocr_medium | PASS | 100.0% | 95 | 88 | 94.4 |
| 09_clean_simple | PASS | 100.0% | 97 | 92 | 96.4 |
| 10_clean_medium | PASS | 100.0% | 88 | 97 | 94.3 |

**Overall:** 95.5 avg, 92.6 worst

### 01_blog_simple — issues
- FIDELITY: prep_in_name: Butter (unsalted), 4 tbsp: Softened., Garlic, 3 cloves: Minced., Parsley (fresh), 2 tbsp: Chopped.

### 02_blog_medium — issues
- FIDELITY: detritus_retained: "Comes together in about 30 minutes." (blog narrative), "Tags: weeknight, easy, quick" (metadata not in original recipe block)

### 03_blog_complex — issues
- FIDELITY: detritus_retained: Soft, gooey, and perfect for Christmas morning. (subtitle retained from blog headline — minor), Tags: make-ahead (not in original recipe metadata)

### 04_card_simple — issues
- FIDELITY: detritus_retained: Tags: vegetarian, quick, weeknight — not present in original
- FIDELITY: prep_in_name: Onion, 1 medium: Diced., Garlic, 3 cloves: Minced., Basil (fresh): For garnish.

### 05_card_medium — issues
- FIDELITY: prep_in_name: Beef chuck roast, 2 lbs: Cut into 1 1/2-inch cubes., Onion, 1 large: Diced., Garlic, 4 cloves: Minced., Potatoes (Yukon Gold), 3 medium: Cut into 1-inch cubes., Carrots, 3 large: Peeled and sliced into 1/2-inch rounds., Celery, 2 stalks: Sliced.

### 06_card_complex — issues
- FIDELITY: instructions_dropped: The proofing step (step 5) was placed under 'Shape the dough' section rather than 'Proof and bake' section, misaligning the instruction grouping
- FIDELITY: detritus_retained: 'Sesame seeds, flaky sea salt, and rolled oats are optional toppings.' — redundant trailing line not in original recipe content
- FIDELITY: prep_in_name: Water (warm), 350 g: Around 100°F. — 'warm' is a prep descriptor in the ingredient name, Rice flour, 30 g: For dusting the banneton. — prep note leaked into ingredient entry, Sesame seeds, 10 g: Optional. — substitution/usage note in ingredient name, Flaky sea salt, 2 g: Optional. — substitution/usage note in ingredient name, Rolled oats, 15 g: Optional. — substitution/usage note in ingredient name

### 07_ocr_simple — issues
- FIDELITY: detritus_retained: Category: Bread — hallucinated/incorrect category metadata not present in original (reference says 'Baking')
- FIDELITY: prep_in_name: Butter (cold), 1/3 cup: Cut into small pieces.

### 08_ocr_medium — issues
- FIDELITY: quantities_changed: Serves listed as '4' instead of '4 to 6'
- FIDELITY: detritus_retained: Footer note 'Fresh basil is for garnish. Reserve 1/2 cup of pasta water for tossing with the finished dish.' is redundant elaboration not in original recipe text, though minor

### 09_clean_simple — issues
- FIDELITY: detritus_retained: "A go-to dressing for any salad. Adjust the ratio to taste." — preamble/description retained (though reference also keeps it, so minor)

### 10_clean_medium — issues
- FIDELITY: ingredients_added: Steak (as a separate assembly ingredient — redundant since it's already in marinade section)
- FIDELITY: instructions_dropped: "Cook til you run out of steak" closing line omitted
- FIDELITY: detritus_retained: "So this is my go-to taco situation when we have people over. It's dead simple but everyone always asks for the recipe." — blog preamble removed, which is correct; none retained
- FIDELITY: prep_in_name: Garlic, 3 cloves: Smashed. — prep note formatted as part of ingredient entry (acceptable style), White onion, 1: Diced. — prep note in ingredient entry (acceptable style), Avocado, 1: Sliced. — prep instruction leaked into ingredient name without basis; original does not specify sliced avocado in the ingredient list, Steak: Sliced thin against the grain. — a duplicate ingredient entry with prep instruction embedded; steak is already listed in marinade section
