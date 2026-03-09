# frozen_string_literal: true

# Placeholder — architectural header comment will be added in Task 4.
class CategoriesController < ApplicationController
  before_action :require_membership, only: [:update_order]

  def order_content
    categories = current_kitchen.categories.ordered
    render json: {
      categories: categories.map { |c| { name: c.name, position: c.position, recipe_count: c.recipes.size } }
    }
  end

  def update_order
    result = CategoryWriteService.update_order(
      kitchen: current_kitchen,
      names: Array(params[:category_order]),
      renames: params[:renames],
      deletes: params[:deletes]
    )
    return render(json: { errors: result.errors }, status: :unprocessable_content) unless result.success

    current_kitchen.broadcast_update
    render json: { status: 'ok' }
  end
end
