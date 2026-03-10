# Unified Write Service Broadcast Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Unify post-write side effects (broadcast + reconcile) so they always live in services, never in controllers.

**Architecture:** Create a new `MealPlanWriteService` to absorb meal plan mutations from the `MealPlanActions` concern. Add `broadcast_update` to `AisleWriteService` and `CategoryWriteService` so they own their full pipeline like `RecipeWriteService` and `CatalogWriteService` already do. Controllers become pure HTTP adapters: parse params, call service, render response.

**Tech Stack:** Rails services, Minitest, Turbo Broadcastable test helper

---

### Task 0: Create MealPlanWriteService with tests

**Files:**
- Create: `app/services/meal_plan_write_service.rb`
- Create: `test/services/meal_plan_write_service_test.rb`

This service absorbs the mutation + reconcile + broadcast pipeline currently
split between `MealPlanActions` concern and controllers. Four class methods
matching the four mutation shapes in MenuController and GroceriesController.

**Step 1: Write the failing tests**

```ruby
# test/services/meal_plan_write_service_test.rb
# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class MealPlanWriteServiceTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    setup_test_kitchen
    setup_test_category
    @plan = MealPlan.for_kitchen(@kitchen)
  end

  # --- apply_action ---

  test 'apply_action persists the mutation' do
    create_focaccia_recipe

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: 'focaccia', selected: true
    )

    @plan.reload
    assert_includes @plan.state['selected_recipes'], 'focaccia'
  end

  test 'apply_action reconciles stale selections' do
    @plan.apply_action('select', type: 'recipe', slug: 'ghost', selected: true)

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: 'ghost', selected: false
    )

    @plan.reload
    assert_not_includes @plan.state['selected_recipes'], 'ghost'
  end

  test 'apply_action broadcasts to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      MealPlanWriteService.apply_action(
        kitchen: @kitchen, action_type: 'check',
        item: 'flour', checked: true
      )
    end
  end

  test 'apply_action retries on StaleObjectError' do
    create_focaccia_recipe
    attempts = 0
    original_apply = @plan.method(:apply_action)

    @plan.define_singleton_method(:apply_action) do |*args, **kwargs|
      attempts += 1
      raise ActiveRecord::StaleObjectError, self if attempts == 1

      original_apply.call(*args, **kwargs)
    end

    MealPlan.stub(:for_kitchen, @plan) do
      MealPlanWriteService.apply_action(
        kitchen: @kitchen, action_type: 'select',
        type: 'recipe', slug: 'focaccia', selected: true
      )
    end

    assert_equal 2, attempts
  end

  # --- select_all ---

  test 'select_all selects all provided slugs' do
    MealPlanWriteService.select_all(
      kitchen: @kitchen, recipe_slugs: %w[a b], quick_bite_slugs: %w[c]
    )

    @plan.reload
    assert_equal %w[a b], @plan.state['selected_recipes']
    assert_equal %w[c], @plan.state['selected_quick_bites']
  end

  test 'select_all broadcasts to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      MealPlanWriteService.select_all(
        kitchen: @kitchen, recipe_slugs: [], quick_bite_slugs: []
      )
    end
  end

  # --- clear ---

  test 'clear empties selections and checked_off' do
    @plan.apply_action('select', type: 'recipe', slug: 'x', selected: true)
    @plan.apply_action('check', item: 'flour', checked: true)

    MealPlanWriteService.clear(kitchen: @kitchen)

    @plan.reload
    assert_empty @plan.state['selected_recipes']
    assert_empty @plan.state['checked_off']
  end

  test 'clear broadcasts to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      MealPlanWriteService.clear(kitchen: @kitchen)
    end
  end

  # --- reconcile ---

  test 'reconcile prunes stale selections and broadcasts' do
    @plan.apply_action('select', type: 'quick_bite', slug: 'gone', selected: true)

    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      MealPlanWriteService.reconcile(kitchen: @kitchen)
    end

    @plan.reload
    assert_not_includes @plan.state['selected_quick_bites'], 'gone'
  end

  private

  def create_focaccia_recipe
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix

      - Flour, 3 cups

      Mix well.
    MD
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/meal_plan_write_service_test.rb`
Expected: Error — `MealPlanWriteService` not defined

**Step 3: Write the service**

