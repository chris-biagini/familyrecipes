# frozen_string_literal: true

# Category ordering dialog — serves the Turbo Frame for the Edit Categories
# editor and processes the staged changeset (renames, deletes, reorder) via
# CategoryWriteService. Read-only access is public; writes require membership.
#
# - CategoryWriteService: orchestrates rename/delete/reorder mutations
class CategoriesController < ApplicationController
  before_action :require_membership, only: [:update_order]

  def order_content
    categories = current_kitchen.categories.ordered
    render partial: 'categories/order_frame',
           locals: { items: categories.map(&:name) },
           layout: false
  end

  def update_order
    result = CategoryWriteService.update(
      kitchen: current_kitchen,
      names: Array(params[:category_order]),
      renames: params[:renames],
      deletes: params[:deletes]
    )
    return render(json: { errors: result.errors }, status: :unprocessable_content) unless result.success

    render json: { status: 'ok' }
  end
end
