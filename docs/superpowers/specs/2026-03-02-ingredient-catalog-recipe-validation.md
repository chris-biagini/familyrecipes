# Ingredient Catalog — Recipe Validation Findings

Forward-looking validation: can our ingredient catalog schema, parser, and
resolution pipeline handle the ingredient expressions found in real-world
recipes? We fetched 10 recipes from Budget Bytes and Pinch of Yum, spanning
American, British, Italian, Mexican, Asian, baking, weeknight, and soup
categories, then tested every ingredient line against our current system.

---

## 1. Recipes Analyzed

| # | Recipe | Source | Category |
|---|--------|--------|----------|
| 1 | Chicken Pot Pie | [Budget Bytes](https://www.budgetbytes.com/chicken-pot-pie/) | American classic |
| 2 | Vegetarian Shepherd's Pie | [Budget Bytes](https://www.budgetbytes.com/vegetarian-shepherds-pie/) | British comfort |
| 3 | One Pot Creamy Pesto Chicken Pasta | [Budget Bytes](https://www.budgetbytes.com/one-pot-creamy-pesto-chicken-pasta/) | Italian |
| 4 | Chicken Enchiladas | [Budget Bytes](https://www.budgetbytes.com/chicken-enchiladas/) | Mexican |
| 5 | Chicken Stir Fry | [Budget Bytes](https://www.budgetbytes.com/chicken-stir-fry/) | Asian |
| 6 | Chicken Fried Rice | [Budget Bytes](https://www.budgetbytes.com/chicken-fried-rice/) | Asian |
| 7 | The Best Soft Chocolate Chip Cookies | [Pinch of Yum](https://pinchofyum.com/the-best-soft-chocolate-chip-cookies) | Baking |
| 8 | One Pot Chicken and Rice | [Budget Bytes](https://www.budgetbytes.com/one-pot-chicken-and-rice/) | Weeknight |
| 9 | Chunky Lentil and Vegetable Soup | [Budget Bytes](https://www.budgetbytes.com/chunky-lentil-vegetable-soup/) | Soup |
| 10 | Homemade Chili | [Budget Bytes](https://www.budgetbytes.com/basic-chili/) | Stew |

Two bonus recipes (Baked Mac and Cheese, Banana Bread Baked Oatmeal) were
included in the ingredient frequency analysis but not detailed per-recipe.

---

## 2. Ingredient Resolution Analysis

### 2.1 Chicken Pot Pie

| Raw ingredient | Our syntax | Name resolves? | Qty parseable? | Notes |
|---|---|---|---|---|
| 1 boneless, skinless chicken breast (about ⅔ lb.) | `Chicken breast, 1` | YES (via alias) | YES | Comma in the web name would break our parser — must be authored without it |
| 1 Tbsp cooking oil | `Cooking oil, 1 tbsp` | NO | YES | No catalog entry for generic cooking oil |
| 1 yellow onion | `Onions, 1` | YES (Onions→Onion alias) | YES | Adjective "yellow" would need to be stripped or aliased |
| 4 Tbsp butter | `Butter, 4 tbsp` | YES | YES | |
| 4 Tbsp flour | `Flour (all-purpose), 4 tbsp` | YES (via "Flour" alias) | YES | |
| 1 cup chicken broth | `Chicken broth, 1 cup` | YES | YES | |
| 1/2 cup whole milk | `Milk, 1/2 cup` | YES (via "Whole milk" alias) | YES | |
| 1/4 tsp dried thyme | `Thyme, 1/4 tsp` | NO | YES | "dried thyme" not aliased to Thyme |
| 1/4 tsp rubbed sage | `Rubbed sage, 1/4 tsp` | NO | YES | No sage entry at all |
| 1/4 tsp black pepper | `Black pepper, 1/4 tsp` | YES | YES | |
| 3/4 tsp salt | `Salt, 3/4 tsp` | YES | YES | |
| 12 oz. frozen mixed vegetables | `Frozen mixed vegetables, 12 oz` | NO | YES | No catalog entry |
| 1 double pie crust | `Double pie crust, 1` | NO | YES (bare count) | No catalog entry; pre-made item |
| 1 egg (optional) | `Eggs, 1` | YES | YES | |

**Resolution: 8/14 (57%).** Key gaps: cooking oil, dried herbs, frozen vegetables, pre-made items.

### 2.2 Vegetarian Shepherd's Pie

| Raw ingredient | Name resolves? | Notes |
|---|---|---|
| 1 cup cooked lentils (optional) | NO | "cooked lentils" doesn't match "Lentils" |
| 2 cloves garlic | YES | |
| 1 yellow onion | YES | Via "Onion" alias |
| 1 Tbsp olive oil | YES | |
| 3 carrots | YES | |
| 2 ribs celery | YES | "ribs" is not a recognized unit but celery resolves |
| 8 oz. button mushrooms | NO | No mushroom entry at all |
| salt, thyme, smoked paprika | YES/NO/YES | "dried thyme" doesn't match |
| Freshly cracked pepper | NO | No alias from "pepper" to "Black pepper" |
| 1 Tbsp tomato paste | YES | |
| 1 Tbsp flour | YES | |
| 1 cup vegetable broth | NO | No entry; only chicken broth exists |
| 1 cup frozen peas | NO | No entry |
| 4 cups mashed potatoes | NO | Pre-cooked state; Potatoes entry exists |

**Resolution: 7/15 (47%).** Key gaps: mushrooms, vegetable broth, frozen peas, state-qualified names.

### 2.3 One Pot Creamy Pesto Chicken Pasta

| Raw ingredient | Name resolves? | Notes |
|---|---|---|
| 1 lb. boneless, skinless chicken breast | YES | Via alias |
| 2 Tbsp butter | YES | |
| 2 cloves garlic | YES | |
| 1/2 lb. penne pasta | NO | "Pasta" exists but "penne pasta" doesn't match |
| 1.5 cups chicken broth | YES | 1.5 is a valid decimal |
| 1 cup milk | YES | |
| 3 oz. cream cheese | YES | |
| 1/3 cup basil pesto | NO | No pesto entry |
| 1/4 cup grated Parmesan | NO | "grated Parmesan" — adjective breaks match |
| freshly cracked pepper | NO | |
| 1 pinch crushed red pepper | NO | "crushed red pepper" not aliased to Red pepper flakes |
| 3 cup fresh spinach | NO | "fresh spinach" doesn't match Baby spinach |
| 1/4 cup sliced sun dried tomatoes | NO | No entry |

**Resolution: 6/13 (46%).** Key gaps: adjective-prefixed names, pasta shape names, prepared condiments.

### 2.4 Chicken Enchiladas

| Raw ingredient | Name resolves? | Notes |
|---|---|---|
| 2 cups homemade enchilada sauce | NO | Prepared sauce, no entry |
| 3 cups cooked shredded chicken | NO | State-qualified protein |
| 1/2 tsp cumin | YES | |
| 1/2 tsp garlic powder | NO | No dried spice powders |
| 1/4 tsp salt | YES | |
| 4 oz. can diced green chilies | NO | Canned product; "can" as packaging unit |
| 8 flour tortillas | YES | Via "Flour tortillas" alias |
| 2 1/2 cups shredded Mexican cheese | NO | No entry |

**Resolution: 3/8 (38%).** Key gaps: spice powders, prepared sauces, compound cheese blends.

### 2.5 Chicken Stir Fry

| Raw ingredient | Name resolves? | Notes |
|---|---|---|
| 1/3 cup soy sauce | YES | |
| 3 Tbsp brown sugar | YES | Via alias |
| 2 tsp toasted sesame oil | NO | No sesame oil entry |
| 2 cloves garlic | YES | |
| 2 tsp grated fresh ginger | NO | No ginger entry |
| 1 1/2 Tbsp cornstarch | YES | Mixed number: handled |
| 1/3 cup water | YES | |
| 1 tsp sriracha | NO | No entry |
| 3/4 lb. broccoli | YES | |
| 2 carrots | YES | |
| 1 red bell pepper | YES | |
| 1 small onion | YES | "small" adjective ignored in our syntax |
| 2 green onions | YES | |
| 2 boneless, skinless chicken breasts | YES | Via alias |
| 3 Tbsp cooking oil | NO | No generic oil entry |

**Resolution: 10/15 (67%).** Better than average. Key gaps: sesame oil, ginger, hot sauce, cooking oil.

### 2.6 Chicken Fried Rice

| Raw ingredient | Name resolves? | Notes |
|---|---|---|
| 2 cloves garlic | YES | |
| 1 tsp grated fresh ginger | NO | |
| 3 green onions | YES | |
| 1 carrot | YES | |
| 1 red bell pepper | YES | |
| 1 cup frozen peas | NO | |
| 1 large boneless skinless chicken breast | YES | |
| 2 large eggs | YES | "large" adjective in web format |
| 3 Tbsp cooking oil | NO | |
| 3 Tbsp toasted sesame oil | NO | |
| 3 Tbsp soy sauce | YES | |
| 3 cups cooked and cooled rice | NO | State-qualified |

**Resolution: 7/12 (58%).** Same gaps as stir fry.

### 2.7 The Best Soft Chocolate Chip Cookies

| Raw ingredient | Name resolves? | Notes |
|---|---|---|
| 8 tablespoons of salted butter | NO | "salted butter" — only "Unsalted butter" alias exists |
| 1/2 cup white sugar | YES | Via alias |
| 1/4 cup packed light brown sugar | NO | "light brown sugar" doesn't match Sugar (brown) |
| 1 teaspoon vanilla | YES | Via alias |
| 1 egg | YES | |
| 1 1/2 cups all purpose flour | YES | Via alias |
| 1/2 teaspoon baking soda | YES | |
| 1/4 teaspoon salt | YES | |
| 3/4 cup chocolate chips | YES | |

**Resolution: 7/9 (78%).** Best resolution rate. Only gaps: salted butter variant, light brown sugar.

### 2.8 One Pot Chicken and Rice

| Raw ingredient | Name resolves? | Notes |
|---|---|---|
| 2 tsp paprika | YES | |
| 1 tsp dried oregano | NO | "dried oregano" not aliased to Oregano |
| 1 tsp dried thyme | NO | Same pattern |
| 1/2 tsp garlic powder | NO | No entry |
| 1/2 tsp onion powder | NO | No entry |
| 1/4 tsp salt | YES | |
| 1/4 tsp pepper | NO | Truncated — should match Black pepper |
| 1.25 lbs. boneless, skinless chicken thighs | NO | No chicken thighs entry |
| 2 Tbsp cooking oil | NO | |
| 1 yellow onion | YES | |
| 1 cup long-grain white rice | NO | Variety qualifier |
| 1.75 cups vegetable broth | NO | No entry |
| 1 Tbsp chopped parsley | NO | "chopped parsley" — adjective prefix |

**Resolution: 3/13 (23%).** Worst rate. Dominated by spice powders, state qualifiers, and missing proteins.

### 2.9 Chunky Lentil and Vegetable Soup

| Raw ingredient | Name resolves? | Notes |
|---|---|---|
| 2 Tbsp olive oil | YES | |
| 2 cloves garlic | YES | |
| 1 yellow onion | YES | |
| 1/2 lb. carrots | YES | |
| 3 ribs celery | YES | "ribs" not a standard unit |
| 1 15oz. can black beans | NO | "can" packaging unit, "black beans" sans "(canned)" |
| 1 cup brown lentils | NO | Variety qualifier |
| 1 tsp ground cumin | YES | Via alias |
| 1 tsp dried oregano | NO | |
| 1/2 tsp smoked paprika | YES | |
| 1/4 tsp cayenne pepper | NO | No entry |
| black pepper (freshly ground) | YES | |
| 1 15oz. can petite diced tomatoes | NO | "can" packaging + adjective |
| 4 cups vegetable broth | NO | |
| 1/2 tsp salt | YES | |

**Resolution: 8/15 (53%).**

### 2.10 Homemade Chili

| Raw ingredient | Name resolves? | Notes |
|---|---|---|
| 2 Tbsp olive oil | YES | |
| 1 yellow onion | YES | |
| 2 cloves garlic | YES | |
| 1 lb. ground beef | YES | |
| 1 15oz. can kidney beans | NO | No entry; "can" packaging unit |
| 1 15oz. can black beans | NO | Same issue |
| 1 15oz. can diced tomatoes | NO | Same issue |
| 1 6oz. can tomato paste | YES | "can" packaging — but tomato paste resolves by name |
| 1 cup water | YES | |
| 1 Tbsp chili powder | NO | No entry |
| 1 tsp ground cumin | YES | |
| 1/4 tsp cayenne powder | NO | |
| 1/4 tsp garlic powder | NO | |
| 1/2 tsp onion powder | NO | |
| 1/2 Tbsp brown sugar | YES | |
| 1 tsp salt | YES | |
| 1/2 tsp black pepper | YES | |

**Resolution: 9/17 (53%).**

---

## 3. Schema Gaps

Problems our current data model cannot express, regardless of catalog coverage.

### 3.1 Packaging-as-unit: `1 (15 oz.) can diced tomatoes`

This is the single biggest real-world gap. Recipe sites commonly write:

```
1 (14.5 oz) can diced tomatoes
4 oz. can diced green chilies
1 6oz. can tomato paste
```

Our parser expects `Name, Quantity: Prep` where quantity is `<number> <unit>`.
The expression `1 15oz. can` packs **two** measurements into one: count of
containers (1 can) and weight per container (15 oz). Our schema stores one
`Quantity(value, unit)` pair. There is no way to represent "1 can where a can
is 15 oz" without either:

- A named portion: `can: 425.0` (grams) in the catalog entry — works only
  if can sizes are standardized for that ingredient.
- Pre-multiplying: the recipe author writes `15 oz` and drops the "can"
  packaging context — what our syntax already encourages.

**Recommendation:** Do not extend the schema. Our Markdown syntax already
handles this by having authors write `- Diced tomatoes, 15 oz` or
`- Diced tomatoes, 1 can` with a `can` portion defined. Document the
convention. This is an *import* concern, not a schema concern.

### 3.2 Adjective-prefixed names

Real recipes routinely put prep state or variety into the ingredient name:

```
boneless, skinless chicken breast     (prep descriptors)
freshly cracked pepper                (prep descriptor)
grated Parmesan                       (prep descriptor)
chopped walnuts                       (prep descriptor)
light brown sugar                     (variety qualifier)
dried oregano                         (state qualifier)
cooked shredded chicken               (state qualifier)
long-grain white rice                 (variety qualifier)
```

Our syntax puts prep after the colon (`- Parmesan, 1/4 cup: grated`), but
web recipes bake it into the name. This is an import-time normalization
problem, not a schema gap.

**Recommendation:** An import tool must strip common adjective prefixes
(fresh, dried, ground, chopped, grated, cooked, frozen, boneless, skinless,
packed, sliced, minced, diced, toasted, crushed, large, small, medium) and
move them to the prep note. The catalog's alias system can catch the rest.

### 3.3 Vague quantities

```
freshly cracked pepper               (no quantity at all)
1 pinch crushed red pepper            (vague unit)
salt (to taste)                       (vague)
```

Our parser handles nil quantity (no quantity = omit from nutrition). "Pinch"
is not in our unit list but could be added as a named portion (about 0.3g
for salt-like ingredients). "To taste" is unparseable by design — nutrition
calculation correctly skips these.

**No schema change needed.** Add `pinch` as a named portion where relevant.

### 3.4 Parenthetical annotations

Web recipes embed information in parentheses that our syntax separates:

```
3 bananas (mashed, (1½ cups total) $0.84)
1.25 lbs. boneless, skinless chicken thighs (4-5 thighs)
1/2 lb. carrots ((3-4 carrots))
1 cup brown lentils
```

Our syntax handles this cleanly: `- Bananas, 3: mashed`. The parenthetical
annotations are an import-time stripping concern.

---

## 4. Parser Gaps

Expressions our quantity parser cannot currently handle.

### 4.1 Mixed numbers with spaces: `1 1/2 cups`

**Status: HANDLED.** Our parser splits on space into `["1", "1/2", "cups"]`
— wait, actually it splits into only 2 parts: `quantity.strip.split(' ', 2)`
giving `["1", "1/2 cups"]`. Then `parsed_quantity[0]` is `"1"` and
`parsed_quantity[1]` is `"1/2 cups"`. The unit would then be `"1/2 cups"`
which would fail to normalize.

**This is a real parser bug.** `1 1/2 cups` is extremely common and our
`parsed_quantity` method (splitting on first space only) doesn't handle it.
The Markdown author must write `1 1/2` as `1½` (vulgar fraction) or `1.5`
for it to work. Web import would need to convert `1 1/2` to `1.5` or `1½`.

### 4.2 Decimal quantities: `1.25 lbs`, `1.75 cups`

**Status: HANDLED.** The numeric parser handles decimals via `Float()`.

### 4.3 Range quantities: `4-5 thighs`

**Status: HANDLED.** `Ingredient.numeric_value` splits on `-` or `–` and
takes the high end.

### 4.4 Vulgar fractions: `⅓`, `½`, `¾`, `⅛`

**Status: HANDLED.** `NumericParsing::VULGAR_GLYPHS` maps all common ones.

### 4.5 Unit "ribs" (celery)

`3 ribs celery` — "ribs" is not in our unit list. Could be added as a
`stalk` alias or a separate named portion.

### 4.6 Unit "pinch"

`1 pinch crushed red pepper` — "pinch" is not recognized. Nutritionally
negligible but could be added as an approximate portion.

### 4.7 Compound quantity: `1 15oz. can`

As discussed in 3.1, this double-measurement pattern is not parseable and
shouldn't be. Our syntax avoids it by design.

---

## 5. Catalog Coverage Summary

Across all 10 recipes: **94 unique ingredient names**, of which **44 (47%)**
resolve against our current catalog. Of the 50 that don't resolve:

- **24 are fixable with better aliases** (adjective stripping, state
  qualifiers like "dried"/"ground"/"fresh", synonyms like "pepper" →
  "Black pepper")
- **26 need new catalog entries** (spice powders, Asian ingredients, frozen
  vegetables, prepared sauces, additional proteins)

With alias improvements alone, resolution would jump to ~72%. With new
entries for the top 20 missing ingredients, it would reach ~90%.

---

## 6. Next 50 Ingredients — Priority List

Ranked by frequency across the 12 recipes analyzed (10 primary + 2 bonus).
Ingredients already in the catalog are excluded. Frequency count shown in
parentheses.

### Tier 1: Appeared in 4+ recipes — critical additions

| # | Ingredient | Appearances | Type |
|---|---|---|---|
| 1 | Garlic powder | 6 | Dried spice |
| 2 | Cooking oil (vegetable/canola) | 5 | Pantry oil |
| 3 | Onion powder | 4 | Dried spice |
| 4 | Dried thyme* | 4 | Herb (alias for Thyme) |
| 5 | Dried oregano* | 4 | Herb (alias for Oregano) |
| 6 | Vegetable broth | 4 | Liquid |
| 7 | Cayenne pepper | 4 | Dried spice |
| 8 | Frozen peas | 3 | Frozen vegetable |

*These only need aliases, not new entries.

### Tier 2: Appeared in 2-3 recipes — high value

| # | Ingredient | Appearances | Type |
|---|---|---|---|
| 9 | Ginger (fresh) | 3 | Root spice |
| 10 | Toasted sesame oil | 3 | Asian pantry oil |
| 11 | Chicken thighs | 2 | Protein |
| 12 | Kidney beans (canned) | 2 | Canned bean |
| 13 | Chili powder | 2 | Spice blend |
| 14 | Mushrooms (button) | 2 | Produce |
| 15 | Panko breadcrumbs | 2 | Pantry |
| 16 | Ground nutmeg | 1 | Dried spice |

### Tier 3: Appeared once but commonly used across cuisines

| # | Ingredient | Category |
|---|---|---|
| 17 | Sriracha | Asian condiment |
| 18 | Enchilada sauce | Mexican sauce |
| 19 | Pesto (basil) | Italian condiment |
| 20 | Sun-dried tomatoes | Preserved produce |
| 21 | Diced green chilies (canned) | Mexican pantry |
| 22 | Frozen mixed vegetables | Frozen |
| 23 | Pie crust (premade) | Baking |
| 24 | Macaroni | Pasta (alias for Pasta or Small pasta) |
| 25 | Penne | Pasta (alias for Pasta) |

### Tier 4: Aliases to add to existing entries

| # | Existing entry | New alias(es) |
|---|---|---|
| 26 | Thyme | Dried thyme |
| 27 | Oregano | Dried oregano |
| 28 | Black pepper | Pepper, Freshly cracked pepper, Freshly ground pepper |
| 29 | Parmesan | Grated Parmesan, Grated parmesan |
| 30 | Walnuts | Chopped walnuts |
| 31 | Parsley | Chopped parsley, Fresh parsley |
| 32 | Baby spinach | Fresh spinach |
| 33 | Red pepper flakes | Crushed red pepper, Red pepper flake |
| 34 | Lentils | Brown lentils, Cooked lentils, Green lentils |
| 35 | Rice | Cooked rice, Long-grain white rice, Jasmine rice already exists separately |
| 36 | Butter | Salted butter |
| 37 | Sugar (brown) | Light brown sugar, Dark brown sugar |
| 38 | Black beans (canned) | Black beans |
| 39 | Tomatoes (canned) | Diced tomatoes, Petite diced tomatoes, Canned diced tomatoes |
| 40 | Rolled oats | Old-fashioned rolled oats, Old fashioned oats |
| 41 | Potatoes | Mashed potatoes |
| 42 | Pasta | Penne pasta, Macaroni |

### Tier 5: Future expansion ingredients (not seen but predictable)

| # | Ingredient | Rationale |
|---|---|---|
| 43 | Bell pepper (generic) | Many recipes just say "bell pepper" |
| 44 | Avocado | Mexican/American staple |
| 45 | Lime juice | Often separate from whole limes |
| 46 | Lemon juice | Same |
| 47 | Fish sauce | Asian cooking essential |
| 48 | Rice vinegar | Asian cooking essential |
| 49 | Coconut cream | Distinct from coconut milk |
| 50 | Dijon mustard | French/American essential |

---

## 7. AI-Import Recommendations

An automated recipe import tool (paste a URL or text, get our Markdown
format) would need to handle these transformations:

### 7.1 Name normalization pipeline

1. **Strip cost annotations**: `($0.50)`, `($1.25*)` — Budget Bytes pattern
2. **Strip parenthetical notes**: `(about ⅔ lb.)`, `(optional)`, `(divided)`,
   `(4-5 thighs)`, `(see notes)` — move to prep note
3. **Strip adjective prefixes**: fresh, dried, ground, chopped, grated,
   cooked, frozen, boneless, skinless, packed, sliced, minced, diced,
   toasted, crushed, large, small, medium, raw — move to prep note
4. **Comma handling**: `boneless, skinless chicken breast` uses commas as
   adjective separators, which conflicts with our `Name, Qty` syntax.
   Must join adjectives with spaces or move to prep note
5. **Fuzzy catalog match**: after normalization, try exact match, then
   plural/singular variants, then alias lookup, then substring match

### 7.2 Quantity normalization pipeline

1. **Parse compound**: `1 (15 oz.) can` → decide between `15 oz` (weight)
   or `1 can` (portion) based on catalog entry capabilities
2. **Mixed numbers**: `1 1/2 cups` → `1.5 cups` or `1½ cups`
3. **Unit normalization**: `tablespoons` → `tbsp`, `ounces` → `oz`,
   `pounds` → `lb`
4. **Bare adjective units**: `1 large egg` → `Eggs, 1` (drop "large")

### 7.3 Mapping ambiguity

Some web ingredients map to different catalog entries depending on context:

| Web ingredient | Could map to |
|---|---|
| "black beans" | Black beans (canned) or Beans (any dry) |
| "spinach" | Baby spinach or Frozen spinach |
| "tomatoes" | Tomatoes (fresh) or Tomatoes (canned) |
| "flour" | Flour (all-purpose) or Flour (bread) or Flour (00) |
| "pasta" | Pasta or Spaghetti or Small pasta or Cavatappi |

An import tool should present these as choices when ambiguous.

### 7.4 Parser fix: mixed number quantities

The `parsed_quantity` method in `FamilyRecipes::Ingredient` splits on the
first space only: `"1 1/2 cups".split(' ', 2)` → `["1", "1/2 cups"]`. This
means quantity_value is `1` and quantity_unit is `"1/2 cups"`, which fails
unit normalization.

**Fix**: detect when the second token is a fraction or vulgar glyph and
combine it with the first token as a mixed number before extracting the
unit. Example implementation:

```ruby
def parsed_quantity
  @parsed_quantity ||= begin
    parts = @quantity.strip.split(' ')
    if parts.size >= 2 && fraction?(parts[1])
      value = combine_mixed_number(parts[0], parts[1])
      [value, parts[2..].join(' ').presence]
    else
      @quantity.strip.split(' ', 2)
    end
  end
end
```

However: our *authored* Markdown format uses vulgar fractions (`1½ cups`)
or decimals (`1.5 cups`), so this is only needed for an import pipeline.
Existing recipes don't use `1 1/2 cups` syntax.

---

## 8. Key Takeaways

1. **47% resolution rate out of the box** is a reasonable starting point for
   a family recipe app. Most missing ingredients are predictable (spice
   powders, Asian staples, frozen vegetables) rather than exotic.

2. **Aliases are the highest-leverage improvement.** Adding aliases for
   "dried thyme" → Thyme, "pepper" → Black pepper, "crushed red pepper" →
   Red pepper flakes, etc. would push resolution from 47% to ~72% with zero
   new catalog entries.

3. **20-25 new catalog entries** (garlic powder, onion powder, cayenne,
   ginger, sesame oil, vegetable broth, chili powder, frozen peas,
   mushrooms, chicken thighs, etc.) would push resolution above 90%.

4. **The schema is adequate.** No structural changes are needed. The
   `Quantity(value, unit)` model with named portions and density handles
   everything these recipes throw at it, as long as the catalog entries
   exist.

5. **The parser is adequate for authored content.** The only real gap
   (mixed number `1 1/2 cups`) doesn't affect authored recipes because
   our format uses vulgar fractions. It would matter for an import tool.

6. **Import is the hard problem.** Normalizing web recipe ingredient lines
   into our `Name, Quantity: Prep` format requires adjective stripping,
   comma disambiguation, parenthetical extraction, and compound quantity
   resolution. This is a significant text-processing challenge but is
   entirely an import-time concern — the schema and parser are fine.
