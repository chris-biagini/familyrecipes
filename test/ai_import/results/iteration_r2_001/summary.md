# Iteration iteration_r2_001

| Recipe | Parse | Format | Fidelity | Detritus | Aggregate |
|--------|-------|--------|----------|----------|-----------|
| 01_blog_brownies | PASS | 100.0% | 88 | 72 | 86.8 |
| 02_blog_bolognese | PASS | 100.0% | 30 | 85 | 67.5 |
| 03_blog_chicken_tikka | PASS | 100.0% | 94 | 85 | 93.1 |
| 04_blog_chocolate_cookies | PASS | 100.0% | 38 | 90 | 72.2 |
| 05_card_grilled_cheese | PASS | 91.7% | 82 | 78 | 83.7 |
| 06_card_pizza_dough | PASS | 100.0% | 78 | 72 | 82.8 |
| 07_card_pot_pie | PASS | 100.0% | 88 | 72 | 86.8 |
| 08_clean_roast_chicken | PASS | 100.0% | 30 | 90 | 69.0 |
| 09_clean_banana_bread | PASS | 100.0% | 91 | 82 | 91.0 |
| 10_baking_crusty_bread | PASS | 100.0% | 78 | 88 | 87.6 |

**Overall:** 82.1 avg, [86.8, 67.5, 93.1, 72.2, 83.7, 82.8, 86.8, 69.0, 91.0, 87.6] worst

### 01_blog_brownies — issues
- FIDELITY: instructions_rewritten: 'stirring between intervals until melted and smooth' was added/expanded beyond original, 'until combined' added after almond meal and rice flour step, 'Pour into prepared pan and' added before bake instruction
- FIDELITY: detritus_retained: 'Rich, fudgy gluten-free brownies with minimal ingredients.' — preamble/description not in original recipe, 'Makes: 16 brownies' and 'Category: Dessert' — category label not in original, 'Recipe from RecipeTin Eats by Nagi.' — attribution footer retained

**Output snippet (first 20 lines):**
```
# Flourless Chocolate Brownies

Rich, fudgy gluten-free brownies with minimal ingredients.

Makes: 16 brownies
Category: Dessert

- Dark chocolate chips, 1 cup
- Butter (unsalted), 85 g
- Brown sugar, 3/4 cup
- Eggs (large), 2
- Almond meal, 2/3 cup
- Rice flour, 1/3 cup
- Vanilla extract, 1 tsp
- Salt, 1/4 tsp

Preheat oven to 180°C (325°F) with rack in lower third. Grease and line a 20 cm square pan.

Melt chocolate and butter together in the microwave in 30-second intervals, stirring between intervals until melted and smooth. Cool 5 minutes, then stir in vanilla and brown sugar. Mix in eggs, then almond meal and rice flour until combined.


```

### 02_blog_bolognese — issues
- FIDELITY: ingredients_added: Olive oil, 1 tbsp, Onion, 1, Garlic, 3 cloves, Sugar, 1 tsp, Salt, Black pepper
- FIDELITY: detritus_retained: Rating: 4.98 out of 5 stars (460 ratings) — not present (good), Recipe from RecipeTin Eats — attribution line retained at bottom

**Output snippet (first 20 lines):**
```
# Spaghetti Bolognese

A quick weeknight bolognese ready in 40 minutes.

Serves: 5

## Brown the meat and aromatics.

- Olive oil, 1 tbsp
- Onion, 1: Finely diced.
- Garlic, 3 cloves: Minced.
- Ground beef, 1 lb

Heat olive oil in a large saucepan over medium-high heat. Add onion and garlic, and sauté until softened, about 2-3 minutes. Add ground beef and cook, breaking it up as it cooks, until browned, about 5-7 minutes.

## Build the sauce.

- Red wine, 1/2 cup
- Tomatoes (crushed), 28 oz can
- Tomato paste, 2 tbsp

```

