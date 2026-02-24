# frozen_string_literal: true

class GroceriesController < ApplicationController
  before_action :require_membership

  def show
    @categories = current_kitchen.categories.ordered.includes(recipes: { steps: :ingredients })
    @quick_bites_by_subsection = load_quick_bites_by_subsection
    @quick_bites_content = current_kitchen.quick_bites_content || ''
  end

  def state
    list = GroceryList.for_kitchen(current_kitchen)
    shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, grocery_list: list).build

    render json: {
      version: list.version,
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
    apply_and_respond('custom_items',
                      item: params[:item],
                      action: params[:action_type])
  end

  def clear
    list = GroceryList.for_kitchen(current_kitchen)
    list.clear!
    GroceryListChannel.broadcast_version(current_kitchen, list.version)
    render json: { version: list.version }
  end

  def update_quick_bites
    content = params[:content].to_s
    return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_entity if content.blank?

    current_kitchen.update!(quick_bites_content: content)

    GroceryListChannel.broadcast_content_changed(current_kitchen)
    render json: { status: 'ok' }
  end

  def update_aisle_order
    current_kitchen.aisle_order = params[:aisle_order].to_s
    current_kitchen.normalize_aisle_order!
    current_kitchen.save!

    GroceryListChannel.broadcast_content_changed(current_kitchen)
    render json: { status: 'ok' }
  end

  def aisle_order_content
    render json: { aisle_order: build_aisle_order_text }
  end

  private

  def apply_and_respond(action_type, **action_params)
    list = GroceryList.for_kitchen(current_kitchen)
    list.apply_action(action_type, **action_params)
    GroceryListChannel.broadcast_version(current_kitchen, list.version)
    render json: { version: list.version }
  end

  def build_aisle_order_text
    saved = current_kitchen.parsed_aisle_order
    catalog_aisles = IngredientCatalog.lookup_for(current_kitchen)
                                      .values
                                      .filter_map(&:aisle)
                                      .uniq
                                      .reject { |a| a == 'omit' }
                                      .sort

    new_aisles = catalog_aisles - saved
    (saved + new_aisles).join("\n")
  end

  def load_quick_bites_by_subsection
    content = current_kitchen.quick_bites_content
    return {} unless content

    FamilyRecipes.parse_quick_bites_content(content)
                 .group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
  end
end
