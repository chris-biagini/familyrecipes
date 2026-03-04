# frozen_string_literal: true

# Broadcasts Turbo Stream morphs for the groceries and menu pages. Called by
# controllers (after state mutations) and RecipeBroadcaster (after recipe CRUD).
# Wraps all queries in ActsAsTenant.with_tenant since callers like
# RecipeBroadcaster lack controller tenant context.
#
# - ShoppingListBuilder: produces the grocery shopping list
# - RecipeAvailabilityCalculator: computes ingredient availability dots
# - Turbo::StreamsChannel: transport layer for stream pushes
class MealPlanBroadcaster
  def self.broadcast_grocery_morph(kitchen, catalog_lookup: nil)
    new(kitchen, catalog_lookup:).broadcast_grocery_morph
  end

  def self.broadcast_menu_morph(kitchen, catalog_lookup: nil)
    new(kitchen, catalog_lookup:).broadcast_menu_morph
  end

  def self.broadcast_all(kitchen, catalog_lookup: nil)
    new(kitchen, catalog_lookup:).broadcast_all
  end

  def initialize(kitchen, catalog_lookup: nil)
    @kitchen = kitchen
    @catalog_lookup = catalog_lookup
  end

  def broadcast_grocery_morph
    with_plan { |plan| broadcast_grocery_streams(plan) }
  end

  def broadcast_menu_morph
    with_plan { |plan| broadcast_menu_streams(plan) }
  end

  def broadcast_all
    with_plan do |plan|
      broadcast_grocery_streams(plan)
      broadcast_menu_streams(plan)
    end
  end

  private

  attr_reader :kitchen

  def catalog_lookup
    @catalog_lookup ||= IngredientCatalog.lookup_for(kitchen)
  end

  def with_plan
    ActsAsTenant.with_tenant(kitchen) do
      yield MealPlan.for_kitchen(kitchen)
    end
  end

  def broadcast_grocery_streams(plan)
    broadcast_shopping_list(plan)
    broadcast_custom_items(plan)
  end

  def broadcast_menu_streams(plan)
    broadcast_recipe_selector(plan)
  end

  def broadcast_shopping_list(plan)
    shopping_list = ShoppingListBuilder.new(kitchen:, meal_plan: plan, catalog_lookup:).build

    Turbo::StreamsChannel.broadcast_action_to(
      kitchen, 'groceries',
      action: :update, attributes: { method: :morph },
      target: 'shopping-list',
      partial: 'groceries/shopping_list',
      locals: { shopping_list:, checked_off: plan.checked_off_set }
    )
  end

  def broadcast_custom_items(plan)
    Turbo::StreamsChannel.broadcast_action_to(
      kitchen, 'groceries',
      action: :replace, attributes: { method: :morph },
      target: 'custom-items-section',
      partial: 'groceries/custom_items',
      locals: { custom_items: plan.custom_items_list }
    )
  end

  def broadcast_recipe_selector(plan)
    checked_off = plan.state.fetch('checked_off', [])
    availability = RecipeAvailabilityCalculator.new(kitchen:, checked_off:, catalog_lookup:).call

    Turbo::StreamsChannel.broadcast_action_to(
      kitchen, 'menu',
      action: :replace, attributes: { method: :morph },
      target: 'recipe-selector',
      partial: 'menu/recipe_selector',
      locals: {
        categories: kitchen.categories.ordered.includes(:recipes),
        quick_bites_by_subsection: kitchen.quick_bites_by_subsection,
        selected_recipes: plan.selected_recipes_set,
        selected_quick_bites: plan.selected_quick_bites_set,
        availability:
      }
    )
  end
end