### 03_blog_chicken_tikka — issues
- FIDELITY: ingredients_added: Cilantro (listed as a separate ingredient — not listed as an ingredient in the original, only mentioned in instructions)
- FIDELITY: detritus_retained: "Serves: 4" and "Category: Mains" were added without basis in the original (serves count not specified, category label differs), "Recipe from RecipeTin Eats by Nagi." attribution line at footer — minor detritus

### 04_blog_chocolate_cookies — issues
- FIDELITY: ingredients_added: Flour (all-purpose), 2 1/4 cups — quantity not in original, Baking soda, 1 tsp — quantity not in original, Cornstarch, 1 tbsp — quantity not in original, Butter (unsalted), 1 cup — quantity not in original, Sugar (brown), 3/4 cup and Sugar (light brown), 3/4 cup — original lists one brown sugar entry; output splits into two separate entries with invented quantities, Sugar (white), 1/4 cup — quantity not in original, Egg yolk, 1 large — quantity not in original, Vanilla extract, 2 tsp — quantity not in original, Salt — not mentioned in original, Chocolate chips (semi-sweet), 2 cups — quantity not in original
- FIDELITY: quantities_changed: All quantities are hallucinated; the original provides no specific measurements for any ingredient
- FIDELITY: instructions_rewritten: Detailed step-by-step mixing and baking instructions were invented/expanded; the original only summarizes preparation at a high level — cooling on wire rack, 5-minute rest, spacing of 2 inches were added without basis
- FIDELITY: detritus_retained: User review summary is correctly removed, Recipe overview/webpage description correctly removed

**Output snippet (first 20 lines):**
```
# Best Chocolate Chip Cookies

Ultra-soft, chewy chocolate chip cookies.

Makes: 24 cookies

- Flour (all-purpose), 2 1/4 cups: Spooned and leveled.
- Baking soda, 1 tsp
- Cornstarch, 1 tbsp
- Butter (unsalted), 1 cup: Melted and cooled.
- Sugar (brown), 3/4 cup
- Sugar (light brown), 3/4 cup
- Sugar (white), 1/4 cup
- Egg, 1 large
- Egg yolk, 1 large
- Vanilla extract, 2 tsp
- Salt
- Chocolate chips (semi-sweet), 2 cups

Whisk together flour, baking soda, cornstarch, and salt in a small bowl. Set aside.

```

### 05_card_grilled_cheese — issues
- FORMAT: prep_notes_formatted — 1.3-1.5 cm thick.
- FIDELITY: quantities_changed: Butter (salted) has no quantity specified — original also lacks a specific quantity, so this is acceptable; no true change
- FIDELITY: instructions_rewritten: Instructions were expanded/reconstructed beyond what the original explicitly stated — original only mentions 'butter both sides,' a light toasting step, and ~3 minutes per side; output adds 'Heat a heavy-based skillet over medium heat' and 'Top each slice with...' as explicit steps not directly quoted in the original summary
- FIDELITY: detritus_retained: 'Category: Mains' — original categorizes it as 'Sandwiches and Sliders', not 'Mains', 'Recipe by Nagi of RecipeTin Eats.' — attribution footer is marginal non-recipe content, Rating information and author bio details were correctly removed
- FIDELITY: prep_leaked_into_name: Cheddar (vintage) or gruyere, freshly grated — 'freshly grated' is a prep note but appears in the name/quantity field rather than after the colon, Mozzarella (fresh), grated — 'grated' is a prep note but appears in the name field rather than after the colon

**Output snippet (first 20 lines):**
```
# Grilled Cheese Sandwich

Makes: 1 sandwich
Category: Mains

- Sourdough bread, 2 slices: 1.3-1.5 cm thick.
- Butter (salted)
- Cheddar (vintage) or gruyere, freshly grated
- Mozzarella (fresh), grated

Butter both sides of the bread. Heat a heavy-based skillet over medium heat. Add bread slices and toast lightly. Top each slice with freshly grated vintage cheddar or gruyere and fresh mozzarella. Cook for approximately 3 minutes per side until the exterior is crispy and the cheese is melted.

---

Recipe by Nagi of RecipeTin Eats.
```

