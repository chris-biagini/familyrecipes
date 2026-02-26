# frozen_string_literal: true

class GroceriesController < ApplicationController
  before_action :require_membership

  rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_record

  def show
    @categories = recipe_selector_categories
    @quick_bites_by_subsection = load_quick_bites_by_subsection
    @quick_bites_content = current_kitchen.quick_bites_content || ''
  end

  def state
    list = GroceryList.for_kitchen(current_kitchen)
    shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, grocery_list: list).build

    render json: {
      version: list.lock_version,
      **list.state.slice(*GroceryList::STATE_KEYS),
      shopping_list: shopping_list
    }
  end

  def select
    apply_and_respond('select',
                      type: params[:type],
                      slug: params[:slug],
                      selected: params[:selected])
  end

  def check
    apply_and_respond('check',
                      item: params[:item],
                      checked: params[:checked])
  end

  def update_custom_items
    item = params[:item].to_s
    max = GroceryList::MAX_CUSTOM_ITEM_LENGTH
    if item.size > max
      return render json: { errors: ["Custom item name is too long (max #{max} characters)"] },
                    status: :unprocessable_content
    end

    apply_and_respond('custom_items', item: item, action: params[:action_type])
  end

  def clear
    list = GroceryList.for_kitchen(current_kitchen)
    list.with_optimistic_retry { list.clear! }
    GroceryListChannel.broadcast_version(current_kitchen, list.lock_version)
    render json: { version: list.lock_version }
  end

  def update_quick_bites
    content = params[:content].to_s
    return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_content if content.blank?

    current_kitchen.update!(quick_bites_content: content)

    broadcast_recipe_selector_update
    render json: { status: 'ok' }
  end

  def update_aisle_order
    current_kitchen.aisle_order = params[:aisle_order].to_s
    current_kitchen.normalize_aisle_order!

    errors = validate_aisle_order
    return render json: { errors: }, status: :unprocessable_content if errors.any?

    current_kitchen.save!

    list = GroceryList.for_kitchen(current_kitchen)
    list.with_optimistic_retry { list.save! }
    GroceryListChannel.broadcast_version(current_kitchen, list.lock_version)
    render json: { status: 'ok' }
  end

  def aisle_order_content
    render json: { aisle_order: build_aisle_order_text }
  end

  private

  def apply_and_respond(action_type, **action_params)
    list = GroceryList.for_kitchen(current_kitchen)
    list.with_optimistic_retry do
      list.apply_action(action_type, **action_params)
    end
    GroceryListChannel.broadcast_version(current_kitchen, list.lock_version)
    render json: { version: list.lock_version }
  end

  def handle_stale_record
    render json: { error: 'Grocery list was modified by another request. Please refresh.' },
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
      current_kitchen, 'grocery_content',
      target: 'recipe-selector',
      partial: 'groceries/recipe_selector',
      locals: {
        categories: recipe_selector_categories,
        quick_bites_by_subsection: load_quick_bites_by_subsection
      }
    )
  end
end
