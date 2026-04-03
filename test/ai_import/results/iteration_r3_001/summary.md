# Iteration iteration_r3_001

| Recipe | Parse | Format | Fidelity | Detritus | Aggregate |
|--------|-------|--------|----------|----------|-----------|
| 01_blog_brownies | PASS | 100.0% | 97 | 98 | 98.2 |
| 02_blog_bolognese | PASS | 100.0% | 95 | 98 | 97.4 |
| 03_blog_chicken_tikka | PASS | 100.0% | 94 | 92 | 95.2 |
| 04_blog_chocolate_cookies | PASS | 100.0% | 91 | 95 | 94.9 |
| 05_card_grilled_cheese | PASS | 100.0% | 82 | 85 | 88.3 |
| 06_card_pizza_dough | PASS | 100.0% | 95 | 90 | 95.0 |
| 07_card_pot_pie | PASS | 100.0% | 97 | 99 | 98.5 |
| 08_clean_roast_chicken | PASS | 100.0% | 93 | 97 | 96.3 |
| 09_clean_banana_bread | PASS | 100.0% | 91 | 98 | 95.8 |
| 10_baking_crusty_bread | PASS | 100.0% | 88 | 85 | 90.7 |

**Overall:** 95.0 avg, [98.2, 97.4, 95.2, 94.9, 88.3, 95.0, 98.5, 96.3, 95.8, 90.7] worst

### 01_blog_brownies — issues
- FIDELITY: detritus_retained: Rating & Reception section not present in output — correctly excluded

### 02_blog_bolognese — issues
- FIDELITY: quantities_changed: Sugar listed as '2 tsp' without the qualifier 'if needed' in the ingredient entry (though this is noted in the substitution footer)

### 03_blog_chicken_tikka — issues
- FIDELITY: ingredients_missing: Basmati rice (for serving)

### 04_blog_chocolate_cookies — issues
- FIDELITY: quantities_changed: Vanilla extract: original specifies 'pure vanilla extract', output uses 'Vanilla extract' without 'pure' — minor but notable; original yield is '16 XL cookies or 20 medium/large cookies', Makes line shows only '16 cookies'
- FIDELITY: detritus_retained: 'Chocolate chunks may be substituted for chocolate chips.' — this substitution note was not in the original recipe and appears to be hallucinated content added in the footer

### 05_card_grilled_cheese — issues
- FIDELITY: ingredients_missing: Gruyere (as alternative to vintage cheddar)
- FIDELITY: detritus_retained: Rating information context is absent (correctly so), but the footer note 'The source text is a summary...' is a meta-commentary about transcription quality, not recipe content — minor issue
- FIDELITY: prep_leaked_into_name: Cheddar (vintage), freshly grated — 'freshly grated' is a prep note that leaked into the name/quantity field rather than appearing after the colon

**Output snippet (first 20 lines):**
```
# Grilled Cheese Sandwich

Makes: 1 sandwich
Serves: 1
Category: Mains

## Make the sandwich.

- Bread (sourdough), 2 slices: Thick-cut (1.3-1.5 cm).
- Butter (salted): For spreading.
- Cheddar (vintage), freshly grated
- Mozzarella (fresh), grated

Butter both sides of the bread. Lightly toast the bread, then add cheese. Cook approximately 3 minutes per side until the exterior is crispy and the cheese is melted inside.

---

The source text is a summary of the recipe page rather than the full recipe. Quantities for cheese and butter were not provided in the source. Vintage cheddar or gruyere may be used. Recipe by Nagi, RecipeTin Eats.
```

### 06_card_pizza_dough — issues
- FIDELITY: detritus_retained: "The page includes 18 user reviews with ratings averaging 4.96/5 stars" context was not retained, which is correct — but the dough descriptor sentence ('The dough produces puffy edges with a chewy crumb, similar to Italian wood-fired pizzerias.') is borderline marketing copy from the page description rather than a recipe instruction, though it is recipe-relevant and minor

### 07_card_pot_pie — issues
- FIDELITY: ingredients_added: Butter listed as (unsalted) — original does not specify unsalted
- FIDELITY: quantities_changed: Flour changed from 1/3 cup to 1/3 cup — actually correct, no change

### 08_clean_roast_chicken — issues
- FIDELITY: quantities_changed: Chicken listed as '1.75 kg' only; original specifies '1.75-2 kg (3.5-4 lb)' range, Salt and pepper listed as '1/2 tsp each' in original butter section, but split into separate '1/2 tsp' lines in output — acceptable but the 'each' framing is lost
- FIDELITY: instructions_rewritten: The wine/broth substitution note was moved from the ingredients list to a footer line, though content is preserved
- FIDELITY: prep_leaked_into_name: Chicken (whole), 1.75 kg: Patted dry — 'whole' is a variant descriptor which is fine, but 'Patted dry' is correctly in the prep note, no issue here

### 09_clean_banana_bread — issues
- FIDELITY: quantities_changed: Sugar: original says 'cane sugar or brown sugar' but output labels it 'Sugar (white)' — this is potentially misleading, though substitution note appears at bottom
- FIDELITY: detritus_retained: Ratings section not present — correctly omitted

### 10_baking_crusty_bread — issues
- FIDELITY: quantities_changed: Flour listed as 900g only (original: 7½ cups/900g); Water listed as 680g only (original: 3 cups/680g); Salt listed as 18g only (original: 1 tablespoon/18g); Yeast listed as 14g only (original: 1½ tablespoons/14g) — cup/tablespoon measures dropped, grams retained
- FIDELITY: detritus_retained: Rating: 4.70 stars from 1,453 reviews — omitted (acceptable), Recognition/award details partially retained in footer ('Recipe of the Year for King Arthur Baking in both 2016 and 2026') — this is borderline non-recipe content but minor
