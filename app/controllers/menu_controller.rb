# frozen_string_literal: true

# Meal planning page -- member-only. Displays a recipe selector (recipes + quick
# bites) with checkboxes. Mutations return inline Turbo Stream morph responses
# and broadcast via MealPlanBroadcaster for cross-device sync. Quick bites
# content is web-editable; changes broadcast to all connected clients.
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
    MealPlanBroadcaster.broadcast_all(current_kitchen)
    render_menu_morph
  end

  def select_all
    mutate_plan { |plan| plan.select_all!(all_recipe_slugs, all_quick_bite_slugs) }
    MealPlanBroadcaster.broadcast_all(current_kitchen)
    render_menu_morph
  end

  def clear
    mutate_plan(&:clear_selections!)
    MealPlanBroadcaster.broadcast_all(current_kitchen)
    render_menu_morph
  end

  def quick_bites_content
    render json: { content: current_kitchen.quick_bites_content || '' }
  end

  def update_quick_bites
    content = params[:content].to_s
    return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_content if content.blank?

    current_kitchen.update!(quick_bites_content: content)
    MealPlan.prune_stale_items(kitchen: current_kitchen)
    MealPlanBroadcaster.broadcast_all(current_kitchen)
    render json: { status: 'ok' }
  end

  private

  def render_menu_morph
    plan = MealPlan.for_kitchen(current_kitchen)
    checked_off = plan.state.fetch('checked_off', [])
    availability = RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off:).call

    render turbo_stream: turbo_stream.action(
      :replace, 'recipe-selector', method: :morph,
      partial: 'menu/recipe_selector',
      locals: {
        categories: recipe_selector_categories,
        quick_bites_by_subsection: current_kitchen.quick_bites_by_subsection,
        selected_recipes: plan.selected_recipes_set,
        selected_quick_bites: plan.selected_quick_bites_set,
        availability:
      }
    )
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
