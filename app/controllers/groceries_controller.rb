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
    broadcast_meal_plan_refresh
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
    broadcast_meal_plan_refresh
    head :no_content
  end

  def update_aisle_order
    current_kitchen.aisle_order = params[:aisle_order].to_s
    current_kitchen.normalize_aisle_order!

    errors = validate_aisle_order
    return render json: { errors: }, status: :unprocessable_content if errors.any?

    current_kitchen.save!
    broadcast_meal_plan_refresh
    render json: { status: 'ok' }
  end

  def aisle_order_content
    render json: { aisle_order: build_aisle_order_text }
  end

  private

  def validate_aisle_order
    lines = current_kitchen.parsed_aisle_order
    too_many = lines.size > Kitchen::MAX_AISLES ? ["Too many aisles (max #{Kitchen::MAX_AISLES})"] : []

    max = Kitchen::MAX_AISLE_NAME_LENGTH
    too_long = lines.filter_map do |line|
      "Aisle name '#{line.truncate(20)}' is too long (max #{max} characters)" if line.size > max
    end

    too_many + too_long
  end

  def build_aisle_order_text
    current_kitchen.all_aisles.join("\n")
  end
end
