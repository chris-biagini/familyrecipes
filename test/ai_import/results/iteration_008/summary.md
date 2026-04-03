# Iteration iteration_008

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-----------|
| 01_blog_serious_eats_a | PASS | PASS | 83.3% | 0 | 0 | 100 | 46.7 |
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 93 | 98 | 100 | 97.8 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 90 | 97 | 100 | 96.8 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 93 | 97 | 100 | 97.5 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 91 | 92 | 100 | 95.8 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 86 | 95 | 100 | 95.3 |
| 08_agg_allrecipes | PASS | PASS | 100.0% | 93 | 95 | 100 | 97.0 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 95 | 100 | 100 | 98.8 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 82 | 78 | 100 | 90.0 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 96 | 100 | 100 | 99.0 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 95 | 100 | 100 | 98.8 |
| 15_clean_text_message | PASS | PASS | 100.0% | 90 | 100 | 100 | 97.5 |
| 16_clean_email | PASS | PASS | 100.0% | 88 | 95 | 100 | 95.8 |

**Overall:** 92.8 avg, 46.7 worst

### 01_blog_serious_eats_a — issues
- FORMAT: single_divider
- FORMAT: step_splitting_appropriate — Expected explicit (2+ named steps) but got 1 steps, headers=false

**Output snippet (first 20 lines):**
```
# Classic Pecan Pie

Serves: 8
Category: Dessert

- Pie dough (easy), 1/2 recipe
- Eggs, 3: Beaten.
- Honey, 2 tbsp
- Corn syrup (light), 1 cup
- Sugar (brown), 1/4 cup
- Butter, 4 tbsp: Melted and cooled.
- Salt, 1/2 tsp
- Vanilla extract, 1 tsp
- Pecans, 3 cups: Toasted. 2 cups roughly chopped, 1 cup left whole.

Adjust oven rack to lower-middle position and preheat oven to 375°F (190°C).

Roll pie dough into a circle roughly 12-inches in diameter. Transfer to a 9-inch pie plate. Using a pair of kitchen shears, trim the edges of the pie dough until it overhangs the edge of the pie plate by 1/2 an inch all the way around. Fold edges of pie dough down, tucking it under itself, working your way all the way around the pie plate until everything is well tucked. Use the forefinger on your left hand and the thumb and forefinger on your right hand to crimp the edges. If a well-done crust is desired, you may chill and blind bake it before proceeding.

In a large bowl, whisk together eggs, honey, corn syrup, brown sugar, melted butter, salt, and vanilla. Whisk for approximately 30 seconds, until the mixture is homogenous and slightly frothy.

```

### 03_blog_serious_eats_c — issues
- FIDELITY: quantities_changed: Serves changed from '6 to 8 servings' to '8', Shallots: 'medium' descriptor dropped, Thyme: 'leaves' descriptor dropped from 'fresh thyme leaves'
- FIDELITY: instructions_rewritten: '35 to 45 minutes' changed to '35-45 minutes' (minor formatting)

### 04_blog_smitten_kitchen — issues
- FIDELITY: quantities_changed: Butter prep note adds 'Divided' — implied by instructions but not stated in the ingredient line, Yield simplified from '10 3-inch (big!) biscuits' to '10 biscuits' — lost biscuit size info

### 06_blog_pioneer_woman — issues
- FIDELITY: ingredients_added: "(canned)" added as descriptor to tomato sauce and tomato paste — original lists them as "cans" in the quantity but does not use "canned" as a name descriptor
- FIDELITY: quantities_changed: Serves changed from "6 - 8" to "8" — lost the lower end of the range
- FIDELITY: detritus_retained: Footer note "Cheddar, bacon, and jalapeños are for topping" repackages inline information already conveyed by the ingredient list context — counts as an invented summary note

### 07_blog_bon_appetit — issues
- FIDELITY: quantities_changed: Serves changed from '4-6 servings' to '6' — lost the range, Potatoes lost '(about 2 large)' descriptor from the original, Salt lost 'Diamond Crystal' brand and 'or 1 1/2 tsp. Morton' alternative from ingredient line (Morton partially noted in footer but Diamond Crystal omitted entirely), Dijon mustard '(or more)' changed to 'Plus more to taste', Salt and pepper 'plus more' changed to 'plus more to taste' — original did not say 'to taste', Pepper described as 'Black pepper' — original says 'freshly ground pepper' without specifying black

### 08_agg_allrecipes — issues
- FIDELITY: quantities_changed: Ham: original specifies '18 slices deli smoked ham (18 ounces)' with weight; output drops the '(18 ounces)' weight
- FIDELITY: instructions_rewritten: Step 3: 'Tbsp.' normalized to 'tablespoons' — trivial

### 10_agg_epicurious — issues
- FIDELITY: instructions_rewritten: '2 to 3 minutes' changed to '2-3 minutes', '250 degrees F' changed to '250°F' (equivalent formatting change)

### 11_agg_nyt_style — issues
- FIDELITY: quantities_changed: Yield changed from 'One 1 1/2-pound loaf' to '1 loaf' — lost the weight detail
- FIDELITY: instructions_rewritten: 'about 70 degrees' changed to 'about 70°F' — unit symbol added where original just said 'degrees', '15 to 30 minutes' changed to '15-30 minutes' — minor formatting
- FIDELITY: detritus_retained: Footer substitution notes ('Or bread flour in place of all-purpose flour. Or wheat bran in place of cornmeal.') are invented framings — the original listed these as co-equal alternatives in the ingredient line, not as substitution suggestions, Footer historical note ('The original recipe called for 3 cups flour; updated to 3 1/3 cups/430 grams after receiving reader feedback') is headnote/blog context, not recipe content

### 13_ocr_beef_stew — issues
- FIDELITY: instructions_rewritten: "simmer for l l/2 to 2 hours" → "simmer for 1 1/2-2 hours" — 'to' replaced with hyphen

### 15_clean_text_message — issues
- FIDELITY: instructions_dropped: Jalapeño qualifier 'if u dont like spicy' is lost from the output
- FIDELITY: instructions_rewritten: Cilantro note 'if u have it' reworded to 'Optional.'

### 16_clean_email — issues
- FIDELITY: ingredients_added: Lemon (extracted from a casual serving suggestion about what Dad does, not a listed ingredient)
- FIDELITY: quantities_changed: Chicken: original '1 whole chicken (about 3-4 lbs)' → output 'Chicken (whole), about 3-4 lbs' (count '1' dropped), Pepper: original 'pepper' → output 'Black pepper' (descriptor 'Black' added without basis in original)
