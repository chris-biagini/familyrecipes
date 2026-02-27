# frozen_string_literal: true

class RecipesController < ApplicationController
  before_action :require_membership, only: %i[create update destroy]

  def show
    @recipe = current_kitchen.recipes
                             .includes(steps: [:ingredients, { cross_references: :target_recipe }])
                             .find_by!(slug: params[:slug])
    @nutrition = @recipe.nutrition_data
  end

  def create
    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: }, status: :unprocessable_content if errors.any?

    recipe = MarkdownImporter.import(params[:markdown_source], kitchen: current_kitchen)
    recipe.update!(edited_at: Time.current)

    MealPlanChannel.broadcast_content_changed(current_kitchen)
    render json: { redirect_url: recipe_path(recipe.slug) }
  rescue ActiveRecord::RecordInvalid, RuntimeError => error
    render json: { errors: [error.message] }, status: :unprocessable_content
  end

  def update # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    @recipe = current_kitchen.recipes.find_by!(slug: params[:slug])

    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: }, status: :unprocessable_content if errors.any?

    old_title = @recipe.title
    recipe = MarkdownImporter.import(params[:markdown_source], kitchen: current_kitchen)

    updated_references = if old_title == recipe.title
                           []
                         else
                           CrossReferenceUpdater.rename_references(
                             old_title:, new_title: recipe.title, kitchen: current_kitchen
                           )
                         end

    @recipe.destroy! if recipe.slug != @recipe.slug
    recipe.update!(edited_at: Time.current)
    Category.cleanup_orphans(current_kitchen)

    MealPlanChannel.broadcast_content_changed(current_kitchen)
    response_json = { redirect_url: recipe_path(recipe.slug) }
    response_json[:updated_references] = updated_references if updated_references.any?
    render json: response_json
  rescue ActiveRecord::RecordInvalid, RuntimeError => error
    render json: { errors: [error.message] }, status: :unprocessable_content
  end # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  def destroy
    @recipe = current_kitchen.recipes.find_by!(slug: params[:slug])

    updated_references = CrossReferenceUpdater.strip_references(@recipe)
    @recipe.destroy!
    Category.cleanup_orphans(current_kitchen)

    MealPlanChannel.broadcast_content_changed(current_kitchen)
    response_json = { redirect_url: home_path }
    response_json[:updated_references] = updated_references if updated_references.any?
    render json: response_json
  end
end
