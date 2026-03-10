# FDA Nutrition Label Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the multi-column nutrition table with an FDA-style Nutrition Facts label showing per-serving values, serving weight in grams, and % Daily Values.

**Architecture:** Add `total_weight_grams` to `NutritionCalculator::Result` by summing resolved ingredient weights. Add `DAILY_VALUES` to `NutritionConstraints`. Rewrite the view partial and CSS to match FDA label typography (Helvetica, bold rules, proper indentation hierarchy). Remove nutrition scaling from the recipe_state Stimulus controller.

**Tech Stack:** Ruby (NutritionCalculator, NutritionConstraints, RecipesHelper), ERB view partial, CSS, Stimulus JS cleanup, Minitest.

---

## Design Decisions

**Columns:** Drop "Total" and "Per Unit" columns. Single per-serving display only.

**Serving size weight:** Sum all resolved ingredient weights in grams during calculation, divide by serving_count. Show even when some ingredients are partial/missing — the existing footnotes handle the approximation caveat.

**% Daily Values:** FDA 2,000-calorie reference. No %DV for calories, trans fat, or total sugars (per FDA rules).

**Scaling:** Remove nutrition scaling entirely. Doubling a recipe doubles servings, not per-serving values. Yield lines in the header already scale.

**No Makes/No Serves:** When neither exists, treat the whole recipe as 1 serving. Display "1 serving per recipe" and "Serving size: entire recipe (X g)".

**FDA visual style:** Black/white self-contained widget. Helvetica Neue/Helvetica/Arial font stack. Thick rules above/below calories, thin rules between nutrients. Proper indentation for sub-nutrients.

## Serving Header Logic

| Makes | Serves | Servings line | Serving size |
|-------|--------|---------------|--------------|
| 12 pancakes | 2 | 2 servings per recipe | 6 pancakes (X g) |
| 12 pancakes | — | 12 servings per recipe | 1 pancake (X g) |
| — | 4 | 4 servings per recipe | ¼ recipe (X g) |
| — | — | 1 serving per recipe | entire recipe (X g) |

## FDA Daily Values (2,000-calorie diet)

| Nutrient | Daily Value | Show %DV? |
|----------|-------------|-----------|
| Calories | — | No |
| Total Fat | 78 g | Yes |
| Saturated Fat | 20 g | Yes |
| Trans Fat | — | No |
| Cholesterol | 300 mg | Yes |
| Sodium | 2,300 mg | Yes |
| Total Carbs | 275 g | Yes |
| Fiber | 28 g | Yes |
| Total Sugars | — | No |
| Added Sugars | 50 g | Yes |
| Protein | 50 g | Yes |
