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
    @shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen).build
    all_entries = OnHandEntry.where(kitchen_id: current_kitchen.id).to_a
    @on_hand_names = all_entries.select(&:on_hand?).to_set(&:ingredient_name)
    @on_hand_data = all_entries.index_by { |e| e.ingredient_name.downcase }
    @custom_names = CustomGroceryItem.where(kitchen_id: current_kitchen.id).pluck(:name).to_set(&:downcase)
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

  # Bulk IC actions: confirm or deplete all inventory check items at once.
  # Post-vacation recovery (have all) or fresh-start restock (need all).
  def confirm_all
    bulk_ic_action('have_it')
  end

  def deplete_all
    bulk_ic_action('need_it')
  end

  def need
    result = MealPlanWriteService.apply_action(
      kitchen: current_kitchen, action_type: 'quick_add',
      item: params[:item].to_s, aisle: params[:aisle].presence || 'Miscellaneous'
    )
    if result.errors.any?
      return render json: { status: 'error', message: result.errors.first }, status: :unprocessable_content
    end

    render json: { status: result.status }
  end

  def update_custom_items
    result = MealPlanWriteService.apply_action(
      kitchen: current_kitchen, action_type: 'custom_items',
      item: params[:item].to_s, action: params[:action_type],
      aisle: params[:aisle].presence || 'Miscellaneous'
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

  private

  def bulk_ic_action(action_type)
    items = Array(params[:items])
    Kitchen.batch_writes(current_kitchen) do
      items.each do |item|
        MealPlanWriteService.apply_action(kitchen: current_kitchen, action_type:, item:)
      end
    end
    head :no_content
  end
end
