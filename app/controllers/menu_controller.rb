# frozen_string_literal: true

# Meal planning page — member-only. Displays a recipe selector (recipes + quick
# bites) with checkboxes. Mutations delegate to write services and return
# 204 No Content; broadcasts happen inside the services for cross-device sync.
#
# - MealPlanWriteService: select/deselect, select-all, clear, reconcile
# - QuickBitesWriteService: quick bites content updates
# - MealPlanActions: rescue_from for StaleObjectError
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
    render json: { content: current_kitchen.quick_bites_content || '' }
  end

  def update_quick_bites
    result = QuickBitesWriteService.update(
      kitchen: current_kitchen, content: params[:content]
    )

    body = { status: 'ok' }
    body[:warnings] = result.warnings if result.warnings.any?
    render json: body
  end

  private

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
