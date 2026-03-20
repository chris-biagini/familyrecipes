# frozen_string_literal: true

# Shopping list page — member-only. Server-renders the full shopping list on page
# load via ShoppingListBuilder. Mutations delegate to write services and return
# 204 No Content; broadcasts happen inside the services for cross-device sync.
#
# - MealPlanWriteService: check-off and custom item mutations
# - AisleWriteService: aisle order mutations
# - MealPlanActions: param coercion and StaleObjectError rescue
# - ShoppingListBuilder: computes the shopping list for rendering
class GroceriesController < ApplicationController
  include MealPlanActions

  before_action :require_membership
  before_action :prevent_html_caching, only: :show

  def show
    plan = MealPlan.for_kitchen(current_kitchen)
    @shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).build
    @checked_off = plan.checked_off.to_set
    @custom_items = plan.custom_items
  end

  def check
    MealPlanWriteService.apply_action(
      kitchen: current_kitchen, action_type: 'check',
      item: params[:item], checked: truthy_param?(params[:checked])
    )
    head :no_content
  end

  def update_custom_items
    result = MealPlanWriteService.apply_action(
      kitchen: current_kitchen, action_type: 'custom_items',
      item: params[:item].to_s, action: params[:action_type]
    )
    return render json: { errors: result.errors }, status: :unprocessable_content if result.errors.any?

    head :no_content
  end

  def update_aisle_order
    result = AisleWriteService.update(
      kitchen: current_kitchen,
      aisle_order: params[:aisle_order].to_s,
      renames: params[:renames],
      deletes: params[:deletes]
    )
    return render(json: { errors: result.errors }, status: :unprocessable_content) if result.errors.any?

    render json: { status: 'ok' }
  end

  def aisle_order_content
    aisles = current_kitchen.all_aisles

    respond_to do |format|
      format.html { render partial: 'groceries/aisle_order_frame', locals: { items: aisles }, layout: false }
      format.json { render json: { aisle_order: aisles.join("\n") } }
    end
  end
end
