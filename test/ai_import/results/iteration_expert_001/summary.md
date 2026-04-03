# Iteration iteration_expert_001

| Recipe | Parse | Format | Fidelity | Detritus | Aggregate |
|--------|-------|--------|----------|----------|-----------|
| 01_blog_brownies | PASS | 91.7% | 97 | 95 | 94.8 |
| 02_blog_bolognese | PASS | 91.7% | 95 | 92 | 93.1 |
| 03_blog_chicken_tikka | PASS | 91.7% | 91 | 95 | 92.4 |
| 04_blog_chocolate_cookies | PASS | 91.7% | 88 | 95 | 91.2 |
| 05_card_grilled_cheese | PASS | 83.3% | 88 | 82 | 84.8 |
| 06_card_pizza_dough | PASS | 91.7% | 95 | 95 | 94.0 |
| 07_card_pot_pie | PASS | 91.7% | 95 | 97 | 94.6 |
| 08_clean_roast_chicken | PASS | 91.7% | 97 | 98 | 95.7 |
| 09_clean_banana_bread | PASS | 91.7% | 78 | 82 | 83.3 |
| 10_baking_crusty_bread | PASS | 91.7% | 92 | 78 | 87.7 |

**Overall:** 91.2 avg, [94.8, 93.1, 92.4, 91.2, 84.8, 94.0, 94.6, 95.7, 83.3, 87.7] worst

### 01_blog_brownies — issues
- FORMAT: no_tags_invented
- FIDELITY: detritus_retained: Rating & Reception section omitted correctly, but rating info not retained — this is correct behavior, no issue
- FIDELITY: tags_invented: Tags: gluten-free, baked — tags were added without instruction to do so

### 02_blog_bolognese — issues
- FORMAT: no_tags_invented
- FIDELITY: instructions_rewritten: 'cook 3 minutes until light golden and softened' became 'about 3 minutes until softened and light golden' — minor reordering but not substantial
- FIDELITY: tags_invented: Tags: weeknight, italian — tags were not present in the original and should not have been added

### 03_blog_chicken_tikka — issues
- FORMAT: no_tags_invented
- FIDELITY: ingredients_missing: Basmati rice (listed as serving ingredient in original)
- FIDELITY: quantities_changed: Butter for sauce base: original specifies '30g unsalted butter or ghee' — output splits into two entries but drops the 'or ghee' variant note (minor); same for 50g butter
- FIDELITY: tags_invented: Tags: indian, comfort-food — tags were not present in original and should not have been added

### 04_blog_chocolate_cookies — issues
- FORMAT: no_tags_invented
- FIDELITY: quantities_changed: Butter listed as '3/4 cup' without the gram equivalents (170g/12 Tbsp) — minor omission but not a change, Vanilla extract listed as '2 tsp' instead of '2 teaspoons pure vanilla extract' — acceptable
- FIDELITY: instructions_dropped: Instruction note that egg should also be at room temperature (only egg yolk is noted as room temperature in output)
- FIDELITY: instructions_rewritten: 'Centers will look soft' changed to 'centers will look underdone' — subtle meaning shift, 'Chilling overnight prevents overspreading' moved from step 3 to footer note rather than appearing in context of the refrigeration step
- FIDELITY: tags_invented: Tags: vegetarian, baked — tags should not be added

### 05_card_grilled_cheese — issues
- FORMAT: prep_notes_formatted — 1.3-1.5 cm thick.
- FORMAT: no_tags_invented
- FIDELITY: quantities_changed: Butter has no quantity specified (original says 'for spreading' which is preserved, but salted butter quantity is inherently informal — acceptable)
- FIDELITY: detritus_retained: Rating information not present — correctly excluded, Substitute Gruyère for vintage cheddar if preferred — this is a minor hallucinated substitution note not present in original (original lists both as options, not as a substitution tip)
- FIDELITY: tags_invented: Tags: vegetarian, quick — tags should not be added

