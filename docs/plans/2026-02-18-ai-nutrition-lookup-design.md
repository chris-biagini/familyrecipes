# AI-Assisted Nutrition Lookup — Design

## Problem

The `bin/nutrition-lookup` tool requires human judgment to pick USDA entries and validate portion weights. But the human (the recipe author) lacks the domain knowledge to judge data quality — is 0 calories for apples a data error or a legit entry? Is 240g per cup of flour reasonable? An AI model with world knowledge can make these calls better and faster.

## Solution

Add an `--auto` flag to `bin/nutrition-lookup` that replaces human decision-making with Claude (via `claude -p`). The script reuses all existing USDA API code; only the "decision layer" changes.

## Architecture

```
bin/nutrition-lookup --auto [--model MODEL]
  │
  ├─ find_missing_ingredients()          # existing
  │
  └─ For each missing ingredient:
       ├─ search_usda(name)              # existing — top 10 results
       ├─ get_food_detail(fdc_id)        # existing — for top 5 results (portions)
       ├─ build_claude_prompt(...)       # NEW — formats USDA data into prompt
       ├─ call_claude(prompt, model)     # NEW — shells out to `claude -p`
       ├─ Parse JSON response
       └─ save_nutrition_data()          # existing
```

Model defaults to `haiku` (fast, cheap). Override with `--model sonnet` if needed.

## Claude Prompt Design

The prompt gives Claude the ingredient name, all USDA search results with per-100g nutrients, and portion data. Guidelines tell it to:

- Prefer Foundation data over SR Legacy
- Prefer raw/whole/with-skin over processed variants
- Skip entries with obviously wrong data (0 calories for caloric foods)
- Use USDA portion weights when reasonable, override from world knowledge when not
- Include `~unitless` only for countable items (eggs, lemons, apples)

Response is constrained via `--json-schema` to:

```json
{
  "fdc_id": 171688,
  "reasoning": "Foundation data, raw with skin matches typical home use",
  "per_100g": { "calories": 52, "protein": 0.26, ... },
  "portions": { "cup": 125, "~unitless": 182 }
}
```

`reasoning` is printed to stdout but not saved to YAML.

## Output & Review

- Per-ingredient progress printed as it goes
- Skips logged for ingredients with no USDA results or unparseable Claude responses
- Final summary: "Added N/M ingredients. K skipped."
- User reviews via `git diff resources/nutrition-data.yaml`

## What's NOT Changing

- The interactive (human) path remains untouched
- `NutritionCalculator` and all existing code/tests unchanged
- No new gem dependencies — uses `claude` CLI already on the system
