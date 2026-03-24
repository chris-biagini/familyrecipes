# RecipeBroadcaster Consolidation Design

## Problem

`RecipeBroadcaster` was built to be the single owner of Turbo Stream broadcasting for recipe-related content. Three other components bypass it and call `Turbo::StreamsChannel` directly, creating duplication and coupling:

1. **`RecipeWriteService#broadcast_to_referencing_recipes`** — On recipe destroy, the service reaches into `RecipeBroadcaster::SHOW_INCLUDES` and manually reproduces the `broadcast_replace_to` call that `RecipeBroadcaster#replace_recipe_content` already encapsulates. Two places know the partial name, stream target, and locals shape.

2. **`MenuController#broadcast_recipe_selector_update`** — After updating Quick Bites, the controller manually fires a Turbo Stream replacement. `RecipeBroadcaster` has an identical private method. The stream name differs (`menu_content` vs `recipes`) intentionally, but the controller duplicates partial/target/locals knowledge.

3. **Duplicated Quick Bites grouping** — `MenuController#load_quick_bites_by_subsection` and `RecipeBroadcaster#parse_quick_bites` both do `.group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }`.

Additionally, two smaller smells in `MealPlanActions` compound the problem:

4. **`prune_if_deselect`** copy-pastes `[true, 'true'].include?(...)` from `MealPlan#truthy?`.

5. **`select_all` and `clear`** in `MenuController` duplicate the retry/broadcast/render pattern from `MealPlanActions#apply_and_respond`.

## Design

### Change 1: Kitchen#quick_bites_by_subsection

Move the `delete_prefix('Quick Bites: ')` grouping to the Kitchen model:

```ruby
def quick_bites_by_subsection
  parsed_quick_bites.group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
end
```

Delete `RecipeBroadcaster#parse_quick_bites` and `MenuController#load_quick_bites_by_subsection`. Both callers use `kitchen.quick_bites_by_subsection`.

### Change 2: RecipeBroadcaster.broadcast_destroy

New class method that owns the full destroy broadcast lifecycle:

```ruby
def self.broadcast_destroy(kitchen:, recipe:, recipe_title:, parent_ids:)
```

It performs three things in sequence:

1. Notify the recipe page (replace content with "deleted" message, append toast) — what `notify_recipe_deleted` does today. Verified that Turbo's `signed_stream_name` works identically on destroyed AR records.
2. Update referencing recipe pages by `parent_ids` — what `broadcast_to_referencing_recipes` does today, but through `RecipeBroadcaster` instead of reaching past it.
3. Fire the full CRUD broadcast (listings, selector, ingredients, toast) — what `broadcast(action: :deleted)` does today.

`RecipeWriteService#destroy` becomes:

```ruby
def destroy(slug:)
  recipe = kitchen.recipes.find_by!(slug:)
  parent_ids = recipe.referencing_recipes.pluck(:id)
  recipe.destroy!
  RecipeBroadcaster.broadcast_destroy(kitchen:, recipe:, recipe_title: recipe.title, parent_ids:)
  post_write_cleanup
  Result.new(recipe:, updated_references: [])
end
```

`RecipeWriteService#broadcast_to_referencing_recipes` is deleted.
`RecipeBroadcaster.notify_recipe_deleted` becomes a private method (no external callers remain).

### Change 3: RecipeBroadcaster.broadcast_recipe_selector

New class method with a `stream:` keyword:

```ruby
def self.broadcast_recipe_selector(kitchen:, stream: 'recipes')
```

When called standalone (from `MenuController` for Quick Bites updates), it loads categories with light includes (`.includes(:recipes)`). When called from the full `broadcast` method, it reuses the pre-loaded deep categories.

`MenuController#update_quick_bites` calls:

```ruby
RecipeBroadcaster.broadcast_recipe_selector(kitchen: current_kitchen, stream: 'menu_content')
```

`MenuController#broadcast_recipe_selector_update` is deleted.

The `stream:` parameter isn't speculative — two real callers use different streams today:
- Recipe CRUD broadcasts on `'recipes'` (reaches homepage, menu, ingredients pages)
- Quick Bites edits broadcast on `'menu_content'` (reaches menu page only)

### Change 4: MealPlan.truthy? promoted to public class method

```ruby
def self.truthy?(value)
  [true, 'true'].include?(value)
end
```

`MealPlanActions#prune_if_deselect` calls `MealPlan.truthy?` instead of inlining the check. The private instance method `truthy?` calls the class method to avoid duplication.

### Change 5: MealPlanActions#mutate_and_respond

Extract the retry/broadcast/render pattern into a block-based helper:

```ruby
def mutate_and_respond
  plan = MealPlan.for_kitchen(current_kitchen)
  plan.with_optimistic_retry { yield plan }
  MealPlanChannel.broadcast_version(current_kitchen, plan.lock_version)
  render json: { version: plan.lock_version }
end
```

`select_all`, `clear`, and `apply_and_respond` all use it:

```ruby
def select_all
  mutate_and_respond { |plan| plan.select_all!(all_recipe_slugs, all_quick_bite_slugs) }
end

def clear
  mutate_and_respond { |plan| plan.clear_selections! }
end

def apply_and_respond(action_type, **action_params)
  mutate_and_respond do |plan|
    plan.apply_action(action_type, **action_params)
    prune_if_deselect(action_type, action_params)
  end
end
```

## Files Touched

| File | Action |
|------|--------|
| `app/models/kitchen.rb` | Add `quick_bites_by_subsection` |
| `app/services/recipe_broadcaster.rb` | Add `broadcast_destroy` class method, add `broadcast_recipe_selector` class method with `stream:`, make `notify_recipe_deleted` private, delete `parse_quick_bites`, use `kitchen.quick_bites_by_subsection` |
| `app/services/recipe_write_service.rb` | Collapse destroy to one broadcaster call, delete `broadcast_to_referencing_recipes` |
| `app/controllers/menu_controller.rb` | Delete `broadcast_recipe_selector_update`, delete `load_quick_bites_by_subsection`, use `kitchen.quick_bites_by_subsection` in `show`, delegate to `RecipeBroadcaster.broadcast_recipe_selector` in `update_quick_bites`, use `mutate_and_respond` for `select_all`/`clear` |
| `app/controllers/concerns/meal_plan_actions.rb` | Add `mutate_and_respond`, refactor `apply_and_respond` to use it, update `prune_if_deselect` to use `MealPlan.truthy?` |
| `app/models/meal_plan.rb` | Promote `truthy?` to public class method |

## Testing

Existing tests for `RecipeWriteService#destroy`, `MenuController#update_quick_bites`, `MenuController#select_all`, `MenuController#clear`, and `MealPlanActions` should continue to pass with no behavioral changes. The Turbo Stream broadcast assertions will verify the correct streams and targets. No new test files needed — this is a refactor of internal wiring, not a behavior change.
