# Iteration iteration_r2_002

| Recipe | Parse | Format | Fidelity | Detritus | Aggregate |
|--------|-------|--------|----------|----------|-----------|
| 01_blog_brownies | PASS | 100.0% | 97 | 97 | 97.9 |
| 02_blog_bolognese | PASS | 100.0% | 95 | 97 | 97.1 |
| 03_blog_chicken_tikka | PASS | 100.0% | 97 | 97 | 97.9 |
| 04_blog_chocolate_cookies | PASS | 100.0% | 88 | 100 | 95.2 |
| 05_card_grilled_cheese | PASS | 100.0% | 88 | 97 | 94.3 |
| 06_card_pizza_dough | PASS | 100.0% | 95 | 97 | 97.1 |
| 07_card_pot_pie | PASS | 100.0% | 95 | 82 | 92.6 |
| 08_clean_roast_chicken | PASS | 100.0% | 82 | 97 | 91.9 |
| 09_clean_banana_bread | PASS | 100.0% | 93 | 97 | 96.3 |
| 10_baking_crusty_bread | PASS | 100.0% | 88 | 97 | 94.3 |

**Overall:** 95.5 avg, [97.9, 97.1, 97.9, 95.2, 94.3, 97.1, 92.6, 91.9, 96.3, 94.3] worst

### 03_blog_chicken_tikka — issues
- FIDELITY: ingredients_added: Optional cilantro for garnish (not listed as ingredient in original, only mentioned in instructions)

### 04_blog_chocolate_cookies — issues
- FIDELITY: quantities_changed: Butter listed as '3/4 cup' but original specifies '3/4 cup (170g/12 Tbsp)' — metric and tablespoon equivalents dropped (minor), Chocolate chips listed as '1 1/4 cups' but original specifies '1 1/4 cups (225g)' — metric dropped (minor), Vanilla extract listed as '2 teaspoons' but original specifies '2 teaspoons pure vanilla extract' — 'pure' moved out (very minor)
- FIDELITY: instructions_dropped: Temperature in Celsius (163°C) omitted from preheat instruction
- FIDELITY: instructions_rewritten: Yield note reworded: original states '16 XL cookies or 20 medium/large cookies'; output Makes line says '16 cookies' and footer only mentions '20 medium-large cookies', losing the XL framing and pairing

### 05_card_grilled_cheese — issues
- FIDELITY: quantities_changed: Butter (salted) has no quantity in either original or output — acceptable; Cheddar and Mozzarella have no quantities in either — acceptable
- FIDELITY: instructions_rewritten: Instructions were constructed/expanded from the brief method description in the original; original did not provide a full step-by-step, so the output elaborated slightly (e.g., 'Heat a heavy-based skillet over medium heat' and 'Top each slice with...' are reasonable inferences but not explicitly stated in the original)
- FIDELITY: detritus_retained: Rating information not present — good, Publication date not present — good

### 07_card_pot_pie — issues
- FIDELITY: detritus_retained: Footer note about reviewer variations (mushrooms, green beans, mashed potato topping, GF adaptations) is drawn from user reviews, not the original recipe content

### 08_clean_roast_chicken — issues
- FIDELITY: ingredients_missing: Salt and pepper (for the chicken surface — listed as separate seasoning ingredient)
- FIDELITY: quantities_changed: Salt listed without '1/2 tsp each' quantity (from the butter section); Black pepper listed without '1/2 tsp each' quantity (from the butter section); dry white wine listed without 'or low sodium chicken broth' alternative; wine quantity missing ml equivalent (250 ml)
- FIDELITY: instructions_dropped: Fahrenheit equivalents dropped from oven temperatures in instructions (450 F and 350 F / 430 F), Internal temperature Fahrenheit equivalent dropped (165 F)

### 09_clean_banana_bread — issues
- FIDELITY: prep_leaked_into_name: Butter (melted) or vegetable oil, 1/2 cup — 'melted' is a state change that should be a prep note; also 'or vegetable oil' is a substitution note that could be handled differently, though it mirrors the original's phrasing

### 10_baking_crusty_bread — issues
- FIDELITY: quantities_changed: Flour: original gives both 7½ cups and 900g; output uses only 900g (cup measurement dropped), Water: original gives both 3 cups and 680g; output uses only 680g (cup measurement dropped), Salt: original gives both 1 tablespoon and 18g; output uses only 18g (tablespoon measurement dropped), Yeast: original gives both 1½ tablespoons and 14g; output uses only 14g (tablespoon measurement dropped)
- FIDELITY: detritus_retained: Rating: 4.70 stars from 1,453 reviews — not retained (good), 2026/2016 Recipe of the Year designation — not retained (acceptable)
