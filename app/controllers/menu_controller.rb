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
    plan = MealPlan.for_kitchen(current_kitchen)
    @categories = recipe_selector_categories
    @quick_bites_by_subsection = current_kitchen.quick_bites_by_subsection
    @selected_recipes = plan.selected_recipes.to_set
    @selected_quick_bites = plan.selected_quick_bites.to_set
    on_hand_names = plan.effective_on_hand.keys
    recipes = @categories.flat_map(&:recipes)
    @availability = RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off: on_hand_names, recipes:).call
    @cook_weights = CookHistoryWeighter.call(plan.cook_history)
  end

  def select
    MealPlanWriteService.apply_action(
      kitchen: current_kitchen, action_type: 'select',
      type: params[:type], slug: params[:slug], selected: truthy_param?(params[:selected])
    )
    head :no_content
  end

  def quick_bites_content
    content = current_kitchen.quick_bites_content || ''
    result = FamilyRecipes.parse_quick_bites_content(content)
    structure = FamilyRecipes::QuickBitesSerializer.to_ir(result.quick_bites)
    render json: { content:, structure: }
  end

  def quickbites_editor_frame
    content = current_kitchen.quick_bites_content || ''
    result = FamilyRecipes.parse_quick_bites_content(content)
    structure = FamilyRecipes::QuickBitesSerializer.to_ir(result.quick_bites)

    render partial: 'menu/quickbites_editor_frame', locals: {
      content:, structure:
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

  def recipe_selector_categories
    current_kitchen.categories.ordered.includes(
      recipes: { steps: [:ingredients, { cross_references: { target_recipe: { steps: :ingredients } } }] }
    )
  end
end
