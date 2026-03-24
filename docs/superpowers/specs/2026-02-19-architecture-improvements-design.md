# Architecture Improvements Design

Date: 2026-02-19

## Context

After a round of RuboCop integration and idiomatic Ruby refactoring, an architectural review identified targeted improvements that reduce primitive obsession, improve immutability contracts, and decompose the largest class. The codebase is already well-structured (clean dependency graph, strong test coverage, idiomatic Ruby); these changes sharpen it further.

## Changes

### 1. Quantity Value Object

**Problem:** Ingredient quantities flow through the system as bare `[value, unit]` two-element arrays. They appear in IngredientAggregator, NutritionCalculator, CrossReference, and Recipe — at least 6 locations. There is no type safety, no self-documentation, and changes to the representation would require shotgun surgery.

**Solution:** `Quantity = Data.define(:value, :unit)` in `lib/familyrecipes/quantity.rb`.

- Every `[value, unit]` becomes `Quantity[value, unit]`
- `nil` sentinel for unquantified ingredients remains `nil`
- Data.define provides `deconstruct`/`deconstruct_keys` for pattern matching
- Immutable by default — correct contract for a computed value

**Files affected:**
- New: `lib/familyrecipes/quantity.rb`
- Modified: `ingredient_aggregator.rb`, `nutrition_calculator.rb`, `cross_reference.rb`, `recipe.rb`, `site_generator.rb` (validate_nutrition destructuring)
- Tests: update any tests that assert on `[value, unit]` tuples

### 2. Struct to Data.define Conversions

**Problem:** `LineClassifier::LineToken` and `NutritionCalculator::Result` use `Struct`, which is mutable. Neither is ever mutated after creation.

**Solution:** Convert both to `Data.define`.

- `LineToken = Data.define(:type, :content, :line_number)` — enforces all three fields, immutable
- `Result = Data.define(:totals, :serving_count, :per_serving, :missing_ingredients, :partial_ingredients)` with `complete?` method in block — same interface, now frozen

**Files affected:**
- `line_classifier.rb` (LineToken definition)
- `nutrition_calculator.rb` (Result definition)
- Tests: minimal changes (Data.define uses keyword-only construction)

### 3. BuildValidator Extraction

**Problem:** SiteGenerator is 340 lines with 3 validation methods (cross-references, ingredients, nutrition) plus a `detect_cycles` helper totaling ~120 lines. The `validate_nutrition` method is 77 lines and requires a `# rubocop:disable Metrics` comment.

**Solution:** Extract `FamilyRecipes::BuildValidator` class in `lib/familyrecipes/build_validator.rb`.

```ruby
class BuildValidator
  def initialize(recipes:, quick_bites:, recipe_map:, alias_map:,
                 known_ingredients:, omit_set:, nutrition_calculator:)
  end

  def validate_cross_references  # + detect_cycles private helper
  def validate_ingredients
  def validate_nutrition
end
```

SiteGenerator creates one after loading data and delegates the three calls. SiteGenerator drops from ~340 to ~220 lines. The `rubocop:disable Metrics` comment is removed.

**Files affected:**
- New: `lib/familyrecipes/build_validator.rb`
- Modified: `site_generator.rb` (delegate validation calls)
- New test: `test/build_validator_test.rb`
- Modified: `site_generator_test.rb` (if any validation assertions exist there)

## What Was Considered and Rejected

- **GroceryItem value object** for `{ name:, aliases: }` hashes — moderate churn, narrow scope, modest gain
- **ParsedIngredient/ParsedCrossReference Data objects** for IngredientParser output — hashes are created and immediately consumed; window too narrow
- **RecipeDocument Data object** for RecipeBuilder output — same reason
- **Extracting utility methods from familyrecipes.rb** — stateless functions work well as module-level methods
- **Zeitwerk autoloading** — adds a dependency to save 14 require_relative lines; not justified for a build tool
- **dry-rb gems** — Ruby 3.2+ native features (Data.define, pattern matching) cover all needs
- **Rendering/output extraction from SiteGenerator** — validation is the cleaner boundary; rendering is tightly coupled to the generate flow

## Testing Strategy

- Existing tests updated to use Quantity objects and Data.define construction
- New unit tests for BuildValidator covering all three validation paths
- Full `rake test` and `rake lint` must pass after each change
