# frozen_string_literal: true

# Shopping list page — member-only. Server-renders the full shopping list on page
# load via ShoppingListBuilder. Mutations delegate to write services and return
# 204 No Content; broadcasts happen inside the services for cross-device sync.
#
# - MealPlanWriteService: check-off, have_it, need_it, and custom item mutations
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
    @on_hand_names = plan.effective_on_hand.keys.to_set
    @on_hand_data = plan.on_hand
    @custom_items = plan.custom_items
  end

  def check
    MealPlanWriteService.apply_action(
      kitchen: current_kitchen, action_type: 'check',
      item: params[:item], checked: truthy_param?(params[:checked])
    )
    head :no_content
  end

  def have_it # rubocop:disable Naming/PredicatePrefix -- action name, not a boolean predicate
    MealPlanWriteService.apply_action(
      kitchen: current_kitchen, action_type: 'have_it',
      item: params[:item]
    )
    head :no_content
  end

  def need_it
    MealPlanWriteService.apply_action(
      kitchen: current_kitchen, action_type: 'need_it',
      item: params[:item]
    )
    head :no_content
  end

  # Post-vacation recovery: confirm all inventory check items at once
  def confirm_all
    items = Array(params[:items])
    Kitchen.batch_writes(current_kitchen) do
      items.each do |item|
        MealPlanWriteService.apply_action(
          kitchen: current_kitchen, action_type: 'have_it', item:
        )
      end
    end
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
    render partial: 'groceries/aisle_order_frame',
           locals: { items: current_kitchen.all_aisles },
           layout: false
  end
end
