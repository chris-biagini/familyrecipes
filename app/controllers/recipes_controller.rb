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

    RecipeBroadcaster.broadcast(kitchen: current_kitchen, action: :created, recipe_title: recipe.title, recipe: recipe)
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

    if recipe.slug != @recipe.slug
      RecipeBroadcaster.broadcast_rename(@recipe, new_title: recipe.title, new_slug: recipe.slug)
      @recipe.destroy!
    end
    recipe.update!(edited_at: Time.current)
    Category.cleanup_orphans(current_kitchen)
    MealPlan.for_kitchen(current_kitchen).prune_checked_off

    RecipeBroadcaster.broadcast(kitchen: current_kitchen, action: :updated, recipe_title: recipe.title, recipe: recipe)
    response_json = { redirect_url: recipe_path(recipe.slug) }
    response_json[:updated_references] = updated_references if updated_references.any?
    render json: response_json
  rescue ActiveRecord::RecordInvalid, RuntimeError => error
    render json: { errors: [error.message] }, status: :unprocessable_content
  end # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  def destroy
    @recipe = current_kitchen.recipes.find_by!(slug: params[:slug])

    updated_references = CrossReferenceUpdater.strip_references(@recipe)
    RecipeBroadcaster.notify_recipe_deleted(@recipe, recipe_title: @recipe.title)
    @recipe.destroy!
    Category.cleanup_orphans(current_kitchen)
    MealPlan.for_kitchen(current_kitchen).prune_checked_off

    RecipeBroadcaster.broadcast(kitchen: current_kitchen, action: :deleted,
                                recipe_title: @recipe.title)

    response_json = { redirect_url: home_path }
    response_json[:updated_references] = updated_references if updated_references.any?
    render json: response_json
  end
end