```ruby
# app/services/meal_plan_write_service.rb
# frozen_string_literal: true

# Orchestrates all direct MealPlan mutations: action application (select,
# check, custom items), select-all, clear, and standalone reconciliation.
# Owns optimistic-locking retry, reconciliation of stale state, and
# Kitchen#broadcast_update — controllers never call these directly.
#
# - MealPlan: singleton-per-kitchen JSON state record
# - MealPlan#reconcile!: prunes stale selections and checked-off items
# - Kitchen#broadcast_update: page-refresh morph for all connected clients
class MealPlanWriteService
  def self.apply_action(kitchen:, action_type:, **params)
    new(kitchen:).apply_action(action_type:, **params)
  end

  def self.select_all(kitchen:, recipe_slugs:, quick_bite_slugs:)
    new(kitchen:).select_all(recipe_slugs:, quick_bite_slugs:)
  end

  def self.clear(kitchen:)
    new(kitchen:).clear
  end

  def self.reconcile(kitchen:)
    new(kitchen:).reconcile
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def apply_action(action_type:, **params)
    mutate_plan do |plan|
      plan.apply_action(action_type, **params)
      plan.reconcile!
    end
    kitchen.broadcast_update
  end

  def select_all(recipe_slugs:, quick_bite_slugs:)
    mutate_plan { |plan| plan.select_all!(recipe_slugs, quick_bite_slugs) }
    kitchen.broadcast_update
  end

  def clear
    mutate_plan(&:clear_selections!)
    kitchen.broadcast_update
  end

  def reconcile
    mutate_plan(&:reconcile!)
    kitchen.broadcast_update
  end

  private

  attr_reader :kitchen

  def mutate_plan
    plan = MealPlan.for_kitchen(kitchen)
    plan.with_optimistic_retry { yield plan }
    plan
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/meal_plan_write_service_test.rb`
Expected: All pass

**Step 5: Commit**

```bash
git add app/services/meal_plan_write_service.rb test/services/meal_plan_write_service_test.rb
git commit -m "feat: add MealPlanWriteService to own meal plan mutation pipeline"
```

---

### Task 1: Add broadcast_update to AisleWriteService

**Files:**
- Modify: `app/services/aisle_write_service.rb`
- Modify: `test/services/aisle_write_service_test.rb`

**Step 1: Write the failing test**

Add to `test/services/aisle_write_service_test.rb`:

```ruby
test 'update_order broadcasts to kitchen updates stream' do
  assert_turbo_stream_broadcasts [@kitchen, :updates] do
    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: 'Produce', renames: {}, deletes: []
    )
  end
end

test 'update_order does not broadcast on validation failure' do
  assert_no_turbo_stream_broadcasts [@kitchen, :updates] do
    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: 'a' * 51, renames: {}, deletes: []
    )
  end
end
```

Also add `require 'turbo/broadcastable/test_helper'` and
`include Turbo::Broadcastable::TestHelper` to the test class.

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/aisle_write_service_test.rb -n test_update_order_broadcasts_to_kitchen_updates_stream`
Expected: FAIL — no broadcasts detected

**Step 3: Add broadcast to the service**

In `app/services/aisle_write_service.rb`, add `kitchen.broadcast_update` after
the successful transaction in `update_order`:

```ruby
def update_order(aisle_order:, renames:, deletes:)
  kitchen.aisle_order = aisle_order.to_s

  errors = validate_order
  return Result.new(success: false, errors:) if errors.any?

  kitchen.normalize_aisle_order!

  ActiveRecord::Base.transaction do
    cascade_renames(renames)
    cascade_deletes(deletes)
    kitchen.save!
  end

  kitchen.broadcast_update
  Result.new(success: true, errors: [])
end
```

Also update the header comment to list `Kitchen#broadcast_update` as a collaborator.

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/aisle_write_service_test.rb`
Expected: All pass

**Step 5: Commit**

```bash
git add app/services/aisle_write_service.rb test/services/aisle_write_service_test.rb
git commit -m "feat: AisleWriteService owns its broadcast_update"
```

---

### Task 2: Add broadcast_update to CategoryWriteService

**Files:**
- Modify: `app/services/category_write_service.rb`
- Modify: `test/services/category_write_service_test.rb`

**Step 1: Write the failing test**

Add to `test/services/category_write_service_test.rb`:

```ruby
test 'update_order broadcasts to kitchen updates stream' do
  assert_turbo_stream_broadcasts [@kitchen, :updates] do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: %w[Bread Dessert], renames: {}, deletes: []
    )
  end
end

test 'update_order does not broadcast on validation failure' do
  assert_no_turbo_stream_broadcasts [@kitchen, :updates] do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: (1..51).map { |i| "Cat #{i}" }, renames: {}, deletes: []
    )
  end
end
```

Also add `require 'turbo/broadcastable/test_helper'` and
`include Turbo::Broadcastable::TestHelper` to the test class.

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/category_write_service_test.rb -n test_update_order_broadcasts_to_kitchen_updates_stream`
Expected: FAIL — no broadcasts detected

**Step 3: Add broadcast to the service**