### 06_card_pizza_dough — issues
- FIDELITY: ingredients_added: Sugar (white) — the original does not specify white sugar
- FIDELITY: instructions_rewritten: Instructions were fully written out with added detail (e.g., 'shaggy dough forms', 'lightly oiled bowl', 'parchment-lined baking tray', 'until the crust is golden and the cheese is melted and bubbling') that goes beyond what the original source summary provides
- FIDELITY: detritus_retained: 'Puffy edges with a chewy crumb, similar to Italian wood-fired pizzerias.' — this is a marketing/description line from the page content, not a recipe instruction, 'Category: Pizza' — this is metadata/tag-like content not part of the recipe itself
- FIDELITY: tags_invented: Category: Pizza

**Output snippet (first 20 lines):**
```
# Pizza Dough

Puffy edges with a chewy crumb, similar to Italian wood-fired pizzerias.

Makes: 3 pizzas
Category: Pizza

- Flour (bread or pizza), 600 g
- Yeast (instant), 2 tsp
- Salt, 2 1/2 tsp
- Sugar (white), 4 tsp
- Olive oil, 4 tbsp
- Water (warm), 330 mL

Combine flour, yeast, salt, and sugar in a large bowl. Add olive oil and warm water, then mix until a shaggy dough forms. Knead by hand for 5 minutes, or use a food processor fitted with a dough blade and mix for 40 seconds, until the dough comes together.

Place dough in a lightly oiled bowl, cover, and let rise at room temperature for 1-2 hours until doubled in size. For enhanced flavor, cover and refrigerate for up to 5 days before proceeding.

Divide dough into three equal portions and form into balls. Place on a parchment-lined baking tray, cover, and let rise for 1 hour until puffy.


```

### 07_card_pot_pie — issues
- FIDELITY: quantities_changed: Flour changed from 1/3 cup to 1/3 cup — actually correct, no change
- FIDELITY: detritus_retained: 'Category: Mains' line added without basis in original, 'Can substitute mushrooms, green beans, or frozen corn for vegetables' — sourced from user reviews, not the recipe itself, 'Can be made gluten-free using gluten-free pastry and gluten-free flour' — sourced from user reviews, 'Can be topped with cheesy mashed potato instead of puff pastry' — sourced from user reviews, Rating stats and author/date info were correctly excluded, but substitution suggestions from reviews leaked into recipe notes
- FIDELITY: tags_invented: Category: Mains — category tag added without basis in original recipe

**Output snippet (first 20 lines):**
```
# Chicken Pot Pie

A creamy chicken and vegetable filling with thyme, topped with flaky puff pastry.

Serves: 6
Category: Mains

## Cook the chicken.

- Milk, 2 cups
- Chicken broth, 1 cup
- Stock powder (chicken or vegetable), 2 tsp
- Thyme sprigs, 2: Optional.
- Chicken breast or boneless thighs, 600 g

Place milk, broth, and stock powder in large saucepan; bring to gentle simmer on medium heat. Add chicken and thyme sprigs. Cover and simmer gently on medium-low for 15 minutes (avoid boiling to prevent milk separation). Remove chicken, shred or dice (some uncooked parts are fine). Set poaching liquid aside.

## Make the filling.

- Butter, 50 g

```

