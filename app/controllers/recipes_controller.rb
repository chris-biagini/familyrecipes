# frozen_string_literal: true

class RecipesController < ApplicationController
  before_action :require_membership, only: %i[create update destroy]

  def show
    @recipe = current_kitchen.recipes
                             .includes(steps: %i[ingredients cross_references])
                             .find_by!(slug: params[:slug])
    @nutrition = @recipe.nutrition_data
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def create
    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

    recipe = MarkdownImporter.import(params[:markdown_source], kitchen: current_kitchen)
    recipe.update!(edited_at: Time.current)

    render json: { redirect_url: recipe_path(recipe.slug) }
  end

  def update
    @recipe = current_kitchen.recipes.find_by!(slug: params[:slug])

    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

    old_title = @recipe.title
    recipe = MarkdownImporter.import(params[:markdown_source], kitchen: current_kitchen)

    updated_references = if title_changed?(old_title, recipe.title)
                           CrossReferenceUpdater.rename_references(
                             old_title: old_title, new_title: recipe.title, kitchen: current_kitchen
                           )
                         else
                           []
                         end

    @recipe.destroy! if recipe.slug != @recipe.slug
    recipe.update!(edited_at: Time.current)
    current_kitchen.categories.left_joins(:recipes).where(recipes: { id: nil }).destroy_all

    response_json = { redirect_url: recipe_path(recipe.slug) }
    response_json[:updated_references] = updated_references if updated_references.any?
    render json: response_json
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def destroy
    @recipe = current_kitchen.recipes.find_by!(slug: params[:slug])

    updated_references = CrossReferenceUpdater.strip_references(@recipe)
    @recipe.destroy!
    current_kitchen.categories.left_joins(:recipes).where(recipes: { id: nil }).destroy_all

    response_json = { redirect_url: kitchen_root_path }
    response_json[:updated_references] = updated_references if updated_references.any?
    render json: response_json
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def title_changed?(old_title, new_title)
    old_title != new_title
  end
end
