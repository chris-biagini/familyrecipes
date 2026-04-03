# Iteration iteration_baseline_v3

| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Aggregate |
|--------|-------|--------|--------|----------|----------|-------|-----------|
| 01_blog_serious_eats_a | PASS | PASS | 75.0% | 93 | 100 | 100 | 93.3 |
| 03_blog_serious_eats_c | PASS | PASS | 100.0% | 85 | 82 | 100 | 91.8 |
| 04_blog_smitten_kitchen | PASS | PASS | 100.0% | 79 | 78 | 100 | 89.3 |
| 05_blog_budget_bytes | PASS | PASS | 100.0% | 93 | 100 | 100 | 98.3 |
| 06_blog_pioneer_woman | PASS | PASS | 100.0% | 80 | 85 | 100 | 91.3 |
| 07_blog_bon_appetit | PASS | PASS | 100.0% | 87 | 97 | 100 | 96.0 |
| 08_agg_allrecipes | PASS | PASS | 91.7% | 88 | 97 | 98 | 94.0 |
| 10_agg_epicurious | PASS | PASS | 100.0% | 90 | 97 | 100 | 96.8 |
| 11_agg_nyt_style | PASS | PASS | 100.0% | 89 | 95 | 100 | 96.0 |
| 12_ocr_biscuits | PASS | PASS | 100.0% | 96 | 100 | 100 | 99.0 |
| 13_ocr_beef_stew | PASS | PASS | 100.0% | 93 | 97 | 100 | 97.5 |
| 15_clean_text_message | PASS | PASS | 100.0% | 88 | 80 | 98 | 91.4 |
| 16_clean_email | PASS | PASS | 100.0% | 87 | 96 | 98 | 95.2 |

**Overall:** 94.6 avg, 89.3 worst

### 01_blog_serious_eats_a — issues
- FORMAT: prep_notes_formatted — 2 cups roughly chopped, 1 cup left whole.
- FORMAT: single_divider
- FORMAT: step_splitting_appropriate — Expected explicit (2+ named steps) but got 1 steps, headers=false
- FIDELITY: quantities_changed: Pie dough: 'easy' descriptor dropped from 'easy pie dough', Flour: 'divided' prep note dropped from ingredient line, Vanilla: renamed to 'Vanilla extract' — original says only 'vanilla', Sugar in pie dough: '(white)' descriptor added, original says only 'sugar'

### 03_blog_serious_eats_c — issues
- FIDELITY: quantities_changed: Serves changed from '6 to 8 servings' to '8' — lower end of range dropped, Foie gras lost sizing detail 'about 2 1/2-inch slabs', Shallots lost volume equivalent '(about 1/2 cup)'
- FIDELITY: instructions_dropped: All timing metadata dropped (Prep 40 mins, Cook 90 mins, Active 90 mins, Chilling Time 90 mins, Total 3 hrs 40 mins), Puff pastry note 'using this recipe' link/reference dropped
- FIDELITY: instructions_rewritten: Foie gras pate note: 'skip step 7' rewritten to 'skip searing it'; 'In step 9' rewritten to 'during assembly', Puff pastry descriptor 'frozen or homemade' dropped from ingredient line and not noted in footer, Oil 'divided' dropped from quantity
- FIDELITY: detritus_retained: Footer note 'Any mushroom variety works — button, cremini, shiitake, portabello, or a mix' repackages inline ingredient info, Footer note 'Substitute spicy brown or hot English mustard for Dijon mustard' repackages inline ingredient alternatives, Footer note 'Substitute canola oil for vegetable oil' repackages inline ingredient alternatives, Footer note 'Substitute other brandy or barrel-aged spirit, such as bourbon, for Cognac' repackages inline ingredient alternatives, Footer note 'Coarse sea salt such as Maldon or fleur de sel works well here' repackages inline ingredient info

### 04_blog_smitten_kitchen — issues
- FIDELITY: quantities_changed: Butter: original '9 tablespoons (127 grams)' provided both imperial and metric; output splits into '1 tbsp' + '8 tbsp' (imperial) and drops the 127g metric measurement entirely, Butter imperial equivalent also missing from the footer
- FIDELITY: instructions_dropped: Yield '10 3-inch (big!) biscuits' reduced to 'Makes: 10 biscuits' — loses the 3-inch size and '(big!)' note
- FIDELITY: instructions_rewritten: '10 to 20 more minutes' → '10-20 more minutes' (minor formatting), '20 to 23 minutes' → '20-23 minutes' (minor formatting)
- FIDELITY: detritus_retained: Footer note 'Substitute another Swiss-style cheese for gruyère.' is an invented substitution suggestion — the original simply lists 'gruyère or another Swiss-style cheese' as co-equal options in the ingredient line, Footer note 'Kosher salt may be substituted for coarse salt.' is invented — the original says 'coarse or kosher salt' (listed as equals, not as a substitution), Footer note 'Buttermilk can be made at home.' is a rephrasing of the original's inline '(or make your own)' repackaged as a footer tip

**Output snippet (first 20 lines):**
```
# Caramelized Onion and Gruyère Biscuits

Makes: 10 biscuits
Category: Baking
Tags: vegetarian, baked

- Butter (unsalted), 1 tbsp
- Olive oil, 1 tbsp
- Onion (small), 2: Halved and thinly sliced.
- Butter (unsalted), 8 tbsp: Cold, diced into 1/2-inch bits.
- Flour (all-purpose), 345 g
- Sugar (white), 15 g
- Baking powder, 2 tsp
- Baking soda, 1 tsp
- Salt (coarse), 3/4 tsp
- Gruyère, 115 g: Cut into 1/2-inch cubes.
- Buttermilk, 1 cup
- Salt (flaky)
- Black pepper: Freshly ground.


```

