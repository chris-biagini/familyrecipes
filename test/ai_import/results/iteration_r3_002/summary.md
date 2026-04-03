# Iteration iteration_r3_002

| Recipe | Parse | Format | Fidelity | Detritus | Aggregate |
|--------|-------|--------|----------|----------|-----------|
| 01_blog_brownies | PASS | 100.0% | 97 | 97 | 97.9 |
| 02_blog_bolognese | PASS | 100.0% | 95 | 100 | 98.0 |
| 03_blog_chicken_tikka | PASS | 100.0% | 97 | 90 | 95.8 |
| 04_blog_chocolate_cookies | PASS | 100.0% | 80 | 97 | 91.1 |
| 05_card_grilled_cheese | PASS | 100.0% | 82 | 95 | 91.3 |
| 06_card_pizza_dough | PASS | 100.0% | 97 | 97 | 97.9 |
| 07_card_pot_pie | PASS | 100.0% | 97 | 97 | 97.9 |
| 08_clean_roast_chicken | PASS | 100.0% | 97 | 95 | 97.3 |
| 09_clean_banana_bread | PASS | 100.0% | 90 | 100 | 96.0 |
| 10_baking_crusty_bread | PASS | 100.0% | 88 | 85 | 90.7 |

**Overall:** 95.4 avg, [97.9, 98.0, 95.8, 91.1, 91.3, 97.9, 97.9, 97.3, 96.0, 90.7] worst

### 02_blog_bolognese — issues
- FIDELITY: quantities_changed: Sugar listed without the qualifier 'if needed' being in the ingredient entry (though it is mentioned in the substitution notes at the bottom), Red wine quantity converted from '1/2 cup (125 ml)' to '125 ml' only — dual format dropped but value is accurate
- FIDELITY: detritus_retained: Nutrition information was correctly excluded; no detritus retained

### 03_blog_chicken_tikka — issues
- FIDELITY: detritus_retained: 'Substitute ghee for the butter. Cilantro is optional as a garnish.' — these notes in the footer attribution line are added commentary not present as a standalone statement in the original (ghee substitution is inline in ingredients, cilantro mention is in instructions); minor but slightly beyond a clean attribution

### 04_blog_chocolate_cookies — issues
- FIDELITY: quantities_changed: Flour changed from '2 1/4 cups (281g)' to '281 g' only — cup measurement dropped, Butter changed from '3/4 cup (170g/12 Tbsp)' to '170 g' only — cup and tbsp measurements dropped, Brown sugar changed from '3/4 cup (150g)' to '150 g' only — cup measurement dropped, Granulated sugar changed from '1/2 cup (100g)' to '100 g' only — cup measurement dropped, Chocolate chips changed from '1 1/4 cups (225g)' to '225 g' only — cup measurement dropped, Vanilla extract changed from '2 teaspoons pure vanilla extract' to '2 tsp' — 'pure' qualifier dropped, Makes line shows '16 cookies' but original specifies '16 XL cookies or 20 medium/large cookies'

### 05_card_grilled_cheese — issues
- FIDELITY: quantities_changed: Vintage cheddar or gruyere listed as two options in original; output splits cheddar into its own ingredient and mentions gruyere only as a substitution note in the footer — acceptable but a minor structural change, Butter has no quantity in either, consistent
- FIDELITY: instructions_dropped: Light toasting step before adding cheese is preserved but condensed, Use of heavy-based skillet not mentioned
- FIDELITY: instructions_rewritten: Instructions condensed into a short paragraph rather than preserving the original's step-by-step structure, though the original was also not highly detailed
- FIDELITY: prep_leaked_into_name: Cheddar (vintage), freshly grated — 'freshly grated' is prep info in the name field rather than after the colon, Mozzarella (fresh), grated — 'grated' is prep info in the name field rather than after the colon

### 07_card_pot_pie — issues
- FIDELITY: quantities_changed: Flour changed from 1/3 cup to 1/3 cup — actually correct, no change

### 08_clean_roast_chicken — issues
- FIDELITY: quantities_changed: Salt and pepper listed as '1/2 tsp each' in original for butter section — output splits into separate '1/2 tsp' lines for each, which is accurate; no actual change

### 09_clean_banana_bread — issues
- FIDELITY: quantities_changed: Sugar: original says 'cane sugar or brown sugar' but output changes to 'Sugar (white)' — this misrepresents the original, which lists cane sugar as the first option, not white sugar
- FIDELITY: instructions_rewritten: Substitution notes moved to a footer paragraph rather than being integrated into the ingredient list, but content is preserved

### 10_baking_crusty_bread — issues
- FIDELITY: quantities_changed: All quantities converted from original mixed (cups/grams) to grams only; original listed both e.g. '7½ cups (900g)' but output lists only '900g'
- FIDELITY: detritus_retained: 'Imperial equivalents: 7 1/2 cups flour, 3 cups water, 1 tablespoon salt, 1 1/2 tablespoons yeast.' — this is a redundant footer note not part of the recipe format, Rating and review count not expected but also not present — no issue, '2026 Recipe of the Year' / '2016 Recipe of the Year' recognition blurb omitted — acceptable as detritus removal
