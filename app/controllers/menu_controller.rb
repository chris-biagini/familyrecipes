# frozen_string_literal: true

# Meal planning page — member-only. Displays a recipe selector (recipes + quick
# bites) with checkboxes. Mutations delegate to write services and return
# 204 No Content; broadcasts happen inside the services for cross-device sync.
#
# - MealPlanWriteService: select/deselect
# - QuickBitesWriteService: quick bites content updates
# - MealPlanActions: param coercion and StaleObjectError rescue
class MenuController < ApplicationController
  include MealPlanActions
  include StructureValidation

  before_action :require_membership
  before_action :prevent_html_caching, only: :show

  def show
    @categories = recipe_selector_categories
    @selected_recipes = selected_ids_for('Recipe')
    @selected_quick_bites = selected_ids_for('QuickBite').to_set(&:to_i)
    @availability = compute_availability
    @cook_weights = CookHistoryWeighter.call(CookHistoryEntry.where(kitchen_id: current_kitchen.id).recent)
  end

  def select
    MealPlanWriteService.apply_action(
      kitchen: current_kitchen, action_type: 'select',
      type: params[:type], slug: params[:slug], selected: truthy_param?(params[:selected])
    )
    head :no_content
  end

  def quick_bites_content
    ir = FamilyRecipes::QuickBitesSerializer.from_records(current_kitchen)
    content = FamilyRecipes::QuickBitesSerializer.serialize(ir)
    render json: { content:, structure: ir }
  end

  def quickbites_editor_frame
    ir = FamilyRecipes::QuickBitesSerializer.from_records(current_kitchen)
    content = FamilyRecipes::QuickBitesSerializer.serialize(ir)

    render partial: 'menu/quickbites_editor_frame', locals: {
      content:, structure: ir
    }, layout: false
  end

  def update_quick_bites
    result = if params[:structure]
               QuickBitesWriteService.update_from_structure(
                 kitchen: current_kitchen, structure: validated_quick_bites_structure
               )
             else
               QuickBitesWriteService.update(
                 kitchen: current_kitchen, content: params[:content]
               )
             end

    body = { status: 'ok' }
    body[:warnings] = result.warnings if result.warnings.any?
    render json: body
  rescue ActiveRecord::RecordInvalid => error
    render json: { errors: [error.message] }, status: :unprocessable_content
  end

  def parse_quick_bites
    result = FamilyRecipes.parse_quick_bites_content(params[:content].to_s)
    ir = FamilyRecipes::QuickBitesSerializer.to_ir(result.quick_bites)
    render json: ir
  end

  def serialize_quick_bites
    content = FamilyRecipes::QuickBitesSerializer.serialize(validated_quick_bites_structure)
    render json: { content: }
  end

  private

  def selected_ids_for(type)
    MealPlanSelection.where(kitchen_id: current_kitchen.id, selectable_type: type)
                     .pluck(:selectable_id).to_set
  end

  def compute_availability
    Rails.cache.fetch(['menu_availability', current_kitchen.id, current_kitchen.updated_at.to_f]) do
      on_hand_names = OnHandEntry.where(kitchen_id: current_kitchen.id).active.pluck(:ingredient_name)
      recipes = @categories.flat_map(&:recipes)
      RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off: on_hand_names, recipes:).call
    end
  end

  def recipe_selector_categories
    current_kitchen.categories.ordered.includes(
      quick_bites: :quick_bite_ingredients,
      recipes: { steps: [:ingredients, { cross_references: { target_recipe: { steps: :ingredients } } }] }
    )
  end
end