### 05_blog_budget_bytes — issues
- FIDELITY: instructions_rewritten: Note about ground beef condensed: 'Ground beef is the base for this recipe, and I suggest using 80/20 (20% fat) ground beef.' → 'Use 80/20 (20% fat) ground beef.', Note about sugar slightly reworded: 'But I know ketchup is already pretty sweet' → 'But ketchup is already pretty sweet'

### 06_blog_pioneer_woman — issues
- FIDELITY: quantities_changed: Serves changed from '6 - 8 serving(s)' to '8'
- FIDELITY: instructions_dropped: Prep Time (30 mins) and Total Time (2 hrs) not included
- FIDELITY: detritus_retained: Invented footer note: 'Substitute regular cornmeal for the masa harina' repackages inline ingredient alternative into a substitution suggestion, Invented footer note: 'Shredded cheddar, crumbled bacon, and sliced jalapeños are for topping' summarizes ingredient-list info as a new sentence

### 07_blog_bon_appetit — issues
- FIDELITY: quantities_changed: Serves changed from '4-6 servings' to '6', Flour gram weight '(187 g)' dropped from ingredient line (divided portions 31 g and 156 g still present in instructions), Potatoes descriptor 'about 2 large' dropped from ingredient line, Dijon mustard '(or more)' reworded to 'Plus more to taste', Salt: 'Diamond Crystal or 1 1/2 tsp. Morton' dual-brand distinction removed from ingredient line (covered in footer), Pepper: 'divided' and 'plus more' changed to 'Plus more to taste'; 'Black' added to name without basis in original
- FIDELITY: instructions_dropped: Total time '1 hour 45 minutes' not included anywhere in the output, 'divided' note dropped from flour, salt, and pepper ingredient lines (though instructions make the division clear)
- FIDELITY: instructions_rewritten: Step 3: '425°' changed to '425°F' (minor clarification addition)

### 08_agg_allrecipes — issues
- FORMAT: prep_notes_formatted — 8-oz loaves, split.
- FIDELITY: quantities_changed: Pork: original includes '(12 ounces)' weight equivalent, output drops it, Ham: original includes '(18 ounces)' weight equivalent, output drops it
- FIDELITY: instructions_dropped: Prep time (20 mins), cook time (20 mins), and total time (40 mins) are omitted
- FIDELITY: instructions_rewritten: '6 to 8 minutes' changed to '6-8 minutes' (minor formatting), '1 to 1 1/2 hours' changed to '1-1 1/2 hours' (minor formatting), Temperature notation changed from 'degrees F' to '°F' (cosmetic)
- STEPS: flow_issues: The skillet-readiness tip from the original's introduction was relocated to the end of the output, after the roasted pork footnote — minor positional shift of supplementary content

### 10_agg_epicurious — issues
- FIDELITY: quantities_changed: Salt: 'divided' usage note dropped from '1 tablespoon plus 1 teaspoon kosher salt, divided', Parsley: 'leaves' descriptor dropped from '1 tablespoon chopped fresh parsley leaves'
- FIDELITY: instructions_dropped: Active time (35 minutes) and total time (6 hours 35 minutes) not preserved anywhere in the output
- FIDELITY: instructions_rewritten: '2 to 3 minutes' changed to '2-3 minutes', '250 degrees F' changed to '250°F' (minor formatting)

### 11_agg_nyt_style — issues
- FIDELITY: quantities_changed: Flour: original says 'all-purpose or bread flour' — the 'or bread flour' alternative is dropped from the output, Makes line: original says 'One 1 1/2-pound loaf' — output says '1 loaf', dropping the weight
- FIDELITY: instructions_rewritten: Step 1: '1 1/2 cups/345 grams water' replaced with just 'water' (quantity moved to ingredient list — acceptable), '15 to 30 minutes' compressed to '15-30 minutes' — trivial formatting change
- FIDELITY: detritus_retained: Footer note 'Or wheat bran in place of cornmeal.' repackages information from the original ingredient line ('Cornmeal or wheat bran, as needed') into an invented substitution note

### 13_ocr_beef_stew — issues
- FIDELITY: instructions_rewritten: Section header 'For the beef:' rewritten as step title 'Brown the beef.', Section header 'For the stew:' rewritten as step title 'Make the stew.'

### 15_clean_text_message — issues
- FIDELITY: instructions_rewritten: Minor punctuation: 'dont overmix it should be chunky' → 'Dont overmix, it should be chunky.' (added comma)
- FIDELITY: detritus_retained: Hallucinated tags not in original: 'vegan, gluten-free, quick, easy', Footer note 'Use less jalapeño if u dont like spicy' repackages inline ingredient info into an invented summary note
- STEPS: flow_issues: The jalapeño spice-level note was originally part of the ingredient line but was moved to a separate footer note after a horizontal rule, slightly reorganizing the source content

### 16_clean_email — issues
- FIDELITY: ingredients_added: Water (extracted from instructions — acceptable), Lemon (extracted from instructions — acceptable)
- FIDELITY: quantities_changed: Chicken: original says '1 whole chicken (about 3-4 lbs)', output drops the '1' count — 'Chicken (whole), about 3-4 lbs', Lemon: original says 'a squeeze of lemon', output invents 'Lemon, 1' — quantity '1' is not in the source, Pepper: original says 'pepper', output says 'Black pepper' — descriptor 'Black' added without basis
- STEPS: flow_issues: The lemon note was originally part of the final instruction paragraph ('Dad always adds a squeeze of lemon at the table but that's optional') but was separated out below a horizontal rule, splitting a single source paragraph into two distinct sections.
