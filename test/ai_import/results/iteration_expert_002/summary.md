# Iteration iteration_expert_002

| Recipe | Parse | Format | Fidelity | Detritus | Aggregate |
|--------|-------|--------|----------|----------|-----------|
| 01_blog_brownies | PASS | 100.0% | 97 | 97 | 97.9 |
| 02_blog_bolognese | PASS | 100.0% | 93 | 90 | 94.2 |
| 03_blog_chicken_tikka | PASS | 100.0% | 91 | 97 | 95.5 |
| 04_blog_chocolate_cookies | PASS | 100.0% | 82 | 90 | 89.8 |
| 05_card_grilled_cheese | PASS | 100.0% | 88 | 85 | 90.7 |
| 06_card_pizza_dough | PASS | 100.0% | 97 | 95 | 97.3 |
| 07_card_pot_pie | PASS | 100.0% | 94 | 92 | 95.2 |
| 08_clean_roast_chicken | PASS | 100.0% | 96 | 88 | 94.8 |
| 09_clean_banana_bread | PASS | 100.0% | 84 | 88 | 90.0 |
| 10_baking_crusty_bread | PASS | 100.0% | 90 | 88 | 92.4 |

**Overall:** 93.8 avg, [97.9, 94.2, 95.5, 89.8, 90.7, 97.3, 95.2, 94.8, 90.0, 92.4] worst

### 02_blog_bolognese — issues
- FIDELITY: quantities_changed: Beef mince: original lists '1 lb / 500g'; output lists only '500 g' (dual quantity removed, acceptable but minor), Dry red wine: original lists '1/2 cup (125 ml)'; output lists only '125 ml' (unit change from cups to ml), Tomatoes: original lists '800g / 28 oz can'; output lists only '800 g'
- FIDELITY: instructions_rewritten: 'Cook, breaking it up as you go, until browned' rewritten as 'cook breaking it up until browned' — minor but casual paraphrase, 'adding water if sauce gets too thick' rewritten as 'Add a splash of water if sauce gets too thick' — informal substitution for 'adding water'
- FIDELITY: detritus_retained: 'Tags: weeknight, quick, italian' — tag metadata not present in original and not a standard expected output field

### 03_blog_chicken_tikka — issues
- FIDELITY: ingredients_missing: Basmati rice (listed as serving ingredient in original)
- FIDELITY: quantities_changed: Butter first addition: original says '30g unsalted butter or ghee', output drops 'or ghee' option; Butter second addition: original says '50g unsalted butter or ghee', output drops 'or ghee' option

### 04_blog_chocolate_cookies — issues
- FIDELITY: quantities_changed: Flour changed from 2 1/4 cups (281g) to 281g only — cup measurement dropped, Butter changed from 3/4 cup (170g/12 Tbsp) to 170g only — cup/tbsp measurements dropped, Brown sugar changed from 3/4 cup (150g) to 150g only — cup measurement dropped, Granulated sugar changed from 1/2 cup (100g) to 100g only — cup measurement dropped, Chocolate chips changed from 1 1/4 cups (225g) to 225g only — cup measurement dropped, Vanilla extract listed as 2 tsp instead of 2 teaspoons pure vanilla extract (minor, but 'pure' qualifier dropped from quantity/name)
- FIDELITY: instructions_dropped: Instruction that the flour should be 'spooned & leveled' is not mentioned, Original specifies 'XL cookie' size context for the 3 tbsp scoop; output says 'per cookie' losing the XL/medium-large distinction in the baking step
- FIDELITY: instructions_rewritten: 'Centers will look soft' rewritten as 'centers will look underdone' — changes the meaning slightly, 'cooling rack' rewritten as 'rack'
- FIDELITY: detritus_retained: Tags line ('Tags: vegetarian, baked') is non-recipe metadata not requested by format

**Output snippet (first 20 lines):**
```
# Chewy Chocolate Chip Cookies

Worth the overnight wait.

Makes: 16 cookies
Category: Baking
Tags: vegetarian, baked

## Mix dough.

- Flour (all-purpose), 281 g
- Baking soda, 1 tsp
- Cornstarch, 1 1/2 tsp
- Salt, 1/2 tsp
- Butter (unsalted), 170 g: Melted and cooled 5 minutes.
- Sugar (brown), 150 g: Packed.
- Sugar (white), 100 g
- Egg, 1: Room temperature.
- Egg yolk, 1: Room temperature.
- Vanilla extract, 2 tsp

```

### 05_card_grilled_cheese — issues
- FIDELITY: quantities_changed: Cheddar and mozzarella have no quantities listed — original also lacked specific quantities, so no true change, but cheddar is listed without 'or gruyere' as an alternative (gruyere moved to footer note instead of ingredient line)
- FIDELITY: detritus_retained: Rating information not present — correctly removed, Tags line (vegetarian, quick) is a minor addition without basis in original, though low impact
- FIDELITY: prep_leaked_into_name: Cheddar (vintage), freshly grated — 'freshly grated' is a prep note appearing in the quantity/name field rather than after a colon, Mozzarella (fresh), grated — 'grated' is a prep note appearing in the quantity field rather than after a colon

### 06_card_pizza_dough — issues
- FIDELITY: detritus_retained: "18 user reviews with ratings averaging 4.96/5 stars" context not present — clean, AdThrive/analytics infrastructure not present — clean

### 07_card_pot_pie — issues
- FIDELITY: quantities_changed: Flour changed from 1/3 cup to 1/3 cup — actually correct, no change
- FIDELITY: instructions_dropped: Instruction to note that some uncooked parts of chicken are fine after shredding/dicing
- FIDELITY: instructions_rewritten: 'avoid boiling to prevent milk separation' reworded to 'don't boil or milk will split' — acceptable paraphrase, 'cool in fridge' reworded to 'refrigerate' — minor
- FIDELITY: detritus_retained: Tags line (comfort-food, make-ahead, freezer-friendly) is not part of the standard output format and represents added content, though minor

### 08_clean_roast_chicken — issues
- FIDELITY: detritus_retained: Tags: roasted — minor non-recipe metadata not part of standard output format, Substitute chicken broth for the white wine. — redundant footer note (already captured as prep note on white wine ingredient)

### 09_clean_banana_bread — issues
- FIDELITY: quantities_changed: Sugar: original says 'cane sugar or brown sugar' but output says 'Sugar (white)' — this inverts the implied default and misrepresents the option, Butter: original says 'melted butter or vegetable oil' but output specifies '(unsalted)' with no basis in original
- FIDELITY: instructions_rewritten: Substitution options for butter/oil and sugar types moved from ingredient list to a footer note rather than expressed inline
- FIDELITY: detritus_retained: Tags line ('Tags: vegetarian, baked, comfort-food') is not part of the expected output format and has no basis in the original recipe

### 10_baking_crusty_bread — issues
- FIDELITY: quantities_changed: Flour listed as 900g only (original: 7½ cups / 900g); Water listed as 680g only (original: 3 cups / 680g); Salt listed as 18g only (original: 1 tablespoon / 18g); Yeast listed as 14g only (original: 1½ tablespoons / 14g) — though imperial equivalents are provided in a footer note
- FIDELITY: detritus_retained: Tags: make-ahead — a tags line was not part of the expected output format and has no basis in the original recipe content, Rating and review count not retained (acceptable), but '2026 Recipe of the Year' and '2016 Recipe of the Year' designations were dropped without replacement — these are editorial notes, acceptable to omit
