# frozen_string_literal: true

# Shopping list page -- member-only. Server-renders the full shopping list on
# page load via ShoppingListBuilder. Mutations return 204 No Content and
# broadcast a page-refresh signal for cross-device sync. Manages check-off
# state, custom items, and aisle ordering.
class GroceriesController < ApplicationController
  include MealPlanActions
  include OrderedListEditor

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
    current_kitchen.aisle_order = params[:aisle_order].to_s
    current_kitchen.normalize_aisle_order!

    errors = validate_ordered_list(
      current_kitchen.parsed_aisle_order,
      max_items: Kitchen::MAX_AISLES,
      max_name_length: Kitchen::MAX_AISLE_NAME_LENGTH
    )
    return render json: { errors: }, status: :unprocessable_content if errors.any?

    ActiveRecord::Base.transaction do
      cascade_aisle_renames
      cascade_aisle_deletes
      current_kitchen.save!
    end

    current_kitchen.broadcast_update
    render json: { status: 'ok' }
  end

  def aisle_order_content
    render json: { aisle_order: build_aisle_order_text }
  end

  private

  def cascade_aisle_renames
    renames = params[:renames]
    return unless renames.is_a?(ActionController::Parameters)

    renames.each_pair do |old_name, new_name|
      current_kitchen.ingredient_catalog.where(aisle: old_name).update_all(aisle: new_name) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def cascade_aisle_deletes
    deletes = params[:deletes]
    return unless deletes.is_a?(Array)

    current_kitchen.ingredient_catalog.where(aisle: deletes).update_all(aisle: nil) # rubocop:disable Rails/SkipsModelValidations
  end

  def build_aisle_order_text
    current_kitchen.all_aisles.join("\n")
  end
end
