# frozen_string_literal: true

# Meal planning page -- member-only. Displays a recipe selector (recipes + quick
# bites) with checkboxes. Mutations return 204 No Content and broadcast a
# page-refresh signal for cross-device sync. Quick bites content is web-editable;
# changes broadcast to all connected clients.
class MenuController < ApplicationController
  include MealPlanActions

  before_action :require_membership
  before_action :prevent_html_caching, only: :show

  def show
    plan = MealPlan.for_kitchen(current_kitchen)
    @categories = recipe_selector_categories
    @quick_bites_by_subsection = current_kitchen.quick_bites_by_subsection
    @selected_recipes = plan.selected_recipes_set
    @selected_quick_bites = plan.selected_quick_bites_set
    checked_off = plan.state.fetch('checked_off', [])
    @availability = RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off:).call
  end

  def select
    apply_plan('select', type: params[:type], slug: params[:slug], selected: params[:selected])
    current_kitchen.broadcast_update
    head :no_content
  end

  def select_all
    mutate_plan { |plan| plan.select_all!(all_recipe_slugs, all_quick_bite_slugs) }
    current_kitchen.broadcast_update
    head :no_content
  end

  def clear
    mutate_plan(&:clear_selections!)
    current_kitchen.broadcast_update
    head :no_content
  end

  def quick_bites_content
    render json: { content: current_kitchen.quick_bites_content || '' }
  end

  def update_quick_bites
    stored = params[:content].to_s.presence
    result = parse_quick_bites(stored)
    current_kitchen.update!(quick_bites_content: stored)
    plan = MealPlan.for_kitchen(current_kitchen)
    plan.with_optimistic_retry do
      plan.prune_checked_off(visible_names: shopping_list_visible_names(plan))
      plan.prune_stale_selections(kitchen: current_kitchen)
    end
    current_kitchen.broadcast_update

    body = { status: 'ok' }
    body[:warnings] = result.warnings if result.warnings.any?
    render json: body
  end

  private

  def parse_quick_bites(content)
    return FamilyRecipes::QuickBitesResult.new(quick_bites: [], warnings: []) unless content

    FamilyRecipes.parse_quick_bites_content(content)
  end

  def recipe_selector_categories
    current_kitchen.categories.ordered.includes(:recipes)
  end

  def all_recipe_slugs
    current_kitchen.recipes.pluck(:slug)
  end

  def all_quick_bite_slugs
    current_kitchen.parsed_quick_bites.map(&:id)
  end
end
