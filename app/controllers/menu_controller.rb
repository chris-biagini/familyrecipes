# frozen_string_literal: true

class MenuController < ApplicationController
  before_action :require_membership

  rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_record

  def show
    @categories = recipe_selector_categories
    @quick_bites_by_subsection = load_quick_bites_by_subsection
    @quick_bites_content = current_kitchen.quick_bites_content || ''
  end

  def select
    apply_and_respond('select',
                      type: params[:type],
                      slug: params[:slug],
                      selected: params[:selected])
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

  def update_quick_bites
    content = params[:content].to_s
    return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_content if content.blank?

    current_kitchen.update!(quick_bites_content: content)

    broadcast_recipe_selector_update
    render json: { status: 'ok' }
  end

  private

  def apply_and_respond(action_type, **action_params)
    plan = MealPlan.for_kitchen(current_kitchen)
    plan.with_optimistic_retry do
      plan.apply_action(action_type, **action_params)
    end
    MealPlanChannel.broadcast_version(current_kitchen, plan.lock_version)
    render json: { version: plan.lock_version }
  end

  def handle_stale_record
    render json: { error: 'Meal plan was modified by another request. Please refresh.' },
           status: :conflict
  end

  def load_quick_bites_by_subsection
    content = current_kitchen.quick_bites_content
    return {} unless content

    FamilyRecipes.parse_quick_bites_content(content)
                 .group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
  end

  def recipe_selector_categories
    current_kitchen.categories.ordered.includes(recipes: { steps: :ingredients })
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
