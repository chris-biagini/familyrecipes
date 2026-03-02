# frozen_string_literal: true

# Meal planning page — member-only. Displays a recipe selector (recipes + quick
# bites) with checkboxes. Manages MealPlan state (select/select_all/clear) and
# broadcasts version updates via MealPlanChannel for cross-device sync. Quick
# bites content is web-editable; changes broadcast Turbo Stream replacements
# to update all connected clients.
class MenuController < ApplicationController
  include MealPlanActions

  before_action :require_membership
  before_action :prevent_html_caching, only: :show

  def show
    @categories = recipe_selector_categories
    @quick_bites_by_subsection = load_quick_bites_by_subsection
  end

  def select
    apply_and_respond('select',
                      type: params[:type],
                      slug: params[:slug],
                      selected: params[:selected])
  end

  def select_all
    plan = MealPlan.for_kitchen(current_kitchen)
    plan.with_optimistic_retry { plan.select_all!(all_recipe_slugs, all_quick_bite_slugs) }
    MealPlanChannel.broadcast_version(current_kitchen, plan.lock_version)
    render json: { version: plan.lock_version }
  end

  def clear
    plan = MealPlan.for_kitchen(current_kitchen)
    plan.with_optimistic_retry { plan.clear_selections! }
    MealPlanChannel.broadcast_version(current_kitchen, plan.lock_version)
    render json: { version: plan.lock_version }
  end

  def quick_bites_content
    render json: { content: current_kitchen.quick_bites_content || '' }
  end

  def state
    plan = MealPlan.for_kitchen(current_kitchen)
    checked_off = plan.state.fetch('checked_off', [])
    availability = RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off: checked_off).call

    render json: {
      version: plan.lock_version,
      **plan.state.slice('selected_recipes', 'selected_quick_bites'),
      availability: availability
    }
  end

  def update_quick_bites
    content = params[:content].to_s
    return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_content if content.blank?

    current_kitchen.update!(quick_bites_content: content)
    MealPlan.prune_stale_items(kitchen: current_kitchen)

    broadcast_recipe_selector_update
    MealPlanChannel.broadcast_content_changed(current_kitchen)
    render json: { status: 'ok' }
  end

  private

  def load_quick_bites_by_subsection
    current_kitchen.parsed_quick_bites
                   .group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
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

  def broadcast_recipe_selector_update
    Turbo::StreamsChannel.broadcast_replace_to(
      current_kitchen, 'menu_content',
      target: 'recipe-selector',
      partial: 'menu/recipe_selector',
      locals: {
        categories: recipe_selector_categories,
        quick_bites_by_subsection: load_quick_bites_by_subsection
      }
    )
  end
end
