# frozen_string_literal: true

# Manages category ordering, renaming, and deletion via the Edit Categories
# dialog on the homepage. Uses the same staged-changeset pattern as the aisle
# editor: client tracks renames/deletes/reorders, submits them in a single PATCH.
#
# - OrderedListEditor concern: shared validation
# - Kitchen#broadcast_update: page-refresh morph for all connected clients
# - Category: AR model with position column for ordering
class CategoriesController < ApplicationController
  include OrderedListEditor

  before_action :require_membership, only: [:update_order]

  MAX_CATEGORIES = 50
  MAX_NAME_LENGTH = 50

  def order_content
    categories = current_kitchen.categories.ordered
    render json: {
      categories: categories.map { |c| { name: c.name, position: c.position, recipe_count: c.recipes.size } }
    }
  end

  def update_order
    names = Array(params[:category_order])
    errors = validate_ordered_list(names, max_items: MAX_CATEGORIES, max_name_length: MAX_NAME_LENGTH)
    return render(json: { errors: }, status: :unprocessable_content) if errors.any?

    ActiveRecord::Base.transaction do
      cascade_category_renames
      cascade_category_deletes
      update_category_positions(names)
    end

    current_kitchen.broadcast_update
    render json: { status: 'ok' }
  end

  private

  def cascade_category_renames
    renames = params[:renames]
    return unless renames.is_a?(ActionController::Parameters)

    renames.each_pair do |old_name, new_name|
      category = current_kitchen.categories.find_by!(slug: FamilyRecipes.slugify(old_name))
      category.update!(name: new_name, slug: FamilyRecipes.slugify(new_name))
    end
  end

  def cascade_category_deletes
    deletes = Array(params[:deletes])
    return if deletes.empty?

    misc = find_or_create_miscellaneous

    deletes.each do |name|
      category = current_kitchen.categories.find_by(slug: FamilyRecipes.slugify(name))
      next unless category

      category.recipes.update_all(category_id: misc.id) # rubocop:disable Rails/SkipsModelValidations
      category.destroy!
    end
  end

  def find_or_create_miscellaneous
    slug = FamilyRecipes.slugify('Miscellaneous')
    current_kitchen.categories.find_or_create_by!(slug: slug) do |cat|
      cat.name = 'Miscellaneous'
      cat.position = current_kitchen.categories.maximum(:position).to_i + 1
    end
  end

  def update_category_positions(names)
    names.each_with_index do |name, index|
      current_kitchen.categories.where(slug: FamilyRecipes.slugify(name)).update_all(position: index) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