### 08_clean_roast_chicken — issues
- FIDELITY: ingredients_added: Butter (unsalted), 100 g, Garlic, 4 cloves, Lemon zest (from 1 lemon), Rosemary (fresh), 1 1/2 tbsp, Parsley (fresh), 1 1/2 tbsp, Sage (fresh), 1 tbsp, Onion, 1, Garlic bulb, 1, Lemon (for cavity), 1, Olive oil, 2 tbsp, Dry white wine or chicken broth, 1 cup
- FIDELITY: quantities_changed: Nearly all quantities are hallucinated — the original only listed ingredients loosely without precise amounts (e.g., '100 g butter', '4 cloves garlic', '1 1/2 tbsp rosemary', '2 tbsp olive oil', '1 cup wine/broth' are all fabricated specifics not present in the original)
- FIDELITY: instructions_rewritten: The detailed step-by-step instructions (basting halfway, 20-minute initial roast, 50-60 minute continuation, 10-minute rest, pat dry, loosen skin method) are all elaborated and invented — the original only states the basic method in vague terms without these specifics
- FIDELITY: detritus_retained: Recipe by Nagi | RecipeTin Eats — attribution line retained at bottom, which is borderline non-recipe content

**Output snippet (first 20 lines):**
```
# Roast Chicken

Slathered with a garlic-herb-lemon butter then oven roasted to golden crispy perfection. Juicy on the inside with liquid gold pan juices loaded with flavour.

Serves: 5

## Prepare the herb butter.

- Butter (unsalted), 100 g: Softened to room temperature.
- Garlic, 4 cloves: Minced.
- Lemon, 1: Zest only.
- Rosemary (fresh), 1 1/2 tbsp: Finely chopped.
- Parsley (fresh), 1 1/2 tbsp: Finely chopped.
- Sage (fresh), 1 tbsp: Finely chopped.
- Salt
- Black pepper

Mix together softened butter, minced garlic, lemon zest, rosemary, parsley, sage, salt, and pepper until well combined.

## Roast the chicken.

```

### 09_clean_banana_bread — issues
- FIDELITY: instructions_rewritten: Bake section reorders preheating/greasing step to after 'pour batter' step, which changes the logical sequence (preheat should come first)
- FIDELITY: detritus_retained: Category: Baking (not in original), Makes: 1 loaf (not in original, though Serves: 8 is fine), Recipe from Love and Lemons by Jeanine Donofrio and Phoebe Moore (attribution line not part of recipe content)
- FIDELITY: prep_leaked_into_name: Butter or vegetable oil (melted), 1/2 cup — 'melted' is a preparation state that should be in the prep note after the colon, not in the parenthetical variant of the name

### 10_baking_crusty_bread — issues
- FIDELITY: quantities_changed: Salt: original specifies '1 tablespoon (18g)' but output drops the gram weight; Yeast: original specifies '1½ tablespoons (14g)' but output drops the gram weight; Flour: original specifies '7½ cups (900g)' but output drops the gram weight; Water: original specifies '3 cups (680g)' but output drops the gram weight
- FIDELITY: instructions_rewritten: Output adds 'The dough can be stored refrigerated for up to 2 weeks' — not present in original, Output adds 'until the crust is golden brown and the loaf sounds hollow when tapped on the bottom' — not present in original, Output adds 'round or oval loaf' shape description — not in original, Output adds 'with a knife or bread lame' for scoring — not in original
- FIDELITY: detritus_retained: Attribution line at bottom ('Based on a recipe from King Arthur Baking Company...') is marginal non-recipe content, though borderline acceptable

**Output snippet (first 20 lines):**
```
# No-Knead Crusty White Bread

Artisan-style bread through an overnight refrigeration method requiring minimal active work.

Makes: 4 loaves

## Mix and bulk ferment.

- Flour (all-purpose), 7 1/2 cups
- Water (lukewarm), 3 cups
- Salt, 1 tbsp
- Yeast (instant or active dry), 1 1/2 tbsp

Mix all ingredients together until you have a shaggy, sticky dough. Let the dough rest at room temperature for 2 hours.

## Refrigerate dough.

After the initial 2-hour rise, cover the dough and refrigerate for a minimum of 2-7 days. The dough can be stored refrigerated for up to 2 weeks.

## Shape and proof.

```
