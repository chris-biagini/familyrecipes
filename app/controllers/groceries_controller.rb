# frozen_string_literal: true

class GroceriesController < ApplicationController
  before_action :require_membership, only: %i[select check update_custom_items clear update_quick_bites]

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

  private

  def apply_and_respond(action_type, **action_params)
    list = GroceryList.for_kitchen(current_kitchen)
    list.apply_action(action_type, **action_params)
    GroceryListChannel.broadcast_version(current_kitchen, list.version)
    render json: { version: list.version }
  end

  def load_quick_bites_by_subsection
    content = current_kitchen.quick_bites_content
    return {} unless content

    FamilyRecipes.parse_quick_bites_content(content)
                 .group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
  end
end