In `app/services/category_write_service.rb`, add `kitchen.broadcast_update`
after the successful transaction in `update_order`:

```ruby
def update_order(names:, renames:, deletes:)
  errors = validate_order(names)
  return Result.new(success: false, errors:) if errors.any?

  ActiveRecord::Base.transaction do
    cascade_renames(renames)
    cascade_deletes(deletes)
    update_positions(names)
  end

  kitchen.broadcast_update
  Result.new(success: true, errors: [])
end
```

Update the header comment: remove "(called by controller, not service)" from
line 8 and add `Kitchen#broadcast_update` as a collaborator.

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/category_write_service_test.rb`
Expected: All pass

**Step 5: Commit**

```bash
git add app/services/category_write_service.rb test/services/category_write_service_test.rb
git commit -m "feat: CategoryWriteService owns its broadcast_update"
```

---

### Task 3: Update MenuController to use MealPlanWriteService

**Files:**
- Modify: `app/controllers/menu_controller.rb`
- Modify: `test/controllers/menu_controller_test.rb` (verify existing tests still pass)

**Step 1: Rewrite the controller actions**

Replace `apply_plan`, `mutate_plan`, and `broadcast_update` calls with
`MealPlanWriteService` calls. Remove the `include MealPlanActions` line —
re-add it in Task 5 after slimming the concern (we still need the
`rescue_from` handler).

```ruby
class MenuController < ApplicationController
  include MealPlanActions

  before_action :require_membership
  before_action :prevent_html_caching, only: :show

  def show
    # ... unchanged ...
  end

  def select
    MealPlanWriteService.apply_action(
      kitchen: current_kitchen, action_type: 'select',
      type: params[:type], slug: params[:slug], selected: params[:selected]
    )
    head :no_content
  end

  def select_all
    MealPlanWriteService.select_all(
      kitchen: current_kitchen,
      recipe_slugs: all_recipe_slugs,
      quick_bite_slugs: all_quick_bite_slugs
    )
    head :no_content
  end

  def clear
    MealPlanWriteService.clear(kitchen: current_kitchen)
    head :no_content
  end

  def quick_bites_content
    # ... unchanged ...
  end

  def update_quick_bites
    stored = params[:content].to_s.presence
    result = parse_quick_bites(stored)
    current_kitchen.update!(quick_bites_content: stored)
    MealPlanWriteService.reconcile(kitchen: current_kitchen)

    body = { status: 'ok' }
    body[:warnings] = result.warnings if result.warnings.any?
    render json: body
  end

  # ... private helpers unchanged ...
end
```

**Step 2: Run existing controller tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: All pass — including the broadcast assertions and 409 conflict tests.

Note: The 409 conflict tests stub `MealPlan.for_kitchen` to raise
`StaleObjectError`. Since `MealPlanWriteService` calls `MealPlan.for_kitchen`
internally, these stubs still work. The `rescue_from` in `MealPlanActions`
still catches the exception bubbling up through the service.

**Step 3: Commit**

```bash
git add app/controllers/menu_controller.rb
git commit -m "refactor: MenuController delegates to MealPlanWriteService"
```

---

### Task 4: Update GroceriesController to use MealPlanWriteService

**Files:**
- Modify: `app/controllers/groceries_controller.rb`
- Modify: `test/controllers/groceries_controller_test.rb` (verify existing tests still pass)

**Step 1: Rewrite the controller actions**

Replace `apply_plan` and `broadcast_update` calls with `MealPlanWriteService`
calls. Remove the `broadcast_update` call from `update_aisle_order` (the
service owns it now).

```ruby
class GroceriesController < ApplicationController
  include MealPlanActions

  before_action :require_membership
  before_action :prevent_html_caching, only: :show

  def show
    # ... unchanged ...
  end

  def check
    MealPlanWriteService.apply_action(
      kitchen: current_kitchen, action_type: 'check',
      item: params[:item], checked: params[:checked]
    )
    head :no_content
  end

  def update_custom_items
    item = params[:item].to_s
    max = MealPlan::MAX_CUSTOM_ITEM_LENGTH
    if item.size > max
      return render json: { errors: ["Custom item name is too long (max #{max} characters)"] },
                    status: :unprocessable_content
    end

    MealPlanWriteService.apply_action(
      kitchen: current_kitchen, action_type: 'custom_items',
      item: item, action: params[:action_type]
    )
    head :no_content
  end

  def update_aisle_order
    result = AisleWriteService.update_order(
      kitchen: current_kitchen,
      aisle_order: params[:aisle_order].to_s,
      renames: params[:renames],
      deletes: params[:deletes]
    )
    return render(json: { errors: result.errors }, status: :unprocessable_content) if result.errors.any?

    render json: { status: 'ok' }
  end

  def aisle_order_content
    # ... unchanged ...
  end
