# frozen_string_literal: true

# Thin HTTP adapter for recipe CRUD. Show is public; writes require membership.
# Validates Markdown params, delegates to RecipeWriteService for orchestration,
# and renders JSON responses. All domain logic (import, broadcast, cleanup)
# lives in the service.
class RecipesController < ApplicationController
  before_action :require_membership, only: %i[create update destroy]

  def show
    @recipe = current_kitchen.recipes.with_full_tree.find_by!(slug: params[:slug])
    @nutrition = @recipe.nutrition_data
  end

  def create
    return render_validation_errors if validation_errors.any?

    result = RecipeWriteService.create(
      markdown: params[:markdown_source], kitchen: current_kitchen, category_name: params[:category]
    )
    render json: { redirect_url: recipe_path(result.recipe.slug) }
  rescue ActiveRecord::RecordInvalid, RuntimeError => error
    render json: { errors: [error.message] }, status: :unprocessable_content
  end

  def update
    current_kitchen.recipes.find_by!(slug: params[:slug])
    return render_validation_errors if validation_errors.any?

    result = RecipeWriteService.update(
      slug: params[:slug], markdown: params[:markdown_source],
      kitchen: current_kitchen, category_name: params[:category]
    )
    render json: update_response(result)
  rescue ActiveRecord::RecordInvalid, RuntimeError => error
    render json: { errors: [error.message] }, status: :unprocessable_content
  end

  def destroy
    RecipeWriteService.destroy(slug: params[:slug], kitchen: current_kitchen)
    render json: { redirect_url: home_path }
  end

  private

  def validation_errors
    @validation_errors ||= MarkdownValidator.validate(params[:markdown_source])
  end

  def render_validation_errors
    render json: { errors: @validation_errors }, status: :unprocessable_content
  end

  def update_response(result)
    response = { redirect_url: recipe_path(result.recipe.slug) }
    response[:updated_references] = result.updated_references if result.updated_references.any?
    response
  end
end
