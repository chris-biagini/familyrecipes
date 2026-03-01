# frozen_string_literal: true

# Shopping list page — member-only. Renders the grocery list built by
# ShoppingListBuilder from the MealPlan's selections. Manages check-off state,
# custom items, and aisle ordering. All state mutations broadcast version updates
# via MealPlanChannel for cross-device sync.
class GroceriesController < ApplicationController
  before_action :require_membership
  before_action :prevent_html_caching, only: :show

  rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_record

  def show; end

  def state
    list = MealPlan.for_kitchen(current_kitchen)
    shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: list).build

    render json: {
      version: list.lock_version,
      **list.state.slice(*MealPlan::STATE_KEYS),
      shopping_list: shopping_list
    }
  end

  def check
    apply_and_respond('check',
                      item: params[:item],
                      checked: params[:checked])
  end

  def update_custom_items
    item = params[:item].to_s
    max = MealPlan::MAX_CUSTOM_ITEM_LENGTH
    if item.size > max
      return render json: { errors: ["Custom item name is too long (max #{max} characters)"] },
                    status: :unprocessable_content
    end

    apply_and_respond('custom_items', item: item, action: params[:action_type])
  end

  def update_aisle_order
    current_kitchen.aisle_order = params[:aisle_order].to_s
    current_kitchen.normalize_aisle_order!

    errors = validate_aisle_order
    return render json: { errors: }, status: :unprocessable_content if errors.any?

    current_kitchen.save!

    list = MealPlan.for_kitchen(current_kitchen)
    list.update!(updated_at: Time.current)
    MealPlanChannel.broadcast_version(current_kitchen, list.lock_version)
    render json: { status: 'ok' }
  end

  def aisle_order_content
    render json: { aisle_order: build_aisle_order_text }
  end

  private

  def apply_and_respond(action_type, **action_params)
    list = MealPlan.for_kitchen(current_kitchen)
    list.with_optimistic_retry do
      list.apply_action(action_type, **action_params)
    end
    MealPlanChannel.broadcast_version(current_kitchen, list.lock_version)
    render json: { version: list.lock_version }
  end

  def handle_stale_record
    render json: { error: 'Meal plan was modified by another request. Please refresh.' },
           status: :conflict
  end

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