**Output snippet (first 20 lines):**
```
# Grilled Cheese Sandwich

Worth it.

Serves: 1
Category: Mains
Tags: vegetarian, quick

## Assemble and cook.

- Sourdough bread, 2 slices: 1.3-1.5 cm thick.
- Butter (salted): For spreading.
- Cheddar (vintage) or Gruyère: Freshly grated.
- Mozzarella (fresh): Grated.

Butter both sides of each bread slice. Heat heavy-based skillet over medium. Lightly toast bread, then add cheese and cook about 3 minutes per side until exterior is crispy and cheese is melted.

---

Recipe by Nagi, RecipeTin Eats. Substitute Gruyère for vintage cheddar if preferred.
```

### 06_card_pizza_dough — issues
- FORMAT: no_tags_invented
- FIDELITY: tags_invented: Tags: vegetarian — tags should not be added

### 07_card_pot_pie — issues
- FORMAT: no_tags_invented
- FIDELITY: instructions_dropped: Note that some uncooked chicken parts after poaching are fine (mentioned in original, omitted in output)
- FIDELITY: instructions_rewritten: 'cool in fridge' changed to 'Refrigerate' — minor but acceptable paraphrase
- FIDELITY: tags_invented: Tags: comfort-food, make-ahead, freezer-friendly — tags were added without instruction to do so

### 08_clean_roast_chicken — issues
- FORMAT: no_tags_invented
- FIDELITY: quantities_changed: Salt and black pepper listed as '1/2 tsp each' in original; OUTPUT splits them into separate '1/2 tsp' lines each — technically accurate but changes presentation
- FIDELITY: tags_invented: Tags: roasted — tags line was added without instruction to do so

### 09_clean_banana_bread — issues
- FORMAT: no_tags_invented
- FIDELITY: quantities_changed: Sugar: original says 'cane sugar or brown sugar' but output says 'Sugar (white)' — changes the default/type implied, Butter: original says 'melted butter or vegetable oil' but output labels it as '(unsalted)' — unsalted not specified in original
- FIDELITY: instructions_dropped: Step 4 specifies 'fold in ½ cup walnuts' separately from topping — preserved in instructions but the split quantity is merged in the ingredient line as '1/2 cup + 2 tbsp'
- FIDELITY: instructions_rewritten: 'stirring until just combined without overmixing' paraphrased to 'stirring until just combined — don't overmix' — minor but notable, 'top springs back when touched' changed to 'top springs back when pressed'
- FIDELITY: detritus_retained: Substitution suggestions ('Substitute vegetable oil for the butter. Substitute brown sugar for white.') are editorial additions not part of the original recipe instructions
- FIDELITY: tags_invented: Tags: vegetarian, baked, comfort-food — tags should not be added

**Output snippet (first 20 lines):**
```
# Banana Bread

Moist, simple, reliable.

Serves: 8
Category: Baking
Tags: vegetarian, baked, comfort-food

## Mix and bake.

- Banana, 2 cups: Mashed very ripe (about 4 large).
- Sugar (white), 1/2 cup
- Butter (unsalted), 1/2 cup: Melted.
- Egg, 2
- Vanilla extract, 1 tsp
- Flour (all-purpose), 1 1/2 cups
- Baking soda, 1 tsp
- Salt, 1/2 tsp
- Cinnamon, 1/2 tsp
- Nutmeg, 1/4 tsp

```

### 10_baking_crusty_bread — issues
- FORMAT: no_tags_invented
- FIDELITY: detritus_retained: Tags: make-ahead — tags should not be added, Imperial equivalents footer line is not part of the original recipe and adds unrequested content
- FIDELITY: tags_invented: make-ahead

**Output snippet (first 20 lines):**
```
# No-Knead Crusty White Bread

Fridge does the work.

Makes: 4 loaves
Category: Bread
Tags: make-ahead

## Mix and rest dough.

- Flour (all-purpose), 900 g
- Water, 680 g: Lukewarm.
- Salt, 18 g
- Yeast, 14 g

Combine all ingredients, mixing until a sticky, shaggy dough forms. Cover and rest at room temperature 2 hours, then refrigerate 2-7 days.

## Shape and bake.

Preheat oven to 450°F with steam setup ready. Tear off about one-quarter of the dough, shape into a round, and let rise about 60 minutes. Score surface and bake 25-35 minutes until deep golden and hollow-sounding when tapped.

```
