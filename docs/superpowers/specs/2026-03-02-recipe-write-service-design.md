# Recipe Write Service — Design

Extract the recipe write-path orchestration from `RecipesController` into a
dedicated service. The controller currently acts as a workflow engine: validate,
import, handle renames, clean up orphan categories, prune meal plan state, and
broadcast real-time updates — all inline in 33-line and 16-line action methods
decorated with RuboCop disable comments. The service owns this pipeline; the
controller becomes a thin HTTP adapter.

## Problem

`RecipesController#update` (33 lines, 7 responsibilities) and `#destroy`
(16 lines, 5 responsibilities) mix HTTP concerns with domain orchestration.
The prune-checked-off pattern is duplicated across 4 call sites in 3
controllers. The `MealPlanActions` concern leaks `build_visible_names` into
every controller that prunes, coupling them to `ShoppingListBuilder`.

## Approach

Single service class (`RecipeWriteService`) with three class methods:
`create`, `update`, `destroy`. Each returns a `Result` value object. Prune
logic consolidates into `MealPlan.prune_stale_items(kitchen:)` — a class
method that owns its own `ShoppingListBuilder` call and retry wrapping.

Alternatives considered:
- **Service per action** (CreateRecipe, UpdateRecipe, DestroyRecipe) — three
  files for one concept, shared post-write steps need a module or base class.
  Over-engineered.
- **Model callbacks** (after_save/after_destroy) — triggers jobs, broadcasts,
  and cross-model mutations from callbacks. Seed and test paths would fire
  side effects. Actively harmful.

## RecipeWriteService

Lives at `app/services/recipe_write_service.rb`. Three class methods delegate
to a private instance that holds `kitchen`.

```ruby
class RecipeWriteService
  Result = Data.define(:recipe, :updated_references)

  def self.create(markdown:, kitchen:) ...
  def self.update(slug:, markdown:, kitchen:) ...
  def self.destroy(slug:, kitchen:) ...
end
```

### Create pipeline

1. `MarkdownImporter.import`
2. Set `edited_at`
3. `RecipeBroadcaster.broadcast(:created)`
4. Post-write cleanup
5. Return `Result.new(recipe:, updated_references: [])`

### Update pipeline

1. Find existing recipe by slug
2. `MarkdownImporter.import`
3. If title changed: `CrossReferenceUpdater.rename_references` → capture
   updated references list
4. If slug changed: `RecipeBroadcaster.broadcast_rename` + destroy old record
5. Set `edited_at`
6. `RecipeBroadcaster.broadcast(:updated)`
7. Post-write cleanup
8. Return `Result.new(recipe:, updated_references:)`

### Destroy pipeline

1. Find recipe, capture referencing recipe IDs
2. `RecipeBroadcaster.notify_recipe_deleted`
3. Destroy recipe
4. Broadcast Turbo Stream replacement to referencing recipes
5. `RecipeBroadcaster.broadcast(:deleted)`
6. Post-write cleanup
7. Return `Result.new(recipe:, updated_references: [])`

### Post-write cleanup (shared)

```ruby
def post_write_cleanup
  Category.cleanup_orphans(kitchen)
  MealPlan.prune_stale_items(kitchen:)
end
```

### Validation stays in the controller

`MarkdownValidator.validate` is an HTTP gate — the controller validates
params before calling the service. The service assumes valid input.

## MealPlan.prune_stale_items

New class method on `MealPlan` that encapsulates the full prune operation:

```ruby
def self.prune_stale_items(kitchen:)
  plan = for_kitchen(kitchen)
  shopping_list = ShoppingListBuilder.new(kitchen:, meal_plan: plan).build
  visible = shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }.to_set
  plan.with_optimistic_retry { plan.prune_checked_off(visible_names: visible) }
end
```

This eliminates:
- `build_visible_names` from `MealPlanActions` (deleted)
- 4 inline prune blocks across RecipesController, MenuController, and
  MealPlanActions
- The coupling between controllers and `ShoppingListBuilder`

## Controller changes

### RecipesController

- Remove `include MealPlanActions` — no longer needed
- Each action: validate → service call → render JSON (5-8 lines)
- Remove `broadcast_to_referencing_recipes` private method (moves to service)
- Remove RuboCop disable comments on `update`

### MenuController

- `update_quick_bites` replaces inline prune with
  `MealPlan.prune_stale_items(kitchen: current_kitchen)`
- Keeps `include MealPlanActions` for `apply_and_respond`

### MealPlanActions concern

- Delete `build_visible_names`
- Simplify `prune_if_deselect` to call
  `MealPlan.prune_stale_items(kitchen: current_kitchen)`

## Testing

### New: `test/services/recipe_write_service_test.rb`

Tests against real database state (no mocks). Verifies full pipeline
completion: recipe saved, cross-references resolved, nutrition computed,
categories cleaned up, meal plan pruned.

Key cases:
- `create` — imports, sets edited_at, returns Result
- `update` — imports, returns Result
- `update` with title rename — returns updated_references, old slug destroyed
- `update` with slug change — old record gone
- `destroy` — recipe gone, orphan category cleaned, meal plan pruned
- `destroy` with referencing recipes — references nullified

### New cases in `test/models/meal_plan_test.rb`

- `prune_stale_items` prunes items not in current shopping list
- Preserves custom items
- No-ops when nothing to prune

### Existing controller tests

Stay as integration tests verifying HTTP layer (params → JSON). Remove any
tests that were asserting orchestration internals now owned by the service.

### What the service does NOT test

Broadcasting payloads (RecipeBroadcaster's job) and markdown parsing
(MarkdownImporter's job). Service tests verify side effects happened (records
exist, categories cleaned) but don't assert on Turbo Stream content.