end
```

**Step 2: Run existing controller tests**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: All pass

**Step 3: Commit**

```bash
git add app/controllers/groceries_controller.rb
git commit -m "refactor: GroceriesController delegates to MealPlanWriteService and AisleWriteService"
```

---

### Task 5: Update CategoriesController to remove broadcast

**Files:**
- Modify: `app/controllers/categories_controller.rb`

**Step 1: Remove the broadcast call**

The service owns it now. Also update the header comment to remove
`Kitchen#broadcast_update` as a collaborator.

```ruby
def update_order
  result = CategoryWriteService.update_order(
    kitchen: current_kitchen,
    names: Array(params[:category_order]),
    renames: params[:renames],
    deletes: params[:deletes]
  )
  return render(json: { errors: result.errors }, status: :unprocessable_content) unless result.success

  render json: { status: 'ok' }
end
```

**Step 2: Run existing controller tests**

Run: `ruby -Itest test/controllers/categories_controller_test.rb`
Expected: All pass (the test doesn't assert broadcasts at controller level —
those assertions live in the service test now)

**Step 3: Commit**

```bash
git add app/controllers/categories_controller.rb
git commit -m "refactor: CategoriesController drops broadcast, service owns it"
```

---

### Task 6: Slim MealPlanActions concern

**Files:**
- Modify: `app/controllers/concerns/meal_plan_actions.rb`

**Step 1: Remove the mutation helpers**

The concern now only provides the `rescue_from StaleObjectError` handler.
`mutate_plan` and `apply_plan` are no longer called by any controller.

```ruby
# frozen_string_literal: true

# Provides StaleObjectError handling for controllers whose write paths pass
# through MealPlanWriteService. The service uses optimistic-locking retry
# internally, but if retries are exhausted the exception bubbles up here.
# Used by MenuController and GroceriesController.
module MealPlanActions
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_record
  end

  private

  def handle_stale_record
    render json: { error: 'Meal plan was modified by another request. Please refresh.' },
           status: :conflict
  end
end
```

**Step 2: Run the full test suite for affected controllers**

Run: `ruby -Itest test/controllers/menu_controller_test.rb test/controllers/groceries_controller_test.rb`
Expected: All pass

**Step 3: Commit**

```bash
git add app/controllers/concerns/meal_plan_actions.rb
git commit -m "refactor: slim MealPlanActions to rescue_from only"
```

---

### Task 7: Update header comments and CLAUDE.md

**Files:**
- Modify: `app/controllers/menu_controller.rb` (header comment)
- Modify: `app/controllers/groceries_controller.rb` (header comment)
- Modify: `app/controllers/categories_controller.rb` (header comment)
- Modify: `app/services/aisle_write_service.rb` (header comment)
- Modify: `CLAUDE.md` (Architecture section)

**Step 1: Update controller header comments**

Remove references to `Kitchen#broadcast_update` from controller headers. Add
`MealPlanWriteService` as a collaborator where applicable.

**Step 2: Update CLAUDE.md Architecture section**

In the "Write path" paragraph, add `MealPlanWriteService` to the list:

> `MealPlanWriteService` orchestrates all direct `MealPlan` mutations — action
> application (select, check, custom items), select-all, clear, and standalone
> reconciliation.

Remove the sentence about `MealPlanActions` providing optimistic-locking retry
and update it to say it provides StaleObjectError rescue only.

**Step 3: Commit**

```bash
git add app/controllers/menu_controller.rb app/controllers/groceries_controller.rb \
  app/controllers/categories_controller.rb app/services/aisle_write_service.rb CLAUDE.md
git commit -m "docs: update header comments and CLAUDE.md for unified broadcast pattern"
```

---

### Task 8: Full test suite verification

**Step 1: Run lint**

Run: `bundle exec rubocop`
Expected: 0 offenses

**Step 2: Run full test suite**

Run: `rake test`
Expected: All pass, 0 failures, 0 errors

**Step 3: Verify broadcast call sites**

Run: `grep -rn 'broadcast_update' app/`

Expected: `broadcast_update` appears ONLY in:
- `app/models/kitchen.rb` (the method definition)
- `app/services/recipe_write_service.rb` (3 calls)
- `app/services/catalog_write_service.rb` (2 calls)
- `app/services/aisle_write_service.rb` (1 call)
- `app/services/category_write_service.rb` (1 call)
- `app/services/meal_plan_write_service.rb` (4 calls)
- `app/services/import_service.rb` (1 call)

Zero calls in `app/controllers/`. That's the win.
