# frozen_string_literal: true

# Shopping list page -- member-only. Server-renders the full shopping list on
# page load via ShoppingListBuilder. Mutations return 204 No Content and
# broadcast a page-refresh signal for cross-device sync. Manages check-off
# state, custom items, and aisle ordering.
class GroceriesController < ApplicationController
  include MealPlanActions

  before_action :require_membership
  before_action :prevent_html_caching, only: :show

  def show
    plan = MealPlan.for_kitchen(current_kitchen)
    @shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).build
    @checked_off = plan.checked_off_set
    @custom_items = plan.custom_items_list
  end

  def check
    apply_plan('check', item: params[:item], checked: params[:checked])
    current_kitchen.broadcast_update
    head :no_content
  end

  def update_custom_items
    item = params[:item].to_s
    max = MealPlan::MAX_CUSTOM_ITEM_LENGTH
    if item.size > max
      return render json: { errors: ["Custom item name is too long (max #{max} characters)"] },
                    status: :unprocessable_content
    end

    apply_plan('custom_items', item: item, action: params[:action_type])
    current_kitchen.broadcast_update
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

    current_kitchen.broadcast_update
    render json: { status: 'ok' }
  end

  def aisle_order_content
    render json: { aisle_order: current_kitchen.all_aisles.join("\n") }
  end
end
